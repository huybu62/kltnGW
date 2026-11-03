import Foundation
import Network

/// Opens a connection to a discovered peer over the best available link.
///
/// Routes are tried in rank order — Thunderbolt Bridge, Ethernet, Wi-Fi,
/// Direct Wi-Fi (AWDL) — each pinned with `requiredInterface` and a short
/// timeout, then a final unpinned attempt lets the OS choose. A plugged-in
/// Thunderbolt cable therefore always wins, but its absence costs nothing:
/// a pinned attempt on a dead interface fails within ~2 s at worst.
public enum PeerConnector {
    public static func connect(to peer: DiscoveredPeer,
                               callbackQueue: DispatchQueue = .main) async throws -> PeerConnection {
        var failures: [String] = []

        for route in peer.routes where route.interface != nil {
            try Task.checkCancellation()
            let connection = PeerConnection.outgoing(to: route.endpoint, via: route.interface,
                                                     callbackQueue: callbackQueue)
            do {
                try await withTimeout(route.link.connectTimeout) { try await connection.start() }
                return connection
            } catch is CancellationError {
                connection.cancel()
                throw CancellationError()
            } catch {
                connection.cancel()
                failures.append("\(route.link.displayName): \(error.localizedDescription)")
            }
        }

        guard let endpoint = peer.primaryEndpoint else {
            throw PeerConnectionError.unreachable(attempts: failures + ["no endpoint"])
        }
        try Task.checkCancellation()
        let connection = PeerConnection.outgoing(to: endpoint, via: nil, callbackQueue: callbackQueue)
        do {
            try await withTimeout(8) { try await connection.start() }
            return connection
        } catch {
            connection.cancel()
            if error is CancellationError { throw error }
            failures.append("auto: \(error.localizedDescription)")
            throw PeerConnectionError.unreachable(attempts: failures)
        }
    }

    /// The same Bonjour service without the interface pin a browse result can
    /// carry, so the OS may pick any path (e.g. a cable plugged in later).
    public static func unpinned(_ endpoint: NWEndpoint) -> NWEndpoint {
        if case let .service(name, type, domain, _) = endpoint {
            return .service(name: name, type: type, domain: domain, interface: nil)
        }
        return endpoint
    }

    /// Opens a second connection to an already-connected peer, but only
    /// returns it if it runs over a better link than `current` (a cable that
    /// was just plugged in). Wired paths are tried first.
    public static func upgrade(to endpoint: NWEndpoint, betterThan current: LinkType,
                               callbackQueue: DispatchQueue = .main) async -> PeerConnection? {
        for prohibitWiFi in [true, false] {
            let connection = PeerConnection(
                connection: NWConnection(to: endpoint, using: ScreenBridgeParameters.make(prohibitWiFi: prohibitWiFi)),
                callbackQueue: callbackQueue)
            do {
                try await withTimeout(3) { try await connection.start() }
            } catch {
                connection.cancel()
                continue
            }
            if connection.link < current { return connection }
            connection.cancel()
        }
        return nil
    }

    /// Reconnects to a known peer over whatever path works now.
    public static func reconnect(to endpoint: NWEndpoint,
                                 callbackQueue: DispatchQueue = .main) async throws -> PeerConnection {
        let connection = PeerConnection(
            connection: NWConnection(to: endpoint, using: ScreenBridgeParameters.make()),
            callbackQueue: callbackQueue)
        do {
            try await withTimeout(4) { try await connection.start() }
            return connection
        } catch {
            connection.cancel()
            throw error
        }
    }

    /// Connect to an explicit address (manual fallback when multicast is
    /// blocked, e.g. guest/corporate Wi-Fi with client isolation).
    public static func connect(host: String, port: UInt16,
                               callbackQueue: DispatchQueue = .main) async throws -> PeerConnection {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw PeerConnectionError.unreachable(attempts: ["invalid port \(port)"])
        }
        let connection = PeerConnection.outgoing(to: .hostPort(host: NWEndpoint.Host(host), port: nwPort),
                                                 callbackQueue: callbackQueue)
        do {
            try await withTimeout(8) { try await connection.start() }
            return connection
        } catch {
            connection.cancel()
            throw error
        }
    }
}

/// Runs `operation`, throwing `PeerConnectionError.timedOut` if it takes too
/// long. The operation must react to cancellation (ours do: they cancel the
/// NWConnection), otherwise the timeout waits for it to finish.
public func withTimeout<T: Sendable>(_ seconds: TimeInterval,
                           operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw PeerConnectionError.timedOut
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw PeerConnectionError.timedOut }
        return result
    }
}
