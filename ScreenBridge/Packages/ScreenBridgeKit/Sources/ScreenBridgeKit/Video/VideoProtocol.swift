import Foundation
import CoreMedia

public enum VideoCodec: String, Codable, Sendable {
    case h264
    case hevc

    public var displayName: String { self == .hevc ? "HEVC" : "H.264" }

    var codecType: CMVideoCodecType {
        self == .hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264
    }
}

/// Extend = the iPad/Mac becomes an extra screen (virtual display).
/// Mirror = it shows a copy of the Host's main screen.
public enum StreamMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case extend
    case mirror

    public var id: String { rawValue }
    public var displayName: String { self == .extend ? "Extend" : "Mirror" }
}

/// How many frames per second to stream. 120 needs a ProMotion display
/// (iPad Pro) and a fast link; the Host clamps to what the Display supports.
public enum StreamFrameRate: Int, Codable, CaseIterable, Sendable, Identifiable {
    case fps30 = 30
    case fps60 = 60
    case fps120 = 120

    public var id: Int { rawValue }
    public var displayName: String { "\(rawValue) Hz" }

    /// The highest option the Display can show.
    static func clamped(_ requested: StreamFrameRate, toDisplayMax maxRefresh: Int?) -> StreamFrameRate {
        let limit = maxRefresh ?? 60
        return allCases.reversed().first { $0.rawValue <= max(limit, 30) && $0.rawValue <= requested.rawValue } ?? .fps30
    }
}

/// Resolution + bitrate. Frame rate is chosen separately.
public enum StreamQuality: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Half resolution, low bitrate: least battery and Wi-Fi use.
    case lowPower
    /// The display's full resolution.
    case balanced
    /// Full resolution, generous bitrate for text and fine detail.
    case maximum

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .lowPower: return "Battery Saver"
        case .balanced: return "Balanced"
        case .maximum: return "Best Quality"
        }
    }

    var resolutionScale: Double { self == .lowPower ? 0.5 : 1.0 }

    /// Encoded bits per pixel per frame. Desktop content is mostly static
    /// and compresses very well, so these are modest.
    var bitsPerPixel: Double {
        switch self {
        case .lowPower: return 0.05
        case .balanced: return 0.08
        case .maximum: return 0.14
        }
    }

    /// Frames above 60 fps differ less from each other, so they get half
    /// weight: 120 fps costs ~1.5× the bitrate of 60, not 2×.
    func bitrate(width: Int, height: Int, framesPerSecond: Int) -> Int {
        let fps = Double(framesPerSecond)
        let effectiveFPS = fps <= 60 ? fps : 60 + (fps - 60) / 2
        let raw = Double(width * height) * effectiveFPS * bitsPerPixel
        return Int(min(max(raw, 4_000_000), 100_000_000))
    }
}

/// Sent (sealed, JSON) before the first frame and with every keyframe, so
/// the Display can (re)build its decoder at any time.
public struct VideoFormat: Codable, Sendable, Equatable {
    public var streamID: UInt32
    public var codec: VideoCodec
    public var width: Int
    public var height: Int
    /// SPS/PPS (H.264) or VPS/SPS/PPS (HEVC), without start codes.
    public var parameterSets: [Data]
    /// Size of the length prefix before each NAL unit (normally 4).
    public var nalUnitHeaderLength: Int
    /// Frame rate the Host streams at. The iPad keeps ProMotion at 120 Hz
    /// when this is above 60, so touch/trackpad input is reported at 120 Hz too.
    public var framesPerSecond: Int? = nil
}

/// Prefix of every `sealedVideoFrame` payload; the rest is one encoded
/// access unit in AVCC/HVCC form (length-prefixed NAL units), exactly as
/// VideoToolbox produces and consumes it, so no conversion on either side.
struct VideoFrameHeader: Equatable {
    static let size = 16

    var frameNumber: UInt32
    var streamID: UInt32
    var timestampMicros: UInt64

    func encoded() -> Data {
        var data = Data(capacity: Self.size)
        Self.append(UInt64(frameNumber), bytes: 4, to: &data)
        Self.append(UInt64(streamID), bytes: 4, to: &data)
        Self.append(timestampMicros, bytes: 8, to: &data)
        return data
    }

    init(frameNumber: UInt32, streamID: UInt32, timestampMicros: UInt64) {
        self.frameNumber = frameNumber
        self.streamID = streamID
        self.timestampMicros = timestampMicros
    }

    init?(_ data: Data) {
        guard data.count >= Self.size else { return nil }
        let bytes = Array(data.prefix(Self.size))
        func read(_ offset: Int, _ count: Int) -> UInt64 {
            bytes[offset..<(offset + count)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        }
        frameNumber = UInt32(read(0, 4))
        streamID = UInt32(read(4, 4))
        timestampMicros = read(8, 8)
    }

    private static func append(_ value: UInt64, bytes: Int, to data: inout Data) {
        for shift in stride(from: (bytes - 1) * 8, through: 0, by: -8) {
            data.append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
    }
}

enum VideoFrameFlags {
    static let keyframe: UInt16 = 0x0001
}

/// Live numbers shown in the UI on both sides.
public struct StreamStats: Equatable, Sendable {
    public var codec: VideoCodec
    public var width: Int
    public var height: Int
    public var framesPerSecond: Double
    public var megabitsPerSecond: Double
    /// Host: send → Display acknowledgement. Display: nil.
    public var latencyMs: Double?
    /// Host: frames skipped because the link was busy (flow control).
    public var skippedFrames: Int

    public var summary: String {
        var parts = ["\(codec.displayName) \(width)×\(height)",
                     String(format: "%.0f fps", framesPerSecond),
                     String(format: "%.1f Mbps", megabitsPerSecond)]
        if let latencyMs { parts.append(String(format: "%.0f ms", latencyMs)) }
        return parts.joined(separator: " · ")
    }
}

/// Makes `value` even and at least 2 (encoders need even dimensions).
func evenDimension(_ value: Double) -> Int {
    max(2, Int(value.rounded()) & ~1)
}
