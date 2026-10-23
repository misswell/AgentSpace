import Foundation

/// Everything the virtual-network configuration must satisfy before it is
/// allowed near a tunnel, and the conflict report a person reads when it is not.
///
/// Pure: no interfaces are read here. The caller supplies what this machine
/// knows (its own addresses and routes, plus each node's last report), which is
/// what makes every rule testable on a machine with no tunnel at all.

public enum NetworkConflictSeverity: String, Codable, Sendable {
    /// Refuses the configuration. No override exists.
    case blocking
    /// Refuses unless the matching advanced flag is set, and the UI must say
    /// which flag and why.
    case overrideable
    /// Reported, applied anyway.
    case warning
}

public struct NetworkConflict: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(kind.rawValue):\(detail)" }
    public var kind: Kind
    public var severity: NetworkConflictSeverity
    public var detail: String
    /// What the person can do about it. Never empty: a conflict with no
    /// remediation is a dead end presented as information.
    public var remediation: String

    public enum Kind: String, Codable, Sendable {
        case invalidPool
        case poolNotPrivate
        case addressOutsidePool
        case addressReserved
        case duplicateAddress
        case poolTooSmall
        case overlapsLocalNetwork
        case addressInUseLocally
        case invalidPort
        case invalidPublicKey
        case missingNodeKey
        case ipv6Unsupported
    }

    public init(kind: Kind, severity: NetworkConflictSeverity, detail: String, remediation: String) {
        self.kind = kind
        self.severity = severity
        self.detail = detail
        self.remediation = remediation
    }
}

/// What this machine reports about its own networking. Supplied by the caller so
/// the validator stays pure.
///
/// `addresses` and `interfaceNetworks` are deliberately separate: a subnet that
/// *covers* our chosen address is not the same thing as this Mac already *owning*
/// it. The first is a routing hazard the person may accept; the second cannot be
/// made to work by any route, so the two must never be collapsed into one check.
public struct LocalNetworkSnapshot: Equatable, Sendable {
    public var addresses: [IPv4Address]
    public var interfaceNetworks: [IPv4Network]
    public var routes: [IPv4Network]
    /// True when the snapshot could not be taken at all; conflicts are then
    /// reported as unverified rather than as "no conflict".
    public var complete: Bool

    public init(
        addresses: [IPv4Address] = [],
        interfaceNetworks: [IPv4Network] = [],
        routes: [IPv4Network] = [],
        complete: Bool = true
    ) {
        self.addresses = addresses
        self.interfaceNetworks = interfaceNetworks
        self.routes = routes
        self.complete = complete
    }

    public static let unknown = LocalNetworkSnapshot(complete: false)
}

public struct NetworkValidation: Equatable, Sendable {
    public var conflicts: [NetworkConflict]

    public init(conflicts: [NetworkConflict] = []) {
        self.conflicts = conflicts
    }

    public var blocking: [NetworkConflict] { conflicts.filter { $0.severity == .blocking } }
    public var overrideable: [NetworkConflict] { conflicts.filter { $0.severity == .overrideable } }
    public var warnings: [NetworkConflict] { conflicts.filter { $0.severity == .warning } }
    public var isValid: Bool { blocking.isEmpty && overrideable.isEmpty }
    public var hasUnverifiedConflicts: Bool {
        conflicts.contains { $0.kind == .overlapsLocalNetwork && $0.severity == .warning }
    }
}

public enum VirtualNetworkValidator {

    public static let minimumHostCount: UInt64 = 8
    public static let maximumHostCount: UInt64 = 65_534
    public static let allowedPortRange = 1024...65_535
    public static let defaultPort = 8787

    /// The rules, in the order a person would want to fix them.
    public static func validate(
        _ config: VirtualNetworkConfig,
        local: LocalNetworkSnapshot = .unknown,
        reservedAddresses: Set<IPv4Address> = []
    ) -> NetworkValidation {
        var conflicts: [NetworkConflict] = []

        // Pool shape.
        if config.pool.prefixLength > 29 {
            conflicts.append(NetworkConflict(
                kind: .poolTooSmall,
                severity: .blocking,
                detail: "\(config.pool) has room for fewer than \(minimumHostCount) nodes.",
                remediation: "Use a pool of /29 or larger (for example /24)."))
        }
        if config.pool.prefixLength < 16 {
            conflicts.append(NetworkConflict(
                kind: .poolTooSmall,
                severity: .blocking,
                detail: "\(config.pool) is larger than this product manages; the limit is /16.",
                remediation: "Use a /16 or smaller pool."))
        }
        if !config.pool.isPrivateOrShared && !config.allowNonPrivatePool {
            conflicts.append(NetworkConflict(
                kind: .poolNotPrivate,
                severity: .overrideable,
                detail: "\(config.pool) is not an RFC 1918 or RFC 6598 range.",
                remediation: "Choose a private pool, or enable “Allow a non-private pool” deliberately."))
        }

        // Port.
        if !allowedPortRange.contains(config.apiPort) {
            conflicts.append(NetworkConflict(
                kind: .invalidPort,
                severity: .blocking,
                detail: "Port \(config.apiPort) is outside \(allowedPortRange.lowerBound)–\(allowedPortRange.upperBound).",
                remediation: "Choose a port in the unprivileged range."))
        }

        // Every required address is inside the pool and not reserved.
        let required: [(String, IPv4Address)] = [
            ("Network hub", config.hub),
            ("Main system", config.controller),
            ("This Mac", config.local),
        ]
        for (name, address) in required {
            if !config.pool.contains(address) {
                conflicts.append(NetworkConflict(
                    kind: .addressOutsidePool,
                    severity: .blocking,
                    detail: "\(name) \(address) is outside \(config.pool).",
                    remediation: "Move \(address) into the pool or widen the pool."))
            }
            if address == config.pool.address || address == config.pool.broadcast {
                conflicts.append(NetworkConflict(
                    kind: .addressReserved,
                    severity: .blocking,
                    detail: "\(name) \(address) is the network or broadcast address of \(config.pool).",
                    remediation: "Pick a host address inside the pool."))
            }
        }

        // Duplicates across every node, including the three fixed ones.
        var seen: [IPv4Address: [String]] = [:]
        for (name, address) in required { seen[address, default: []].append(name) }
        for node in config.nodes {
            seen[node.address, default: []].append(node.name)
        }
        for (address, names) in seen.sorted(by: { $0.key < $1.key }) where names.count > 1 {
            conflicts.append(NetworkConflict(
                kind: .duplicateAddress,
                severity: .blocking,
                detail: "\(address) is assigned to \(names.joined(separator: ", ")).",
                remediation: "Give each node its own address."))
        }

        // Capacity.
        let assigned = UInt64(seen.count)
        if assigned > config.pool.hostCount {
            conflicts.append(NetworkConflict(
                kind: .poolTooSmall,
                severity: .blocking,
                detail: "\(assigned) addresses do not fit in \(config.pool) (\(config.pool.hostCount) usable).",
                remediation: "Widen the pool or remove nodes."))
        }

        // Node records.
        for node in config.nodes {
            if node.publicKey == nil {
                conflicts.append(NetworkConflict(
                    kind: .missingNodeKey,
                    severity: .warning,
                    detail: "\(node.name) has no registered public key yet.",
                    remediation: "Register the node from its own machine; it cannot carry traffic until then."))
            }
            if let key = node.publicKey, !WireGuardKey.isValidPublicKey(key) {
                conflicts.append(NetworkConflict(
                    kind: .invalidPublicKey,
                    severity: .blocking,
                    detail: "\(node.name)'s public key is not a 32-byte base64 WireGuard key.",
                    remediation: "Re-register the node."))
            }
        }

        // Local overlap. A host route does not make a duplicate address safe, so
        // an exact address collision is always blocking, while a mere subnet
        // overlap is overrideable.
        if local.complete {
            if local.addresses.contains(config.local) {
                conflicts.append(NetworkConflict(
                    kind: .addressInUseLocally,
                    severity: .blocking,
                    detail: "\(config.local) is already assigned to an interface on this Mac.",
                    remediation: "Choose another address for this Mac."))
            }
            for node in config.nodes where local.addresses.contains(node.address) {
                conflicts.append(NetworkConflict(
                    kind: .addressInUseLocally,
                    severity: .blocking,
                    detail: "\(node.name)'s address \(node.address) is already assigned to an interface on this Mac.",
                    remediation: "Give that node another address."))
            }
            for network in local.interfaceNetworks + local.routes where network.overlaps(config.pool) {
                if config.allowOverlap { continue }
                conflicts.append(NetworkConflict(
                    kind: .overlapsLocalNetwork,
                    severity: .overrideable,
                    detail: "\(config.pool) overlaps \(network), which this Mac already routes.",
                    remediation: "Choose a different pool, or enable the overlap override — precise host routes keep other traffic out of the tunnel, but an identical address is still refused."))
            }
        } else {
            conflicts.append(NetworkConflict(
                kind: .overlapsLocalNetwork,
                severity: .warning,
                detail: "This Mac's interfaces and routes could not be read, so overlap was not checked.",
                remediation: "Run `agentspace network doctor` to see why the local network snapshot failed."))
        }

        // A pool that contains a reserved address is not automatically wrong,
        // but handing one out is; that is covered above by `addressReserved`
        // and by the per-node checks below.
        for node in config.nodes where node.address == config.pool.address || node.address == config.pool.broadcast {
            conflicts.append(NetworkConflict(
                kind: .addressReserved,
                severity: .blocking,
                detail: "\(node.name) \(node.address) is the network or broadcast address of \(config.pool).",
                remediation: "Pick a host address inside the pool."))
        }

        // A caller-supplied reservation list (addresses this process must not
        // claim, e.g. the API's own loopback) is honoured too.
        for address in reservedAddresses.sorted() where config.pool.contains(address) {
            conflicts.append(NetworkConflict(
                kind: .addressInUseLocally,
                severity: .blocking,
                detail: "\(address) is reserved and cannot be assigned inside \(config.pool).",
                remediation: "Widen the pool or move the reservation."))
        }

        return NetworkValidation(conflicts: conflicts)
    }
}

// MARK: - WireGuard keys

/// Key shape checks. The private key is generated and kept on the node; the
/// control plane only ever sees the public one, so this is the only place the
/// product validates key material.
public enum WireGuardKey {
    public static let byteCount = 32

    /// 32 bytes, base64, no padding beyond the one `=` a 32-byte value needs.
    public static func isValidPublicKey(_ text: String) -> Bool {
        guard let data = Data(base64Encoded: text), data.count == byteCount else { return false }
        // A private key accidentally pasted as a public key would still decode;
        // clamp its shape is impossible from the bytes alone, so the caller
        // separately refuses values that equal a known private key.
        return !text.isEmpty
    }
}
