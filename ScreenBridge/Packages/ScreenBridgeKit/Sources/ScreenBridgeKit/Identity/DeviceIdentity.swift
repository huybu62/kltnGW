import Foundation
import CryptoKit

/// A device's long-term cryptographic identity.
///
/// This is how ScreenBridge works across *different Apple IDs*: instead of
/// relying on iCloud/Continuity trust (which is what limits Sidecar to one
/// Apple ID), each install generates its own Ed25519 key. Devices pair once
/// by comparing a 6-digit code, then remember each other's public keys.
public final class DeviceIdentity: @unchecked Sendable {
    public let signingKey: Curve25519.Signing.PrivateKey

    /// Stable identifier shown in TXT records: hex of the first 16 bytes of
    /// SHA-256(public key). Cannot be spoofed without the private key, because
    /// the handshake checks the presented key hashes to this value.
    public let fingerprint: String

    public var publicKey: Curve25519.Signing.PublicKey { signingKey.publicKey }
    public var publicKeyData: Data { signingKey.publicKey.rawRepresentation }

    public init(signingKey: Curve25519.Signing.PrivateKey) {
        self.signingKey = signingKey
        self.fingerprint = DeviceIdentity.fingerprint(of: signingKey.publicKey.rawRepresentation)
    }

    /// Generates a throwaway identity (tests, previews).
    public static func ephemeral() -> DeviceIdentity {
        DeviceIdentity(signingKey: Curve25519.Signing.PrivateKey())
    }

    private static let account = "device-signing-key.v1"

    /// Loads the identity from the Keychain, creating it on first launch.
    public static func loadOrCreate(store: SecretStore = .default) throws -> DeviceIdentity {
        if let raw = try store.read(account: account),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) {
            return DeviceIdentity(signingKey: key)
        }
        let key = Curve25519.Signing.PrivateKey()
        try store.write(key.rawRepresentation, account: account)
        return DeviceIdentity(signingKey: key)
    }

    /// Creates a brand new identity. Every previously paired peer will see
    /// this device as a stranger and require pairing again.
    public static func reset(store: SecretStore = .default) throws -> DeviceIdentity {
        store.delete(account: account)
        return try loadOrCreate(store: store)
    }

    public static func fingerprint(of publicKeyData: Data) -> String {
        SHA256.hash(data: publicKeyData).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    public func sign(_ data: Data) throws -> Data {
        try signingKey.signature(for: data)
    }
}
