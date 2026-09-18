import Foundation
import Security

/// Where a Space's login password lives.
///
/// Plan §9: a 32-byte random password is generated per Space, is never a fixed
/// value, and is stored in the **macOS Keychain**. Explicitly not in a
/// `config.json`, not in `NSUserDefaults`, and not in a log. The user can reveal
/// it once, in the app, to type it at the fast-user-switching login window; after
/// that it is only ever needed again if the Space is re-created.
///
/// This matters more than it looks. The password is the only credential that
/// grants an interactive login to a Space's account. Anything that writes it to
/// disk in the clear — including the app's own logs — hands that login to any
/// process that can read the file, which is a much wider set of processes than
/// "anything that can read the user's Keychain".
///
/// The Keychain also gives the right *lifecycle* for free: the item is owned by
/// the main user's login keychain, unlocked when they are logged in, and it
/// disappears with the account.
public struct KeychainStore {

    /// The Keychain service name. Configurable so tests can use a separate
    /// namespace and never touch, or be confused by, real Space passwords.
    public var service: String

    public init(service: String = "com.agentspace.AgentSpace") {
        self.service = service
    }

    public enum Failure: Error, CustomStringConvertible {
        case keychain(OSStatus, String)

        public var description: String {
            switch self {
            case .keychain(let status, let operation):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
                return "the Keychain \(operation) failed: \(message) (\(status))"
            }
        }
    }

    private func baseQuery(for spaceID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: spaceID.uuidString,
        ]
    }

    /// Store (or replace) a Space's password.
    ///
    /// `kSecAttrAccessibleWhenUnlocked` rather than `…Always`: the password is only
    /// needed while the main user is logged in and looking at the app, so there is
    /// no reason for it to be readable from a locked machine.
    public func store(password: String, for spaceID: UUID) throws {
        // Delete first rather than using `SecItemUpdate`, because the add path is
        // the one that must work on a fresh machine and having two code paths here
        // means only one of them gets exercised.
        try? delete(for: spaceID)

        var query = baseQuery(for: spaceID)
        query[kSecValueData as String] = Data(password.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        // A comment so a human browsing Keychain Access can tell what this is and
        // why it exists, rather than finding an opaque item and deleting it.
        query[kSecAttrComment as String] = "AgentSpace login password. Needed once to sign in to this Space's macOS account."

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw Failure.keychain(status, "add")
        }
    }

    /// Read a Space's password, or `nil` if there is not one.
    public func password(for spaceID: UUID) throws -> String? {
        var query = baseQuery(for: spaceID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw Failure.keychain(status, "read")
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Forget a Space's password. Deleting a Space must leave nothing behind.
    public func delete(for spaceID: UUID) throws {
        let status = SecItemDelete(baseQuery(for: spaceID) as CFDictionary)
        // "Not found" is the desired end state, not a failure. Treating it as one
        // would make "delete an already-deleted Space" fail confusingly.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.keychain(status, "delete")
        }
    }

    public func exists(for spaceID: UUID) -> Bool {
        (try? password(for: spaceID)) ?? nil != nil
    }

    /// Every Space password this app has stored.
    ///
    /// Used by the orphan sweep: if the registry and the machine ever disagree —
    /// a crash between creating the account and saving the record — this is how the
    /// leftover is found. It is deliberately read-only and returns identifiers
    /// only, never the passwords.
    public func storedSpaceIDs() -> [UUID] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny

        var items: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
              let entries = items as? [[String: Any]] else {
            return []
        }
        return entries.compactMap { entry in
            (entry[kSecAttrAccount as String] as? String).flatMap(UUID.init(uuidString:))
        }
    }
}

/// A generated password, kept in memory only for as long as it is needed.
///
/// A `String` is a poor container for a secret — it can be copied anywhere and
/// cannot be zeroed — but it is what `sysadminctl -password` and the Keychain API
/// both require, and the alternative (`Data` plus manual lifetime management)
/// buys very little against an adversary who can already read this process's
/// memory. The honest mitigation is to hold it for as short a time as possible and
/// never to put it in a `String` that reaches a log.
public struct SpacePassword {
    public let value: String

    public init() {
        self.value = HelperValidation.generatePassword()
    }

    init(value: String) {
        self.value = value
    }

    /// True if this looks like a password AgentSpace generated — so the app can
    /// refuse to store one a user typed, which would be a different (and worse)
    /// kind of secret to be holding.
    public var isGenerated: Bool {
        HelperValidation.validatePassword(value) == nil
    }
}
