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
