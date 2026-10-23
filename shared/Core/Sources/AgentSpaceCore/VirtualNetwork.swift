import Foundation

/// IPv4 addresses and networks for the virtual network.
///
/// Deliberately a value type with strict parsing rather than `String` in the
/// model: every address in this feature is either inside a validated pool or a
/// refusal, and a string that is only checked at the edge lets an invalid
/// address reach the tunnel configuration.

public struct IPv4Address: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Strict dotted quad: four decimal octets, no leading zeros, no signs,
    /// no whitespace. `inet_pton` would accept some of those; the tunnel
    /// configuration and the certificate SAN both need exactly one spelling.
    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard !part.isEmpty, part.count <= 3,
                  part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber),
                  part.count == 1 || part.first != "0",
                  let octet = UInt32(part), octet <= 255 else { return nil }
            value = (value << 8) | octet
        }
        self.rawValue = value
    }

    public var description: String {
        let bytes = [
            (rawValue >> 24) & 0xff, (rawValue >> 16) & 0xff,
            (rawValue >> 8) & 0xff, rawValue & 0xff,
        ]
        return bytes.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: IPv4Address, rhs: IPv4Address) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let address = IPv4Address(text) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "\(text) is not an IPv4 address")
        }
        self = address
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    // MARK: Ranges

    /// RFC 1918: 10/8, 172.16/12, 192.168/16.
    public var isPrivate: Bool {
        let a = (rawValue >> 24) & 0xff
        let b = (rawValue >> 16) & 0xff
        if a == 10 { return true }
        if a == 172, (16...31).contains(b) { return true }
        if a == 192, b == 168 { return true }
        return false
    }

    /// RFC 6598 shared address space, 100.64/10. Not RFC 1918, but it is the
    /// range the revised plan prefers because home routers almost never use it.
    public var isSharedAddressSpace: Bool {
        let a = (rawValue >> 24) & 0xff
        let b = (rawValue >> 16) & 0xff
        return a == 100 && (64...127).contains(b)
    }

    public var isLoopback: Bool { (rawValue >> 24) & 0xff == 127 }
    public var isLinkLocal: Bool {
        let a = (rawValue >> 24) & 0xff
        let b = (rawValue >> 16) & 0xff
        return a == 169 && b == 254
    }
    public var isMulticast: Bool { (rawValue >> 28) == 0xe }
    public var isBroadcast: Bool { rawValue == 0xffff_ffff }
    public var isUnspecified: Bool { rawValue == 0 }

    /// Addresses the product may hand out without the advanced override.
    public var isAllocatableByDefault: Bool { isPrivate || isSharedAddressSpace }
}

public struct IPv4Network: Hashable, Codable, Sendable, CustomStringConvertible {
    /// Network address (all host bits clear).
    public let address: IPv4Address
    public let prefixLength: Int

    public init?(address: IPv4Address, prefixLength: Int) {
        guard (0...32).contains(prefixLength) else { return nil }
        self.address = IPv4Address(rawValue: address.rawValue & IPv4Network.mask(prefixLength))
        self.prefixLength = prefixLength
    }

    public init?(_ cidr: String) {
        let parts = cidr.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let prefix = Int(parts[1]),
              let address = IPv4Address(String(parts[0])),
              let network = IPv4Network(address: address, prefixLength: prefix) else { return nil }
        // `10.0.0.1/24` is accepted and normalised, but `10.0.0.1/24` written
        // back out as `10.0.0.0/24` — one spelling, so comparisons are exact.
        self = network
    }

    public static func mask(_ prefixLength: Int) -> UInt32 {
        prefixLength == 0 ? 0 : UInt32.max << (32 - UInt32(prefixLength))
    }

    public var netmask: IPv4Address { IPv4Address(rawValue: IPv4Network.mask(prefixLength)) }
    public var broadcast: IPv4Address {
        IPv4Address(rawValue: address.rawValue | ~IPv4Network.mask(prefixLength))
    }

    /// The first address usable by a node. For a /31 and /32 every address is
    /// treated as usable, which is what point-to-point links expect.
    public var firstHost: IPv4Address {
        prefixLength >= 31 ? address : IPv4Address(rawValue: address.rawValue + 1)
    }

    public var lastHost: IPv4Address {
        prefixLength >= 31 ? broadcast : IPv4Address(rawValue: broadcast.rawValue - 1)
    }

    public var hostCount: UInt64 {
        if prefixLength >= 31 { return prefixLength == 32 ? 1 : 2 }
        return (UInt64(1) << UInt64(32 - prefixLength)) - 2
    }

    public var description: String { "\(address)/\(prefixLength)" }

    public func contains(_ candidate: IPv4Address) -> Bool {
        (candidate.rawValue & IPv4Network.mask(prefixLength)) == address.rawValue
    }

    public func overlaps(_ other: IPv4Network) -> Bool {
        contains(other.address) || other.contains(address)
    }

    public var isPrivateOrShared: Bool {
        let first = firstHost
        let last = lastHost
        // A pool is only "private" if both ends are inside the same allowed
        // range; a /8 that starts private and ends public is not a private pool.
        if first.isSharedAddressSpace && last.isSharedAddressSpace { return true }
        guard first.isPrivate, last.isPrivate else { return false }
        let a = (first.rawValue >> 24) & 0xff
        let b = (last.rawValue >> 24) & 0xff
        if a == 10 && b == 10 { return true }
        if a == 172, b == 172 { return true }
        if a == 192, b == 192 { return true }
        return false
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let network = IPv4Network(text) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "\(text) is not an IPv4 network")
        }
        self = network
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

// MARK: - Nodes

public enum VirtualNodeRole: String, Codable, Sendable, CaseIterable {
    /// The coordination service's own address inside the network.
    case hub
    /// The machine that drives the agents (the "main system").
    case controller
    /// This Mac.
    case agentSpace
    /// Any other authorised device.
    case node

    public var displayName: String {
        switch self {
        case .hub: return "Network hub"
        case .controller: return "Main system"
        case .agentSpace: return "This Mac"
        case .node: return "Node"
        }
    }
}

public struct VirtualNode: Codable, Equatable, Sendable, Identifiable {
    /// Stable across address changes; the WireGuard public key can rotate.
    public var id: String
    public var name: String
    public var role: VirtualNodeRole
    public var address: IPv4Address
    /// Base64 WireGuard public key. The private key never leaves the node.
    public var publicKey: String?
    public var endpoint: String?
    public var persistentKeepalive: Int?
    /// CIDRs observed on that node the last time it reported. Used for
    /// conflict detection; a stale report is marked as such, never presented
    /// as a live check.
    public var lastKnownNetworks: [IPv4Network]
    public var lastSeen: Date?

    public init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        role: VirtualNodeRole,
        address: IPv4Address,
        publicKey: String? = nil,
        endpoint: String? = nil,
        persistentKeepalive: Int? = 25,
        lastKnownNetworks: [IPv4Network] = [],
        lastSeen: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.address = address
        self.publicKey = publicKey
        self.endpoint = endpoint
        self.persistentKeepalive = persistentKeepalive
        self.lastKnownNetworks = lastKnownNetworks
        self.lastSeen = lastSeen
    }
}

// MARK: - Configuration

public enum VirtualAddressMode: String, Codable, Sendable, CaseIterable {
    case automatic
    case manual

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .manual: return "Manual"
        }
    }
}

/// The committed virtual-network configuration.
///
/// One JSON file, versioned, with the previous successful version kept beside
/// it. Every field a person can edit is here; derived values (netmask, host
/// ranges, routes) are never stored, so a stored file cannot disagree with the
/// validator.
public struct VirtualNetworkConfig: Codable, Equatable, Sendable {
    /// Monotonic; bumped by every successful apply. A candidate that is not
    /// committed never advances it.
    public var version: Int
    public var mode: VirtualAddressMode
    public var pool: IPv4Network
    public var hub: IPv4Address
    public var controller: IPv4Address
    /// This Mac's address. Named `local` in JSON for readability; the wire and
    /// file spelling is stable.
    public var local: IPv4Address
    public var apiPort: Int
    public var ipv6Enabled: Bool
    /// Explicit opt-in for a pool that is neither RFC 1918 nor RFC 6598.
    public var allowNonPrivatePool: Bool
    /// Explicit opt-in to apply a pool that overlaps a local network, when no
    /// address actually collides. Never implied by host routes.
    public var allowOverlap: Bool
    public var nodes: [VirtualNode]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        version: Int = 1,
        mode: VirtualAddressMode = .automatic,
        pool: IPv4Network,
        hub: IPv4Address,
        controller: IPv4Address,
        local: IPv4Address,
        apiPort: Int = 8787,
        ipv6Enabled: Bool = false,
        allowNonPrivatePool: Bool = false,
        allowOverlap: Bool = false,
        nodes: [VirtualNode] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.version = version
        self.mode = mode
        self.pool = pool
        self.hub = hub
        self.controller = controller
        self.local = local
        self.apiPort = apiPort
        self.ipv6Enabled = ipv6Enabled
        self.allowNonPrivatePool = allowNonPrivatePool
        self.allowOverlap = allowOverlap
        self.nodes = nodes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var allNodes: [VirtualNode] {
        var all = nodes
        all.append(VirtualNode(id: "hub", name: "Network hub", role: .hub, address: hub))
        all.append(VirtualNode(id: "controller", name: "Main system", role: .controller, address: controller))
        all.append(VirtualNode(id: "local", name: "This Mac", role: .agentSpace, address: local))
        return all
    }

    public func node(for address: IPv4Address) -> VirtualNode? {
        allNodes.first { $0.address == address }
    }

    /// Every address that must exist as a precise host route. Never the whole
    /// pool: routing the /24 would capture traffic meant for a physical network
    /// that happens to use the same range.
    public var hostRoutes: [IPv4Address] {
        allNodes.map(\.address).sorted()
    }
}
