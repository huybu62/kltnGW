import XCTest
import CoreGraphics
@testable import ScreenBridgeKit

final class InputTests: XCTestCase {
    func testInputEventsRoundTrip() throws {
        let events: [InputEvent] = [
            .pointer(phase: .began, button: .left, x: 0.25, y: 0.75),
            .pointer(phase: .moved, button: .none, x: 1, y: 0),
            .rightClick(x: 0.5, y: 0.5),
            .scroll(phase: .moved, x: 0.1, y: 0.2, deltaX: -3.5, deltaY: 12),
        ]
        for event in events {
            XCTAssertEqual(try WireCoding.decode(InputEvent.self, from: WireCoding.encode(event)), event)
        }
    }

    func testLetterboxedVideoMapping() {
        // 16:10 Mac picture shown on a 4:3 iPad view → bars top and bottom.
        let bounds = CGRect(x: 0, y: 0, width: 1024, height: 768)
        let video = CGSize(width: 2880, height: 1800)
        let rect = VideoGeometry.videoRect(videoSize: video, in: bounds)
        XCTAssertEqual(rect.width, 1024, accuracy: 0.01)
        XCTAssertEqual(rect.height, 640, accuracy: 0.01)
        XCTAssertEqual(rect.minY, 64, accuracy: 0.01)

        let center = VideoGeometry.normalize(CGPoint(x: 512, y: 384), videoSize: video, in: bounds)
        XCTAssertEqual(center.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(center.y, 0.5, accuracy: 0.001)

        // A touch in the black bar clamps to the picture's edge.
        let inBar = VideoGeometry.normalize(CGPoint(x: 0, y: 10), videoSize: video, in: bounds)
        XCTAssertEqual(inBar.x, 0)
        XCTAssertEqual(inBar.y, 0)
    }
}
