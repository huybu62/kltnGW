import XCTest
import CoreMedia
import CoreVideo
@testable import ScreenBridgeKit

final class VideoProtocolTests: XCTestCase {
    func testFrameHeaderRoundTrip() throws {
        let header = VideoFrameHeader(frameNumber: 0xDEADBEEF, streamID: 42, timestampMicros: 123_456_789_012)
        let encoded = header.encoded()
        XCTAssertEqual(encoded.count, VideoFrameHeader.size)
        XCTAssertEqual(VideoFrameHeader(encoded + Data([1, 2, 3])), header)
        XCTAssertNil(VideoFrameHeader(Data(count: 8)))
    }

    func testNewControlMessagesRoundTrip() throws {
        for message in [ControlMessage.requestKeyframe, .frameAck(frameNumber: 7), .streamStopped(reason: "x"),
                        .cursor(x: 0.25, y: 0.5, visible: true)] {
            let data = try WireCoding.encode(message)
            XCTAssertEqual(try WireCoding.decode(ControlMessage.self, from: data), message)
        }
    }

    func testBitrateStaysInBounds() {
        XCTAssertEqual(StreamQuality.lowPower.bitrate(width: 16, height: 16, framesPerSecond: 30), 4_000_000)
        XCTAssertEqual(StreamQuality.maximum.bitrate(width: 8000, height: 8000, framesPerSecond: 120), 100_000_000)
        let ipad60 = StreamQuality.balanced.bitrate(width: 2732, height: 2048, framesPerSecond: 60)
        XCTAssertGreaterThan(ipad60, 15_000_000)
        XCTAssertLessThan(ipad60, 40_000_000)
        let ipad120 = StreamQuality.balanced.bitrate(width: 2732, height: 2048, framesPerSecond: 120)
        XCTAssertEqual(Double(ipad120) / Double(ipad60), 1.5, accuracy: 0.01)
    }

    func testFrameRateClampsToDisplay() {
        XCTAssertEqual(StreamFrameRate.clamped(.fps120, toDisplayMax: 120), .fps120)
        XCTAssertEqual(StreamFrameRate.clamped(.fps120, toDisplayMax: 60), .fps60)
        XCTAssertEqual(StreamFrameRate.clamped(.fps60, toDisplayMax: 120), .fps60)
        XCTAssertEqual(StreamFrameRate.clamped(.fps120, toDisplayMax: nil), .fps60)
        XCTAssertEqual(StreamFrameRate.clamped(.fps30, toDisplayMax: 120), .fps30)
    }

    func testEvenDimensions() {
        XCTAssertEqual(evenDimension(1365.4), 1364)
        XCTAssertEqual(evenDimension(1366), 1366)
        XCTAssertEqual(evenDimension(0.2), 2)
    }
}

#if os(macOS)
/// Real hardware encoder → real decoder, exactly the bytes that go on the wire.
final class VideoPipelineTests: XCTestCase {
    private func makePixelBuffer(width: Int, height: Int, luma: UInt8) -> CVPixelBuffer {
        var created: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [String: Any]()]
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                            attributes as CFDictionary, &created)
        let buffer = created!
        CVPixelBufferLockBaseAddress(buffer, [])
        for plane in 0..<CVPixelBufferGetPlaneCount(buffer) {
            if let base = CVPixelBufferGetBaseAddressOfPlane(buffer, plane) {
                let size = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane) * CVPixelBufferGetHeightOfPlane(buffer, plane)
                memset(base, Int32(plane == 0 ? luma : 128), size)
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    private func roundTrip(_ codec: VideoCodec) throws {
        let width = 640, height = 360
        let encoder = try VideoEncoder(configuration: .init(codec: codec, width: width, height: height,
                                                            framesPerSecond: 30, bitrate: 2_000_000))
        let lock = NSLock()
        var frames: [VideoEncoder.EncodedFrame] = []
        encoder.onOutput = { frame in
            guard let frame else { return }
            lock.lock(); frames.append(frame); lock.unlock()
        }
        for index in 0..<6 {
            encoder.encode(makePixelBuffer(width: width, height: height, luma: UInt8(30 * index)),
                           presentationTime: CMTime(value: Int64(index), timescale: 30))
        }
        encoder.invalidate()  // flushes all pending frames first

        lock.lock(); let output = frames; lock.unlock()
        XCTAssertFalse(output.isEmpty, "encoder produced nothing")
        let first = try XCTUnwrap(output.first)
        XCTAssertTrue(first.isKeyframe)
        let sets = try XCTUnwrap(first.parameterSets)
        XCTAssertGreaterThanOrEqual(sets.count, encoder.codec == .hevc ? 3 : 2)

        let format = VideoFormat(streamID: 1, codec: encoder.codec, width: width, height: height,
                                 parameterSets: sets, nalUnitHeaderLength: first.nalUnitHeaderLength)
        // Survives the JSON trip it takes over the network.
        let wireFormat = try WireCoding.decode(VideoFormat.self, from: WireCoding.encode(format))
        let decoder = VideoDecoder()
        XCTAssertTrue(decoder.configure(wireFormat))

        let decoded = expectation(description: "decoded")
        decoded.expectedFulfillmentCount = output.count
        decoder.onDecoded = { pixelBuffer in
            XCTAssertEqual(CVPixelBufferGetWidth(pixelBuffer), width)
            XCTAssertEqual(CVPixelBufferGetHeight(pixelBuffer), height)
            decoded.fulfill()
        }
        decoder.onNeedsKeyframe = { XCTFail("decoder lost sync") }
        for frame in output {
            decoder.decode(frame.data, isKeyframe: frame.isKeyframe)
        }
        wait(for: [decoded], timeout: 10)
    }

    func testH264RoundTrip() throws { try roundTrip(.h264) }

    /// Falls back to H.264 automatically on Macs without an HEVC encoder.
    func testHEVCRoundTrip() throws { try roundTrip(.hevc) }
}
#endif
