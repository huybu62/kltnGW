import Foundation
import Network

/// The single place NWParameters are built, so the listener (Display/Host
/// advertiser) and outgoing connections always agree on the protocol stack.
public enum ScreenBridgeParameters {
    /// TCP + ScreenBridge framing.
    ///
    /// No TLS layer here on purpose: TLS needs certificates or a PSK known
    /// *before* the handshake, and neither exists between devices on
    /// different Apple IDs that have never met. Instead the application-level
    /// handshake (`SessionHandshake`) does ECDH + identity signatures and all
    /// post-handshake traffic is sealed with ChaCha20-Poly1305.
    ///
    /// - Parameters:
    ///   - requiredInterface: pin the connection to one interface, used to
    ///     force Thunderbolt/Ethernet when the peer is reachable there.
    ///   - prohibitWiFi: skip Wi-Fi (incl. AWDL); used to look for a cable path.
    public static func make(requiredInterface: NWInterface? = nil, prohibitWiFi: Bool = false) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true                 // never Nagle a video frame
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 2
        tcp.keepaliveInterval = 1
        tcp.keepaliveCount = 3             // dead peer noticed in ~5 s
        tcp.connectionTimeout = 6

        let parameters = NWParameters(tls: nil, tcp: tcp)
        // AWDL: lets two devices connect with no shared Wi-Fi network (or on
        // networks with client isolation) regardless of Apple ID.
        parameters.includePeerToPeer = true
        parameters.serviceClass = .interactiveVideo
        parameters.prohibitedInterfaceTypes = prohibitWiFi ? [.cellular, .wifi] : [.cellular]
        if let requiredInterface {
            parameters.requiredInterface = requiredInterface
        }

        let framer = NWProtocolFramer.Options(definition: ScreenBridgeFramer.definition)
        parameters.defaultProtocolStack.applicationProtocols.insert(framer, at: 0)
        return parameters
    }

    /// Parameters for NWBrowser (discovery only; no protocol stack needed).
    static func browsing() -> NWParameters {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        parameters.prohibitedInterfaceTypes = [.cellular]
        return parameters
    }
}
