import Foundation
import Network

/// Message types on the wire. Unknown values are delivered as-is (see
/// `WireMessage.rawType`) so newer peers can add types without breaking us.
public enum MessageType: UInt8, Sendable {
    // Handshake (plaintext, but every field is bound into the signed transcript)
    case clientHello = 0x01
    case serverHello = 0x02
    case keyReveal = 0x03
    case authenticate = 0x04
    case handshakeFailure = 0x0F

    // Post-handshake, sealed with SessionCrypto
    case sealedControl = 0x20

    // Reserved for Phase 2/3
    case sealedVideoFormat = 0x30   // parameter sets (SPS/PPS/VPS), resolution, codec
    case sealedVideoFrame = 0x31    // one encoded access unit
    case sealedAudio = 0x32         // 16-bit PCM, see AudioPacket
    case sealedInput = 0x40         // pointer / keyboard events from Display → Host
}

/// 8-byte frame header:
///
///     0      1      2      3      4      5      6      7
///   +------+------+------+------+------+------+------+------+
///   | 0x5B | type |    flags    |       payload length      |
///   +------+------+------+------+------+------+------+------+
///
/// All integers big-endian. The magic byte catches stream desync early.
struct WireHeader: Equatable {
    static let size = 8
    static let magic: UInt8 = 0x5B
    /// Upper bound on a single message. A 5K HEVC keyframe is ~1–3 MB.
    static let maxPayloadLength: UInt32 = 32 * 1024 * 1024

    var type: UInt8
    var flags: UInt16
    var length: UInt32

    var encoded: Data {
        Data([
            Self.magic, type,
            UInt8(flags >> 8), UInt8(flags & 0xFF),
            UInt8((length >> 24) & 0xFF), UInt8((length >> 16) & 0xFF),
            UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF),
        ])
    }

    /// Returns nil for a bad magic byte or an oversized length.
    init?(decoding bytes: UnsafeRawBufferPointer) {
        guard bytes.count >= Self.size, bytes[0] == Self.magic else { return nil }
        type = bytes[1]
        flags = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        length = UInt32(bytes[4]) << 24 | UInt32(bytes[5]) << 16 | UInt32(bytes[6]) << 8 | UInt32(bytes[7])
        guard length <= Self.maxPayloadLength else { return nil }
    }

    init(type: UInt8, flags: UInt16, length: UInt32) {
        self.type = type
        self.flags = flags
        self.length = length
    }
}

/// Length-prefixed message framing as an NWProtocolFramer, so NWConnection
/// hands us whole messages and the same stack works over any TCP path
/// (Thunderbolt, Ethernet, Wi-Fi, AWDL).
final class ScreenBridgeFramer: NWProtocolFramerImplementation {
    static let label = "ScreenBridge"
    static let definition = NWProtocolFramer.Definition(implementation: ScreenBridgeFramer.self)

    required init(framer: NWProtocolFramer.Instance) {}

    func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult { .ready }
    func wakeup(framer: NWProtocolFramer.Instance) {}
    func stop(framer: NWProtocolFramer.Instance) -> Bool { true }
    func cleanup(framer: NWProtocolFramer.Instance) {}

    func handleOutput(framer: NWProtocolFramer.Instance, message: NWProtocolFramer.Message,
                      messageLength: Int, isComplete: Bool) {
        guard messageLength <= Int(WireHeader.maxPayloadLength) else {
            framer.markFailed(error: .posix(.EMSGSIZE))
            return
        }
        let header = WireHeader(type: message.screenBridgeRawType,
                                flags: message.screenBridgeFlags,
                                length: UInt32(messageLength))
        framer.writeOutput(data: header.encoded)
        do {
            try framer.writeOutputNoCopy(length: messageLength)
        } catch {
            framer.markFailed(error: .posix(.EIO))
        }
    }

    func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        while true {
            var parsedHeader: WireHeader?
            var malformed = false
            let parsed = framer.parseInput(minimumIncompleteLength: WireHeader.size,
                                           maximumLength: WireHeader.size) { buffer, _ in
                guard let buffer, buffer.count >= WireHeader.size else { return 0 }
                parsedHeader = WireHeader(decoding: UnsafeRawBufferPointer(buffer))
                malformed = parsedHeader == nil
                return WireHeader.size
            }
            if malformed {
                framer.markFailed(error: .posix(.EBADMSG))
                return 0
            }
            guard parsed, let header = parsedHeader else {
                return WireHeader.size  // need more bytes for a header
            }
            let message = NWProtocolFramer.Message(screenBridgeRawType: header.type, flags: header.flags)
            if !framer.deliverInputNoCopy(length: Int(header.length), message: message, isComplete: true) {
                return 0  // body not fully arrived; we'll be called again
            }
        }
    }
}

extension NWProtocolFramer.Message {
    private static let typeKey = "sb.type"
    private static let flagsKey = "sb.flags"

    convenience init(screenBridgeRawType: UInt8, flags: UInt16 = 0) {
        self.init(definition: ScreenBridgeFramer.definition)
        self[Self.typeKey] = screenBridgeRawType
        self[Self.flagsKey] = flags
    }

    var screenBridgeRawType: UInt8 { self[Self.typeKey] as? UInt8 ?? 0 }
    var screenBridgeFlags: UInt16 { self[Self.flagsKey] as? UInt16 ?? 0 }
}

/// One framed message received from a peer.
public struct WireMessage: Sendable {
    public let rawType: UInt8
    public let flags: UInt16
    public let payload: Data

    public var type: MessageType? { MessageType(rawValue: rawType) }
}

/// JSON coding for handshake and control messages (small, infrequent).
/// Video payloads are binary and never go through JSON.
enum WireCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder = JSONDecoder()

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw PeerConnectionError.protocolViolation("Malformed \(T.self): \(error.localizedDescription)")
        }
    }
}
