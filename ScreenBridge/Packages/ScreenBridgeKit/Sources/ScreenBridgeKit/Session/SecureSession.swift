import Foundation

/// Small control messages exchanged after the handshake (always encrypted).
public enum ControlMessage: Codable, Sendable, Equatable {
    case ping(id: UInt64, sentAt: TimeInterval)
    case pong(id: UInt64, sentAt: TimeInterval)
    case goodbye(reason: String)
    /// Display → Host: decoder lost sync; send a keyframe now.
    case requestKeyframe
    /// Display → Host: video frame received (flow control + latency).
    case frameAck(frameNumber: UInt32)
    /// Host → Display: the video stream ended (mode change, error, stop).
    case streamStopped(reason: String)
}

public enum SessionEvent: @unchecked Sendable {
    case control(ControlMessage)
    /// Round-trip time measured from a ping we sent.
    case roundTrip(TimeInterval)
    /// Any other decrypted message type (video, input).
    case message(type: UInt8, payload: Data, flags: UInt16)
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
    /// Held while sealing + enqueueing so the encryption counter reaches
    /// the wire in order even when several threads send at once.
    private let sendLock = NSLock()
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

    // MARK: Sending (safe to call from any thread)

    public func send(_ control: ControlMessage) async throws {
        try await sendSealed(.sealedControl, payload: WireCoding.encode(control))
    }

    /// For high-rate control messages (frame acks) from non-async code.
    public func sendWithoutWaiting(_ control: ControlMessage) {
        guard let payload = try? WireCoding.encode(control) else { return }
        try? enqueueSealed(.sealedControl, payload: payload, flags: 0, completion: nil)
    }

    public func sendSealed(_ type: MessageType, payload: Data, flags: UInt16 = 0) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try enqueueSealed(type, payload: payload, flags: flags) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Non-blocking variant for per-frame video.
    public func sendSealedWithoutWaiting(_ type: MessageType, payload: Data, flags: UInt16 = 0) throws {
        try enqueueSealed(type, payload: payload, flags: flags, completion: nil)
    }

    /// Like `sendSealedWithoutWaiting`, but reports when the network stack
    /// has taken the data (used to measure send throughput).
    public func sendSealed(_ type: MessageType, payload: Data, flags: UInt16 = 0,
                           completion: @escaping (Error?) -> Void) {
        do {
            try enqueueSealed(type, payload: payload, flags: flags, completion: completion)
        } catch {
            completion(error)
        }
    }

    private func enqueueSealed(_ type: MessageType, payload: Data, flags: UInt16,
                               completion: ((Error?) -> Void)?) throws {
        sendLock.lock()
        defer { sendLock.unlock() }
        let sealed = try crypto.seal(payload, messageType: type.rawValue)
        connection.enqueue(type, payload: sealed, flags: flags, completion: completion)
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
                        // Unknown control messages (newer peer) are ignored, not fatal.
                        guard let control = try? WireCoding.decode(ControlMessage.self, from: plaintext) else {
                            continue
                        }
                        switch control {
                        case .ping(let id, let sentAt):
                            self.sendWithoutWaiting(.pong(id: id, sentAt: sentAt))
                        case .pong(_, let sentAt):
                            let rtt = ProcessInfo.processInfo.systemUptime - sentAt
                            queue.async { handler(.roundTrip(rtt)) }
                        default:
                            break
                        }
                        queue.async { handler(.control(control)) }
                        if case .goodbye = control {
                            self.markClosed(queue: queue, handler: handler, error: nil)
                            return
                        }
                    } else {
                        queue.async {
                            handler(.message(type: wire.rawType, payload: plaintext, flags: wire.flags))
                        }
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

/// Receives the media side of a session (video now, input in Phase 3).
/// `sessionStarted`/`sessionEnded` run on the main thread; `received…`
/// run on a dedicated high-priority queue and must not block.
public protocol SessionMediaSink: AnyObject, Sendable {
    func sessionStarted(_ session: SecureSession)
    /// `willReconnect`: the link dropped or is being switched, and the same
    /// peer is expected back shortly. Keep state (virtual display, last
    /// frame) for a while instead of tearing everything down.
    func sessionEnded(willReconnect: Bool)
    func received(type: UInt8, payload: Data, flags: UInt16)
    func receivedControl(_ message: ControlMessage)
}
