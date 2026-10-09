import AppKit
import Foundation
import AgentSpaceCore

/// The live answer to "is this session's desktop up?", sampled on demand.
///
/// The decision itself is Core's (`DesktopReadinessCheck`) so it can be tested
/// with synthetic facts; this type is the part that can only run in a session —
/// it reads the session dictionary, the graphic-access bit, and whether the two
/// processes that make a session a *desktop* are running.
///
/// Every input was measured in the agent account's own Aqua session on
/// 2026-09-23:
///
/// - `kCGSessionLoginDoneKey` is present and `1` (`__NSCFBoolean`);
/// - `SessionGetInfo`'s `sessionHasGraphicAccess` is the only probe that answers
///   "is there a window server" — `NSRunningApplication` reports **no**
///   `WindowServer` process, so looking for one would be a check that can never
///   pass;
/// - Dock (pid 25866), Finder (pid 25870) and loginwindow (pid 25770) are all
///   running, and `NSRunningApplication` finds them by bundle id even though the
///   window-list view (`AppControl.runningApps`) does not: Dock owns no layer-0
///   window, so a visibility-filtered list is the wrong probe for existence.
final class DesktopSessionMonitor {
    private let source: SessionInfoSource
    private let lock = NSLock()
    private var lastLogged: String?
    private var lastLocked: Bool?

    init(source: SessionInfoSource = SystemSessionInfo()) {
        self.source = source
    }

    func facts() -> DesktopFacts {
        let dictionary = source.currentSessionDictionary()
        func flag(_ key: String) -> Bool? {
            guard let value = dictionary?[key] else { return nil }
            if let number = value as? NSNumber { return number.boolValue }
            if let boolean = value as? Bool { return boolean }
            return nil
        }
        let locked = flag("CGSSessionScreenIsLocked") ?? false
        logLockChange(locked: locked, dictionary: dictionary)
        return DesktopFacts(
            sessionDictionaryReadable: dictionary != nil,
            loginDone: flag("kCGSessionLoginDoneKey"),
            hasGraphicAccess: source.hasGraphicAccess(),
            dockRunning: Self.isRunning("com.apple.dock"),
            finderRunning: Self.isRunning("com.apple.finder"),
            // Absent while unlocked — measured: the key is simply not in the
            // dictionary for a background session, which is why this is
            // `?? false` and not a three-valued answer.
            screenLocked: locked)
    }

    func readiness() -> DesktopReadiness {
        DesktopReadinessCheck.evaluate(facts())
    }

    private static func isRunning(_ bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    /// Wait, bounded, for the desktop to come up — the ordering rule's middle
    /// step (*Session → Desktop Ready → Capture → Input*).
    ///
    /// Bounded rather than open-ended on purpose: a worker that never binds its
    /// socket because a Dock is missing is a worker whose `status` cannot explain
    /// why, and the app would show "offline" for a session that is perfectly
    /// inspectable. So the wait is short, its result is logged, and the input
    /// path keeps asking the same question per call.
    @discardableResult
    func waitForReady(timeout: TimeInterval, pollInterval: TimeInterval = 0.5) -> DesktopReadiness {
        let deadline = Date().addingTimeInterval(timeout)
        var readiness = self.readiness()
        logTransition(readiness)
        while !readiness.isReady && Date() < deadline {
            Thread.sleep(forTimeInterval: pollInterval)
            readiness = self.readiness()
            logTransition(readiness)
        }
        return readiness
    }

    /// One line per state change, so a session that takes ten seconds to come up
    /// is a handful of lines rather than a poll log.
    func logTransition(_ readiness: DesktopReadiness) {
        lock.lock()
        defer { lock.unlock() }
        let summary = readiness.summary
        guard summary != lastLogged else { return }
        lastLogged = summary
        if readiness.isReady {
            Log.session.info("\(summary)")
        } else {
            Log.session.error("\(summary)")
        }
    }

    /// What the lock was made of, on every edge of the lock bit.
    ///
    /// Gated on the bit rather than on the readiness summary, and gated at all
    /// rather than logged per probe: `desktopReadiness()` runs on *every* input
    /// call, so reading three preferences per keystroke would make a diagnostic
    /// cost the thing it describes. The line is the only way to tell, after a
    /// person reports it, which of the two measured lock classes fired — see
    /// `LockEvidence`.
    private func logLockChange(locked: Bool, dictionary: [String: Any]?) {
        lock.lock()
        let changed = lastLocked != locked
        if changed { lastLocked = locked }
        lock.unlock()
        guard changed else { return }

        func number(_ key: String) -> Int? { (dictionary?[key] as? NSNumber)?.intValue }
        func flag(_ key: String) -> Bool? { (dictionary?[key] as? NSNumber)?.boolValue }

        let evidence = LockEvidence(
            screenIsLocked: locked,
            lockedForSeconds: number("CGSSessionScreenLockedTime"),
            secureInputPID: number("kCGSSessionSecureInputPID"),
            onConsole: flag("kCGSSessionOnConsoleKey"),
            screensaverIdleTime: SessionIdleLockRunner.read(key: SessionIdleLockRunner.key),
            askForPassword: SessionIdleLockRunner.read(key: "askForPassword"),
            askForPasswordDelay: SessionIdleLockRunner.read(key: "askForPasswordDelay"))
        if locked {
            Log.session.error("lock evidence: \(evidence.line)")
        } else {
            Log.session.info("lock evidence: \(evidence.line)")
        }
    }
}
