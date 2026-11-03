#if os(macOS)
import Foundation
import CoreGraphics
import CoreMedia
import CoreVideo

/// One video stream from this Mac to the connected Display:
/// (virtual) display → ScreenCaptureKit → VideoToolbox → encrypted session.
///
/// Flow control: the Display acknowledges every frame. At most
/// `maxFramesInFlight` frames may be unacknowledged; newer screen updates
/// replace a waiting one instead of queueing, so latency never builds up
/// on a slow link. The newest frame is always delivered eventually.
final class HostStreamer: @unchecked Sendable {
    enum StreamError: Error, LocalizedError {
        case screenRecordingDenied
        case virtualDisplayFailed

        var errorDescription: String? {
            switch self {
            case .screenRecordingDenied:
                return "ScreenBridge needs Screen Recording permission."
            case .virtualDisplayFailed:
                return "Couldn't create the extra display. Try Mirror mode."
            }
        }
    }

    let mode: StreamMode
    let quality: StreamQuality
    let frameRate: StreamFrameRate
    /// Send the Mac's sound to the Display.
    let sendsAudio: Bool
    private let audioPacketizer = AudioPacketizer()

    /// Delivered on the main thread.
    var onStats: ((StreamStats) -> Void)?
    var onFailure: ((Error) -> Void)?

    /// Swapped when the connection moves to another link (see `attach`).
    private var session: SecureSession
    /// The Display this stream is for; a reconnecting session from the same
    /// device can take the stream over without rebuilding the virtual display.
    let peerID: String
    private let peerName: String
    private var capturedDisplayID: CGDirectDisplayID?
    private let peerDisplay: DisplayCapabilities?
    private let streamID = UInt32.random(in: 1...UInt32.max)
    private let capturer = ScreenCapturer()
    /// Serializes frame admission and encoder submission.
    private let frameQueue = DispatchQueue(label: "app.screenbridge.frames", qos: .userInteractive)
    /// Unacknowledged frames allowed: about 100 ms of video (min 4). A fixed
    /// small window caps throughput at window ÷ round-trip time, e.g. 4
    /// frames over an 80 ms Wi-Fi round trip = 50 fps, whatever the setting.
    private let maxFramesInFlight: Int

    private let lock = NSLock()
    private var encoder: VideoEncoder?
    private var virtualDisplay: VirtualDisplay?
    private var width = 0
    private var height = 0
    private var targetBitrate = 0
    private var currentBitrate = 0
    private var stopped = false

    // Frame state (frameQueue)
    private var pendingFrame: CVPixelBuffer?
    private var lastFrame: CVPixelBuffer?

    // Flow control + stats (lock)
    private var framesAwaitingEncoder = 0
    private var lastSentFrame: UInt32 = 0
    private var lastAckedFrame: UInt32 = 0
    private var sendTimes: [UInt32: TimeInterval] = [:]
    private var lastProgress = ProcessInfo.processInfo.systemUptime
    private var latencyMs: Double?
    private var framesThisSecond = 0
    private var bytesThisSecond = 0
    private var skippedTotal = 0
    private var skippedThisSecond = 0
    private var calmSeconds = 0
    private var statsTimer: DispatchSourceTimer?

    init(session: SecureSession, peerDisplay: DisplayCapabilities?, mode: StreamMode,
         quality: StreamQuality, frameRate: StreamFrameRate, sendsAudio: Bool) {
        self.session = session
        self.sendsAudio = sendsAudio
        self.peerID = session.peer.id
        self.peerName = session.peer.name
        self.peerDisplay = peerDisplay
        self.mode = mode
        self.quality = quality
        self.frameRate = StreamFrameRate.clamped(frameRate, toDisplayMax: peerDisplay?.maxRefreshRate)
        self.maxFramesInFlight = max(4, self.frameRate.rawValue / 10)
    }

    // MARK: - Lifecycle

    func start() async throws {
        guard ScreenCapturer.hasPermission else {
            ScreenCapturer.requestPermission()
            throw StreamError.screenRecordingDenied
        }

        let target = try await prepareDisplay()
        setCapturedDisplay(target.displayID)
        let fps = frameRate.rawValue
        let bitrate = quality.bitrate(width: target.width, height: target.height, framesPerSecond: fps)
        let encoder = try VideoEncoder(configuration: .init(
            codec: (peerDisplay?.supportsHEVC ?? false) ? .hevc : .h264,
            width: target.width, height: target.height,
            framesPerSecond: fps, bitrate: bitrate))
        encoder.onOutput = { [weak self] frame in self?.handleEncoded(frame) }
        install(encoder, width: target.width, height: target.height, bitrate: bitrate)

        capturer.onFrame = { [weak self] pixelBuffer, _ in
            guard let self else { return }
            self.frameQueue.async { self.admit(pixelBuffer) }
        }
        capturer.onAudio = { [weak self] sampleBuffer in
            guard let self, let packet = self.audioPacketizer.packet(from: sampleBuffer) else { return }
            try? self.currentSession().sendSealedWithoutWaiting(.sealedAudio, payload: packet)
        }
        capturer.onStop = { [weak self] error in
            DispatchQueue.main.async { self?.onFailure?(error) }
        }
        do {
            try await capturer.start(displayID: target.displayID, width: target.width,
                                     height: target.height, framesPerSecond: fps, captureAudio: sendsAudio)
        } catch ScreenCapturer.CaptureError.permissionDenied {
            throw StreamError.screenRecordingDenied
        }
        startStatsTimer()
    }

    func stop(reason: String = "stopped") async {
        guard let teardown = markStopped() else { return }
        let (timer, encoder, display) = teardown

        timer?.cancel()
        await capturer.stop()
        encoder?.invalidate()
        frameQueue.sync {
            pendingFrame = nil
            lastFrame = nil
        }
        currentSession().sendWithoutWaiting(.streamStopped(reason: reason))
        // Remove the virtual display on the main thread.
        if let display {
            DispatchQueue.main.async { withExtendedLifetime(display) {} }
        }
    }

    // MARK: - Session hand-over

    /// The display being captured (for mapping input), once started.
    var displayID: CGDirectDisplayID? {
        lock.lock(); defer { lock.unlock() }
        return capturedDisplayID
    }

    /// Continues this stream on a new session from the same Display (link
    /// switch or reconnect). Flow control restarts and a keyframe follows.
    func attach(_ newSession: SecureSession) {
        lock.lock()
        session = newSession
        lastAckedFrame = lastSentFrame
        framesAwaitingEncoder = 0
        sendTimes.removeAll()
        latencyMs = nil
        lastProgress = ProcessInfo.processInfo.systemUptime
        lock.unlock()
        requestKeyframe()
    }

    private func currentSession() -> SecureSession {
        lock.lock(); defer { lock.unlock() }
        return session
    }

    // Lock helpers are synchronous: NSLock must not be used directly in async code.

    private func install(_ encoder: VideoEncoder, width: Int, height: Int, bitrate: Int) {
        lock.lock(); defer { lock.unlock() }
        self.encoder = encoder
        self.width = width
        self.height = height
        targetBitrate = bitrate
        currentBitrate = bitrate
    }

    private func setCapturedDisplay(_ displayID: CGDirectDisplayID) {
        lock.lock(); defer { lock.unlock() }
        capturedDisplayID = displayID
    }

    private func keep(_ display: VirtualDisplay) {
        lock.lock(); defer { lock.unlock() }
        virtualDisplay = display
    }

    /// Returns what needs tearing down, or nil if already stopped.
    private func markStopped() -> (DispatchSourceTimer?, VideoEncoder?, VirtualDisplay?)? {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { return nil }
        stopped = true
        let result = (statsTimer, encoder, virtualDisplay)
        statsTimer = nil
        encoder = nil
        virtualDisplay = nil
        return result
    }

    /// Chooses what to capture and at what size.
    private func prepareDisplay() async throws -> (displayID: CGDirectDisplayID, width: Int, height: Int) {
        let screenWidth = peerDisplay?.pixelWidth ?? 1920
        let screenHeight = peerDisplay?.pixelHeight ?? 1080
        let scale = quality.resolutionScale

        switch mode {
        case .extend:
            let name = "ScreenBridge – \(peerName)"
            let refresh = Double(max(frameRate.rawValue, 60))
            let created = await MainActor.run {
                VirtualDisplay(name: name, pixelWidth: screenWidth, pixelHeight: screenHeight, refreshRate: refresh)
            }
            guard let display = created else { throw StreamError.virtualDisplayFailed }
            keep(display)

            var size = (screenWidth, screenHeight)
            for _ in 0..<20 {
                if let current = display.currentPixelSize {
                    size = (current.width, current.height)
                    break
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            return (display.displayID,
                    evenDimension(Double(size.0) * scale),
                    evenDimension(Double(size.1) * scale))

        case .mirror:
            let displayID = CGMainDisplayID()
            let mode = CGDisplayCopyDisplayMode(displayID)
            let sourceWidth = Double(mode?.pixelWidth ?? 1920)
            let sourceHeight = Double(mode?.pixelHeight ?? 1080)
            // Keep the Mac's aspect ratio; never upscale beyond the source.
            let fit = min(Double(screenWidth) / sourceWidth, Double(screenHeight) / sourceHeight, 1) * scale
            return (displayID, evenDimension(sourceWidth * fit), evenDimension(sourceHeight * fit))
        }
    }

    // MARK: - Frames in

    /// frameQueue. The newest screen image always replaces a waiting one.
    private func admit(_ pixelBuffer: CVPixelBuffer) {
        if pendingFrame != nil {
            lock.lock(); skippedTotal += 1; skippedThisSecond += 1; lock.unlock()
        }
        pendingFrame = pixelBuffer
        lastFrame = pixelBuffer
        drain()
    }

    /// frameQueue. Encodes the pending frame if the link has room.
    private func drain() {
        guard let pixelBuffer = pendingFrame else { return }

        lock.lock()
        guard !stopped, let encoder else { lock.unlock(); return }
        let now = ProcessInfo.processInfo.systemUptime
        let inFlight = framesAwaitingEncoder + Int(lastSentFrame &- lastAckedFrame)
        var forceKeyframe = false
        if inFlight >= maxFramesInFlight {
            guard now - lastProgress > 1.5 else { lock.unlock(); return }
            // No acknowledgement for 1.5 s: assume frames were lost, resync.
            lastAckedFrame = lastSentFrame
            framesAwaitingEncoder = 0
            sendTimes.removeAll()
            lastProgress = now
            forceKeyframe = true
        }
        framesAwaitingEncoder += 1
        lock.unlock()

        pendingFrame = nil
        if forceKeyframe { encoder.requestKeyframe() }
        // Host-clock timestamps always increase, even when re-encoding a frame.
        let submitted = encoder.encode(pixelBuffer, presentationTime: CMClockGetTime(CMClockGetHostTimeClock()))
        if !submitted {
            lock.lock(); framesAwaitingEncoder = max(0, framesAwaitingEncoder - 1); lock.unlock()
        }
    }

    // MARK: - Frames out

    /// VideoToolbox thread, in order.
    private func handleEncoded(_ frame: VideoEncoder.EncodedFrame?) {
        lock.lock()
        framesAwaitingEncoder = max(0, framesAwaitingEncoder - 1)
        guard let frame, !stopped else { lock.unlock(); return }
        lastSentFrame &+= 1
        let number = lastSentFrame
        sendTimes[number] = ProcessInfo.processInfo.systemUptime
        framesThisSecond += 1
        bytesThisSecond += frame.data.count
        let format = frame.isKeyframe ? currentFormat(frame) : nil
        let session = self.session
        lock.unlock()

        if let format, let json = try? WireCoding.encode(format) {
            try? session.sendSealedWithoutWaiting(.sealedVideoFormat, payload: json)
        }
        let micros = UInt64(max(0, CMTimeGetSeconds(frame.presentationTime)) * 1_000_000)
        var payload = VideoFrameHeader(frameNumber: number, streamID: streamID, timestampMicros: micros).encoded()
        payload.append(frame.data)
        try? session.sendSealedWithoutWaiting(.sealedVideoFrame, payload: payload,
                                              flags: frame.isKeyframe ? VideoFrameFlags.keyframe : 0)
    }

    /// Caller holds `lock`.
    private func currentFormat(_ frame: VideoEncoder.EncodedFrame) -> VideoFormat? {
        guard let sets = frame.parameterSets, !sets.isEmpty, let encoder else { return nil }
        return VideoFormat(streamID: streamID, codec: encoder.codec, width: width, height: height,
                           parameterSets: sets, nalUnitHeaderLength: frame.nalUnitHeaderLength)
    }

    // MARK: - Feedback from the Display (media queue)

    func acknowledge(frameNumber: UInt32) {
        lock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        // Ignore stale acks (wrap-safe comparison).
        if Int32(bitPattern: frameNumber &- lastAckedFrame) > 0 {
            lastAckedFrame = frameNumber
        }
        if let sentAt = sendTimes.removeValue(forKey: frameNumber) {
            let ms = (now - sentAt) * 1000
            latencyMs = latencyMs.map { $0 * 0.9 + ms * 0.1 } ?? ms
        }
        if sendTimes.count > 120 {
            sendTimes = sendTimes.filter { Int32(bitPattern: $0.key &- frameNumber) > 0 }
        }
        lastProgress = now
        lock.unlock()
        frameQueue.async { [weak self] in self?.drain() }
    }

    /// The Display lost sync. Re-send the current screen as a keyframe, even
    /// if nothing on screen is changing.
    func requestKeyframe() {
        lock.lock(); let encoder = self.encoder; lock.unlock()
        encoder?.requestKeyframe()
        frameQueue.async { [weak self] in
            guard let self else { return }
            if self.pendingFrame == nil { self.pendingFrame = self.lastFrame }
            self.drain()
        }
    }

    // MARK: - Stats + adaptive bitrate

    private func startStatsTimer() {
        let timer = DispatchSource.makeTimerSource(queue: frameQueue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.tick() }
        lock.lock(); statsTimer = timer; lock.unlock()
        timer.resume()
    }

    /// frameQueue, once per second.
    private func tick() {
        lock.lock()
        guard let encoder, !stopped else { lock.unlock(); return }
        let stats = StreamStats(codec: encoder.codec, width: width, height: height,
                                framesPerSecond: Double(framesThisSecond),
                                megabitsPerSecond: Double(bytesThisSecond) * 8 / 1_000_000,
                                latencyMs: latencyMs, skippedFrames: skippedTotal)
        // Simple adaptation: back off quickly when the link is struggling,
        // recover slowly when it has been calm for a while.
        let struggling = skippedThisSecond > 2 || (latencyMs ?? 0) > 120
        var newBitrate: Int?
        if struggling {
            calmSeconds = 0
            let reduced = max(2_000_000, currentBitrate * 3 / 4)
            if reduced < currentBitrate { newBitrate = reduced }
        } else {
            calmSeconds += 1
            if calmSeconds >= 5, currentBitrate < targetBitrate {
                newBitrate = min(targetBitrate, currentBitrate * 11 / 10)
                calmSeconds = 0
            }
        }
        if let newBitrate { currentBitrate = newBitrate }
        framesThisSecond = 0
        bytesThisSecond = 0
        skippedThisSecond = 0
        lock.unlock()

        if let newBitrate { encoder.updateBitrate(newBitrate) }
        drain()  // also recovers from a stall when the screen is idle
        DispatchQueue.main.async { [weak self] in self?.onStats?(stats) }
    }
}
#endif
