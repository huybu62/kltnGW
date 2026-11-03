import Foundation
import Combine
import Network

/// One object per app that the SwiftUI layer binds to. It owns discovery,
/// identity and trust; turns a radar tap into a connected `SecureSession`;
/// accepts incoming connections; and surfaces pairing-code prompts.
@MainActor
public final class ConnectionCoordinator: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case connecting(peerName: String)
        case awaitingPairing
        case connected
        case failed(String)
    }

    @Published public private(set) var phase: Phase = .idle
    /// Non-nil while the user should compare codes. Drive a sheet from it and
    /// answer with `respondToPairing(approved:)`.
    @Published public private(set) var pairingRequest: PairingRequest?
    @Published public private(set) var session: SecureSession?
    @Published public private(set) var activeLink: LinkType?
    /// Smoothed control-channel round-trip time in milliseconds.
    @Published public private(set) var roundTripMs: Double?
    /// The OS reports a better path (typically: a cable was just plugged
    /// in). The session moves to it automatically when we initiated it.
    @Published public private(set) var betterLinkAvailable = false
    /// True briefly while the session moves to a better link.
    @Published public private(set) var isSwitchingLink = false
    @Published public private(set) var trustedPeers: [TrustedPeer] = []
    /// Set if the Keychain was unusable and a temporary identity is in use.
    @Published public private(set) var identityWarning: String?

    public let role: PeerRole
    public let identity: DeviceIdentity
    public let trustStore: TrustStore
    public let discovery: DiscoveryService
    public private(set) var localDevice: DeviceInfo

    /// Receives video/input for the active session (set by the app).
    public var mediaSink: SessionMediaSink?

    /// Media is handled here, never on the main thread, so UI work can't
    /// delay frames.
    private let mediaQueue = DispatchQueue(label: "app.screenbridge.media", qos: .userInteractive)

    private var connectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var pendingApproval: (id: UUID, continuation: CheckedContinuation<Bool, Never>)?
    private let busy = AtomicFlag()
    private let activePeerID = LockedValue<String?>(nil)
    private var discoveryPausedForSession = false
    private var migrationTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var wiredMonitor: NWPathMonitor?
    private var knownWiredInterfaces: Set<String>?

    public init(role: PeerRole, identity: DeviceIdentity? = nil, trustStore: TrustStore = TrustStore()) {
        var warning: String?
        let resolvedIdentity: DeviceIdentity
        if let identity {
            resolvedIdentity = identity
        } else {
            do {
                resolvedIdentity = try DeviceIdentity.loadOrCreate()
            } catch {
                warning = "Couldn't access secure storage (\(error.localizedDescription)). "
                    + "Pairings will be forgotten when the app quits."
                resolvedIdentity = DeviceIdentity.ephemeral()
            }
        }
        let device = DeviceInfo.current(role: role, identity: resolvedIdentity)

        self.role = role
        self.identity = resolvedIdentity
        self.trustStore = trustStore
        self.localDevice = device
        self.discovery = DiscoveryService(localDevice: device)
        self.identityWarning = warning
        self.trustedPeers = trustStore.all

        discovery.onIncomingConnection = { [weak self] connection in
            self?.acceptIncoming(connection)
        }
        trustStore.onChange = { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.trustedPeers = self.trustStore.all
            }
        }
    }

    // MARK: - Lifecycle

    public func start() { discovery.start() }
    public func stop() {
        disconnect()
        discoveryPausedForSession = false
        discovery.stop()
    }

    /// Call from `scenePhase == .active` on iPadOS (listeners die in background).
    public func appDidBecomeActive() {
        // While connected, discovery stays paused (see `adopt`).
        if session == nil { discovery.restart() }
    }

    /// Rename this device everywhere (TXT record, future handshakes).
    public func rename(to name: String) {
        UserDefaults.standard.set(name, forKey: DeviceInfo.customNameDefaultsKey)
        localDevice = DeviceInfo.current(role: role, identity: identity)
        discovery.updateLocalDevice(localDevice)
    }

    // MARK: - Outgoing

    /// The "1-click connect" from the radar.
    public func connect(to peer: DiscoveredPeer) {
        startOutgoing(name: peer.name) { try await PeerConnector.connect(to: peer) }
    }

    /// Manual fallback when Bonjour is blocked on the network.
    public func connect(host: String, port: UInt16) {
        startOutgoing(name: host) { try await PeerConnector.connect(host: host, port: port) }
    }

    private func startOutgoing(name: String, open: @escaping @Sendable () async throws -> PeerConnection) {
        guard session == nil, connectTask == nil else { return }
        phase = .connecting(peerName: name)
        busy.set(true)
        connectTask = Task { [weak self] in
            do {
                let connection = try await open()
                guard let self else { connection.cancel(); return }
                let session = try await SessionHandshake.initiate(over: connection, config: self.handshakeConfiguration())
                self.connectTask = nil
                self.adopt(session)
            } catch {
                guard let self else { return }
                self.connectTask = nil
                self.busy.set(self.session != nil)
                if Task.isCancelled || error is CancellationError {
                    self.phase = .idle
                } else {
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Incoming

    private func acceptIncoming(_ nwConnection: NWConnection) {
        let connection = PeerConnection(connection: nwConnection)
        let config = handshakeConfiguration()
        Task { [weak self] in
            do {
                try await withTimeout(5) { try await connection.start() }
                let session = try await SessionHandshake.respond(over: connection, config: config)
                guard let self else { connection.cancel(); return }
                if let current = self.session, current.peer.id == session.peer.id {
                    // Our peer moved to a better link or reconnected after a
                    // drop we haven't noticed yet: swap sessions seamlessly.
                    self.replaceSession(with: session)
                    return
                }
                guard self.session == nil, self.connectTask == nil, self.reconnectTask == nil else {
                    // Both sides clicked "Connect" at the same moment; keep ours.
                    await session.close(reason: "busy")
                    return
                }
                self.adopt(session)
            } catch {
                connection.cancel()
                guard let self else { return }
                if case HandshakeError.busy = error { return }  // stranger bounced; leave our state alone
                if self.session == nil, self.connectTask == nil {
                    self.busy.set(false)
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Pairing prompt

    public func respondToPairing(approved: Bool) {
        guard let pending = pendingApproval else { return }
        resolvePairing(id: pending.id, approved: approved)
    }

    private func requestApproval(_ request: PairingRequest) async -> Bool {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                    return
                }
                if let previous = pendingApproval {  // only one prompt at a time
                    resolvePairing(id: previous.id, approved: false)
                }
                pendingApproval = (request.id, continuation)
                pairingRequest = request
                phase = .awaitingPairing
            }
        } onCancel: {
            // Peer declined/disconnected: dismiss the sheet.
            Task { @MainActor [weak self] in self?.resolvePairing(id: request.id, approved: false) }
        }
    }

    private func resolvePairing(id: UUID, approved: Bool) {
        guard let pending = pendingApproval, pending.id == id else { return }
        pendingApproval = nil
        pairingRequest = nil
        if case .awaitingPairing = phase { phase = .connecting(peerName: "") }
        pending.continuation.resume(returning: approved)
    }

    private func handshakeConfiguration() -> HandshakeConfiguration {
        let busy = self.busy
        let activePeerID = self.activePeerID
        return HandshakeConfiguration(
            identity: identity,
            localDevice: localDevice,
            trustStore: trustStore,
            approvePairing: { [weak self] request in
                guard let self else { return false }
                return await self.requestApproval(request)
            },
            isBusy: { peer in busy.value && activePeerID.value != peer.id })
    }

    // MARK: - Session

    private func adopt(_ session: SecureSession) {
        self.session = session
        activePeerID.value = session.peer.id
        busy.set(true)
        discovery.setBusy(true)
        // Pause Bonjour while connected. Browsing with peer-to-peer enabled
        // keeps Apple's device-to-device Wi-Fi (AWDL) active, which makes the
        // Wi-Fi radio hop channels and adds tens of ms of latency to the
        // stream. The established connection is unaffected.
        if discovery.isRunning {
            discovery.stop()
            discoveryPausedForSession = true
        }
        phase = .connected
        activeLink = session.link
        roundTripMs = nil
        betterLinkAvailable = false

        session.connection.onLinkChange = { [weak self] link in self?.activeLink = link }
        session.connection.onBetterPathAvailable = { [weak self] better in
            self?.betterLinkAvailable = better
            if better { self?.switchLink(.upgrade) }
        }
        session.connection.onViabilityChange = { [weak self] viable in
            // A cable was pulled: move to Wi-Fi now rather than waiting for
            // TCP keepalive to declare the connection dead.
            if !viable { self?.switchLink(.failover) }
        }
        if session.role == .initiator { startWiredMonitor() }
        let sink = mediaSink
        sink?.sessionStarted(session)  // before any media can arrive
        session.startReceiving(on: mediaQueue) { @Sendable [weak self, weak session] event in
            switch event {
            case .message(let type, let payload, let flags):
                sink?.received(type: type, payload: payload, flags: flags)
            case .control(let message):
                sink?.receivedControl(message)
            case .roundTrip, .closed:
                let current = session
                Task { @MainActor [weak self] in
                    guard let self, let current, current === self.session else { return }
                    self.handle(event)
                }
            }
        }
        pingTask = Task { [weak self, weak session] in
            var pings = 0
            while !Task.isCancelled {
                guard let session else { return }
                try? await session.ping()
                pings += 1
                // Every ~4 s on wireless, check whether a cable path appeared
                // that the OS didn't announce (the iPad's USB link can show up
                // a few seconds after plugging in).
                if pings % 2 == 0, session.link.isWired == false { self?.switchLink(.upgrade) }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    // MARK: - Link switching & reconnection

    private enum LinkSwitch { case upgrade, failover }

    /// Opens a new session over a better (or, after a cable pull, any working)
    /// path, then swaps it in. Only the side that initiated knows the
    /// peer's Bonjour name; the other side accepts the new session.
    private func switchLink(_ kind: LinkSwitch) {
        guard let session, session.role == .initiator,
              migrationTask == nil, reconnectTask == nil else { return }
        let current = session.link
        switch kind {
        case .upgrade: guard current != .thunderbolt else { return }
        case .failover: guard current.isWired else { return }  // Wi-Fi blips recover on their own
        }
        let endpoint = PeerConnector.unpinned(session.connection.remoteEndpoint)
        if kind == .failover { isSwitchingLink = true }

        migrationTask = Task { [weak self] in
            // Give a fresh interface a moment to get an address.
            try? await Task.sleep(nanoseconds: kind == .upgrade ? 300_000_000 : 100_000_000)
            let connection: PeerConnection?
            switch kind {
            case .upgrade: connection = await PeerConnector.upgrade(to: endpoint, betterThan: current)
            case .failover: connection = try? await PeerConnector.reconnect(to: endpoint)
            }
            guard let self else { connection?.cancel(); return }
            defer {
                self.migrationTask = nil
                self.isSwitchingLink = false
            }
            guard let connection else { return }
            guard self.session === session else { connection.cancel(); return }
            guard let replacement = try? await SessionHandshake.initiate(
                over: connection, config: self.handshakeConfiguration()) else { return }
            guard self.session === session else {
                await replacement.close(reason: "superseded")
                return
            }
            self.replaceSession(with: replacement)
        }
    }

    /// Swaps the active session without going through "disconnected": the
    /// Host keeps its virtual display and stream, the Display just resyncs.
    private func replaceSession(with replacement: SecureSession) {
        let old = session
        if let old { Self.detachCallbacks(old) }
        mediaSink?.sessionEnded(willReconnect: true)
        pingTask?.cancel()
        pingTask = nil
        session = nil
        adopt(replacement)
        if let old {
            Task { await old.close(reason: "switched link") }
        }
    }

    /// Watches for a new wired interface (cable plugged in) while connected.
    private func startWiredMonitor() {
        wiredMonitor?.cancel()
        knownWiredInterfaces = nil
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let wired = Set(path.availableInterfaces.filter { LinkType(interface: $0).isWired }.map(\.name))
            Task { @MainActor [weak self] in self?.wiredInterfacesChanged(wired) }
        }
        monitor.start(queue: .main)
        wiredMonitor = monitor
    }

    private func wiredInterfacesChanged(_ wired: Set<String>) {
        defer { knownWiredInterfaces = wired }
        guard let known = knownWiredInterfaces else { return }  // first report = baseline
        if !wired.subtracting(known).isEmpty { switchLink(.upgrade) }
    }

    /// The connection dropped unexpectedly and we initiated it: keep trying
    /// for ~30 s (Wi-Fi roaming, Mac waking up, cable pulled…).
    private func startReconnect(to endpoint: NWEndpoint, peerName: String) {
        phase = .connecting(peerName: "\(peerName) (reconnecting)")
        busy.set(true)
        reconnectTask = Task { [weak self] in
            for _ in 0..<10 {
                if Task.isCancelled { return }
                if let connection = try? await PeerConnector.reconnect(to: endpoint) {
                    guard let self else { connection.cancel(); return }
                    if let session = try? await SessionHandshake.initiate(
                        over: connection, config: self.handshakeConfiguration()) {
                        self.reconnectTask = nil
                        self.adopt(session)
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            self.reconnectTask = nil
            self.busy.set(false)
            self.phase = .failed("Lost the connection to \(peerName) and couldn't reconnect.")
        }
    }

    private func handle(_ event: SessionEvent) {
        switch event {
        case .roundTrip(let seconds):
            let ms = seconds * 1000
            roundTripMs = roundTripMs.map { $0 * 0.8 + ms * 0.2 } ?? ms
        case .closed(let error):
            let lost = session
            // Only network failures count. A peer that closed cleanly (app
            // quit, Disconnect pressed) must not be reconnected to.
            let unexpected = error.map(Self.isNetworkFailure) ?? false
            // On an unexpected drop the initiator reconnects, so both sides
            // keep their media state for a while.
            teardownSession(willReconnect: unexpected)
            if unexpected, let lost, lost.role == .initiator {
                startReconnect(to: PeerConnector.unpinned(lost.connection.remoteEndpoint), peerName: lost.peer.name)
            } else if let error, unexpected {
                phase = .failed("Disconnected: \(error.localizedDescription)")
            } else {
                phase = .idle
            }
        case .message, .control:
            break  // routed to mediaSink on the media queue
        }
    }

    public func disconnect() {
        connectTask?.cancel()
        connectTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        migrationTask?.cancel()
        migrationTask = nil
        isSwitchingLink = false
        if let pending = pendingApproval { resolvePairing(id: pending.id, approved: false) }
        if let session {
            Task { await session.close(reason: "user") }
        }
        teardownSession()
        phase = .idle
    }

    private static func isNetworkFailure(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let connectionError = error as? PeerConnectionError {
            switch connectionError {
            case .closedByPeer, .cancelled: return false
            default: return true
            }
        }
        return true
    }

    /// Stops a retired connection's events from steering the current session.
    private static func detachCallbacks(_ session: SecureSession) {
        session.connection.onLinkChange = nil
        session.connection.onBetterPathAvailable = nil
        session.connection.onViabilityChange = nil
    }

    private func teardownSession(willReconnect: Bool = false) {
        if let session { Self.detachCallbacks(session) }
        if session != nil { mediaSink?.sessionEnded(willReconnect: willReconnect) }
        pingTask?.cancel()
        pingTask = nil
        wiredMonitor?.cancel()
        wiredMonitor = nil
        session = nil
        activePeerID.value = nil
        activeLink = nil
        roundTripMs = nil
        betterLinkAvailable = false
        busy.set(connectTask != nil)
        discovery.setBusy(false)
        if discoveryPausedForSession {
            discoveryPausedForSession = false
            discovery.start()
        }
    }

    // MARK: - Trust management

    public func forget(_ peer: TrustedPeer) { trustStore.revoke(id: peer.id) }

    public func setAutoAccept(_ autoAccept: Bool, for peer: TrustedPeer) {
        var updated = peer
        updated.autoAccept = autoAccept
        trustStore.trust(updated)
    }

    public func isTrusted(_ peer: DiscoveredPeer) -> Bool {
        trustStore.peer(id: peer.id) != nil
    }
}

/// Lock-protected value readable from any thread.
final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

/// Lock-protected Bool readable from any thread (the responder's busy check
/// runs off the main actor).
final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return _value }
    func set(_ newValue: Bool) { lock.lock(); _value = newValue; lock.unlock() }
}
