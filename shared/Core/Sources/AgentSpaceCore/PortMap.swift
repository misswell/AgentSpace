import Foundation

// The generated external port for a mapped internal one, and the persisted
// mapping list.
//
// The requirement this file serves: a service running inside an agent
// account's session — a local API — must be callable from the main system at
// an address *generated* for that mapping, with no network at all.
//
// The fact that makes that possible is a property of macOS, not of this
// product: every account on this Mac shares one kernel network stack, so a
// service the agent account binds on `127.0.0.1:<port>` is already reachable
// from the main account at `127.0.0.1:<port>`, offline included. What the OS
// does not give that port is a *name* — `127.0.0.1:3000` says nothing about
// which account serves it.
//
// Why the name is a generated *port* and not a per-account IP: a distinct
// loopback IP is not available to an unprivileged process on macOS. Only
// addresses actually assigned to `lo0` can be bound — `127.0.0.1` by default
// — and `bind()` on any other `127.x.y.z` answers **errno 49 (EADDRNOTAVAIL)
// / Can't assign requested address**, measured 2026-10-25 with a plain POSIX
// socket on `127.0.0.2`, `127.1.2.3` and `127.100.231.7`. Assigning more
// addresses to `lo0` is `ifconfig lo0 alias`, which is root. (§399 row 1354's
// "the kernel routes 127.0.0.2" is true of *routing* — a connect gets refused
// rather than unreachable — and says nothing about binding.) So the generated
// address this feature hands out is `127.0.0.1:<generated port>`, derived
// from the account id and the internal port, stable because it is stored with
// the mapping.

/// The external ports this feature may hand out.
public enum AgentPortAllocator {

    /// 45,000–46,999. Below the kernel's 49,152–65,535 ephemeral range, so a
    /// mapping never competes with outgoing connections for its own port, and
    /// clear of the sign-in relay's 47,000–47,999 (`ScreenSharingRelay`).
    public static let range: ClosedRange<UInt16> = 45_000...46_999

    /// FNV-1a (32-bit), the same hash the sign-in relay's stable port uses.
    private static func hash(_ text: String) -> UInt32 {
        var value: UInt32 = 0x811c_9dc5
        for byte in text.utf8 {
            value ^= UInt32(byte)
            value = value &* 0x0100_0193
        }
        return value
    }

    private static func slot(_ account: UUID, _ port: UInt16, salt: Int) -> Int {
        let text = salt == 0
            ? "\(account.uuidString.lowercased())/\(port)"
            : "\(account.uuidString.lowercased())/\(port)#\(salt)"
        return Int(hash(text) % UInt32(range.count))
    }

    /// The deterministic candidate order for one mapping: the hash slot first,
    /// then salted rehashes. Stable for the same (account, port) everywhere
    /// — the CLI, the app and the tests all walk the same sequence.
    public static func candidates(account: UUID, port: UInt16) -> [UInt16] {
        var order: [UInt16] = []
        var seen = Set<UInt16>()
        for salt in 0..<64 {
            let candidate = range.lowerBound + UInt16(slot(account, port, salt: salt))
            if seen.insert(candidate).inserted {
                order.append(candidate)
                if order.count == range.count { break }
            }
        }
        return order
    }

    /// The first candidate the caller considers free, or nil when every
    /// candidate is taken. `isFree` is the caller's because freeness has two
    /// halves this type cannot see: ports already committed to other
    /// mappings, and ports something on this Mac is already listening on.
    public static func choose(
        account: UUID,
        port: UInt16,
        isFree: (UInt16) -> Bool
    ) -> UInt16? {
        candidates(account: account, port: port).first(where: isFree)
    }

    /// Rules for a person-chosen external port (`map 8080 28080`). Returns the
    /// problem, or nil when the choice is acceptable. Chosen ports must stay
    /// outside the generated range so the two worlds cannot collide and each
    /// stays predictable: a generated port is always generator-owned, a
    /// chosen one is always the person's.
    public static func manualPortProblem(_ chosen: UInt16, internal internalPort: UInt16) -> String? {
        if chosen < 1024 {
            return "port \(chosen): ports below 1024 are reserved for the system on this Mac"
        }
        if chosen == internalPort {
            return "port \(chosen) is the service's own port on 127.0.0.1, held by the service itself; the mapping needs a different one"
        }
        if range.contains(chosen) {
            return "port \(chosen) is inside the auto-generated range \(range.lowerBound)–\(range.upperBound); pick a port outside it, or let the generator choose"
        }
        return nil
    }
}

// MARK: - The shared root's one refusal that has a fix

/// The shared root (`/Library/Application Support/AgentSpace`) is root-owned,
/// and its `Network` configuration directory is created and handed to the main
/// user by the helper on every worker install/update (§402). Until a machine
/// has run that once, every write the app or the CLI makes into it is refused
/// — and that one refusal has a fix, so the surfaces translate it instead of
/// showing Cocoa's raw prose.
public enum SharedRootWrite {

    /// Whether a thrown write error is the "not prepared yet" permission
    /// refusal. NSCocoaErrorDomain 513 is what `Data.write` answers with, and
    /// NSPOSIXErrorDomain 13 (EACCES) is what `createDirectory` answers with;
    /// the former usually wraps the latter.
    public static func isPermissionDenied(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == 513 { return true }
        if ns.domain == NSPOSIXErrorDomain && ns.code == 13 { return true }
        if ns.domain == NSCocoaErrorDomain,
           let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain, underlying.code == 13 {
            return true
        }
        return false
    }
}

// MARK: - The one notListening refusal that deserves an upgrade

/// The refinement a `notListening` refusal earns from one machine-wide fact:
/// whether anything on this Mac answers on `127.0.0.1:<port>` at all.
///
/// The account's own worker has already said that none of *its* processes
/// listen on the port. When the port still answers a probe from the main
/// system, the listener is held outside this account — the main system's, another
/// account's, or a system service's — and because every account on macOS
/// shares one kernel network stack, the main system can already reach it at
/// the same port with no mapping at all. That is the exact case a person
/// meets with a service that only *looks* like it belongs to the account (a
/// gateway app whose server runs in the main system while the account's copy
/// is a client), and the flat "nothing is listening" sentence reads like a
/// defect; both surfaces upgrade it instead.
public enum NotListeningRefinement: Equatable, Sendable {
    /// The probe found nothing either: the port is silent machine-wide.
    case nothingAnywhere
    /// The probe answered: a listener exists, and it is not this account's.
    case heldOutsideAccount
}

// MARK: - The rules one mapping must satisfy, as one pure function

/// Everything a mapping must satisfy before it is written, expressed without
/// I/O so both surfaces (app card, CLI) share one definition and the rules can
/// be attacked by tests. The ownership evidence (`listening`) is supplied by
/// the caller because only the account's own worker can produce it.
public enum PortMapRules {

    public enum Problem: Equatable, Sendable {
        /// The account's session has nothing listening on that port right now.
        case notListening(UInt16)
        /// The port is bound only to non-loopback addresses.
        case notOnLoopback(UInt16)
        /// This (account, port) is already mapped.
        case alreadyMapped(UInt16)
        /// The internal port is not a port number at all.
        case invalidInternal
        /// The chosen external port, with the specific rule it broke.
        case invalidExternal(ExternalRule)
        /// Another mapping owns the chosen external port.
        case externalTakenByMapping(UInt16)
        /// Something on this Mac is already listening on the chosen port.
        case externalInUse(UInt16)

        public enum ExternalRule: Equatable, Sendable {
            case belowPrivilegedFloor
            case isInternalPort
            case insideGeneratedRange
        }
    }

    /// Validate one mapping request. `listening` is the account's live port
    /// list (any row for the port with a loopback-covering bind qualifies),
    /// `mappedPorts` the internal ports this account already has mapped, and
    /// `takenExternals` the external ports other mappings own.
    public static func validate(
        internal internalPort: UInt16,
        listening: [ListeningPort],
        mappedPorts: Set<UInt16>,
        chosenExternal: UInt16?,
        takenExternals: Set<UInt16>
    ) -> Problem? {
        let rows = listening.filter { $0.port == internalPort }
        guard !rows.isEmpty else { return .notListening(internalPort) }
        guard rows.contains(where: \.coversLoopback) else { return .notOnLoopback(internalPort) }
        if mappedPorts.contains(internalPort) { return .alreadyMapped(internalPort) }
        if let chosen = chosenExternal {
            if let problem = AgentPortAllocator.manualPortProblem(chosen, internal: internalPort) {
                return .invalidExternal(
                    chosen < 1024 ? .belowPrivilegedFloor
                        : chosen == internalPort ? .isInternalPort
                        : .insideGeneratedRange)
            }
            if takenExternals.contains(chosen) { return .externalTakenByMapping(chosen) }
        }
        return nil
    }

    /// Whether a `notListening` verdict should be upgraded to
    /// "held outside this account", from the two facts a surface can gather
    /// itself: a machine-wide probe of `127.0.0.1:<port>` (a plain TCP
    /// connect from the main system), and whether that port is one of this
    /// product's own forwarder endpoints. A mapping's external port is served
    /// by this app's own forwarder, so its answering says nothing about
    /// anyone's service and must not upgrade the verdict.
    public static func notListeningRefinement(
        probeAnswers: Bool,
        portIsAMappingEndpoint: Bool
    ) -> NotListeningRefinement {
        guard probeAnswers, !portIsAMappingEndpoint else { return .nothingAnywhere }
        return .heldOutsideAccount
    }
}

// MARK: - The persisted mappings

/// One mapped port for one account: the main system calls
/// `127.0.0.1:<external>` and reaches the service this account listens on at
/// `127.0.0.1:<port>`.
public struct PortMapping: Codable, Equatable, Sendable, Identifiable {
    public var account: UUID
    /// The port inside the agent account's session.
    public var port: UInt16
    /// The generated port the main system calls. Stored, not re-derived, so
    /// it cannot move while the mapping exists even if a later rehash would
    /// have ordered candidates differently.
    public var external: UInt16
    public var createdAt: Date

    public init(account: UUID, port: UInt16, external: UInt16, createdAt: Date = Date()) {
        self.account = account
        self.port = port
        self.external = external
        self.createdAt = createdAt
    }

    /// The key the store and the runtime address a mapping by: one account,
    /// one internal port. The external port is chosen, not identifying.
    public var id: String { "\(account.uuidString.lowercased())/\(port)" }

    public var endpoint: String { "127.0.0.1:\(external)" }
}

/// The shape of `<root>/Network/port-map.json`. Keys are stable like every
/// other on-disk record in this product: a future build may add fields, and
/// old records must decode unchanged.
public struct PortMapFile: Codable, Equatable, Sendable {
    public var version: Int
    public var mappings: [PortMapping]
    public var updatedAt: Date

    public init(version: Int = 1, mappings: [PortMapping] = [], updatedAt: Date = Date()) {
        self.version = version
        self.mappings = mappings
        self.updatedAt = updatedAt
    }
}

/// Reads and writes the mapping list. The file is shared state, exactly like
/// `api.json`: the CLI and the account page write it, and the app — the one
/// process that owns the forwarders — picks changes up and applies them.
public struct PortMapStore {
    public let paths: VirtualNetworkPaths

    public init(paths: VirtualNetworkPaths = VirtualNetworkPaths()) {
        self.paths = paths
    }

    public static func path(paths: VirtualNetworkPaths = VirtualNetworkPaths()) -> String {
        paths.portMapPath
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

    /// A missing file is an empty map. A file that cannot be decoded is also
    /// reported as empty rather than crashing the caller: the mappings are
    /// user-recoverable state (re-toggling one port), never the only copy of
    /// anything. The refusal is visible because the next save overwrites the
    /// broken bytes.
    public func load() -> PortMapFile {
        guard let data = FileManager.default.contents(atPath: paths.portMapPath),
              let file = try? decoder.decode(PortMapFile.self, from: data) else {
            return PortMapFile()
        }
        return file
    }

    public func save(_ file: PortMapFile) throws {
        try FileManager.default.createDirectory(
            atPath: paths.directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let data = try encoder.encode(file)
        try data.write(to: URL(fileURLWithPath: paths.portMapPath), options: .atomic)
    }

    public func mappings(account: UUID) -> [PortMapping] {
        load().mappings.filter { $0.account == account }
    }

    /// Every external port already committed, so a new mapping cannot be
    /// handed a port another mapping owns.
    public func externalPortsInUse() -> Set<UInt16> {
        Set(load().mappings.map(\.external))
    }

    /// Adds a mapping. Returns false — and writes nothing — when this
    /// (account, port) is already mapped, or when the external port belongs
    /// to another mapping; both halves of "free" are the caller's to prove.
    @discardableResult
    public func add(account: UUID, port: UInt16, external: UInt16) throws -> Bool {
        var file = load()
        guard !file.mappings.contains(where: { $0.account == account && $0.port == port }),
              !file.mappings.contains(where: { $0.external == external }) else {
            return false
        }
        file.mappings.append(PortMapping(account: account, port: port, external: external))
        file.mappings.sort { ($0.account.uuidString, $0.port) < ($1.account.uuidString, $1.port) }
        file.updatedAt = Date()
        try save(file)
        return true
    }

    @discardableResult
    public func remove(account: UUID, port: UInt16) throws -> Bool {
        var file = load()
        let before = file.mappings.count
        file.mappings.removeAll { $0.account == account && $0.port == port }
        guard file.mappings.count != before else { return false }
        file.updatedAt = Date()
        try save(file)
        return true
    }
}
