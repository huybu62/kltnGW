import Foundation

/// Small control messages exchanged after the handshake (always encrypted).
/// Phase 2/3 add display configuration and bitrate feedback here.
public enum ControlMessage: Codable, Sendable, Equatable {
    case ping(id: UInt64, sentAt: TimeInterval)
    case pong(id: UInt64, sentAt: TimeInterval)
    case goodbye(reason: String)
}

public enum SessionEvent {
    case control(ControlMessage)
    /// Round-trip time measured from a ping we sent.
    case roundTrip(TimeInterval)
    /// Any other decrypted message type (video, input — Phase 3).
    case message(type: UInt8, payload: Data)
    case closed(Error?)
}

/// An authenticated, encrypted channel to one peer.
public final class SecureSession: @unchecked Sendable {
    public let peer: DeviceInfo
    public let connection: PeerConnection
    public let sessionID: String
    public let role: HandshakeRole
    /// True if the user just confirmed a pairing code during this handshake.
    public let wasNewlyPaired: Bool

    let crypto: SessionCrypto
    private let lock = NSLock()
    private var receiveTask: Task<Void, Never>?
    private var nextPingID: UInt64 = 0
    private var closed = false

    public var link: LinkType { connection.link }

    init(peer: DeviceInfo, connection: PeerConnection, crypto: SessionCrypto,
         sessionID: String, role: HandshakeRole, wasNewlyPaired: Bool) {
        self.peer = peer
        self.connection = connection
        self.crypto = crypto
        self.sessionID = sessionID
        self.role = role
        self.wasNewlyPaired = wasNewlyPaired
    }

    // MARK: Sending

    public func send(_ control: ControlMessage) async throws {
        try await sendSealed(.sealedControl, payload: WireCoding.encode(control))
    }

    public func sendSealed(_ type: MessageType, payload: Data, flags: UInt16 = 0) async throws {
        let sealed = try crypto.seal(payload, messageType: type.rawValue)
        try await connection.send(type, payload: sealed, flags: flags)
    }

    /// Non-blocking variant for per-frame video (Phase 3).
    public func sendSealedWithoutWaiting(_ type: MessageType, payload: Data, flags: UInt16 = 0) throws {
        let sealed = try crypto.seal(payload, messageType: type.rawValue)
        connection.sendWithoutWaiting(type, payload: sealed, flags: flags)
    }

    /// Sends a ping; the RTT arrives later as `.roundTrip` in the event handler.
    public func ping() async throws {
        try await send(.ping(id: takePingID(), sentAt: ProcessInfo.processInfo.systemUptime))
    }

    /// Synchronous so NSLock is never held across (or called from) an async context.
    private func takePingID() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        let id = nextPingID
        nextPingID += 1
        return id
    }

    // MARK: Receiving

    /// Starts the receive loop. Pings are answered automatically. Events are
    /// delivered on `queue` (main by default); `.closed` is always last.
    public func startReceiving(on queue: DispatchQueue = .main,
                               handler: @escaping (SessionEvent) -> Void) {
        lock.lock()
        guard receiveTask == nil else { lock.unlock(); return }
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let wire = try await self.connection.receive()
                    let plaintext = try self.crypto.open(wire.payload, messageType: wire.rawType)
                    if wire.type == .sealedControl {
                        let control = try WireCoding.decode(ControlMessage.self, from: plaintext)
                        switch control {
                        case .ping(let id, let sentAt):
                            try? await self.send(.pong(id: id, sentAt: sentAt))
                        case .pong(_, let sentAt):
                            let rtt = ProcessInfo.processInfo.systemUptime - sentAt
                            queue.async { handler(.roundTrip(rtt)) }
                        case .goodbye:
                            break
                        }
                        queue.async { handler(.control(control)) }
                        if case .goodbye = control {
                            self.markClosed(queue: queue, handler: handler, error: nil)
                            return
                        }
                    } else {
                        queue.async { handler(.message(type: wire.rawType, payload: plaintext)) }
                    }
                } catch {
                    self.markClosed(queue: queue, handler: handler, error: error)
                    return
                }
            }
        }
        receiveTask = task
        lock.unlock()
    }

    private func markClosed(queue: DispatchQueue, handler: @escaping (SessionEvent) -> Void, error: Error?) {
        lock.lock()
        let alreadyClosed = closed
        closed = true
        lock.unlock()
        connection.cancel()
        guard !alreadyClosed else { return }
        queue.async { handler(.closed(error)) }
    }

    /// Politely tells the peer and closes.
    public func close(reason: String = "closed") async {
        try? await send(.goodbye(reason: reason))
        receiveTask?.cancel()
        connection.cancel()
    }
}
