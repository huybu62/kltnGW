import Foundation
import Combine
import AVFoundation
import CoreMedia
import CoreVideo

/// Receives the Host's video, decodes it in hardware and shows it on an
/// `AVSampleBufferDisplayLayer` (put `VideoSurfaceView` in your UI).
/// Plug into `ConnectionCoordinator.mediaSink`.
///
/// Every frame is displayed immediately on arrival: there is no jitter
/// buffer, because for a second screen low latency matters more than
/// perfectly even pacing.
public final class DisplayStreamController: ObservableObject, SessionMediaSink, @unchecked Sendable {
    /// True while video is arriving; show `VideoSurfaceView` full screen.
    @Published public private(set) var isReceiving = false
    @Published public private(set) var stats: StreamStats?
    /// The link dropped; the last picture stays up while the Mac reconnects.
    @Published public private(set) var isReconnecting = false

    public let displayLayer: AVSampleBufferDisplayLayer

    private let decoder = VideoDecoder()
    private let audio = AudioPlayer()
    private let lock = NSLock()
    private var session: SecureSession?
    private var lastKeyframeRequest: TimeInterval = 0
    private var framesThisSecond = 0
    private var bytesThisSecond = 0
    private var statsTimer: DispatchSourceTimer?
    private var clearWork: DispatchWorkItem?

    public init() {
        displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.videoGravity = .resizeAspect
        decoder.onDecoded = { [weak self] pixelBuffer in self?.show(pixelBuffer) }
        decoder.onNeedsKeyframe = { [weak self] in self?.requestKeyframe() }
    }

    // MARK: SessionMediaSink

    public func sessionStarted(_ session: SecureSession) {
        clearWork?.cancel()
        clearWork = nil
        isReconnecting = false
        lock.lock(); self.session = session; lock.unlock()
        decoder.reset()
        startStatsTimer()
    }

    public func sessionEnded(_ endedSession: SecureSession, willReconnect: Bool) {
        audio.stop()
        latchedModifiers = []  // the Mac releases everything when a session ends
        latchedFlags.value = 0
        lock.lock()
        session = nil
        let timer = statsTimer
        statsTimer = nil
        lock.unlock()
        timer?.cancel()
        decoder.reset()
        clearWork?.cancel()
        guard willReconnect, isReceiving else {
            clearScreen()
            return
        }
        // Keep the frozen last frame; give up after 20 s.
        isReconnecting = true
        let work = DispatchWorkItem { [weak self] in
            self?.isReconnecting = false
            self?.clearScreen()
        }
        clearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }

    // MARK: Input (any thread)

    /// Size of the incoming picture in pixels, for mapping touches.
    /// Frame rate the Mac is streaming at (nil before the first keyframe).
    public var streamFrameRate: Int? {
        decoder.currentFormat?.framesPerSecond
    }

    public var videoSize: CGSize? {
        decoder.currentFormat.map { CGSize(width: $0.width, height: $0.height) }
    }

    /// Sends a touch / Pencil / mouse event to the Mac.
    public func sendInput(_ event: InputEvent) {
        lock.lock(); let session = self.session; lock.unlock()
        guard let session, let payload = try? WireCoding.encode(event) else { return }
        try? session.sendSealedWithoutWaiting(.sealedInput, payload: payload)
    }

    /// Media queue.
    public func received(type: UInt8, payload: Data, flags: UInt16, from session: SecureSession) {
        switch MessageType(rawValue: type) {
        case .sealedVideoFormat:
            guard let format = try? WireCoding.decode(VideoFormat.self, from: payload) else { return }
            if !decoder.configure(format) { requestKeyframe() }

        case .sealedVideoFrame:
            guard let header = VideoFrameHeader(payload) else { return }
            lock.lock()
            let session = self.session
            framesThisSecond += 1
            bytesThisSecond += payload.count
            lock.unlock()
            // Acknowledge on arrival (not after decoding) so the Host's flow
            // control measures the network, not our decoder.
            session?.sendWithoutWaiting(.frameAck(frameNumber: header.frameNumber))

            if decoder.currentFormat == nil {
                requestKeyframe()
                return
            }
            let isKeyframe = flags & VideoFrameFlags.keyframe != 0
            decoder.decode(payload.subdata(in: payload.startIndex + VideoFrameHeader.size ..< payload.endIndex),
                           isKeyframe: isKeyframe)
            markReceiving(true)

        case .sealedAudio:
            audio.enqueue(payload)

        default:
            break
        }
    }

    public func receivedControl(_ message: ControlMessage, from session: SecureSession) {
        switch message {
        case .streamStopped:
            audio.stop()
            decoder.reset()
            clearScreen()
        case .cursor(let x, let y, let visible):
            DispatchQueue.main.async { [weak self] in
                self?.onCursorUpdate?(CGPoint(x: x, y: y), visible)
            }
        default:
            break
        }
    }

    // MARK: Local pointer

    /// The Mac leaves its pointer out of the video; draw it here.
    public var drawsCursor: Bool {
        decoder.currentFormat?.drawsCursor ?? false
    }

    /// Main thread: the Mac's pointer moved (normalized position, visible on this screen).
    public var onCursorUpdate: ((CGPoint, Bool) -> Void)?

    // MARK: Shortcut bar modifiers

    /// HID usages of ⌘ ⌥ ⌃ ⇧ latched on the shortcut bar (main thread).
    @Published public private(set) var latchedModifiers: Set<UInt16> = []
    private let latchedFlags = LockedValue<UInt32>(0)

    /// Modifier flags held on the shortcut bar, included whenever the iPad
    /// reports its modifier state (so the Mac doesn't drop them). Any thread.
    public var shortcutBarModifierFlags: UInt32 { latchedFlags.value }

    public static func modifierFlag(forUsage usage: UInt16) -> UInt32 {
        switch usage {
        case 0xE1, 0xE5: return 0x2_0000   // ⇧
        case 0xE0, 0xE4: return 0x4_0000   // ⌃
        case 0xE2, 0xE6: return 0x8_0000   // ⌥
        case 0xE3, 0xE7: return 0x10_0000  // ⌘
        default: return 0
        }
    }

    /// Main thread. Presses or releases a modifier from the shortcut bar.
    public func setModifier(_ usage: UInt16, down: Bool) {
        guard down != latchedModifiers.contains(usage) else { return }
        if down { latchedModifiers.insert(usage) } else { latchedModifiers.remove(usage) }
        latchedFlags.value = latchedModifiers.reduce(0) { $0 | Self.modifierFlag(forUsage: $1) }
        sendInput(.key(usage: usage, down: down))
    }

    /// Main thread. Types one shortcut, e.g. ⌘Z = `press(0x1D, with: [0xE3])`.
    public func press(_ usage: UInt16, with modifiers: [UInt16] = []) {
        let extra = modifiers.filter { !latchedModifiers.contains($0) }
        for modifier in extra { sendInput(.key(usage: modifier, down: true)) }
        sendInput(.key(usage: usage, down: true))
        sendInput(.key(usage: usage, down: false))
        for modifier in extra.reversed() { sendInput(.key(usage: modifier, down: false)) }
    }

    /// Lets go of every latched modifier (e.g. when the session ends).
    /// Main thread. Brightness / volume / playback key on the Mac.
    public func pressMediaKey(_ code: Int) {
        sendInput(.mediaKey(code: code))
    }

    public func releaseModifiers() {
        for usage in latchedModifiers { setModifier(usage, down: false) }
    }

    /// Call when the app returns to the foreground (iPadOS may have reset
    /// the decoder and the layer while in the background).
    public func refresh() {
        DispatchQueue.main.async { [weak self] in self?.flushLayerIfFailed() }
        requestKeyframe()
    }

    // MARK: - Internals

    private func requestKeyframe() {
        lock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        let session = self.session
        let tooSoon = now - lastKeyframeRequest < 0.3
        if !tooSoon { lastKeyframeRequest = now }
        lock.unlock()
        guard !tooSoon else { return }
        session?.sendWithoutWaiting(.requestKeyframe)
    }

    /// VideoToolbox thread.
    private func show(_ pixelBuffer: CVPixelBuffer) {
        var description: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &description)
        guard let description else { return }
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                 formatDescription: description, sampleTiming: &timing,
                                                 sampleBufferOut: &sample)
        guard let sample else { return }
        Self.markDisplayImmediately(sample)
        enqueue(sample)
    }

    private func enqueue(_ sample: CMSampleBuffer) {
        if #available(iOS 17.0, macOS 14.0, *) {
            let renderer = displayLayer.sampleBufferRenderer
            if renderer.status == .failed { renderer.flush() }
            renderer.enqueue(sample)
        } else {
            if displayLayer.status == .failed { displayLayer.flush() }
            displayLayer.enqueue(sample)
        }
    }

    private func flushLayerIfFailed() {
        if #available(iOS 17.0, macOS 14.0, *) {
            if displayLayer.sampleBufferRenderer.status == .failed { displayLayer.sampleBufferRenderer.flush() }
        } else if displayLayer.status == .failed {
            displayLayer.flush()
        }
    }

    private func clearScreen() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if #available(iOS 17.0, macOS 14.0, *) {
                self.displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
            } else {
                self.displayLayer.flushAndRemoveImage()
            }
            self.isReceiving = false
            self.stats = nil
        }
    }

    private func markReceiving(_ receiving: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isReceiving != receiving else { return }
            self.isReceiving = receiving
        }
    }

    private static func markDisplayImmediately(_ sample: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
              CFArrayGetCount(attachments) > 0 else { return }
        let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        let trueValue: CFBoolean = kCFBooleanTrue
        CFDictionarySetValue(dictionary,
                             Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                             Unmanaged.passUnretained(trueValue).toOpaque())
    }

    private func startStatsTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.publishStats() }
        lock.lock()
        statsTimer?.cancel()
        statsTimer = timer
        lock.unlock()
        timer.resume()
    }

    private func publishStats() {
        lock.lock()
        let frames = framesThisSecond
        let bytes = bytesThisSecond
        framesThisSecond = 0
        bytesThisSecond = 0
        lock.unlock()
        guard let format = decoder.currentFormat else { return }
        let stats = StreamStats(codec: format.codec, width: format.width, height: format.height,
                                framesPerSecond: Double(frames),
                                megabitsPerSecond: Double(bytes) * 8 / 1_000_000,
                                latencyMs: nil, skippedFrames: 0)
        DispatchQueue.main.async { [weak self] in self?.stats = stats }
    }
}
