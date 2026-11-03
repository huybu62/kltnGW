import XCTest
import Network
@testable import ScreenBridgeKit

/// End-to-end: real NWListener + NWConnection over 127.0.0.1, real framing,
/// real handshake and encryption. Two "devices" with independent identities
/// and trust stores — exactly the different-Apple-ID situation.
final class LoopbackHandshakeTests: XCTestCase {

    private actor Recorder {
        var codes: [String] = []
        var prompts = 0
        func record(_ code: String) { codes.append(code); prompts += 1 }
    }

    private struct Device {
        let identity = DeviceIdentity.ephemeral()
        let trust = TrustStore(fileURL: nil)
        let role: PeerRole

        var info: DeviceInfo {
            DeviceInfo(id: identity.fingerprint, name: role == .host ? "Test Mac" : "Test iPad",
                       platform: role == .host ? .mac : .iPad, model: "Test", role: role,
                       display: role == .display
                           ? DisplayCapabilities(pixelWidth: 2388, pixelHeight: 1668, maxRefreshRate: 120, supportsHEVC: true)
                           : nil)
        }

        func config(approve: @escaping PairingApprovalHandler) -> HandshakeConfiguration {
            HandshakeConfiguration(identity: identity, localDevice: info, trustStore: trust,
                                   approvePairing: approve, handshakeTimeout: 5, pairingTimeout: 5)
        }
    }

    /// Listens on loopback and runs the responder handshake for each connection.
    private final class LoopbackServer: @unchecked Sendable {
        let listener: NWListener
        private let config: HandshakeConfiguration
        private let lock = NSLock()
        private var results: [Result<SecureSession, Error>] = []
        private var waiters: [CheckedContinuation<Result<SecureSession, Error>, Never>] = []

        init(config: HandshakeConfiguration) throws {
            self.config = config
            listener = try NWListener(using: ScreenBridgeParameters.make(), on: .any)
        }

        func start() async throws -> UInt16 {
            let queue = DispatchQueue(label: "test.listener")
            listener.newConnectionHandler = { [weak self] nw in
                guard let self else { return }
                let connection = PeerConnection(connection: nw, callbackQueue: queue)
                Task {
                    do {
                        try await connection.start()
                        let session = try await SessionHandshake.respond(over: connection, config: self.config)
                        self.deliver(.success(session))
                    } catch {
                        self.deliver(.failure(error))
                    }
                }
            }
            return try await withCheckedThrowingContinuation { continuation in
                let once = OnceContinuation<UInt16>()
                once.install(continuation)
                let listener = self.listener
                listener.stateUpdateHandler = { [listener] state in
                    switch state {
                    case .ready: once.resume(with: .success(listener.port?.rawValue ?? 0))
                    case .failed(let error): once.resume(with: .failure(error))
                    default: break
                    }
                }
                listener.start(queue: queue)
            }
        }

        private func deliver(_ result: Result<SecureSession, Error>) {
            lock.lock()
            if !waiters.isEmpty {
                let waiter = waiters.removeFirst()
                lock.unlock()
                waiter.resume(returning: result)
            } else {
                results.append(result)
                lock.unlock()
            }
        }

        func nextResult() async -> Result<SecureSession, Error> {
            await withCheckedContinuation { continuation in
                lock.lock()
                if !results.isEmpty {
                    let result = results.removeFirst()
                    lock.unlock()
                    continuation.resume(returning: result)
                } else {
                    waiters.append(continuation)
                    lock.unlock()
                }
            }
        }

        func stop() { listener.cancel() }
    }

    func testFirstConnectionPairsThenReconnectsSilently() async throws {
        let host = Device(role: .host)
        let display = Device(role: .display)
        let recorder = Recorder()

        let server = try LoopbackServer(config: display.config { request in
            await recorder.record(request.code)
            return true
        })
        let port = try await server.start()
        defer { server.stop() }

        // 1st connection: strangers → both sides see the same code.
        let connection1 = try await PeerConnector.connect(host: "127.0.0.1", port: port, callbackQueue: .global())
        let hostSession1 = try await SessionHandshake.initiate(over: connection1, config: host.config { request in
            await recorder.record(request.code)
            return true
        })
        let displaySession1 = try await server.nextResult().get()

        XCTAssertTrue(hostSession1.wasNewlyPaired)
        XCTAssertTrue(displaySession1.wasNewlyPaired)
        XCTAssertEqual(hostSession1.sessionID, displaySession1.sessionID)
        XCTAssertEqual(hostSession1.peer.id, display.identity.fingerprint)
        XCTAssertEqual(displaySession1.peer.id, host.identity.fingerprint)
        let codes = await recorder.codes
        XCTAssertEqual(codes.count, 2)
        XCTAssertEqual(codes.first, codes.last)
        XCTAssertNotNil(host.trust.peer(id: display.identity.fingerprint))
        XCTAssertNotNil(display.trust.peer(id: host.identity.fingerprint))

        // Encrypted control round trip.
        let gotPong = expectation(description: "pong")
        hostSession1.startReceiving(on: .global()) { event in
            if case .roundTrip = event { gotPong.fulfill() }
        }
        displaySession1.startReceiving(on: .global()) { _ in }
        try await hostSession1.ping()
        await fulfillment(of: [gotPong], timeout: 5)
        await hostSession1.close()
        await displaySession1.close()

        // 2nd connection: known on both sides → no prompt at all.
        let promptsBefore = await recorder.prompts
        let connection2 = try await PeerConnector.connect(host: "127.0.0.1", port: port, callbackQueue: .global())
        let hostSession2 = try await SessionHandshake.initiate(over: connection2, config: host.config { _ in
            XCTFail("should not prompt for a paired device")
            return false
        })
        let displaySession2 = try await server.nextResult().get()
        XCTAssertFalse(hostSession2.wasNewlyPaired)
        XCTAssertFalse(displaySession2.wasNewlyPaired)
        let promptsAfter = await recorder.prompts
        XCTAssertEqual(promptsBefore, promptsAfter)
        await hostSession2.close()
        await displaySession2.close()
    }

    func testDeclinedPairingIsReportedToInitiator() async throws {
        let host = Device(role: .host)
        let display = Device(role: .display)
        let server = try LoopbackServer(config: display.config { _ in false })
        let port = try await server.start()
        defer { server.stop() }

        let connection = try await PeerConnector.connect(host: "127.0.0.1", port: port, callbackQueue: .global())
        do {
            _ = try await SessionHandshake.initiate(over: connection, config: host.config { request in
                // Simulate a user who hasn't answered yet; we must be cancelled
                // when the other side declines.
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                return !Task.isCancelled
            })
            XCTFail("expected rejection")
        } catch HandshakeError.remoteFailure(let reason, _) {
            XCTAssertEqual(reason, .rejectedByUser)
        }
        XCTAssertNil(host.trust.peer(id: display.identity.fingerprint))
        if case .success = await server.nextResult() { XCTFail("display should not have a session") }
    }

    func testForgottenPeerMustRePair() async throws {
        let host = Device(role: .host)
        let display = Device(role: .display)
        let recorder = Recorder()
        let server = try LoopbackServer(config: display.config { request in
            await recorder.record(request.code); return true
        })
        let port = try await server.start()
        defer { server.stop() }

        // Pair once.
        let c1 = try await PeerConnector.connect(host: "127.0.0.1", port: port, callbackQueue: .global())
        let s1 = try await SessionHandshake.initiate(over: c1, config: host.config { _ in true })
        let d1 = try await server.nextResult().get()
        await s1.close(); await d1.close()

        // Display forgets the host → next connection must show codes again.
        display.trust.revoke(id: host.identity.fingerprint)
        let c2 = try await PeerConnector.connect(host: "127.0.0.1", port: port, callbackQueue: .global())
        let s2 = try await SessionHandshake.initiate(over: c2, config: host.config { request in
            XCTAssertTrue(request.previouslyPaired)
            return true
        })
        let d2 = try await server.nextResult().get()
        XCTAssertTrue(s2.wasNewlyPaired)
        XCTAssertTrue(d2.wasNewlyPaired)
        let prompts = await recorder.prompts
        XCTAssertEqual(prompts, 2)
        await s2.close(); await d2.close()
    }
}
