import Foundation

/// Prefix of every `sealedAudio` payload, followed by interleaved signed
/// 16-bit little-endian PCM. Uncompressed on purpose: 48 kHz stereo is only
/// ~1.5 Mbit/s (tiny next to video) and adds no codec delay.
struct AudioPacketHeader: Equatable {
    static let size = 8
    static let sampleRate: UInt32 = 48_000
    static let channels: UInt16 = 2

    var sampleRate: UInt32
    var channels: UInt16

    func encoded() -> Data {
        var data = Data(capacity: Self.size)
        for shift in stride(from: 24, through: 0, by: -8) { data.append(UInt8((sampleRate >> UInt32(shift)) & 0xFF)) }
        data.append(UInt8(channels >> 8))
        data.append(UInt8(channels & 0xFF))
        data.append(contentsOf: [0, 0])  // reserved
        return data
    }

    init(sampleRate: UInt32 = Self.sampleRate, channels: UInt16 = Self.channels) {
        self.sampleRate = sampleRate
        self.channels = channels
    }

    init?(_ data: Data) {
        guard data.count >= Self.size else { return nil }
        let bytes = Array(data.prefix(Self.size))
        sampleRate = bytes[0..<4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        channels = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
    }
}
