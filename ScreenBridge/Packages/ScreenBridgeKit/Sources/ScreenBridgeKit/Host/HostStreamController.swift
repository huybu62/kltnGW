#if os(macOS)
import Foundation
import Combine
import AppKit

/// What the Host's menu-bar UI binds to: starts a stream when a Display
/// connects, restarts it when the user changes mode/quality, and reports
/// state and live stats. Plug into `ConnectionCoordinator.mediaSink`.
///
/// Published properties change on the main thread only.
public final class HostStreamController: ObservableObject, SessionMediaSink, @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case starting
        case streaming
        /// Connection dropped; keeping the extra display for a few seconds
        /// in case the Display comes back.
        case reconnecting
        /// Screen Recording permission is missing (see `openScreenRecordingSettings`).
        case needsScreenRecordingPermission
        case failed(String)
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var stats: StreamStats?
    /// Accessibility permission granted, so touches/Pencil from the
    /// Display can control this Mac.
    @Published public private(set) var canControlMac = InputInjector.isTrusted

    @Published public var mode: StreamMode {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: Self.modeKey)
            restart()
        }
    }

    @Published public var quality: StreamQuality {
        didSet {
            guard quality != oldValue else { return }
            defaults.set(quality.rawValue, forKey: Self.qualityKey)
            restart()
        }
    }

    @Published public var frameRate: StreamFrameRate {
        didSet {
            guard frameRate != oldValue else { return }
            defaults.set(frameRate.rawValue, forKey: Self.frameRateKey)
            restart()
        }
    }

    /// Highest refresh rate the connected Display supports (60 if unknown).
    @Published public private(set) var displayMaxRefreshRate = 60

    /// Play this Mac's sound on the Display.
    @Published public var soundOnDisplay: Bool {
        didSet {
            guard soundOnDisplay != oldValue else { return }
            defaults.set(soundOnDisplay, forKey: Self.soundKey)
            applyMute()
            restart()
        }
    }

    /// Mute this Mac's speakers while its sound plays on the Display.
    @Published public var muteMacWhileSharing: Bool {
        didSet {
            guard muteMacWhileSharing != oldValue else { return }
            defaults.set(muteMacWhileSharing, forKey: Self.muteKey)
            applyMute()
        }
    }

    /// Draw the pointer on the iPad itself instead of in the video: no lag
    /// when moving it, but it's always a plain arrow.
    @Published public var drawPointerOnDisplay: Bool {
        didSet {
            guard drawPointerOnDisplay != oldValue else { return }
            defaults.set(drawPointerOnDisplay, forKey: Self.pointerKey)
            restart()
        }
    }

    /// The Mac stays awake with its lid closed (see `LidClosedMode`).
    @Published public private(set) var lidClosedModeEnabled = LidClosedMode.isEnabled

    private static let pointerKey = "ScreenBridge.drawPointerOnDisplay"
    private static let soundKey = "ScreenBridge.soundOnDisplay"
    private static let muteKey = "ScreenBridge.muteMacWhileSharing"
    private var isSharing = false
    private var awakeAssertion: DisplaySleepAssertion?
    private var mutedByUs = false
    private var lidTimer: Timer?
    private var builtInWasActive = true

    private static let frameRateKey = "ScreenBridge.streamFrameRate"
    private static let modeKey = "ScreenBridge.streamMode"
    private static let qualityKey = "ScreenBridge.streamQuality"
    private let defaults: UserDefaults

    private let lock = NSLock()
    private var session: SecureSession?
    private var streamer: HostStreamer?
    private var generation = 0
    /// A stream kept alive after an unexpected disconnect (see `sessionEnded`).
    private var parkedStreamer: HostStreamer?
    private var parkTimer: DispatchWorkItem?
    private let injector = InputInjector()
    private static let reconnectGrace: TimeInterval = 20

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Self.modeKey).flatMap(StreamMode.init(rawValue:)) ?? .extend
        quality = defaults.string(forKey: Self.qualityKey).flatMap(StreamQuality.init(rawValue:)) ?? .balanced
        let savedRate = defaults.integer(forKey: Self.frameRateKey)
        frameRate = StreamFrameRate(rawValue: savedRate) ?? .fps60
        soundOnDisplay = defaults.object(forKey: Self.soundKey) as? Bool ?? true
        muteMacWhileSharing = defaults.object(forKey: Self.muteKey) as? Bool ?? true
        drawPointerOnDisplay = defaults.object(forKey: Self.pointerKey) as? Bool ?? true
    }

    // MARK: Lid closed, staying awake, sound

    /// Turns "use with the lid closed" on or off (asks for the admin password).
    public func setLidClosedMode(_ enabled: Bool) {
        LidClosedMode.setEnabled(enabled)
        lidClosedModeEnabled = LidClosedMode.isEnabled
        // With the lid closed only the extra display is visible.
        if lidClosedModeEnabled, mode == .mirror { mode = .extend }
    }

    /// Call when the app quits: give the Mac its speakers back.
    public func shutdown() {
        isSharing = false
        applyMute()
    }

    private func beginSharing() {
        guard !isSharing else { return }
        isSharing = true
        awakeAssertion = DisplaySleepAssertion(reason: "ScreenBridge is sharing the screen")
        builtInWasActive = BuiltInDisplay.isActive
        lidTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkLid()
        }
        applyMute()
    }

    private func endSharing() {
        guard isSharing else { return }
        isSharing = false
        awakeAssertion = nil
        lidTimer?.invalidate()
        lidTimer = nil
        applyMute()
    }

    /// Closing the lid turns the built-in screen off; Mirror would then show
    /// nothing, so switch to Extend (the extra display becomes the main one).
    private func checkLid() {
        let active = BuiltInDisplay.isActive
        if builtInWasActive, !active, mode == .mirror {
            mode = .extend
        }
        builtInWasActive = active
    }

    private func applyMute() {
        let shouldMute = isSharing && soundOnDisplay && muteMacWhileSharing
        if shouldMute, !mutedByUs, !SystemAudio.isMuted {
            SystemAudio.setMuted(true)
            mutedByUs = true
        } else if !shouldMute, mutedByUs {
            SystemAudio.setMuted(false)
            mutedByUs = false
        }
    }

    // MARK: SessionMediaSink

    public func sessionStarted(_ session: SecureSession) {
        parkTimer?.cancel()
        parkTimer = nil
        lock.lock()
        self.session = session
        let parked = parkedStreamer
        parkedStreamer = nil
        lock.unlock()
        displayMaxRefreshRate = session.peer.display?.maxRefreshRate ?? 60
        canControlMac = InputInjector.isTrusted
        lidClosedModeEnabled = LidClosedMode.isEnabled
        beginSharing()

        if let parked, parked.peerID == session.peer.id {
            // Same Display came back (link switch / reconnect): continue the
            // stream; windows stay on the extra display.
            parked.attach(session)
            lock.lock(); streamer = parked; lock.unlock()
            state = .streaming
            return
        }
        if let parked { Task { await parked.stop(reason: "replaced") } }
        restart()
    }

    public func sessionEnded(willReconnect: Bool) {
        injector.releaseAll()
        let old = swap(session: nil, streamer: nil)
        stats = nil
        guard let old else {
            state = .idle
            endSharing()
            return
        }
        guard willReconnect else {
            state = .idle
            endSharing()
            Task { await old.stop(reason: "disconnected") }
            return
        }
        lock.lock(); parkedStreamer = old; lock.unlock()
        state = .reconnecting
        let work = DispatchWorkItem { [weak self] in
            guard let self, let parked = self.takeParked() else { return }
            self.state = .idle
            self.endSharing()
            Task { await parked.stop(reason: "disconnected") }
        }
        parkTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reconnectGrace, execute: work)
    }

    /// Media queue (serial): touches / Pencil / mouse from the Display.
    public func received(type: UInt8, payload: Data, flags: UInt16) {
        guard MessageType(rawValue: type) == .sealedInput,
              let event = try? WireCoding.decode(InputEvent.self, from: payload) else { return }
        lock.lock(); let displayID = streamer?.displayID; lock.unlock()
        guard let displayID else { return }
        injector.submit(event, on: displayID)
    }

    /// Opens the Accessibility setting needed for touch control.
    public func requestControlPermission() {
        InputInjector.requestTrust()
        InputInjector.openAccessibilitySettings()
    }

    private func takeParked() -> HostStreamer? {
        lock.lock(); defer { lock.unlock() }
        let parked = parkedStreamer
        parkedStreamer = nil
        return parked
    }

    public func receivedControl(_ message: ControlMessage) {
        lock.lock(); let streamer = self.streamer; lock.unlock()
        switch message {
        case .frameAck(let number): streamer?.acknowledge(frameNumber: number)
        case .requestKeyframe: streamer?.requestKeyframe()
        default: break
        }
    }

    // MARK: Control

    /// Re-attempts streaming (e.g. after granting Screen Recording permission).
    public func retry() { restart() }

    public func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Main thread.
    private func restart() {
        lock.lock()
        let session = self.session
        let old = self.streamer
        generation += 1
        let myGeneration = generation
        let streamer = session.map {
            HostStreamer(session: $0, peerDisplay: $0.peer.display, mode: mode, quality: quality,
                         frameRate: frameRate, sendsAudio: soundOnDisplay,
                         // A Mac display has its own pointer over the window; only iPads draw one.
                         localCursor: drawPointerOnDisplay && $0.peer.platform != .mac)
        }
        self.streamer = streamer
        lock.unlock()

        guard let streamer else { return }
        state = .starting
        stats = nil
        streamer.onStats = { [weak self] stats in
            self?.stats = stats
            self?.canControlMac = InputInjector.isTrusted  // picks up a grant made in Settings
        }
        streamer.onFailure = { [weak self] error in self?.state = .failed(error.localizedDescription) }

        Task { [weak self] in
            await old?.stop(reason: "restarting")
            let outcome: State
            do {
                try await streamer.start()
                outcome = .streaming
            } catch HostStreamer.StreamError.screenRecordingDenied {
                outcome = .needsScreenRecordingPermission
            } catch {
                outcome = .failed(error.localizedDescription)
            }
            await MainActor.run { [weak self] in
                guard let self, self.isCurrent(myGeneration) else { return }
                self.state = outcome
            }
            if outcome != .streaming {
                await streamer.stop(reason: "failed")
            }
        }
    }

    private func isCurrent(_ generation: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generation == self.generation
    }

    private func swap(session: SecureSession?, streamer: HostStreamer?) -> HostStreamer? {
        lock.lock(); defer { lock.unlock() }
        let old = self.streamer
        self.session = session
        self.streamer = streamer
        generation += 1
        return old
    }
}
#endif
