import Foundation
import CoreMedia
import VideoToolbox
#if os(macOS)
import AppKit
import SystemConfiguration
#elseif os(iOS)
import UIKit
#endif

/// What a Display can render. Advertised in TXT so the Host's radar can show
/// "iPad Pro · 2732×2048 · 120 Hz" before connecting; re-sent in the handshake.
public struct DisplayCapabilities: Codable, Hashable, Sendable {
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var maxRefreshRate: Int
    public var supportsHEVC: Bool

    public init(pixelWidth: Int, pixelHeight: Int, maxRefreshRate: Int, supportsHEVC: Bool) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.maxRefreshRate = maxRefreshRate
        self.supportsHEVC = supportsHEVC
    }

    /// "2732×2048"
    public var resolutionLabel: String { "\(pixelWidth)×\(pixelHeight)" }
}

/// Public description of a device. Contains nothing tied to an Apple ID:
/// `id` is the fingerprint of a locally generated signing key.
public struct DeviceInfo: Codable, Hashable, Sendable, Identifiable {
    /// Fingerprint of the device's identity key (see `DeviceIdentity`).
    public let id: String
    public var name: String
    public var platform: DevicePlatform
    public var model: String
    public var role: PeerRole
    public var protocolVersion: Int
    public var display: DisplayCapabilities?

    public init(id: String, name: String, platform: DevicePlatform, model: String,
                role: PeerRole, protocolVersion: Int = ScreenBridgeService.protocolVersion,
                display: DisplayCapabilities?) {
        self.id = id
        self.name = name
        self.platform = platform
        self.model = model
        self.role = role
        self.protocolVersion = protocolVersion
        self.display = display
    }

    /// Key in `UserDefaults` for a user-chosen device name. On iPadOS 16+
    /// `UIDevice.name` returns just "iPad" without a special entitlement, so we
    /// let people rename the device instead of relying on the iCloud name.
    public static let customNameDefaultsKey = "ScreenBridge.customDeviceName"

    /// Describes this device. Must run on the main thread (reads screen info).
    @MainActor
    public static func current(role: PeerRole, identity: DeviceIdentity,
                               defaults: UserDefaults = .standard) -> DeviceInfo {
        let custom = defaults.string(forKey: customNameDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (custom?.isEmpty == false ? custom! : systemDeviceName(fingerprint: identity.fingerprint))
        return DeviceInfo(
            id: identity.fingerprint,
            name: name,
            platform: currentPlatform,
            model: hardwareModel,
            role: role,
            display: role == .display ? currentDisplayCapabilities() : nil
        )
    }

    // MARK: - Platform probing

    @MainActor
    static var currentPlatform: DevicePlatform {
        #if os(macOS)
        return .mac
        #elseif os(iOS)
        if ProcessInfo.processInfo.isiOSAppOnMac { return .mac }
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: return .iPad
        case .phone: return .iPhone
        default: return .unknown
        }
        #else
        return .unknown
        #endif
    }

    @MainActor
    static func systemDeviceName(fingerprint: String) -> String {
        #if os(macOS)
        // SystemConfiguration is fast and sandbox-safe (Host.current() can block on DNS).
        if let name = SCDynamicStoreCopyComputerName(nil, nil) as String?, !name.isEmpty {
            return name
        }
        return "Mac"
        #elseif os(iOS)
        let name = UIDevice.current.name
        // Generic names ("iPad") are ambiguous on a radar full of iPads; add a short tag.
        if name == UIDevice.current.model {
            return "\(name) (\(fingerprint.prefix(4).uppercased()))"
        }
        return name
        #else
        return "Device"
        #endif
    }

    static var hardwareModel: String {
        #if os(macOS)
        return sysctlString("hw.model") ?? "Mac"
        #else
        return sysctlString("hw.machine") ?? "iOS"
        #endif
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    @MainActor
    static func currentDisplayCapabilities() -> DisplayCapabilities? {
        let hevc = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        #if os(macOS)
        guard let screen = NSScreen.main else { return nil }
        let scale = screen.backingScaleFactor
        return DisplayCapabilities(
            pixelWidth: Int(screen.frame.width * scale),
            pixelHeight: Int(screen.frame.height * scale),
            maxRefreshRate: max(screen.maximumFramesPerSecond, 60),
            supportsHEVC: hevc
        )
        #elseif os(iOS)
        let screen = UIScreen.main
        let native = screen.nativeBounds.size
        // nativeBounds is portrait-up; report landscape since that's how a second display is used.
        return DisplayCapabilities(
            pixelWidth: Int(max(native.width, native.height)),
            pixelHeight: Int(min(native.width, native.height)),
            maxRefreshRate: max(screen.maximumFramesPerSecond, 60),
            supportsHEVC: hevc
        )
        #else
        return nil
        #endif
    }
}
