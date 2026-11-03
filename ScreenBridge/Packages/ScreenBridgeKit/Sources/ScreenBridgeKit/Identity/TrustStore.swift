import Foundation

/// A peer this device has paired with.
public struct TrustedPeer: Codable, Hashable, Identifiable, Sendable {
    public var id: String              // identity fingerprint
    public var name: String
    public var platform: DevicePlatform
    public var identityKey: Data       // Ed25519 public key
    public var pairedAt: Date
    public var lastConnectedAt: Date?
    /// When false the user is asked to confirm each connection even though
    /// the device is cryptographically known.
    public var autoAccept: Bool

    public init(id: String, name: String, platform: DevicePlatform, identityKey: Data,
                pairedAt: Date = Date(), lastConnectedAt: Date? = nil, autoAccept: Bool = true) {
        self.id = id
        self.name = name
        self.platform = platform
        self.identityKey = identityKey
        self.pairedAt = pairedAt
        self.lastConnectedAt = lastConnectedAt
        self.autoAccept = autoAccept
    }
}

/// Thread-safe, file-backed list of paired peers. Public keys are not secret,
/// so a JSON file in the app container is fine; it never syncs to iCloud.
public final class TrustStore: @unchecked Sendable {
    private let fileURL: URL?
    private let lock = NSLock()
    private var peers: [String: TrustedPeer] = [:]

    /// Called (on an arbitrary thread) after any change.
    public var onChange: (([TrustedPeer]) -> Void)?

    /// Persistent store in Application Support.
    public convenience init() {
        self.init(fileURL: StorageLocation.directory(named: "trust").appendingPathComponent("trusted-peers.json"))
    }

    /// `fileURL == nil` keeps everything in memory (tests).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([TrustedPeer].self, from: data) {
            peers = Dictionary(decoded.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        }
    }

    public var all: [TrustedPeer] {
        lock.lock(); defer { lock.unlock() }
        return peers.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func peer(id: String) -> TrustedPeer? {
        lock.lock(); defer { lock.unlock() }
        return peers[id]
    }

    /// True only if we paired with `id` *and* it presents the same key now.
    public func isTrusted(id: String, identityKey: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return peers[id]?.identityKey == identityKey
    }

    public func trust(_ peer: TrustedPeer) {
        mutate { $0[peer.id] = peer }
    }

    public func revoke(id: String) {
        mutate { $0[id] = nil }
    }

    public func revokeAll() {
        mutate { $0.removeAll() }
    }

    public func recordConnection(id: String, name: String) {
        mutate {
            $0[id]?.lastConnectedAt = Date()
            $0[id]?.name = name
        }
    }

    private func mutate(_ change: (inout [String: TrustedPeer]) -> Void) {
        lock.lock()
        change(&peers)
        let snapshot = Array(peers.values)
        lock.unlock()
        persist(snapshot)
        onChange?(snapshot)
    }

    private func persist(_ snapshot: [TrustedPeer]) {
        guard let fileURL else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            NSLog("[ScreenBridge] Failed to persist trust store: \(error)")
        }
    }
}
