import Foundation
import Network

/// The physical link a peer was discovered on / a connection runs over,
/// ordered best-first. Thunderbolt always wins when it is plugged in.
public enum LinkType: String, Codable, Hashable, Sendable, CaseIterable, Comparable {
    /// Thunderbolt Bridge (Mac ↔ Mac cable). ~10–40 Gbit/s, sub-ms latency.
    case thunderbolt
    /// Ethernet, including USB-C Ethernet adapters on iPad.
    case ethernet
    /// Both devices on the same Wi-Fi network (infrastructure mode).
    case wifi
    /// Apple Wireless Direct Link: device-to-device Wi-Fi with no router,
    /// works between different Apple IDs. Same tech AirDrop uses.
    case peerToPeerWiFi
    case other
    case loopback

    /// Lower is better.
    public var rank: Int {
        switch self {
        case .thunderbolt: return 0
        case .ethernet: return 1
        case .wifi: return 2
        case .peerToPeerWiFi: return 3
        case .other: return 4
        case .loopback: return 5
        }
    }

    public static func < (lhs: LinkType, rhs: LinkType) -> Bool { lhs.rank < rhs.rank }

    public var isWired: Bool { self == .thunderbolt || self == .ethernet }

    /// How long to wait for a TCP connect on this link before falling back.
    var connectTimeout: TimeInterval { isWired || self == .loopback ? 2 : 5 }

    public var displayName: String {
        switch self {
        case .thunderbolt: return "Thunderbolt"
        case .ethernet: return "Ethernet"
        case .wifi: return "Wi-Fi"
        case .peerToPeerWiFi: return "Direct Wi-Fi"
        case .other: return "Network"
        case .loopback: return "This Mac"
        }
    }

    public var systemImage: String {
        switch self {
        case .thunderbolt: return "bolt.horizontal.fill"
        case .ethernet: return "cable.connector"
        case .wifi: return "wifi"
        case .peerToPeerWiFi: return "antenna.radiowaves.left.and.right"
        case .other: return "network"
        case .loopback: return "arrow.triangle.2.circlepath"
        }
    }

    public init(interface: NWInterface) {
        self = LinkType.classify(name: interface.name, type: interface.type)
    }

    /// Classification by BSD interface name first (more specific than type):
    /// - `bridge0…bridge99` is the Thunderbolt Bridge on macOS (`bridge100+`
    ///   are created by Internet Sharing, so those are not Thunderbolt).
    /// - `awdl*` / `llw*` are AWDL peer-to-peer Wi-Fi.
    static func classify(name: String, type: NWInterface.InterfaceType) -> LinkType {
        if name.hasPrefix("awdl") || name.hasPrefix("llw") { return .peerToPeerWiFi }
        if name.hasPrefix("bridge"), let index = Int(name.dropFirst("bridge".count)), index < 100 {
            return .thunderbolt
        }
        switch type {
        case .wiredEthernet: return .ethernet
        case .wifi: return .wifi
        case .loopback: return .loopback
        default: return .other
        }
    }
}
