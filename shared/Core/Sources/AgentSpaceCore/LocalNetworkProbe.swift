import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Reads what this Mac currently owns on the network: interface addresses, the
/// subnets they sit in, and the IPv4 routing table.
///
/// Read-only and side-effect free. Every failure degrades to
/// `LocalNetworkSnapshot.unknown` rather than to an empty snapshot, because an
/// empty snapshot would be reported as "no conflict" — a claim this code has not
/// earned.
public enum LocalNetworkProbe {

    public static func snapshot() -> LocalNetworkSnapshot {
        guard let interfaces = interfaceSnapshot() else { return .unknown }
        guard let routes = routingTable() else {
            // Addresses without routes is still useful, but the overlap check
            // would silently miss every route, so say the snapshot is partial
            // by leaving `complete` false while keeping what was read.
            return LocalNetworkSnapshot(
                addresses: interfaces.addresses,
                interfaceNetworks: interfaces.networks,
                routes: [],
                complete: false)
        }
        return LocalNetworkSnapshot(
            addresses: interfaces.addresses,
            interfaceNetworks: interfaces.networks,
            routes: routes,
            complete: true)
    }

    /// Just the addresses and subnets, from `getifaddrs`.
    public static func interfaceSnapshot() -> (addresses: [IPv4Address], networks: [IPv4Network])? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var addresses: [IPv4Address] = []
        var networks: [IPv4Network] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = pointer {
            defer { pointer = entry.pointee.ifa_next }
            guard let sockaddrPointer = entry.pointee.ifa_addr,
                  sockaddrPointer.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(entry.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0 else { continue }

            let address = sockaddrPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                IPv4Address(rawValue: UInt32(bigEndian: $0.pointee.sin_addr.s_addr))
            }
            addresses.append(address)

            if let maskPointer = entry.pointee.ifa_netmask {
                let mask = maskPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                }
                // Only contiguous masks describe a network; anything else is a
                // misconfigured interface and must not be turned into a prefix.
                if let prefix = prefixLength(mask),
                   let network = IPv4Network(address: address, prefixLength: prefix),
                   prefix < 32 {
                    networks.append(network)
                }
            }
        }
        return (addresses, networks)
    }

    /// Number of leading ones in a netmask, or nil when the mask has a hole.
    public static func prefixLength(_ mask: UInt32) -> Int? {
        guard mask != 0 else { return 0 }
        let inverted = ~mask
        // A contiguous mask has no set bit after the first zero.
        guard inverted & (inverted &+ 1) == 0 else { return nil }
        return mask.nonzeroBitCount
    }

    /// The IPv4 routing table, via `netstat -rn -f inet`.
    ///
    /// Shelled out rather than read through `sysctl(PF_ROUTE)`: the sysctl
    /// structure is version-dependent and easy to mis-parse silently, while
    /// `netstat`'s text is stable, visible, and can be fed to `parseRoutes` by a
    /// test without a live tunnel.
    public static func routingTable() -> [IPv4Network]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        process.arguments = ["-rn", "-f", "inet"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return parseRoutes(text)
    }

    /// Parse `netstat -rn -f inet` output into the networks it routes.
    ///
    /// Default routes (`default`) are skipped: a default route covers every
    /// address and would make every pool look overlapping. Host routes are
    /// returned as /32 so an exact collision is visible.
    ///
    /// `netstat` abbreviates destinations by dropping trailing zero octets —
    /// `127`, `169.254`, `192.168.1` mean `127.0.0.0/8`, `169.254.0.0/16` and
    /// `192.168.1.0/24`. Treating those as unparseable (the first version did)
    /// silently dropped most of the real routing table, which turned a machine
    /// with three overlapping LANs into a "clean" conflict check.
    public static func parseRoutes(_ text: String) -> [IPv4Network] {
        var networks: [IPv4Network] = []
        for line in text.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2 else { continue }
            let destination = fields[0]
            if destination == "default" || destination.hasPrefix("Destination") { continue }
            guard let network = routeNetwork(destination) else { continue }
            if !networks.contains(network) { networks.append(network) }
        }
        return networks
    }

    /// One destination column → the network it routes.
    static func routeNetwork(_ destination: String) -> IPv4Network? {
        if destination.contains("/") {
            return IPv4Network(destination)
        }
        let parts = destination.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var octets: [String] = parts.map(String.init)
        // Fewer than four octets is netstat's abbreviation for a network whose
        // remaining octets are zero; four bare octets is a host route.
        let prefix = parts.count * 8
        while octets.count < 4 { octets.append("0") }
        guard let address = IPv4Address(octets.joined(separator: ".")),
              let network = IPv4Network(address: address, prefixLength: prefix),
              // The abbreviation is only valid if the missing octets really are
              // zero; `192.168.1.5` written as `192.168.1` would otherwise be
              // silently widened into a /24 that does not exist.
              network.contains(address) else { return nil }
        return network
    }
}
