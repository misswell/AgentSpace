import Foundation

// The per-account loopback address: opt-in, off by default, root-served.
//
// §400 row 1363 measured why this needs the helper: an unprivileged process
// cannot bind any 127.x address that is not assigned to `lo0` (errno 49), and
// assigning one is `ifconfig lo0 alias` — root. This file owns everything
// *around* that fact: the deterministic address (so every observer computes
// the same one), and the on/off record (so the feature is a choice the person
// makes per account, never a side effect of updating).

/// The address an agent account answers on, inside 127.100.0.0/16.
///
/// Derived from the account id — never stored — so it is the same on every
/// launch for the same set of attached accounts, and the helper, the app, the
/// CLI and the docs all name the same address. Collisions between accounts
/// are settled deterministically (id order, salted rehash), like the port
/// allocator settles port collisions.
public enum AgentLoopbackAddress {

    /// `127.100.0.0/16`, the slice the helper's alias operation accepts and
    /// nothing else.
    public static let rangeDescription = "127.100.0.0/16"

    /// FNV-1a (32-bit), the same hash family the rest of this feature uses.
    private static func hash(_ text: String) -> UInt32 {
        var value: UInt32 = 0x811c_9dc5
        for byte in text.utf8 {
            value ^= UInt32(byte)
            value = value &* 0x0100_0193
        }
        return value
    }

    /// One candidate slot in `1...65534`; slot 0 (`.0.0`) and 65535
    /// (`.255.255`) are never handed out, and the helper refuses them too.
    private static func slot(_ account: UUID, salt: Int) -> UInt32 {
        let text = salt == 0
            ? account.uuidString.lowercased()
            : account.uuidString.lowercased() + "#\(salt)"
        return 1 + hash(text) % 65_534
    }

    private static func address(slot: UInt32) -> IPv4Address {
        IPv4Address(rawValue: (127 << 24) | (100 << 16) | slot)
    }

    /// The alias table for a whole set of accounts. Distinct by construction;
    /// the result depends only on the set, never on its order.
    public static func addresses(for accounts: [UUID]) -> [UUID: IPv4Address] {
        var taken = Set<UInt32>()
        var table: [UUID: IPv4Address] = [:]
        for account in Set(accounts).sorted(by: { $0.uuidString < $1.uuidString }) {
            var chosen: UInt32?
            for salt in 0..<64 where !taken.contains(slot(account, salt: salt)) {
                chosen = slot(account, salt: salt)
                break
            }
            if chosen == nil {
                var probe: UInt32 = 1
                while probe <= 65_534 && taken.contains(probe) { probe += 1 }
                chosen = probe <= 65_534 ? probe : nil
            }
            guard let value = chosen else { continue }
            taken.insert(value)
            table[account] = address(slot: value)
        }
        return table
    }

    /// The alias for one account, resolved against the other attached
    /// accounts so a collision is settled the same way every observer settles
    /// it. `others` may include the account itself.
    public static func address(for account: UUID, among others: [UUID] = []) -> IPv4Address? {
        addresses(for: others + [account])[account]
    }

    public static func isAlias(_ candidate: IPv4Address) -> Bool {
        let raw = candidate.rawValue
        return (raw >> 24) & 0xff == 127 && (raw >> 16) & 0xff == 100
    }
}

/// The shape of `<root>/Network/account-addresses.json`: which accounts have
/// the fixed-address feature switched on. A *choice record*, not a state
/// record — whether the alias is really on `lo0` is read from the machine
/// (`getifaddrs`), never from this file, so a crashed app cannot leave the
/// two disagreeing about what is true.
public struct AccountAddressFile: Codable, Equatable, Sendable {
    public var version: Int
    public var enabled: [UUID]
    public var updatedAt: Date

    public init(version: Int = 1, enabled: [UUID] = [], updatedAt: Date = Date()) {
        self.version = version
        self.enabled = enabled
        self.updatedAt = updatedAt
    }
}

public struct AccountAddressStore {
    public let paths: VirtualNetworkPaths

    public init(paths: VirtualNetworkPaths = VirtualNetworkPaths()) {
        self.paths = paths
    }

    public static func path(paths: VirtualNetworkPaths = VirtualNetworkPaths()) -> String {
        paths.accountAddressPath
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

    /// Missing or corrupt → the empty choice (nothing enabled). The safe
    /// direction: a corrupt file cannot leave an alias on the machine that
    /// the app believes nobody asked for, because reconcile removes what no
    /// enabled account owns.
    public func load() -> AccountAddressFile {
        guard let data = FileManager.default.contents(atPath: paths.accountAddressPath),
              let file = try? decoder.decode(AccountAddressFile.self, from: data) else {
            return AccountAddressFile()
        }
        return file
    }

    public func save(_ file: AccountAddressFile) throws {
        try FileManager.default.createDirectory(
            atPath: paths.directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let data = try encoder.encode(file)
        try data.write(to: URL(fileURLWithPath: paths.accountAddressPath), options: .atomic)
    }

    public func isEnabled(_ account: UUID) -> Bool {
        load().enabled.contains(account)
    }

    @discardableResult
    public func setEnabled(_ account: UUID, _ enabled: Bool) throws -> Bool {
        var file = load()
        let before = file.enabled.count
        if enabled {
            file.enabled.append(account)
            file.enabled = Array(Set(file.enabled)).sorted { $0.uuidString < $1.uuidString }
        } else {
            file.enabled.removeAll { $0 == account }
        }
        guard file.enabled.count != before else { return false }
        file.updatedAt = Date()
        try save(file)
        return true
    }
}
