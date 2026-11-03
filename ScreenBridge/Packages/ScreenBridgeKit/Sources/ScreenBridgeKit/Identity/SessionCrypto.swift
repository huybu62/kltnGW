import Foundation
import CryptoKit

/// Per-session authenticated encryption (ChaCha20-Poly1305, one key per
/// direction). Used for control messages now and video frames in Phase 3.
///
/// Sealed layout: counter (8 bytes, big-endian) ‖ ciphertext ‖ tag (16).
/// The counter forms the nonce and is sent explicitly so the same format
/// works over an unordered datagram transport later. Over TCP we require it
/// to strictly increase, which rejects replays and reordering.
///
/// Cost: ChaCha20-Poly1305 runs at multiple GB/s on both Apple Silicon and
/// Intel, so even a 100 Mbit/s Retina stream adds well under 1 ms per frame.
public final class SessionCrypto: @unchecked Sendable {
    public enum CryptoError: Error, LocalizedError {
        case truncated
        case replayed(counter: UInt64)
        case authenticationFailed

        public var errorDescription: String? {
            switch self {
            case .truncated: return "Encrypted message is truncated."
            case .replayed(let counter): return "Rejected replayed message #\(counter)."
            case .authenticationFailed: return "Encrypted message failed authentication."
            }
        }
    }

    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private let lock = NSLock()
    private var nextSendCounter: UInt64 = 0
    private var highestReceived: UInt64?

    static let counterSize = 8
    static let tagSize = 16

    public init(sendKey: SymmetricKey, receiveKey: SymmetricKey) {
        self.sendKey = sendKey
        self.receiveKey = receiveKey
    }

    convenience init(keys: HandshakeCrypto.SessionKeys, role: HandshakeRole) {
        switch role {
        case .initiator:
            self.init(sendKey: keys.initiatorToResponder, receiveKey: keys.responderToInitiator)
        case .responder:
            self.init(sendKey: keys.responderToInitiator, receiveKey: keys.initiatorToResponder)
        }
    }

    /// `messageType` is bound as associated data so a ciphertext cannot be
    /// replayed under a different wire type.
    public func seal(_ plaintext: Data, messageType: UInt8) throws -> Data {
        lock.lock()
        let counter = nextSendCounter
        nextSendCounter += 1
        lock.unlock()

        let box = try ChaChaPoly.seal(plaintext, using: sendKey,
                                      nonce: try Self.nonce(for: counter),
                                      authenticating: Data([messageType]))
        var output = Data(capacity: Self.counterSize + box.ciphertext.count + Self.tagSize)
        output.append(Self.bigEndianBytes(counter))
        output.append(box.ciphertext)
        output.append(box.tag)
        return output
    }

    public func open(_ sealed: Data, messageType: UInt8) throws -> Data {
        guard sealed.count >= Self.counterSize + Self.tagSize else { throw CryptoError.truncated }
        let bytes = [UInt8](sealed)
        let counter = bytes[0..<Self.counterSize].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }

        lock.lock()
        let highest = highestReceived
        lock.unlock()
        if let highest, counter <= highest { throw CryptoError.replayed(counter: counter) }

        let ciphertext = Data(bytes[Self.counterSize..<(bytes.count - Self.tagSize)])
        let tag = Data(bytes[(bytes.count - Self.tagSize)...])
        let plaintext: Data
        do {
            let box = try ChaChaPoly.SealedBox(nonce: try Self.nonce(for: counter),
                                               ciphertext: ciphertext, tag: tag)
            plaintext = try ChaChaPoly.open(box, using: receiveKey, authenticating: Data([messageType]))
        } catch {
            throw CryptoError.authenticationFailed
        }

        lock.lock()
        if let current = highestReceived, counter <= current {
            lock.unlock()
            throw CryptoError.replayed(counter: counter)
        }
        highestReceived = counter
        lock.unlock()
        return plaintext
    }

    private static func nonce(for counter: UInt64) throws -> ChaChaPoly.Nonce {
        try ChaChaPoly.Nonce(data: Data(count: 4) + bigEndianBytes(counter))
    }

    private static func bigEndianBytes(_ value: UInt64) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}
