import Foundation
import CryptoKit

/// Shown to the user when two devices have not paired before (or one side
/// forgot the other). Both screens display the same `code`.
public struct PairingRequest: Sendable, Identifiable {
    public let id = UUID()
    public let peer: DeviceInfo
    /// Six digits, e.g. "482913". Use `formattedCode` for display.
    public let code: String
    /// We had this device on file, but it no longer matches / the peer
    /// forgot us. Worth a warning in the UI.
    public let previouslyPaired: Bool
    public let role: HandshakeRole

    public var formattedCode: String { HandshakeCrypto.formatCode(code) }
}

/// Return true if the user confirmed the codes match. The task is cancelled
/// if the other side declines or disconnects; dismiss your UI when that
/// happens (e.g. with `withTaskCancellationHandler`).
public typealias PairingApprovalHandler = @Sendable (PairingRequest) async -> Bool

public struct HandshakeConfiguration: Sendable {
    public var identity: DeviceIdentity
    public var localDevice: DeviceInfo
    public var trustStore: TrustStore
    public var approvePairing: PairingApprovalHandler
    /// Responder only: reject with `.busy` if this returns true.
    public var isBusy: @Sendable () -> Bool
    /// Time allowed for the non-interactive part of the handshake.
    public var handshakeTimeout: TimeInterval
    /// Extra time allowed while users compare codes.
    public var pairingTimeout: TimeInterval

    public init(identity: DeviceIdentity, localDevice: DeviceInfo, trustStore: TrustStore,
                approvePairing: @escaping PairingApprovalHandler,
                isBusy: @escaping @Sendable () -> Bool = { false },
                handshakeTimeout: TimeInterval = 10, pairingTimeout: TimeInterval = 120) {
        self.identity = identity
        self.localDevice = localDevice
        self.trustStore = trustStore
        self.approvePairing = approvePairing
        self.isBusy = isBusy
        self.handshakeTimeout = handshakeTimeout
        self.pairingTimeout = pairingTimeout
    }
}

public enum HandshakeError: Error, LocalizedError {
    case remoteFailure(HandshakeFailureReason, String?)
    case rejectedLocally
    case unexpectedMessage(UInt8)
    case identityMismatch
    case commitmentMismatch
    case invalidSignature
    case incompatibleVersion(Int)
    case busy
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .remoteFailure(let reason, _): return reason.userMessage
        case .rejectedLocally: return "Connection declined."
        case .unexpectedMessage(let type): return "Unexpected message 0x\(String(type, radix: 16)) during handshake."
        case .identityMismatch: return "The device's identity key doesn't match its ID."
        case .commitmentMismatch: return "Key commitment check failed (possible interception)."
        case .invalidSignature: return "The device failed to prove its identity."
        case .incompatibleVersion(let version): return "Incompatible protocol version \(version)."
        case .busy: return "Already connected to another device."
        case .timedOut: return "Pairing timed out."
        }
    }
}

/// Runs the pairing/authentication handshake over a ready `PeerConnection`
/// and returns an encrypted `SecureSession`. See `HandshakeCrypto` for the
/// protocol. On any failure the connection is cancelled.
public enum SessionHandshake {

    /// Runs the initiator side. Cancelling the calling task aborts the
    /// handshake (and closes the connection) promptly.
    public static func initiate(over connection: PeerConnection,
                                config: HandshakeConfiguration) async throws -> SecureSession {
        try await withTaskCancellationHandler {
            try await runInitiator(over: connection, config: config)
        } onCancel: {
            connection.cancel()
        }
    }

    /// Runs the responder side for a connection accepted by the listener.
    public static func respond(over connection: PeerConnection,
                               config: HandshakeConfiguration) async throws -> SecureSession {
        try await withTaskCancellationHandler {
            try await runResponder(over: connection, config: config)
        } onCancel: {
            connection.cancel()
        }
    }

    // MARK: Initiator

    private static func runInitiator(over connection: PeerConnection,
                                     config: HandshakeConfiguration) async throws -> SecureSession {
        let watchdog = Watchdog(connection: connection, seconds: config.handshakeTimeout)
        defer { watchdog.disarm() }
        do {
            let ephemeral = Curve25519.KeyAgreement.PrivateKey()
            let ephemeralPublic = ephemeral.publicKey.rawRepresentation
            let nonce = HandshakeCrypto.randomBytes(32)

            let hello = try WireCoding.encode(ClientHello(
                device: config.localDevice,
                identityKey: config.identity.publicKeyData,
                ephemeralCommitment: HandshakeCrypto.commitment(ephemeralPublicKey: ephemeralPublic, nonce: nonce)))
            try await connection.send(.clientHello, payload: hello)

            let reply = try await connection.receive()
            try throwIfFailure(reply)
            guard reply.type == .serverHello else { throw HandshakeError.unexpectedMessage(reply.rawType) }
            let serverHello = try WireCoding.decode(ServerHello.self, from: reply.payload)
            try validate(device: serverHello.device, identityKey: serverHello.identityKey)

            let localTrusts = trustsWithoutPrompt(serverHello.device, serverHello.identityKey, config)
            let reveal = try WireCoding.encode(KeyReveal(ephemeralKey: ephemeralPublic, nonce: nonce,
                                                         trustsPeer: localTrusts))
            try await connection.send(.keyReveal, payload: reveal)

            let peerEphemeral = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: serverHello.ephemeralKey)
            let shared = try ephemeral.sharedSecretFromKeyAgreement(with: peerEphemeral)
            let transcript = HandshakeCrypto.transcriptHash([hello, reply.payload, reveal])

            return try await finish(
                role: .initiator, connection: connection, config: config, watchdog: watchdog,
                peer: serverHello.device, peerIdentityKey: serverHello.identityKey,
                shared: shared, transcript: transcript,
                localTrusts: localTrusts, remoteTrusts: serverHello.trustsPeer)
        } catch {
            connection.cancel()
            if watchdog.fired { throw HandshakeError.timedOut }
            throw error
        }
    }

    // MARK: Responder

    private static func runResponder(over connection: PeerConnection,
                                     config: HandshakeConfiguration) async throws -> SecureSession {
        let watchdog = Watchdog(connection: connection, seconds: config.handshakeTimeout)
        defer { watchdog.disarm() }
        do {
            let first = try await connection.receive()
            guard first.type == .clientHello else { throw HandshakeError.unexpectedMessage(first.rawType) }
            let clientHello = try WireCoding.decode(ClientHello.self, from: first.payload)

            do {
                try validate(device: clientHello.device, identityKey: clientHello.identityKey)
            } catch HandshakeError.incompatibleVersion(let version) {
                try? await sendFailure(.incompatibleVersion, on: connection)
                throw HandshakeError.incompatibleVersion(version)
            } catch {
                try? await sendFailure(.identityMismatch, on: connection)
                throw error
            }
            if config.isBusy() {
                try? await sendFailure(.busy, on: connection)
                throw HandshakeError.busy
            }

            let ephemeral = Curve25519.KeyAgreement.PrivateKey()
            let localTrusts = trustsWithoutPrompt(clientHello.device, clientHello.identityKey, config)
            let serverHello = try WireCoding.encode(ServerHello(
                device: config.localDevice,
                identityKey: config.identity.publicKeyData,
                ephemeralKey: ephemeral.publicKey.rawRepresentation,
                nonce: HandshakeCrypto.randomBytes(32),
                trustsPeer: localTrusts))
            try await connection.send(.serverHello, payload: serverHello)

            let third = try await connection.receive()
            try throwIfFailure(third)
            guard third.type == .keyReveal else { throw HandshakeError.unexpectedMessage(third.rawType) }
            let reveal = try WireCoding.decode(KeyReveal.self, from: third.payload)
            let expected = HandshakeCrypto.commitment(ephemeralPublicKey: reveal.ephemeralKey, nonce: reveal.nonce)
            guard expected == clientHello.ephemeralCommitment else {
                try? await sendFailure(.authenticationFailed, on: connection)
                throw HandshakeError.commitmentMismatch
            }

            let peerEphemeral = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: reveal.ephemeralKey)
            let shared = try ephemeral.sharedSecretFromKeyAgreement(with: peerEphemeral)
            let transcript = HandshakeCrypto.transcriptHash([first.payload, serverHello, third.payload])

            return try await finish(
                role: .responder, connection: connection, config: config, watchdog: watchdog,
                peer: clientHello.device, peerIdentityKey: clientHello.identityKey,
                shared: shared, transcript: transcript,
                localTrusts: localTrusts, remoteTrusts: reveal.trustsPeer)
        } catch {
            connection.cancel()
            if watchdog.fired { throw HandshakeError.timedOut }
            throw error
        }
    }

    // MARK: Common tail

    private static func finish(role: HandshakeRole, connection: PeerConnection,
                               config: HandshakeConfiguration, watchdog: Watchdog,
                               peer: DeviceInfo, peerIdentityKey: Data,
                               shared: SharedSecret, transcript: Data,
                               localTrusts: Bool, remoteTrusts: Bool) async throws -> SecureSession {
        let peerSigningKey = try Curve25519.Signing.PublicKey(rawRepresentation: peerIdentityKey)
        let mySignature = try config.identity.sign(
            HandshakeCrypto.signaturePayload(transcript: transcript, role: role))
        let myAuth = try WireCoding.encode(Authenticate(signature: mySignature))

        // Both sides know both flags, so they always agree on the path.
        let needsPairing = !(localTrusts && remoteTrusts)
        let remoteAuth: Authenticate

        if needsPairing {
            watchdog.rearm(seconds: config.pairingTimeout)
            let request = PairingRequest(
                peer: peer,
                code: HandshakeCrypto.shortAuthenticationString(sharedSecret: shared, transcript: transcript),
                previouslyPaired: config.trustStore.peer(id: peer.id) != nil,
                role: role)
            remoteAuth = try await negotiatePairing(request: request, myAuth: myAuth,
                                                    connection: connection, config: config)
        } else {
            try await connection.send(.authenticate, payload: myAuth)
            let message = try await connection.receive()
            try throwIfFailure(message)
            guard message.type == .authenticate else { throw HandshakeError.unexpectedMessage(message.rawType) }
            remoteAuth = try WireCoding.decode(Authenticate.self, from: message.payload)
        }

        let expectedPayload = HandshakeCrypto.signaturePayload(transcript: transcript, role: role.opposite)
        guard peerSigningKey.isValidSignature(remoteAuth.signature, for: expectedPayload) else {
            throw HandshakeError.invalidSignature
        }
        watchdog.disarm()

        if needsPairing {
            let previous = config.trustStore.peer(id: peer.id)
            config.trustStore.trust(TrustedPeer(id: peer.id, name: peer.name, platform: peer.platform,
                                                identityKey: peerIdentityKey, lastConnectedAt: Date(),
                                                autoAccept: previous?.autoAccept ?? true))
        } else {
            config.trustStore.recordConnection(id: peer.id, name: peer.name)
        }

        let keys = HandshakeCrypto.sessionKeys(sharedSecret: shared, transcript: transcript)
        return SecureSession(peer: peer, connection: connection,
                             crypto: SessionCrypto(keys: keys, role: role),
                             sessionID: keys.sessionID, role: role, wasNewlyPaired: needsPairing)
    }

    private enum PairingEvent: Sendable {
        case local(Bool)
        case remote(WireMessage)
    }

    /// Waits for (a) the local user's decision and (b) the peer's
    /// `Authenticate` (= the remote user approved) or failure, whichever
    /// order they arrive in.
    private static func negotiatePairing(request: PairingRequest, myAuth: Data,
                                         connection: PeerConnection,
                                         config: HandshakeConfiguration) async throws -> Authenticate {
        try await withThrowingTaskGroup(of: PairingEvent.self) { group in
            group.addTask { .local(await cancellableApproval(config.approvePairing, request)) }
            group.addTask { .remote(try await connection.receive()) }

            var localApproved = false
            var remoteAuth: Authenticate?
            var failure: Error?

            // On failure, every still-running child must be made to finish
            // before the group can exit: cancelling the group unblocks the
            // approval child, cancelling the connection unblocks the receive.
            while failure == nil, let event = try await group.next() {
                switch event {
                case .local(let approved):
                    guard approved else {
                        try? await sendFailure(.rejectedByUser, on: connection)
                        failure = HandshakeError.rejectedLocally
                        break
                    }
                    localApproved = true
                    do {
                        try await connection.send(.authenticate, payload: myAuth)
                    } catch {
                        failure = error
                    }
                case .remote(let message):
                    if message.type == .handshakeFailure {
                        let decoded = try? WireCoding.decode(HandshakeFailure.self, from: message.payload)
                        failure = HandshakeError.remoteFailure(decoded?.reason ?? .internalError, decoded?.detail)
                    } else if message.type != .authenticate {
                        failure = HandshakeError.unexpectedMessage(message.rawType)
                    } else {
                        do {
                            remoteAuth = try WireCoding.decode(Authenticate.self, from: message.payload)
                        } catch {
                            failure = error
                        }
                    }
                }
                if failure == nil, localApproved, let remoteAuth {
                    return remoteAuth
                }
            }
            group.cancelAll()
            connection.cancel()
            throw failure ?? (PeerConnectionError.closedByPeer as Error)
        }
    }

    /// Wraps the app's approval handler so cancelling us resolves to `false`
    /// immediately and cancels the handler's task (so the UI can dismiss).
    private static func cancellableApproval(_ handler: @escaping PairingApprovalHandler,
                                            _ request: PairingRequest) async -> Bool {
        let box = ApprovalBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                let task = Task { box.resolve(await handler(request)) }
                box.install(continuation, task: task)
            }
        } onCancel: {
            box.resolve(false)
            box.cancelTask()
        }
    }

    // MARK: Helpers

    /// True if we know this exact key *and* the user allows auto-connect.
    /// Reporting false makes both sides fall back to code confirmation.
    private static func trustsWithoutPrompt(_ device: DeviceInfo, _ identityKey: Data,
                                            _ config: HandshakeConfiguration) -> Bool {
        config.trustStore.isTrusted(id: device.id, identityKey: identityKey)
            && config.trustStore.peer(id: device.id)?.autoAccept != false
    }

    private static func validate(device: DeviceInfo, identityKey: Data) throws {
        guard device.protocolVersion >= ScreenBridgeService.minimumCompatibleVersion else {
            throw HandshakeError.incompatibleVersion(device.protocolVersion)
        }
        guard identityKey.count == 32, DeviceIdentity.fingerprint(of: identityKey) == device.id else {
            throw HandshakeError.identityMismatch
        }
    }

    private static func throwIfFailure(_ message: WireMessage) throws {
        guard message.type == .handshakeFailure else { return }
        let failure = try? WireCoding.decode(HandshakeFailure.self, from: message.payload)
        throw HandshakeError.remoteFailure(failure?.reason ?? .internalError, failure?.detail)
    }

    private static func sendFailure(_ reason: HandshakeFailureReason, on connection: PeerConnection) async throws {
        try await connection.send(.handshakeFailure,
                                  payload: WireCoding.encode(HandshakeFailure(reason: reason, detail: nil)))
    }
}

/// Cancels the connection if the handshake stalls. Cancelling (rather than
/// racing a timer task) is what unblocks a pending NWConnection receive.
final class Watchdog: @unchecked Sendable {
    private let lock = NSLock()
    private let connection: PeerConnection
    private var workItem: DispatchWorkItem?
    private var _fired = false

    var fired: Bool {
        lock.lock(); defer { lock.unlock() }
        return _fired
    }

    init(connection: PeerConnection, seconds: TimeInterval) {
        self.connection = connection
        rearm(seconds: seconds)
    }

    func rearm(seconds: TimeInterval) {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock(); self._fired = true; self.lock.unlock()
            self.connection.cancel()
        }
        lock.lock()
        workItem?.cancel()
        workItem = item
        lock.unlock()
        connection.queue.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    func disarm() {
        lock.lock()
        workItem?.cancel()
        workItem = nil
        lock.unlock()
    }
}

/// Single-shot bridge between the app's approval task and our continuation.
private final class ApprovalBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var task: Task<Void, Never>?
    private var result: Bool?

    func install(_ continuation: CheckedContinuation<Bool, Never>, task: Task<Void, Never>) {
        lock.lock()
        self.task = task
        if let result {
            lock.unlock()
            task.cancel()  // resolved early (e.g. cancelled before install)
            continuation.resume(returning: result)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func resolve(_ value: Bool) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }

    func cancelTask() {
        lock.lock()
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}
