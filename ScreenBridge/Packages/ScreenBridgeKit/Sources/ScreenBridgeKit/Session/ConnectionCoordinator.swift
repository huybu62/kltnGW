import Foundation
import Combine
import Network

/// One object per app that the SwiftUI layer binds to. It owns discovery,
/// identity and trust; turns a tap on a nearby device into a connected
/// `SecureSession`; accepts incoming connections; and surfaces pairing-code
/// prompts.
///
/// A Host can be connected to up to `maxConnections` Displays at once (one
/// extended screen each). Every connection has its own link monitoring,
/// cable hand-over and automatic reconnection.
@MainActor
public final class ConnectionCoordinator: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case connecting(peerName: String)
        case awaitingPairing
        case connected
        case failed(String)
    }

    /// The latest operation (connecting, pairing, an error…); `.connected`
    /// once it succeeded. Use `connections` for what is connected right now.
    @Published public private(set) var phase: Phase = .idle
    /// Non-nil while the user should compare codes. Drive a sheet from it and
    /// answer with `respondToPairing(approved:)`.
    @Published public private(set) var pairingRequest: PairingRequest?
    /// Every connected device, in the order they connected.
    @Published public private(set) var connections: [SecureSession] = []
    /// Per device (by peer id): the link in use.
    @Published public private(set) var links: [String: LinkType] = [:]
    /// Per device: smoothed control-channel round-trip time in milliseconds.
    @Published public private(set) var roundTrips: [String: Double] = [:]
    /// Devices for which the OS reports a better path (a cable was plugged in).
    @Published public private(set) var betterLinks: Set<String> = []
    /// Devices whose session is moving to another link right now.
    @Published public private(set) var switchingLinks: Set<String> = []
    @Published public private(set) var trustedPeers: [TrustedPeer] = []
    /// Set if the Keychain was unusable and a temporary identity is in use.
    @Published public private(set) var identityWarning: String?

    /// How many Displays a Host may drive at once (1 or 2). Always 1 for a Display.
    @Published public var maxConnections: Int {
        didSet {
            let clamped = role == .host ? min(max(maxConnections, 1), Self.connectionLimit) : 1
            if clamped != maxConnections { maxConnections = clamped; return }
            if role == .host { UserDefaults.standard.set(clamped, forKey: Self.maxConnectionsKey) }
            updateCapacity()
        }
    }

    public static let connectionLimit = 2
    private static let maxConnectionsKey = "ScreenBridge.maxDisplays"

    // MARK: Single-connection conveniences (the first connection)

    public var session: SecureSession? { connections.first }
    public var isConnected: Bool { !connections.isEmpty }
    public var activeLink: LinkType? { session.flatMap { links[$0.peer.id] } }
    public var roundTripMs: Double? { session.flatMap { roundTrips[$0.peer.id] } }
    public var betterLinkAvailable: Bool { session.map { betterLinks.contains($0.peer.id) } ?? false }
    public var isSwitchingLink: Bool { !switchingLinks.isEmpty }

    /// True if another device can be connected now.
    public var canConnectMore: Bool { connectTask == nil && connections.count < maxConnections }

    public func isConnected(to peerID: String) -> Bool { connection(for: peerID) != nil }

    public let role: PeerRole
    public let identity: DeviceIdentity
    public let trustStore: TrustStore
    public let discovery: DiscoveryService
    public private(set) var localDevice: DeviceInfo

    /// Receives video/audio/input for every session (set by the app).
    public var mediaSink: SessionMediaSink?

    /// Media is handled here, never on the main thread, so UI work can't
    /// delay frames.
    private let mediaQueue = DispatchQueue(label: "app.screenbridge.media", qos: .userInteractive)

    /// Per-connection background work.
    private final class Slot {
        var pingTask: Task<Void, Never>?
        var migrationTask: Task<Void, Never>?
        var wiredMonitor: NWPathMonitor?
        var knownWiredInterfaces: Set<String>?

        func cancel() {
            pingTask?.cancel()
            migrationTask?.cancel()
            wiredMonitor?.cancel()
        }
    }

    private var slots: [String: Slot] = [:]
    private var connectTask: Task<Void, Never>?
    private var reconnectTasks: [String: Task<Void, Never>] = [:]
    private var pendingApproval: (id: UUID, continuation: CheckedContinuation<Bool, Never>)?
    /// No room for another device (read by the responder's busy check off the main actor).
    private let atCapacity = AtomicFlag()
    private let activePeerIDs = LockedValue<Set<String>>([])
    private var discoveryPausedForSessions = false

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
        let saved = UserDefaults.standard.integer(forKey: Self.maxConnectionsKey)
        self.maxConnections = role == .host ? min(max(saved, 1), Self.connectionLimit) : 1

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
        discoveryPausedForSessions = false
        discovery.stop()
    }

    /// Call from `scenePhase == .active` on iPadOS (listeners die in background).
    public func appDidBecomeActive() {
        // While connected, discovery may be paused on purpose (see `updateCapacity`).
        if connections.isEmpty { discovery.restart() }
    }

    /// Rename this device everywhere (TXT record, future handshakes).
    public func rename(to name: String) {
        UserDefaults.standard.set(name, forKey: DeviceInfo.customNameDefaultsKey)
        localDevice = DeviceInfo.current(role: role, identity: identity)
        discovery.updateLocalDevice(localDevice)
    }

    /// Clears an error message without touching the connections.
    public func dismissError() {
        phase = isConnected ? .connected : .idle
    }

    // MARK: - Outgoing

    /// The "1-click connect" from the list of nearby devices.
    public func connect(to peer: DiscoveredPeer) {
        guard !isConnected(to: peer.id) else { return }
        startOutgoing(name: peer.name) { try await PeerConnector.connect(to: peer) }
    }

    /// Manual fallback when Bonjour is blocked on the network.
    public func connect(host: String, port: UInt16) {
        startOutgoing(name: host) { try await PeerConnector.connect(host: host, port: port) }
    }

    private func startOutgoing(name: String, open: @escaping @Sendable () async throws -> PeerConnection) {
        guard canConnectMore else { return }
        phase = .connecting(peerName: name)
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
                self.updateCapacity()
                if Task.isCancelled || error is CancellationError {
                    self.phase = self.isConnected ? .connected : .idle
                } else {
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
        updateCapacity()
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
                if let current = self.connection(for: session.peer.id) {
                    // That device moved to a better link or reconnected after a
                    // drop we haven't noticed yet: swap sessions seamlessly.
                    self.replace(current, with: session)
                    return
                }
                let pending = self.connectTask == nil ? 0 : 1
                guard self.connections.count + pending < self.maxConnections,
                      self.reconnectTasks[session.peer.id] == nil else {
                    // No room (or both sides clicked "Connect" at once; keep ours).
                    await session.close(reason: "busy")
                    return
                }
                self.adopt(session)
            } catch {
                connection.cancel()
                guard let self else { return }
                if case HandshakeError.busy = error { return }  // stranger bounced; leave our state alone
                if !self.isConnected, self.connectTask == nil {
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
        let atCapacity = self.atCapacity
        let activePeerIDs = self.activePeerIDs
        return HandshakeConfiguration(
            identity: identity,
            localDevice: localDevice,
            trustStore: trustStore,
            approvePairing: { [weak self] request in
                guard let self else { return false }
                return await self.requestApproval(request)
            },
            // A device we're already connected to may always come back
            // (link switch, reconnect); others only while there's room.
            isBusy: { peer in atCapacity.value && !activePeerIDs.value.contains(peer.id) })
    }

    // MARK: - Capacity

    private func connection(for peerID: String) -> SecureSession? {
        connections.first { $0.peer.id == peerID }
    }

    /// Recomputes "busy" and pauses discovery once no more devices can join.
    /// Browsing with peer-to-peer enabled keeps Apple's device-to-device
    /// Wi-Fi (AWDL) active, which makes the Wi-Fi radio hop channels and adds
    /// tens of ms of latency to the stream; established connections are
    /// unaffected by pausing it.
    private func updateCapacity() {
        let inFlight = (connectTask == nil ? 0 : 1) + reconnectTasks.count
        atCapacity.set(connections.count + inFlight >= maxConnections)
        activePeerIDs.value = Set(connections.map(\.peer.id))
        let full = !connections.isEmpty && connections.count >= maxConnections
        discovery.setBusy(full)
        if full {
            if discovery.isRunning {
                discovery.stop()
                discoveryPausedForSessions = true
            }
        } else if discoveryPausedForSessions {
            discoveryPausedForSessions = false
            discovery.start()
        }
    }

    // MARK: - Sessions

    private func adopt(_ session: SecureSession) {
        let id = session.peer.id
        if let existing = connection(for: id) {
            replace(existing, with: session)
            return
        }
        connections.append(session)
        links[id] = session.link
        roundTrips[id] = nil
        betterLinks.remove(id)
        let slot = Slot()
        slots[id] = slot
        phase = .connected
        updateCapacity()

        session.connection.onLinkChange = { [weak self] link in self?.links[id] = link }
        session.connection.onBetterPathAvailable = { [weak self] better in
            guard let self else { return }
            if better {
                self.betterLinks.insert(id)
                self.switchLink(.upgrade, peerID: id)
            } else {
                self.betterLinks.remove(id)
            }
        }
        session.connection.onViabilityChange = { [weak self] viable in
            // A cable was pulled: move to Wi-Fi now rather than waiting for
            // TCP keepalive to declare the connection dead.
            if !viable { self?.switchLink(.failover, peerID: id) }
        }
        if session.role == .initiator { startWiredMonitor(for: id) }

        let sink = mediaSink
        sink?.sessionStarted(session)  // before any media can arrive
        session.startReceiving(on: mediaQueue) { @Sendable [weak self, weak session] event in
            guard let session else { return }
            switch event {
            case .message(let type, let payload, let flags):
                sink?.received(type: type, payload: payload, flags: flags, from: session)
            case .control(let message):
                sink?.receivedControl(message, from: session)
            case .roundTrip, .closed:
                Task { @MainActor [weak self] in self?.handle(event, for: session) }
            }
        }

        slot.pingTask = Task { [weak self, weak session] in
            var pings = 0
            while !Task.isCancelled {
                guard let session else { return }
                try? await session.ping()
                pings += 1
                // Every ~4 s on wireless, check whether a cable path appeared
                // that the OS didn't announce (the iPad's USB link can show up
                // a few seconds after plugging in).
                if pings % 2 == 0, session.link.isWired == false { self?.switchLink(.upgrade, peerID: id) }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    /// Swaps one device's session without going through "disconnected": the
    /// Host keeps that Display's virtual screen and stream, the Display just resyncs.
    private func replace(_ old: SecureSession, with replacement: SecureSession) {
        teardown(old, willReconnect: true, updatingCapacity: false)
        adopt(replacement)
        Task { await old.close(reason: "switched link") }
    }

    private func handle(_ event: SessionEvent, for session: SecureSession) {
        let id = session.peer.id
        guard connection(for: id) === session else { return }  // a retired session
        switch event {
        case .roundTrip(let seconds):
            let ms = seconds * 1000
            roundTrips[id] = roundTrips[id].map { $0 * 0.8 + ms * 0.2 } ?? ms
        case .closed(let error):
            // Only network failures count. A peer that closed cleanly (app
            // quit, Disconnect pressed) must not be reconnected to.
            let unexpected = error.map(Self.isNetworkFailure) ?? false
            // On an unexpected drop the initiator reconnects, so both sides
            // keep their media state for a while.
            teardown(session, willReconnect: unexpected)
            if unexpected, session.role == .initiator {
                startReconnect(to: PeerConnector.unpinned(session.connection.remoteEndpoint), peer: session.peer)
            } else if let error, unexpected {
                phase = .failed("Disconnected from \(session.peer.name): \(error.localizedDescription)")
            }
        case .message, .control:
            break  // routed to mediaSink on the media queue
        }
    }

    /// Disconnects every device.
    public func disconnect() {
        connectTask?.cancel()
        connectTask = nil
        for task in reconnectTasks.values { task.cancel() }
        reconnectTasks.removeAll()
        if let pending = pendingApproval { resolvePairing(id: pending.id, approved: false) }
        for session in connections {
            Task { await session.close(reason: "user") }
            teardown(session, willReconnect: false, updatingCapacity: false)
        }
        updateCapacity()
        phase = .idle
    }

    /// Disconnects one device.
    public func disconnect(peerID: String) {
        reconnectTasks.removeValue(forKey: peerID)?.cancel()
        if let session = connection(for: peerID) {
            Task { await session.close(reason: "user") }
            teardown(session, willReconnect: false)
        } else {
            updateCapacity()
        }
        phase = isConnected ? .connected : .idle
    }

    private func teardown(_ session: SecureSession, willReconnect: Bool, updatingCapacity: Bool = true) {
        let id = session.peer.id
        Self.detachCallbacks(session)
        slots.removeValue(forKey: id)?.cancel()
        connections.removeAll { $0 === session }
        links[id] = nil
        roundTrips[id] = nil
        betterLinks.remove(id)
        switchingLinks.remove(id)
        mediaSink?.sessionEnded(session, willReconnect: willReconnect)
        if updatingCapacity { updateCapacity() }
        if connections.isEmpty, phase == .connected { phase = .idle }
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

    // MARK: - Link switching & reconnection

    private enum LinkSwitch { case upgrade, failover }

    /// Opens a new session to the same device over a better (or, after a
    /// cable pull, any working) path, then swaps it in. Only the side that
    /// initiated knows the peer's Bonjour name; the other side accepts the
    /// new session.
    private func switchLink(_ kind: LinkSwitch, peerID: String) {
        guard let session = connection(for: peerID), session.role == .initiator,
              let slot = slots[peerID], slot.migrationTask == nil, reconnectTasks[peerID] == nil else { return }
        let current = session.link
        switch kind {
        case .upgrade: guard current != .thunderbolt else { return }
        case .failover: guard current.isWired else { return }  // Wi-Fi blips recover on their own
        }
        let endpoint = PeerConnector.unpinned(session.connection.remoteEndpoint)
        if kind == .failover { switchingLinks.insert(peerID) }

        slot.migrationTask = Task { [weak self] in
            // Give a fresh interface a moment to get an address.
            try? await Task.sleep(nanoseconds: kind == .upgrade ? 300_000_000 : 100_000_000)
            let connection: PeerConnection?
            switch kind {
            case .upgrade: connection = await PeerConnector.upgrade(to: endpoint, betterThan: current)
            case .failover: connection = try? await PeerConnector.reconnect(to: endpoint)
            }
            guard let self else { connection?.cancel(); return }
            defer {
                if self.connection(for: peerID) === session { self.slots[peerID]?.migrationTask = nil }
                self.switchingLinks.remove(peerID)
            }
            guard let connection else { return }
            guard self.connection(for: peerID) === session else { connection.cancel(); return }
            guard let replacement = try? await SessionHandshake.initiate(
                over: connection, config: self.handshakeConfiguration()) else { return }
            guard self.connection(for: peerID) === session else {
                await replacement.close(reason: "superseded")
                return
            }
            self.replace(session, with: replacement)
        }
    }

    /// Watches for a new wired interface (cable plugged in) while connected.
    private func startWiredMonitor(for peerID: String) {
        guard let slot = slots[peerID] else { return }
        slot.wiredMonitor?.cancel()
        slot.knownWiredInterfaces = nil
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let wired = Set(path.availableInterfaces.filter { LinkType(interface: $0).isWired }.map(\.name))
            Task { @MainActor [weak self] in self?.wiredInterfacesChanged(wired, peerID: peerID) }
        }
        monitor.start(queue: .main)
        slot.wiredMonitor = monitor
    }

    private func wiredInterfacesChanged(_ wired: Set<String>, peerID: String) {
        guard let slot = slots[peerID] else { return }
        defer { slot.knownWiredInterfaces = wired }
        guard let known = slot.knownWiredInterfaces else { return }  // first report = baseline
        if !wired.subtracting(known).isEmpty { switchLink(.upgrade, peerID: peerID) }
    }

    /// The connection dropped unexpectedly and we initiated it: keep trying
    /// for ~30 s (Wi-Fi roaming, Mac waking up, cable pulled…).
    private func startReconnect(to endpoint: NWEndpoint, peer: DeviceInfo) {
        let id = peer.id
        phase = .connecting(peerName: "\(peer.name) (reconnecting)")
        reconnectTasks[id] = Task { [weak self] in
            for _ in 0..<10 {
                if Task.isCancelled { return }
                if let connection = try? await PeerConnector.reconnect(to: endpoint) {
                    guard let self else { connection.cancel(); return }
                    if let session = try? await SessionHandshake.initiate(
                        over: connection, config: self.handshakeConfiguration()) {
                        self.reconnectTasks[id] = nil
                        self.adopt(session)
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            self.reconnectTasks[id] = nil
            self.updateCapacity()
            self.phase = .failed("Lost the connection to \(peer.name) and couldn't reconnect.")
        }
        updateCapacity()
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
