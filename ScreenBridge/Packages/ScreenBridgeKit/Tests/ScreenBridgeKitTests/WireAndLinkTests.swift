import XCTest
import Network
@testable import ScreenBridgeKit

final class WireHeaderTests: XCTestCase {
    func testHeaderRoundTrip() throws {
        let header = WireHeader(type: 0x31, flags: 0xBEEF, length: 1_234_567)
        let encoded = header.encoded
        XCTAssertEqual(encoded.count, WireHeader.size)
        let decoded = try XCTUnwrap(encoded.withUnsafeBytes { WireHeader(decoding: $0) })
        XCTAssertEqual(decoded, header)
    }

    func testRejectsBadMagic() {
        var bytes = WireHeader(type: 1, flags: 0, length: 4).encoded
        bytes[0] = 0x00
        XCTAssertNil(bytes.withUnsafeBytes { WireHeader(decoding: $0) })
    }

    func testRejectsOversizedLength() {
        let bytes = WireHeader(type: 1, flags: 0, length: WireHeader.maxPayloadLength + 1).encoded
        XCTAssertNil(bytes.withUnsafeBytes { WireHeader(decoding: $0) })
    }
}

final class LinkTypeTests: XCTestCase {
    func testThunderboltBridgeBeatsEverything() {
        XCTAssertEqual(LinkType.classify(name: "bridge0", type: .other), .thunderbolt)
        XCTAssertEqual(LinkType.classify(name: "bridge0", type: .wiredEthernet), .thunderbolt)
        XCTAssertEqual([LinkType.wifi, .peerToPeerWiFi, .thunderbolt, .ethernet].sorted().first, .thunderbolt)
    }

    func testInternetSharingBridgeIsNotThunderbolt() {
        XCTAssertNotEqual(LinkType.classify(name: "bridge100", type: .other), .thunderbolt)
    }

    func testAWDLAndWiFi() {
        XCTAssertEqual(LinkType.classify(name: "awdl0", type: .wifi), .peerToPeerWiFi)
        XCTAssertEqual(LinkType.classify(name: "llw0", type: .other), .peerToPeerWiFi)
        XCTAssertEqual(LinkType.classify(name: "en0", type: .wifi), .wifi)
        XCTAssertEqual(LinkType.classify(name: "en5", type: .wiredEthernet), .ethernet)
    }

    func testOrdering() {
        XCTAssertEqual(LinkType.allCases.sorted(),
                       [.thunderbolt, .ethernet, .wifi, .peerToPeerWiFi, .other, .loopback])
    }
}
