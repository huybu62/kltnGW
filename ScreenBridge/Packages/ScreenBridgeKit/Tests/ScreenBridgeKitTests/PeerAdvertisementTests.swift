import XCTest
@testable import ScreenBridgeKit

final class PeerAdvertisementTests: XCTestCase {
    private func makeDevice(name: String = "Lan’s iPad Pro", role: PeerRole = .display) -> DeviceInfo {
        DeviceInfo(id: "3fa1c2d4e5f60718293a4b5c6d7e8f90", name: name, platform: .iPad,
                   model: "iPad13,8", role: role,
                   display: DisplayCapabilities(pixelWidth: 2732, pixelHeight: 2048,
                                                maxRefreshRate: 120, supportsHEVC: true))
    }

    func testRoundTripThroughTXTDictionary() throws {
        let original = PeerAdvertisement(device: makeDevice(), isBusy: true)
        let decoded = try XCTUnwrap(PeerAdvertisement(txtDictionary: original.txtDictionary))
        XCTAssertEqual(decoded, original)
    }

    func testHostRecordHasNoDisplayKeys() {
        let host = PeerAdvertisement(device: DeviceInfo(id: "abc", name: "Mac Studio", platform: .mac,
                                                        model: "Mac13,1", role: .host, display: nil))
        XCTAssertNil(host.txtDictionary["res"])
        XCTAssertNil(PeerAdvertisement(txtDictionary: host.txtDictionary)?.display)
    }

    func testRejectsForeignRecords() {
        XCTAssertNil(PeerAdvertisement(txtDictionary: [:]))
        XCTAssertNil(PeerAdvertisement(txtDictionary: ["id": "x", "r": "zz", "v": "1"]))
        XCTAssertNil(PeerAdvertisement(txtDictionary: ["id": "x", "r": "d"]))  // no version
    }

    func testEveryEntryFitsTXTLimits() {
        let longName = String(repeating: "🖥️", count: 200)
        let ad = PeerAdvertisement(device: makeDevice(name: longName))
        for (key, value) in ad.txtDictionary {
            XCTAssertLessThanOrEqual(key.utf8.count + 1 + value.utf8.count, ScreenBridgeService.maxTXTEntryBytes)
        }
        XCTAssertLessThanOrEqual(ad.serviceName.utf8.count, ScreenBridgeService.maxServiceNameBytes)
    }

    func testUTF8TruncationNeverSplitsCharacters() {
        let s = "ÀÀÀ"  // 2 bytes each
        XCTAssertEqual(s.truncatedUTF8(maxBytes: 5), "ÀÀ")
        XCTAssertEqual(s.truncatedUTF8(maxBytes: 100), s)
    }

    func testIncompatibleVersionIsUnavailable() throws {
        var dict = PeerAdvertisement(device: makeDevice()).txtDictionary
        dict["v"] = "0"
        let ad = try XCTUnwrap(PeerAdvertisement(txtDictionary: dict))
        XCTAssertFalse(ad.isCompatible)
    }
}
