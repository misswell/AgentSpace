import Foundation
import AgentSpaceCore

/// Applies and undoes `SessionIdleLock` for the account this Worker runs as.
///
/// The whole point is that this needs no privilege: the Worker *is* the agent
/// user, inside the agent user's own session, so writing that user's own
/// lock preferences is an ordinary per-user preference write — the same file
/// `defaults -currentHost write com.apple.screensaver idleTime` creates,
/// measured 2026-10-09 as `~/Library/Preferences/ByHost/
/// com.apple.screensaver.<host-uuid>.plist`. No helper operation and no
/// password is involved, which is what keeps this clear of the explicit-login
/// rules (AGENTS.md §7).
///
/// Two keys are pinned, both from `SessionIdleLock.policy`, because the two lock
/// classes have different triggers: `idleTime` is the screensaver's idle clock and
/// `askForPasswordDelay` is what Apple's `ScreensharingAgent` queries before it
/// demands a lock. Writing only the first leaves a desktop that locks the moment
/// its viewer goes away — measured 2026-10-10, four seconds after the viewer closed
/// and with `idleTime=0` already in place (validation §376).
///
/// The record file is what makes the change reversible. It holds one original per
/// key that was *actually* replaced, is written before those writes, and is deleted
/// once they are put back, so "the file exists" means "this account's lock settings
/// are AgentSpace's to undo".
public struct SessionIdleLockRunner {
    public static let domain = "com.apple.screensaver"

    /// The screensaver interval, under its historical name.
    ///
    /// Kept because it is what the pre-0.1.78 record file and the `LockEvidence`
    /// diagnostic line are written against.
    public static let key = "idleTime"

    /// This agent user's own ByHost value for one screensaver key.
    ///
    /// `askForPassword` goes through here for the lock diagnostic (`LockEvidence`)
    /// and nothing else: AgentSpace writes the two keys in `SessionIdleLock.policy`
    /// and no others, so whether a lock needs a password at all stays that account's
    /// own decision — only *when* it stops demanding one is AgentSpace's, and for as
    /// long as its Worker is installed (AGENTS.md §8).
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
        public var read: (String) -> Int?
        public var write: (String, ScreensaverWrite) -> Bool

        public init(read: @escaping (String) -> Int?,
                    write: @escaping (String, ScreensaverWrite) -> Bool) {
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
        /// macOS never reads. `kCFPreferencesAnyHost` is wrong too: both keys live
        /// only in the ByHost domain.
        public static let preferences = Store(
            read: { SessionIdleLockRunner.read(key: $0) },
            write: { key, change in
                switch change {
                case .unchanged:
                    return true
                case .value(let seconds):
                    CFPreferencesSetValue(
                        key as CFString,
                        seconds as CFNumber,
                        SessionIdleLockRunner.domain as CFString,
                        kCFPreferencesCurrentUser,
                        kCFPreferencesCurrentHost)
                case .removeKey:
                    CFPreferencesSetValue(
                        key as CFString,
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
    public var policy: [SessionIdleLock.ManagedPreference]
    public var store: Store
    public var fileManager: FileManager

    public init(recordPath: String,
                policy: [SessionIdleLock.ManagedPreference] = SessionIdleLock.policy,
                store: Store = .preferences,
                fileManager: FileManager = .default) {
        self.recordPath = recordPath
        self.policy = policy
        self.store = store
        self.fileManager = fileManager
    }

    /// What one key held before AgentSpace replaced it. `nil` means it did not exist.
    private struct Original: Codable {
        var value: Int?

        init(_ value: Int?) { self.value = value }

        /// A record written by 0.1.74–0.1.77 has no explicit null for "the key did
        /// not exist" — the whole `previous` field is simply missing — so absent
        /// means absent here rather than "no record for this key".
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.contains(.value) else {
                self.value = nil
                return
            }
            self.value = try container.decodeIfPresent(Int.self, forKey: .value)
        }

        private enum CodingKeys: String, CodingKey { case value }
    }

    /// The originals, keyed by preference — so a record from the Worker that first
    /// touched this account still restores it correctly after the policy grew a
    /// second key.
    ///
    /// Legacy shape (0.1.74–0.1.77): `{"previous": 1200}` for `idleTime` and nothing
    /// else. A Worker updated over a running one finds the interval already pinned
    /// and writes no new record, so the file that gets restored from is often that
    /// older one, and reading it as "no originals" would strand the account pinned
    /// forever.
    private struct Record: Codable {
        var originals: [String: Original]

        init(originals: [String: Original]) {
            self.originals = originals
        }

        private enum CodingKeys: String, CodingKey { case originals, previous }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            var parsed = try container.decodeIfPresent([String: Original].self, forKey: .originals) ?? [:]
            if let previous = try container.decodeIfPresent(Int.self, forKey: .previous),
               parsed[SessionIdleLockRunner.key] == nil {
                parsed[SessionIdleLockRunner.key] = Original(previous)
            }
            originals = parsed
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(originals, forKey: .originals)
        }
    }

    /// The record this account has, if any. `nil` means AgentSpace has never
    /// changed this account's lock settings.
    private var record: Record? {
        guard let data = fileManager.contents(atPath: recordPath),
              let decoded = try? JSONDecoder().decode(Record.self, from: data)
        else { return nil }
        return decoded
    }

    /// Pin the account's lock triggers, remembering what each key held first.
    ///
    /// Returns a one-line description of what happened, for the log; `nil` when
    /// there was nothing to do.
    public func apply() -> String? {
        var changes: [String: String] = [:]
        var failures: [String] = []

        for preference in policy {
            let current = store.read(preference.key)
            guard case .value(let pinned) = preference.apply(current: current) else {
                // Either the person set this themselves, or a Worker already did
                // and never got to restore it. In the second case the record file
                // is still here, so the original is not lost.
                continue
            }
            // Record before writing: a Worker killed between the two would else
            // leave a changed preference with nothing to restore it from. An
            // existing original wins — it holds the true value, from the first
            // Worker that changed this account.
            var saved = record ?? Record(originals: [:])
            if saved.originals[preference.key] == nil {
                saved.originals[preference.key] = Original(current)
                let data = (try? JSONEncoder().encode(saved)) ?? Data("{}".utf8)
                try? data.write(to: URL(fileURLWithPath: recordPath), options: .atomic)
            }
            guard store.write(preference.key, .value(pinned)) else {
                failures.append("\(SessionIdleLockRunner.domain)/\(preference.key)")
                continue
            }
            changes[preference.key] = "\(current.map { "\($0)" } ?? "unset")→\(pinned)"
        }

        guard !changes.isEmpty || !failures.isEmpty else { return nil }
        if !failures.isEmpty {
            return "the account can still lock itself: could not write \(failures.joined(separator: ", "))"
        }
        let rendered = policy.compactMap { changes[$0.key] }
        return "the account will not lock itself: \(rendered.joined(separator: ", "))"
    }

    /// Put every key AgentSpace changed back the way this account had it. A no-op
    /// for a key it never wrote, so stopping a Worker cannot edit a preference it
    /// does not own.
    public func restore() -> String? {
        guard var saved = record, !saved.originals.isEmpty else { return nil }

        var restored: [String] = []
        var failures: [String] = []
        for (key, original) in saved.originals.sorted(by: { $0.key < $1.key }) {
            let change = SessionIdleLock.restore(recorded: original.value)
            guard store.write(key, change) else {
                failures.append(key)
                continue
            }
            saved.originals[key] = nil
            restored.append("\(key)→\(original.value.map { "\($0)" } ?? "absent")")
        }
        // Keep what could not be put back, so the next Worker start still owns it.
        saved.originals = saved.originals.compactMapValues { $0 }
        if saved.originals.isEmpty {
            try? fileManager.removeItem(atPath: recordPath)
        } else {
            let data = (try? JSONEncoder().encode(saved)) ?? Data("{}".utf8)
            try? data.write(to: URL(fileURLWithPath: recordPath), options: .atomic)
        }

        if !failures.isEmpty {
            return "still AgentSpace's to undo: could not restore \(SessionIdleLockRunner.domain)/\(failures.joined(separator: ", "))"
        }
        return "restored the account's own lock settings: \(restored.joined(separator: ", "))"
    }
}
