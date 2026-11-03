import Foundation

/// Constants shared by every ScreenBridge build. Changing `type` requires
/// updating `NSBonjourServices` in every app's Info.plist (see project.yml).
public enum ScreenBridgeService {
    /// Bonjour service type advertised by both Hosts and Displays.
    public static let type = "_screenbridge._tcp"

    /// Wire/handshake protocol version we speak.
    public static let protocolVersion = 1

    /// Oldest peer protocol version we still accept.
    public static let minimumCompatibleVersion = 1

    /// Bonjour service instance names are limited to 63 UTF-8 bytes.
    static let maxServiceNameBytes = 63

    /// Each TXT `key=value` entry is limited to 255 bytes.
    static let maxTXTEntryBytes = 255
}

/// Which side of the mirroring session a device plays.
public enum PeerRole: String, Codable, Hashable, Sendable, CaseIterable {
    /// The Mac whose screen is captured and transmitted.
    case host = "h"
    /// The Mac / iPad that receives and renders the stream.
    case display = "d"

    /// The role this role wants to find on the network.
    public var counterpart: PeerRole { self == .host ? .display : .host }
}

/// Coarse device family, used for icons and capability defaults.
public enum DevicePlatform: String, Codable, Hashable, Sendable {
    case mac
    case iPad = "ipad"
    case iPhone = "iphone"
    case unknown

    public var systemImage: String {
        switch self {
        case .mac: return "desktopcomputer"
        case .iPad: return "ipad.landscape"
        case .iPhone: return "iphone"
        case .unknown: return "display"
        }
    }
}

extension String {
    /// Truncates to at most `maxBytes` UTF-8 bytes without splitting a character.
    func truncatedUTF8(maxBytes: Int) -> String {
        guard utf8.count > maxBytes else { return self }
        var result = ""
        var used = 0
        for character in self {
            let size = String(character).utf8.count
            if used + size > maxBytes { break }
            result.append(character)
            used += size
        }
        return result
    }
}
