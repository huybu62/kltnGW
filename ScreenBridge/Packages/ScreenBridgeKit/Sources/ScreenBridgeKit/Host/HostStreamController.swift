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
        /// Screen Recording permission is missing (see `openScreenRecordingSettings`).
        case needsScreenRecordingPermission
        case failed(String)
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var stats: StreamStats?

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

    private static let modeKey = "ScreenBridge.streamMode"
    private static let qualityKey = "ScreenBridge.streamQuality"
    private let defaults: UserDefaults

    private let lock = NSLock()
    private var session: SecureSession?
    private var streamer: HostStreamer?
    private var generation = 0

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Self.modeKey).flatMap(StreamMode.init(rawValue:)) ?? .extend
        quality = defaults.string(forKey: Self.qualityKey).flatMap(StreamQuality.init(rawValue:)) ?? .balanced
    }

    // MARK: SessionMediaSink

    public func sessionStarted(_ session: SecureSession) {
        lock.lock(); self.session = session; lock.unlock()
        restart()
    }

    public func sessionEnded() {
        let old = swap(session: nil, streamer: nil)
        state = .idle
        stats = nil
        if let old { Task { await old.stop(reason: "disconnected") } }
    }

    public func received(type: UInt8, payload: Data, flags: UInt16) {
        // Phase 3: pointer/keyboard input from the Display arrives here.
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
            HostStreamer(session: $0, peerDisplay: $0.peer.display, mode: mode, quality: quality)
        }
        self.streamer = streamer
        lock.unlock()

        guard let streamer else { return }
        state = .starting
        stats = nil
        streamer.onStats = { [weak self] stats in self?.stats = stats }
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
