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
            .key(usage: 0x04, down: true),
            .macKey(code: 0x37, down: false),
            .zoom(zoomIn: true, x: 0.5, y: 0.5),
            .modifierState(flags: 0x14_0000),
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

    func testAudioHeaderRoundTrip() throws {
        let header = AudioPacketHeader()
        let decoded = try XCTUnwrap(AudioPacketHeader(header.encoded() + Data(repeating: 1, count: 16)))
        XCTAssertEqual(decoded, header)
        XCTAssertEqual(decoded.sampleRate, 48_000)
        XCTAssertNil(AudioPacketHeader(Data([0, 1])))
    }
}

#if os(macOS)
final class KeyMapTests: XCTestCase {
    func testCommonKeys() {
        XCTAssertEqual(KeyMap.macKeyCode(forHIDUsage: 0x04), 0x00)  // A
        XCTAssertEqual(KeyMap.macKeyCode(forHIDUsage: 0x1D), 0x06)  // Z
        XCTAssertEqual(KeyMap.macKeyCode(forHIDUsage: 0x27), 0x1D)  // 0
        XCTAssertEqual(KeyMap.macKeyCode(forHIDUsage: 0x28), 0x24)  // Return
        XCTAssertEqual(KeyMap.macKeyCode(forHIDUsage: 0x2C), 0x31)  // Space
        XCTAssertEqual(KeyMap.macKeyCode(forHIDUsage: 0x50), 0x7B)  // ←
        XCTAssertEqual(KeyMap.macKeyCode(forHIDUsage: 0x3A), 0x7A)  // F1
        XCTAssertEqual(KeyMap.macKeyCode(forHIDUsage: 0xE3), 0x37)  // Left ⌘
        XCTAssertNil(KeyMap.macKeyCode(forHIDUsage: 0x00))
    }

    func testEveryLetterAndDigitIsMappedOnce() {
        let codes = (0x04...0x27).compactMap { KeyMap.macKeyCode(forHIDUsage: UInt16($0)) }
        XCTAssertEqual(codes.count, 36)
        XCTAssertEqual(Set(codes).count, 36)
    }

    func testModifiers() {
        XCTAssertEqual(KeyMap.modifier(forMacKeyCode: 0x37), .command)
        XCTAssertEqual(KeyMap.modifier(forMacKeyCode: 0x3D), .option)
        XCTAssertNil(KeyMap.modifier(forMacKeyCode: 0x00))
    }
}
#endif
