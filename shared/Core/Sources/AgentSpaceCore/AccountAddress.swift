import Foundation

// The per-account loopback address, 127.100.x.y inside lo0.
//
// §400 row 1363 measured why this needed the helper: an unprivileged process
// cannot bind any 127.x address that is not assigned to `lo0` (errno 49), and
// assigning one is `ifconfig lo0 alias` — root. The fixed-address feature
// built on that fact was removed with the port map (§406): a service bound
// hard to 127.0.0.1 never moves to the alias, so the address could not give
// two accounts the same port number after all. What survives is the
// derivation itself, for exactly one job: the app's one-time cleanup that
// removes any alias earlier releases (0.1.99–0.1.104) may have left on lo0 —
// only addresses this derivation could have produced are ever touched, the
// §404 rule.

/// The address an agent account answered on, inside 127.100.0.0/16.
///
/// Derived from the account id — never stored — so every observer computes
/// the same one; collisions between accounts are settled deterministically
/// (id order, salted rehash).
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
