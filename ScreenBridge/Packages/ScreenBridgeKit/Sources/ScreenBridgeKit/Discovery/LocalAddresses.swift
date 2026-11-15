import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// This device's IPv4 addresses, for the manual-connection fallback ("type
/// 192.168.1.20 : 52790 on the other device") when Bonjour can't get through.
public enum LocalAddresses {
    public struct Address: Hashable, Identifiable, Sendable {
        public var id: String { "\(interface)-\(address)" }
        /// BSD interface name, e.g. en0.
        public let interface: String
        public let address: String
        public let link: LinkType
    }

    public static func current() -> [Address] {
        var result: [Address] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }

        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  let socketAddress = entry.pointee.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(socketAddress, socklen_t(socketAddress.pointee.sa_len),
                              &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            let address = String(cString: host)
            let link = LinkType.classify(name: name, type: name.hasPrefix("en0") ? .wifi : .wiredEthernet)
            // Self-assigned addresses only matter on a Thunderbolt Bridge.
            if address.hasPrefix("169.254."), link != .thunderbolt { continue }
            // AWDL has no IPv4 address anyway; skip anything else that isn't useful.
            if link == .peerToPeerWiFi { continue }
            result.append(Address(interface: name, address: address, link: link))
        }
        return result.sorted { $0.link < $1.link }
    }
}
