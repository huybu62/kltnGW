import Foundation
import Network

/// One way to reach a peer: a Bonjour endpoint seen on a specific local interface.
public struct DiscoveredRoute: Hashable {
    public let endpoint: NWEndpoint
    public let interface: NWInterface?
    public let link: LinkType
}

/// A nearby device, merged across every interface it was seen on.
public struct DiscoveredPeer: Identifiable, Hashable {
    public var advertisement: PeerAdvertisement
    /// Best route first (Thunderbolt → Ethernet → Wi-Fi → Direct Wi-Fi).
    public var routes: [DiscoveredRoute]
    public var firstSeen: Date

    public var id: String { advertisement.deviceID }
    public var name: String { advertisement.name }
    public var bestLink: LinkType { routes.first?.link ?? .other }
    public var links: [LinkType] { Array(Set(routes.map(\.link))).sorted() }
    public var isAvailable: Bool { advertisement.isCompatible && !advertisement.isBusy }

    /// Endpoint to use when no specific interface is required.
    public var primaryEndpoint: NWEndpoint? { routes.first?.endpoint }
}

extension DiscoveredPeer {
    /// Groups raw browse results by device id. A Mac connected over both a
    /// Thunderbolt cable and Wi-Fi shows up once, with two routes.
    static func merge(results: Set<NWBrowser.Result>, excluding localID: String,
                      previous: [String: DiscoveredPeer], now: Date = Date()) -> [String: DiscoveredPeer] {
        var merged: [String: DiscoveredPeer] = [:]
        for result in results {
            guard case .bonjour(let txt) = result.metadata,
                  let advertisement = PeerAdvertisement(txtRecord: txt),
                  advertisement.deviceID != localID else { continue }

            let routes: [DiscoveredRoute]
            if result.interfaces.isEmpty {
                routes = [DiscoveredRoute(endpoint: result.endpoint, interface: nil, link: .other)]
            } else {
                routes = result.interfaces.map {
                    DiscoveredRoute(endpoint: result.endpoint, interface: $0, link: LinkType(interface: $0))
                }
            }

            if var existing = merged[advertisement.deviceID] {
                existing.routes.append(contentsOf: routes)
                existing.advertisement = advertisement
                merged[advertisement.deviceID] = existing
            } else {
                merged[advertisement.deviceID] = DiscoveredPeer(
                    advertisement: advertisement, routes: routes,
                    firstSeen: previous[advertisement.deviceID]?.firstSeen ?? now)
            }
        }
        return merged.mapValues { peer in
            var peer = peer
            peer.routes = Self.dedupe(peer.routes).sorted { $0.link < $1.link }
            return peer
        }
    }

    private static func dedupe(_ routes: [DiscoveredRoute]) -> [DiscoveredRoute] {
        var seen = Set<String>()
        return routes.filter { route in
            let key = "\(route.endpoint.debugDescription)|\(route.interface?.name ?? "-")"
            return seen.insert(key).inserted
        }
    }
}
