import Foundation
import CryptoKit

/// Which side of the handshake a device is on (the TCP initiator / listener),
/// independent of Host/Display role: either side may click "Connect".
public enum HandshakeRole: String, Sendable {
    case initiator
    case responder

    var opposite: HandshakeRole { self == .initiator ? .responder : .initiator }
}

/// Pure cryptographic building blocks of the pairing/authentication handshake.
/// Kept free of networking so it can be unit tested in isolation.
///
/// Protocol summary (I = initiator, R = responder):
///  1. I → R  ClientHello { device, IK_I, commit = H(EK_I ‖ nonce_I) }
///  2. R → I  ServerHello { device, IK_R, EK_R, nonce_R, trustsPeer }
///  3. I → R  KeyReveal   { EK_I, nonce_I, trustsPeer }  (R checks the commitment)
///  4. Both: shared = X25519(EK_I, EK_R); TH = H(msg1 ‖ msg2 ‖ msg3)
///  5. Known peers on both sides → exchange Ed25519 signatures over TH. Done.
///     Otherwise → both screens show SAS = HKDF(shared, TH) mod 10^6; each
///     user confirms the codes match, then the signatures are exchanged and
///     each side stores the other's IK. The commitment in step 1 stops a
///     man-in-the-middle from grinding keys to force a matching code, so a
///     MITM succeeds with probability 10^-6 per attempt.
///  6. Session keys = HKDF(shared, TH, direction label) → ChaCha20-Poly1305.
public enum HandshakeCrypto {
    static let protocolLabel = Data("ScreenBridge/handshake/v1".utf8)

    public static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    public static func commitment(ephemeralPublicKey: Data, nonce: Data) -> Data {
        var hasher = SHA256()
        hasher.update(data: Data("commit".utf8))
        hasher.update(data: ephemeralPublicKey)
        hasher.update(data: nonce)
        return Data(hasher.finalize())
    }

    /// Hash of the exact bytes each side sent/received, with length prefixes
    /// so message boundaries cannot be shifted.
    public static func transcriptHash(_ messages: [Data]) -> Data {
        var hasher = SHA256()
        hasher.update(data: protocolLabel)
        for message in messages {
            var length = UInt32(message.count).bigEndian
            withUnsafeBytes(of: &length) { hasher.update(bufferPointer: $0) }
            hasher.update(data: message)
        }
        return Data(hasher.finalize())
    }

    /// Six-digit short authentication string, identical on both devices iff
    /// they share the same ECDH secret and transcript.
    public static func shortAuthenticationString(sharedSecret: SharedSecret, transcript: Data) -> String {
        let key = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: transcript,
            sharedInfo: Data("ScreenBridge SAS".utf8), outputByteCount: 8)
        let value = key.withUnsafeBytes { raw in
            raw.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        }
        let digits = String(value % 1_000_000)
        return String(repeating: "0", count: 6 - digits.count) + digits
    }

    /// What each side signs with its long-term identity key.
    public static func signaturePayload(transcript: Data, role: HandshakeRole) -> Data {
        Data("ScreenBridge auth \(role.rawValue)".utf8) + transcript
    }

    public struct SessionKeys {
        public let initiatorToResponder: SymmetricKey
        public let responderToInitiator: SymmetricKey
        /// Short non-secret identifier for logs.
        public let sessionID: String
    }

    public static func sessionKeys(sharedSecret: SharedSecret, transcript: Data) -> SessionKeys {
        func derive(_ label: String) -> SymmetricKey {
            sharedSecret.hkdfDerivedSymmetricKey(
                using: SHA256.self, salt: transcript,
                sharedInfo: Data("ScreenBridge session \(label)".utf8), outputByteCount: 32)
        }
        let id = SHA256.hash(data: Data("session-id".utf8) + transcript)
            .prefix(6).map { String(format: "%02x", $0) }.joined()
        return SessionKeys(initiatorToResponder: derive("i2r"),
                           responderToInitiator: derive("r2i"),
                           sessionID: id)
    }

    /// "482913" → "482 913"
    public static func formatCode(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }
}
