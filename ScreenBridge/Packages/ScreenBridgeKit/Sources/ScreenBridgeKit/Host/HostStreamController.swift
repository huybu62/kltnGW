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

    /// One connected Display's stream.
    public struct DisplayStream: Identifiable, Equatable, Sendable {
        public let id: String        // the Display's device id
        public var name: String
        public var platform: DevicePlatform
        public var state: State
        public var stats: StreamStats?
    }

    /// Every connected Display (each gets its own extra screen in Extend).
    @Published public private(set) var streams: [DisplayStream] = []

    /// The first Display's state / stats (single-display conveniences).
    public var state: State { streams.first?.state ?? .idle }
    public var stats: StreamStats? { streams.first?.stats }
    /// Accessibility permission granted, so touches/Pencil from the
    /// Display can control this Mac.
    @Published public private(set) var canControlMac = InputInjector.isTrusted

    @Published public var mode: StreamMode {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: Self.modeKey)
            restartAll()
        }
    }

    @Published public var quality: StreamQuality {
        didSet {
            guard quality != oldValue else { return }
            defaults.set(quality.rawValue, forKey: Self.qualityKey)
            restartAll()
        }
    }

    @Published public var frameRate: StreamFrameRate {
        didSet {
            guard frameRate != oldValue else { return }
            defaults.set(frameRate.rawValue, forKey: Self.frameRateKey)
            restartAll()
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
            restartAll()
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
            restartAll()
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

    // Per Display (keyed by device id), guarded by `lock`.
    private let lock = NSLock()
    private var sessions: [String: SecureSession] = [:]
    private var streamers: [String: HostStreamer] = [:]
    private var generations: [String: Int] = [:]
    /// Streams kept alive after an unexpected disconnect (see `sessionEnded`).
    private var parked: [String: HostStreamer] = [:]
    // Main thread.
    private var parkTimers: [String: DispatchWorkItem] = [:]
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
        let id = session.peer.id
        parkTimers.removeValue(forKey: id)?.cancel()
        lock.lock()
        sessions[id] = session
        let parkedStreamer = parked.removeValue(forKey: id)
        lock.unlock()

        upsertStream(id: id) { stream in
            stream.name = session.peer.name
            stream.platform = session.peer.platform
        }
        refreshDisplayCapabilities()
        canControlMac = InputInjector.isTrusted
        lidClosedModeEnabled = LidClosedMode.isEnabled
        beginSharing()

        if let parkedStreamer {
            // Same Display came back (link switch / reconnect): continue its
            // stream; windows stay on its extra screen.
            parkedStreamer.attach(session)
            lock.lock(); streamers[id] = parkedStreamer; lock.unlock()
            setState(.streaming, for: id)
            return
        }
        restart(id)
    }

    public func sessionEnded(_ session: SecureSession, willReconnect: Bool) {
        let id = session.peer.id
        lock.lock()
        guard sessions[id] === session else { lock.unlock(); return }
        sessions[id] = nil
        let old = streamers.removeValue(forKey: id)
        generations[id, default: 0] += 1
        let anyoneLeft = !sessions.isEmpty
        lock.unlock()

        if !anyoneLeft { injector.releaseAll() }
        refreshDisplayCapabilities()
        guard let old else {
            removeStream(id)
            return
        }
        guard willReconnect else {
            removeStream(id)
            Task { await old.stop(reason: "disconnected") }
            return
        }
        lock.lock(); parked[id] = old; lock.unlock()
        setState(.reconnecting, for: id)
        setStats(nil, for: id)
        let work = DispatchWorkItem { [weak self] in
            guard let self, let parkedStreamer = self.takeParked(id) else { return }
            self.parkTimers[id] = nil
            self.removeStream(id)
            Task { await parkedStreamer.stop(reason: "disconnected") }
        }
        parkTimers[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reconnectGrace, execute: work)
    }

    /// Media queue (serial): touches / Pencil / keys from a Display, applied
    /// to that Display's screen.
    public func received(type: UInt8, payload: Data, flags: UInt16, from session: SecureSession) {
        guard MessageType(rawValue: type) == .sealedInput,
              let event = try? WireCoding.decode(InputEvent.self, from: payload) else { return }
        lock.lock(); let displayID = streamers[session.peer.id]?.displayID; lock.unlock()
        guard let displayID else { return }
        injector.submit(event, on: displayID)
    }

    public func receivedControl(_ message: ControlMessage, from session: SecureSession) {
        lock.lock(); let streamer = streamers[session.peer.id]; lock.unlock()
        switch message {
        case .frameAck(let number): streamer?.acknowledge(frameNumber: number)
        case .requestKeyframe: streamer?.requestKeyframe()
        default: break
        }
    }

    /// Opens the Accessibility setting needed for touch control.
    public func requestControlPermission() {
        InputInjector.requestTrust()
        InputInjector.openAccessibilitySettings()
    }

    // MARK: Control

    /// Re-attempts streaming (e.g. after granting Screen Recording permission).
    public func retry() { restartAll() }

    public func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Main thread. Applies new settings to every Display.
    private func restartAll() {
        lock.lock(); let ids = Array(sessions.keys); lock.unlock()
        for id in ids { restart(id) }
    }

    /// Main thread. (Re)starts one Display's stream with the current settings.
    private func restart(_ id: String) {
        lock.lock()
        guard let session = sessions[id] else { lock.unlock(); return }
        let old = streamers[id]
        generations[id, default: 0] += 1
        let myGeneration = generations[id] ?? 0
        let streamer = HostStreamer(
            session: session, peerDisplay: session.peer.display, mode: mode, quality: quality,
            frameRate: frameRate, sendsAudio: soundOnDisplay,
            // A Mac display has its own pointer over the window; only iPads draw one.
            localCursor: drawPointerOnDisplay && session.peer.platform != .mac)
        streamers[id] = streamer
        lock.unlock()

        setState(.starting, for: id)
        setStats(nil, for: id)
        streamer.onStats = { [weak self] stats in
            self?.setStats(stats, for: id)
            self?.canControlMac = InputInjector.isTrusted  // picks up a grant made in Settings
        }
        streamer.onFailure = { [weak self] error in self?.setState(.failed(error.localizedDescription), for: id) }

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
                guard let self, self.isCurrent(id, myGeneration) else { return }
                self.setState(outcome, for: id)
            }
            if outcome != .streaming {
                await streamer.stop(reason: "failed")
            }
        }
    }

    private func isCurrent(_ id: String, _ generation: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generations[id] == generation && streamers[id] != nil
    }

    private func takeParked(_ id: String) -> HostStreamer? {
        lock.lock(); defer { lock.unlock() }
        return parked.removeValue(forKey: id)
    }

    // MARK: Published per-Display state (main thread)

    private func upsertStream(id: String, _ change: (inout DisplayStream) -> Void) {
        if let index = streams.firstIndex(where: { $0.id == id }) {
            change(&streams[index])
        } else {
            var stream = DisplayStream(id: id, name: "", platform: .unknown, state: .starting, stats: nil)
            change(&stream)
            streams.append(stream)
        }
    }

    private func setState(_ state: State, for id: String) {
        guard let index = streams.firstIndex(where: { $0.id == id }) else { return }
        streams[index].state = state
    }

    private func setStats(_ stats: StreamStats?, for id: String) {
        guard let index = streams.firstIndex(where: { $0.id == id }) else { return }
        streams[index].stats = stats
    }

    private func removeStream(_ id: String) {
        streams.removeAll { $0.id == id }
        if streams.isEmpty { endSharing() }
    }

    /// The best refresh rate any connected Display supports (for the picker).
    private func refreshDisplayCapabilities() {
        lock.lock()
        let rates = sessions.values.compactMap { $0.peer.display?.maxRefreshRate }
        lock.unlock()
        displayMaxRefreshRate = rates.max() ?? 60
    }
}
#endif
