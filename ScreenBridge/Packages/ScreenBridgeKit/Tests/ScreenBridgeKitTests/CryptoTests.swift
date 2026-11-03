import XCTest
import CryptoKit
@testable import ScreenBridgeKit

final class HandshakeCryptoTests: XCTestCase {
    func testBothSidesDeriveSameCodeAndKeys() throws {
        let a = Curve25519.KeyAgreement.PrivateKey()
        let b = Curve25519.KeyAgreement.PrivateKey()
        let sharedA = try a.sharedSecretFromKeyAgreement(with: b.publicKey)
        let sharedB = try b.sharedSecretFromKeyAgreement(with: a.publicKey)
        let transcript = HandshakeCrypto.transcriptHash([Data("hello".utf8), Data("world".utf8)])

        let codeA = HandshakeCrypto.shortAuthenticationString(sharedSecret: sharedA, transcript: transcript)
        let codeB = HandshakeCrypto.shortAuthenticationString(sharedSecret: sharedB, transcript: transcript)
        XCTAssertEqual(codeA, codeB)
        XCTAssertEqual(codeA.count, 6)
        XCTAssertTrue(codeA.allSatisfy(\.isNumber))

        let keysA = HandshakeCrypto.sessionKeys(sharedSecret: sharedA, transcript: transcript)
        let keysB = HandshakeCrypto.sessionKeys(sharedSecret: sharedB, transcript: transcript)
        XCTAssertEqual(keysA.sessionID, keysB.sessionID)

        let initiator = SessionCrypto(keys: keysA, role: .initiator)
        let responder = SessionCrypto(keys: keysB, role: .responder)
        let sealed = try initiator.seal(Data("frame".utf8), messageType: 0x31)
        XCTAssertEqual(try responder.open(sealed, messageType: 0x31), Data("frame".utf8))
        let back = try responder.seal(Data("ack".utf8), messageType: 0x20)
        XCTAssertEqual(try initiator.open(back, messageType: 0x20), Data("ack".utf8))
    }

    func testDifferentTranscriptGivesDifferentCode() throws {
        let a = Curve25519.KeyAgreement.PrivateKey()
        let shared = try a.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PrivateKey().publicKey)
        let t1 = HandshakeCrypto.transcriptHash([Data("ab".utf8), Data("c".utf8)])
        let t2 = HandshakeCrypto.transcriptHash([Data("a".utf8), Data("bc".utf8)])  // same bytes, shifted boundary
        XCTAssertNotEqual(t1, t2)
        XCTAssertNotEqual(HandshakeCrypto.sessionKeys(sharedSecret: shared, transcript: t1).sessionID,
                          HandshakeCrypto.sessionKeys(sharedSecret: shared, transcript: t2).sessionID)
    }

    func testCommitmentBindsKeyAndNonce() {
        let key = Data(repeating: 1, count: 32)
        let nonce = Data(repeating: 2, count: 32)
        let c = HandshakeCrypto.commitment(ephemeralPublicKey: key, nonce: nonce)
        XCTAssertEqual(c, HandshakeCrypto.commitment(ephemeralPublicKey: key, nonce: nonce))
        XCTAssertNotEqual(c, HandshakeCrypto.commitment(ephemeralPublicKey: key, nonce: Data(repeating: 3, count: 32)))
    }

    func testFingerprintIsStableAndShort() {
        let identity = DeviceIdentity.ephemeral()
        XCTAssertEqual(identity.fingerprint.count, 32)
        XCTAssertEqual(identity.fingerprint, DeviceIdentity.fingerprint(of: identity.publicKeyData))
    }
}

final class SessionCryptoTests: XCTestCase {
    private func pair() -> (SessionCrypto, SessionCrypto) {
        let k1 = SymmetricKey(size: .bits256), k2 = SymmetricKey(size: .bits256)
        return (SessionCrypto(sendKey: k1, receiveKey: k2), SessionCrypto(sendKey: k2, receiveKey: k1))
    }

    func testRejectsReplay() throws {
        let (a, b) = pair()
        let sealed = try a.seal(Data([1, 2, 3]), messageType: 0x20)
        _ = try b.open(sealed, messageType: 0x20)
        XCTAssertThrowsError(try b.open(sealed, messageType: 0x20))
    }

    func testRejectsTamperingAndTypeConfusion() throws {
        let (a, b) = pair()
        var sealed = try a.seal(Data(repeating: 7, count: 64), messageType: 0x31)
        XCTAssertThrowsError(try b.open(sealed, messageType: 0x20))  // wrong AAD
        sealed[sealed.count - 20] ^= 0xFF
        XCTAssertThrowsError(try b.open(sealed, messageType: 0x31))
    }

    func testRejectsTruncated() {
        let (_, b) = pair()
        XCTAssertThrowsError(try b.open(Data([0, 1, 2]), messageType: 0x20))
    }

    func testEmptyPayload() throws {
        let (a, b) = pair()
        XCTAssertEqual(try b.open(try a.seal(Data(), messageType: 0x20), messageType: 0x20), Data())
    }
}
