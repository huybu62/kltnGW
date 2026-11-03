import Foundation
import Network

/// What a device publishes in its Bonjour TXT record. Short keys keep the
/// record well under the ~400-byte size that fits a single mDNS packet.
///
/// | key  | example        | meaning                                   |
/// |------|----------------|-------------------------------------------|
/// | v    | 1              | protocol version                          |
/// | id   | 3fa1…(32 hex)  | identity fingerprint (stable across names)|
/// | r    | d              | role: h = host, d = display               |
/// | p    | ipad           | platform                                  |
/// | m    | iPad13,8       | hardware model                            |
/// | n    | Lan's iPad     | full display name (service name may be    |
/// |      |                | truncated or auto-renamed by Bonjour)     |
/// | res  | 2732x2048      | display pixels (displays only)            |
/// | hz   | 120            | max refresh (displays only)               |
/// | c    | hevc,h264      | decodable codecs (displays only)          |
/// | busy | 1              | already in a session                      |
public struct PeerAdvertisement: Hashable, Sendable {
    public var deviceID: String
    public var name: String
    public var role: PeerRole
    public var platform: DevicePlatform
    public var model: String
    public var protocolVersion: Int
    public var display: DisplayCapabilities?
    public var isBusy: Bool

    public init(device: DeviceInfo, isBusy: Bool = false) {
        deviceID = device.id
        name = device.name
        role = device.role
        platform = device.platform
        model = device.model
        protocolVersion = device.protocolVersion
        display = device.display
        self.isBusy = isBusy
    }

    public var isCompatible: Bool {
        protocolVersion >= ScreenBridgeService.minimumCompatibleVersion
    }

    // MARK: - TXT encoding

    public var txtDictionary: [String: String] {
        var txt: [String: String] = [
            "v": String(protocolVersion),
            "id": deviceID,
            "r": role.rawValue,
            "p": platform.rawValue,
            "m": model.truncatedUTF8(maxBytes: 64),
            "n": name.truncatedUTF8(maxBytes: 200),
            "busy": isBusy ? "1" : "0",
        ]
        if let display {
            txt["res"] = "\(display.pixelWidth)x\(display.pixelHeight)"
            txt["hz"] = String(display.maxRefreshRate)
            txt["c"] = display.supportsHEVC ? "hevc,h264" : "h264"
        }
        return txt
    }

    public init?(txtDictionary txt: [String: String]) {
        guard let id = txt["id"], !id.isEmpty,
              let roleRaw = txt["r"], let role = PeerRole(rawValue: roleRaw),
              let version = txt["v"].flatMap(Int.init) else {
            return nil  // not a ScreenBridge record, or garbage
        }
        deviceID = id
        self.role = role
        protocolVersion = version
        platform = txt["p"].flatMap(DevicePlatform.init(rawValue:)) ?? .unknown
        model = txt["m"] ?? ""
        name = txt["n"].flatMap { $0.isEmpty ? nil : $0 } ?? "Unnamed device"
        isBusy = txt["busy"] == "1"

        if let res = txt["res"]?.split(separator: "x"), res.count == 2,
           let width = Int(res[0]), let height = Int(res[1]) {
            display = DisplayCapabilities(
                pixelWidth: width, pixelHeight: height,
                maxRefreshRate: txt["hz"].flatMap(Int.init) ?? 60,
                supportsHEVC: txt["c"]?.contains("hevc") ?? false)
        } else {
            display = nil
        }
    }

    public var txtRecord: NWTXTRecord { NWTXTRecord(txtDictionary) }

    public init?(txtRecord: NWTXTRecord) {
        self.init(txtDictionary: txtRecord.dictionary)
    }

    /// Bonjour instance name. Collisions (two "iPad"s) are renamed by mDNS
    /// ("iPad (2)"); that's harmless because peers are keyed by `id`.
    public var serviceName: String {
        name.truncatedUTF8(maxBytes: ScreenBridgeService.maxServiceNameBytes)
    }
}
