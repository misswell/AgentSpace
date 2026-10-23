import Foundation

/// Where the virtual-network configuration lives, and the two-file commit that
/// makes "restore the previous configuration" a real operation rather than a
/// promise.
///
/// Layout (under the same root as the Space registry, so `--root` moves both):
/// ```
/// <root>/
///   Network/
///     config.json          the committed configuration
///     config.previous.json the last configuration that was successfully applied
///     candidates/          written before an apply, deleted after it commits
///     api-tokens.json      token digests only, mode 0600
///     identity.json        this node's WireGuard public key and id
/// ```
public struct VirtualNetworkPaths: Sendable {
    public let root: String

    public init(root: String? = nil) {
        self.root = root ?? AgentSpaceEnvironment.rootOverride ?? RuntimePaths.root
    }

    public var directory: String { root + "/Network" }
    public var configPath: String { directory + "/config.json" }
    public var previousPath: String { directory + "/config.previous.json" }
    public var candidatesDirectory: String { directory + "/candidates" }
    public var tokenPath: String { directory + "/api-tokens.json" }
    public var identityPath: String { directory + "/identity.json" }
    public var apiLogPath: String { root + "/Logs/api.log" }

    public func candidatePath(version: Int) -> String {
        candidatesDirectory + "/candidate-\(version).json"
    }
}

public struct VirtualNetworkStore {
    public let paths: VirtualNetworkPaths

    public init(paths: VirtualNetworkPaths = VirtualNetworkPaths()) {
        self.paths = paths
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: Load

    public func load() -> VirtualNetworkConfig? {
        load(path: paths.configPath)
    }

    public func loadPrevious() -> VirtualNetworkConfig? {
        load(path: paths.previousPath)
    }

    public func loadCandidate(version: Int) -> VirtualNetworkConfig? {
        load(path: paths.candidatePath(version: version))
    }

    private func load(path: String) -> VirtualNetworkConfig? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? decoder.decode(VirtualNetworkConfig.self, from: data)
    }

    // MARK: Save

    /// Write a candidate without touching the committed configuration.
    public func saveCandidate(_ config: VirtualNetworkConfig) throws {
        try ensureDirectory()
        let directory = paths.candidatesDirectory
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try encoder.encode(config).write(
            to: URL(fileURLWithPath: paths.candidatePath(version: config.version)),
            options: .atomic)
    }

    /// Commit a configuration: the current file becomes `config.previous.json`
    /// first, so a failed apply can always be undone without a second copy
    /// having been invented somewhere else.
    public func commit(_ config: VirtualNetworkConfig) throws {
        try ensureDirectory()
        let fm = FileManager.default
        if fm.fileExists(atPath: paths.configPath) {
            if fm.fileExists(atPath: paths.previousPath) {
                try? fm.removeItem(atPath: paths.previousPath)
            }
            try? fm.copyItem(atPath: paths.configPath, toPath: paths.previousPath)
        }
        try encoder.encode(config).write(
            to: URL(fileURLWithPath: paths.configPath), options: .atomic)
        try? fm.removeItem(atPath: paths.candidatePath(version: config.version))
    }

    /// Put the previous committed configuration back. Returns what was restored
    /// so the caller can report a version rather than "rolled back".
    @discardableResult
    public func restorePrevious() throws -> VirtualNetworkConfig? {
        guard let previous = loadPrevious() else { return nil }
        let fm = FileManager.default
        try encoder.encode(previous).write(
            to: URL(fileURLWithPath: paths.configPath), options: .atomic)
        try? fm.removeItem(atPath: paths.previousPath)
        return previous
    }

    public func remove() {
        try? FileManager.default.removeItem(atPath: paths.directory)
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            atPath: paths.directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    }
}

// MARK: - Allocation

/// Chooses the default pool.
///
/// Random, not fixed: two people who install AgentSpace on the same home
/// network must not both claim `100.64.0.0/24`, and a single hard-coded pool is
/// the most likely way to collide with a colleague's setup. The seed is
/// persisted, so the pool does not move on every launch.
public enum VirtualAddressAllocator {

    /// The ranges a default pool may come from, in preference order: RFC 6598
    /// first because home routers almost never use it, then RFC 1918.
    public static let defaultRanges: [IPv4Network] = [
        IPv4Network("100.64.0.0/10")!,
        IPv4Network("10.0.0.0/8")!,
        IPv4Network("172.16.0.0/12")!,
        IPv4Network("192.168.0.0/16")!,
    ]

    /// Deterministic given the seed, so a test can assert the same answer twice
    /// and a persisted seed reproduces the pool after a restart.
    public static func choosePool(seed: UInt64, excluding local: LocalNetworkSnapshot) -> IPv4Network {
        var generator = SplitMix64(seed: seed)
        for _ in 0..<256 {
            let range = defaultRanges[Int(generator.next() % UInt64(defaultRanges.count))]
            let pool = randomPool(in: range, generator: &generator)
            guard let pool else { continue }
            let overlaps = (local.interfaceNetworks + local.routes).contains { $0.overlaps(pool) }
            if !overlaps { return pool }
        }
        // Every candidate collided, which means this machine's routing table is
        // unusual. Returning a fixed private pool is better than failing to
        // produce a configuration at all — and validation will report the
        // overlap, so the person sees it instead of a silent bad choice.
        return IPv4Network("100.64.0.0/24")!
    }

    static func randomPool(in range: IPv4Network, generator: inout SplitMix64) -> IPv4Network? {
        guard range.prefixLength <= 24 else { return nil }
        let bits = 24 - range.prefixLength
        let blockCount = UInt64(1) << UInt64(bits)
        let index = generator.next() % blockCount
        let address = IPv4Address(rawValue: range.address.rawValue + UInt32(index << 8))
        return IPv4Network(address: address, prefixLength: 24)
    }

    /// The standard layout inside a pool: hub first, then the controller, then
    /// this Mac, then other nodes. Every address is a host address — never the
    /// network or broadcast address.
    public static func defaultLayout(pool: IPv4Network) -> (hub: IPv4Address, controller: IPv4Address, local: IPv4Address) {
        let first = pool.firstHost
        return (
            hub: first,
            controller: IPv4Address(rawValue: first.rawValue + 1),
            local: IPv4Address(rawValue: first.rawValue + 10))
    }

    /// The first free host address, skipping the three fixed roles and any
    /// address a node already holds.
    public static func nextFreeAddress(in config: VirtualNetworkConfig) -> IPv4Address? {
        let taken = Set(config.allNodes.map(\.address))
        var candidate = config.pool.firstHost.rawValue
        let last = config.pool.lastHost.rawValue
        while candidate <= last {
            let address = IPv4Address(rawValue: candidate)
            if !taken.contains(address) { return address }
            candidate += 1
        }
        return nil
    }
}

/// A tiny deterministic generator. `SystemRandomNumberGenerator` cannot be
/// seeded, and the pool choice must be reproducible from a persisted seed.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}

// MARK: - Migration

/// The steps a pool or address change performs, produced before anything is
/// applied so a person can read what is about to happen.
public struct NetworkMigrationPlan: Codable, Equatable, Sendable {
    public enum Step: String, Codable, Sendable {
        case validateCandidate
        case keepOldAddresses
        case applyNewAddresses
        case verifyTunnel
        case verifyAPI
        case commitNewVersion
        case cleanupOldAddresses
        case rollback
    }

    public var fromVersion: Int
    public var toVersion: Int
    public var oldPool: IPv4Network
    public var newPool: IPv4Network
    public var addressChanges: [AddressChange]
    public var offlineNodes: [String]
    public var steps: [Step]

    public struct AddressChange: Codable, Equatable, Sendable {
        public var node: String
        public var from: IPv4Address
        public var to: IPv4Address
    }

    public var isNoOp: Bool { addressChanges.isEmpty && oldPool == newPool }

    public init(
        fromVersion: Int, toVersion: Int,
        oldPool: IPv4Network, newPool: IPv4Network,
        addressChanges: [AddressChange], offlineNodes: [String]
    ) {
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.oldPool = oldPool
        self.newPool = newPool
        self.addressChanges = addressChanges
        self.offlineNodes = offlineNodes
        self.steps = [
            .validateCandidate, .keepOldAddresses, .applyNewAddresses,
            .verifyTunnel, .verifyAPI, .commitNewVersion, .cleanupOldAddresses,
        ]
    }

    /// Build the plan a candidate implies. Offline nodes are named, never
    /// silently dropped: the plan says the migration will leave them
    /// unreachable rather than claiming they moved.
    public static func plan(
        from current: VirtualNetworkConfig,
        to candidate: VirtualNetworkConfig,
        offlineNodes: Set<String>
    ) -> NetworkMigrationPlan {
        var changes: [AddressChange] = []
        let candidateByID = Dictionary(
            candidate.allNodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for node in current.allNodes {
            guard let target = candidateByID[node.id], target.address != node.address else { continue }
            changes.append(AddressChange(node: node.name, from: node.address, to: target.address))
        }
        let offline = candidate.nodes
            .filter { offlineNodes.contains($0.id) }
            .map(\.name)
        return NetworkMigrationPlan(
            fromVersion: current.version,
            toVersion: candidate.version,
            oldPool: current.pool,
            newPool: candidate.pool,
            addressChanges: changes.sorted { $0.node < $1.node },
            offlineNodes: offline)
    }
}
