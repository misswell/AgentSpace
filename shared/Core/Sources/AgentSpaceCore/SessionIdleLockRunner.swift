import Foundation
import AgentSpaceCore

/// Applies and undoes `SessionIdleLock` for the account this Worker runs as.
///
/// The whole point is that this needs no privilege: the Worker *is* the agent
/// user, inside the agent user's own session, so writing that user's own
/// screensaver interval is an ordinary per-user preference write — the same
/// file `defaults -currentHost write com.apple.screensaver idleTime` creates,
/// measured 2026-10-09 as `~/Library/Preferences/ByHost/
/// com.apple.screensaver.<host-uuid>.plist`. No helper operation and no
/// password is involved, which is what keeps this clear of the explicit-login
/// rules (AGENTS.md §7).
///
/// The record file is what makes the change reversible. It is written only when
/// a value is actually replaced, and deleted when it is put back, so "the file
/// exists" means "this account's screensaver is AgentSpace's to undo".
public struct SessionIdleLockRunner {
    public static let domain = "com.apple.screensaver"
    public static let key = "idleTime"

    /// This agent user's own ByHost value for one screensaver key.
    ///
    /// `askForPassword` and `askForPasswordDelay` go through here for the lock
    /// diagnostic (`LockEvidence`) and nothing else: AgentSpace writes `idleTime`
    /// and only `idleTime`, so whether a lock needs the account's password stays
    /// that account's own decision.
    ///
    /// Single call site on purpose — the argument order below is the one mistake
    /// that reads and writes a domain nobody uses, so it is not repeated.
    public static func read(key: String) -> Int? {
        let value = CFPreferencesCopyValue(
            key as CFString,
            domain as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost)
        return (value as? NSNumber)?.intValue
    }

    /// The preference access, as a seam: the decision logic is Core's
    /// (`SessionIdleLock`) and the storage is one line each, so the interesting
    /// behaviour — record once, restore once, never invent a value — is
    /// testable without writing a real preference.
    public struct Store {
        public var read: () -> Int?
        public var write: (ScreensaverWrite) -> Bool

        public init(read: @escaping () -> Int?, write: @escaping (ScreensaverWrite) -> Bool) {
            self.read = read
            self.write = write
        }

        /// The real preference store.
        ///
        /// The argument order is `(key, applicationID, userName, hostName)` —
        /// measured 2026-10-09 with a probe run as the agent user: with the last
        /// two swapped `CFPreferencesCopyValue` answers `nil` while
        /// `defaults -currentHost read com.apple.screensaver idleTime` answers 0,
        /// so a Worker would have "found no screensaver" and written a value
        /// macOS never reads. `kCFPreferencesAnyHost` is wrong too: the interval
        /// lives only in the ByHost domain.
        public static let preferences = Store(
            read: { SessionIdleLockRunner.read(key: SessionIdleLockRunner.key) },
            write: { change in
                switch change {
                case .unchanged:
                    return true
                case .value(let seconds):
                    CFPreferencesSetValue(
                        SessionIdleLockRunner.key as CFString,
                        seconds as CFNumber,
                        SessionIdleLockRunner.domain as CFString,
                        kCFPreferencesCurrentUser,
                        kCFPreferencesCurrentHost)
                case .removeKey:
                    CFPreferencesSetValue(
                        SessionIdleLockRunner.key as CFString,
                        nil,
                        SessionIdleLockRunner.domain as CFString,
                        kCFPreferencesCurrentUser,
                        kCFPreferencesCurrentHost)
                }
                return CFPreferencesSynchronize(
                    SessionIdleLockRunner.domain as CFString,
                    kCFPreferencesCurrentUser,
                    kCFPreferencesCurrentHost)
            })
    }

    public let recordPath: String
    public var store: Store
    public var fileManager: FileManager

    public init(recordPath: String, store: Store = .preferences, fileManager: FileManager = .default) {
        self.recordPath = recordPath
        self.store = store
        self.fileManager = fileManager
    }

    /// What the account's screensaver interval was before AgentSpace touched it.
    private struct Record: Codable { var previous: Int? }

    /// The record this account has, if any. `nil` means AgentSpace has never
    /// changed this account's screensaver; a record whose `previous` is `nil`
    /// means the key did not exist before the change.
    private var record: Record? {
        guard let data = fileManager.contents(atPath: recordPath),
              let decoded = try? JSONDecoder().decode(Record.self, from: data)
        else { return nil }
        return decoded
    }

    /// Turn the screensaver off, remembering what it was.
    ///
    /// Returns a one-line description of what happened, for the log; `nil` when
    /// there was nothing to do.
    public func apply() -> String? {
        let current = store.read()
        guard case .value(let never) = SessionIdleLock.apply(current: current) else {
            // Either the person set "Never" themselves, or a Worker already did
            // and never got to restore it. In the second case the record file is
            // still here, so the original is not lost.
            return nil
        }
        // Record before writing: a Worker killed between the two would else
        // leave a changed preference with nothing to restore it from. An
        // existing record wins — it holds the true original, from the first
        // Worker that changed this account.
        if record == nil {
            let data = (try? JSONEncoder().encode(Record(previous: current))) ?? Data("{}".utf8)
            try? data.write(to: URL(fileURLWithPath: recordPath), options: .atomic)
        }
        guard store.write(.value(never)) else {
            return "screensaver is still on: could not write \(SessionIdleLockRunner.domain)/\(SessionIdleLockRunner.key)"
        }
        return "the account's screensaver is off (idleTime=\(never)); it was \(current.map { "\($0)s" } ?? "unset")"
    }

    /// Put the account's screensaver back. A no-op when this account's value
    /// was never changed, so stopping a Worker that never wrote cannot edit a
    /// preference it does not own.
    public func restore() -> String? {
        guard let record else { return nil }
        let change = SessionIdleLock.restore(recorded: record.previous)
        guard store.write(change) else {
            return "could not restore \(SessionIdleLockRunner.domain)/\(SessionIdleLockRunner.key)"
        }
        try? fileManager.removeItem(atPath: recordPath)
        switch change {
        case .value(let seconds): return "restored the account's screensaver to \(seconds)s"
        case .removeKey: return "removed the screensaver interval AgentSpace had set"
        case .unchanged: return nil
        }
    }
}
