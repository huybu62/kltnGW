import Foundation
import Network

public enum PeerConnectionError: Error, LocalizedError {
    case cancelled
    case closedByPeer
    case timedOut
    case unreachable(attempts: [String])
    case protocolViolation(String)
    case network(NWError)

    public var errorDescription: String? {
        switch self {
        case .cancelled: return "The connection was cancelled."
        case .closedByPeer: return "The other device closed the connection."
        case .timedOut: return "The other device did not respond in time."
        case .unreachable(let attempts):
            return "Couldn't reach the device (\(attempts.joined(separator: "; ")))."
        case .protocolViolation(let detail): return "Unexpected data from the other device: \(detail)"
        case .network(let error): return error.localizedDescription
        }
    }
}

/// async/await wrapper around one NWConnection carrying ScreenBridge frames.
///
/// Threading: all NWConnection work happens on a private serial queue (video
/// will be sent from here in Phase 3, so it must never touch the main
/// thread). Observer callbacks are delivered on `callbackQueue` (main by
/// default) so UI code can use them directly.
public final class PeerConnection: @unchecked Sendable {
    public let nwConnection: NWConnection
    public let queue: DispatchQueue
    public let callbackQueue: DispatchQueue

    /// Fires when the link under the connection changes (e.g. Wi-Fi → AWDL).
    public var onLinkChange: ((LinkType) -> Void)?
    /// Fires when the OS sees a better path (e.g. Thunderbolt was plugged in).
    /// TCP can't migrate, so the owner should open a new connection on it.
    public var onBetterPathAvailable: ((Bool) -> Void)?
    /// Fires when the path stops/starts being viable (Wi-Fi blip).
    public var onViabilityChange: ((Bool) -> Void)?
    /// Fires once when the connection ends after having been ready.
    public var onTerminated: ((Error?) -> Void)?

    private let lock = NSLock()
    private var _link: LinkType = .other
    private var didBecomeReady = false
    private var didTerminate = false

    public var link: LinkType {
        lock.lock(); defer { lock.unlock() }
        return _link
    }

    public var remoteEndpoint: NWEndpoint { nwConnection.endpoint }

    public init(connection: NWConnection, callbackQueue: DispatchQueue = .main) {
        self.nwConnection = connection
        self.queue = DispatchQueue(label: "app.screenbridge.connection", qos: .userInteractive)
        self.callbackQueue = callbackQueue
    }

    /// Creates an outgoing connection, optionally pinned to one interface.
    public static func outgoing(to endpoint: NWEndpoint, via interface: NWInterface? = nil,
                                callbackQueue: DispatchQueue = .main) -> PeerConnection {
        let connection = NWConnection(to: endpoint,
                                      using: ScreenBridgeParameters.make(requiredInterface: interface))
        return PeerConnection(connection: connection, callbackQueue: callbackQueue)
    }

    // MARK: - Lifecycle

    /// Starts the connection and waits until it is ready. Throws on failure,
    /// on `.waiting` (no route right now — callers fall back to another
    /// link instead of hanging), or when the calling task is cancelled.
    public func start() async throws {
        let once = OnceContinuation<Void>()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                once.install(continuation)
                let connection = self.nwConnection
                connection.stateUpdateHandler = { [weak self] state in
                    self?.handle(state: state, startup: once)
                }
                connection.pathUpdateHandler = { [weak self] _ in self?.refreshLink() }
                connection.betterPathUpdateHandler = { [weak self] available in
                    guard let self else { return }
                    self.callbackQueue.async { self.onBetterPathAvailable?(available) }
                }
                connection.viabilityUpdateHandler = { [weak self] viable in
                    guard let self else { return }
                    self.callbackQueue.async { self.onViabilityChange?(viable) }
                }
                connection.start(queue: self.queue)
            }
        } onCancel: { [nwConnection] in
            once.resume(with: .failure(PeerConnectionError.cancelled))
            nwConnection.cancel()
        }
    }

    private func handle(state: NWConnection.State, startup: OnceContinuation<Void>) {
        switch state {
        case .ready:
            lock.lock(); didBecomeReady = true; lock.unlock()
            refreshLink()
            startup.resume(with: .success(()))
        case .waiting(let error):
            lock.lock(); let ready = didBecomeReady; lock.unlock()
            if !ready {
                startup.resume(with: .failure(PeerConnectionError.network(error)))
                nwConnection.cancel()
            }
        case .failed(let error):
            startup.resume(with: .failure(PeerConnectionError.network(error)))
            terminate(PeerConnectionError.network(error))
        case .cancelled:
            startup.resume(with: .failure(PeerConnectionError.cancelled))
            terminate(nil)
        default:
            break
        }
    }

    private func terminate(_ error: Error?) {
        lock.lock()
        let notify = didBecomeReady && !didTerminate
        didTerminate = true
        lock.unlock()
        guard notify else { return }
        callbackQueue.async { [self] in onTerminated?(error) }
    }

    /// Graceful close (pending sends are flushed).
    public func cancel() {
        nwConnection.cancel()
    }

    private func refreshLink() {
        guard let interface = nwConnection.currentPath?.availableInterfaces.first else { return }
        let newLink = LinkType(interface: interface)
        lock.lock()
        let changed = newLink != _link
        _link = newLink
        lock.unlock()
        if changed {
            callbackQueue.async { [self] in onLinkChange?(newLink) }
        }
    }

    // MARK: - I/O

    /// Sends one framed message; returns once the stack has accepted it.
    public func send(_ type: MessageType, payload: Data, flags: UInt16 = 0) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            enqueue(type, payload: payload, flags: flags) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Fire-and-forget send for the high-rate video path; errors surface
    /// through `onTerminated`.
    public func sendWithoutWaiting(_ type: MessageType, payload: Data, flags: UInt16 = 0) {
        enqueue(type, payload: payload, flags: flags, completion: nil)
    }

    /// Hands one message to the network stack synchronously. NWConnection
    /// keeps call order, so callers that need ordering (encrypted messages
    /// carry an increasing counter) serialize their calls to this.
    /// `completion` runs when the stack has processed the data.
    public func enqueue(_ type: MessageType, payload: Data, flags: UInt16 = 0,
                        completion: ((Error?) -> Void)?) {
        let context = Self.context(for: type, flags: flags)
        guard let completion else {
            nwConnection.send(content: payload, contentContext: context, isComplete: true,
                              completion: .idempotent)
            return
        }
        nwConnection.send(content: payload, contentContext: context, isComplete: true,
                          completion: .contentProcessed { error in
            completion(error.map { PeerConnectionError.network($0) as Error })
        })
    }

    /// Receives the next whole message. Only one receive may be outstanding.
    public func receive() async throws -> WireMessage {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<WireMessage, Error>) in
            nwConnection.receiveMessage { content, context, isComplete, error in
                if let error {
                    continuation.resume(throwing: PeerConnectionError.network(error))
                    return
                }
                guard let message = context?.protocolMetadata(definition: ScreenBridgeFramer.definition)
                        as? NWProtocolFramer.Message else {
                    // End of stream with no framed message: the peer closed.
                    continuation.resume(throwing: PeerConnectionError.closedByPeer)
                    return
                }
                continuation.resume(returning: WireMessage(rawType: message.screenBridgeRawType,
                                                           flags: message.screenBridgeFlags,
                                                           payload: content ?? Data()))
            }
        }
    }

    private static func context(for type: MessageType, flags: UInt16) -> NWConnection.ContentContext {
        let message = NWProtocolFramer.Message(screenBridgeRawType: type.rawValue, flags: flags)
        return NWConnection.ContentContext(identifier: "sb.\(type.rawValue)", metadata: [message])
    }
}

/// A continuation that can be resumed from several racing places (state
/// handler, cancellation handler) but only takes effect once.
final class OnceContinuation<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var pending: Result<T, Error>?
    private var finished = false

    func install(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        if let pending {
            self.pending = nil
            lock.unlock()
            continuation.resume(with: pending)
            return
        }
        if finished {
            lock.unlock()
            continuation.resume(throwing: PeerConnectionError.cancelled)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func resume(with result: Result<T, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
        } else {
            pending = result  // resumed before install (e.g. already-cancelled task)
            lock.unlock()
        }
    }
}
