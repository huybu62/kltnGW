import Foundation
import Network

/// Health of one discovery component (browser or advertiser), reduced to the
/// cases the UI needs to explain.
public enum DiscoveryHealth: Equatable, Sendable {
    case idle
    case starting
    case running
    /// The user (or MDM) denied the Local Network permission. Nothing will be
    /// found until it is enabled in Settings; retrying is pointless.
    case localNetworkDenied
    /// Temporary problem (Wi-Fi off, interface down). We keep retrying.
    case waiting(String)
    case failed(String)

    init(error: NWError, failed: Bool) {
        if LocalNetworkDiagnostics.isPolicyDenied(error) {
            self = .localNetworkDenied
        } else if failed {
            self = .failed(error.localizedDescription)
        } else {
            self = .waiting(error.localizedDescription)
        }
    }

    /// Combines browser + advertiser health into the one worth showing.
    static func worst(_ a: DiscoveryHealth, _ b: DiscoveryHealth) -> DiscoveryHealth {
        func severity(_ h: DiscoveryHealth) -> Int {
            switch h {
            case .localNetworkDenied: return 5
            case .failed: return 4
            case .waiting: return 3
            case .starting: return 2
            case .idle: return 1
            case .running: return 0
            }
        }
        return severity(a) >= severity(b) ? a : b
    }
}

/// Helpers for the iOS 14+ / macOS 15+ Local Network privacy gate. This is
/// the #1 reason "it finds nothing" — and it is per app, not per Apple ID.
public enum LocalNetworkDiagnostics {
    /// kDNSServiceErr_PolicyDenied from <dns_sd.h>.
    static let policyDeniedCode: Int32 = -65570

    public static func isPolicyDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error { return Int32(code) == policyDeniedCode }
        return false
    }

    /// Plain-language steps for the current platform.
    public static var enablePermissionSteps: [String] {
        #if os(macOS)
        return [
            "Open System Settings → Privacy & Security → Local Network.",
            "Turn on ScreenBridge.",
            "Quit and reopen ScreenBridge.",
        ]
        #else
        return [
            "Open Settings → Privacy & Security → Local Network.",
            "Turn on ScreenBridge.",
            "Come back to ScreenBridge; it will start searching again.",
        ]
        #endif
    }
}
