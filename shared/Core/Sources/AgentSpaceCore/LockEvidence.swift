import Foundation

/// What could be read about the session, and about this account's own
/// screensaver preference, at the moment its lock bit changed.
///
/// The reason this is logged instead of measured by hand: the two lock classes
/// measured in the AgentUse account on 2026-10-09 set the same
/// `CGSSessionScreenIsLocked` bit and look identical in the interface, but only
/// one of them is preventable.
///
/// - **idle** — `loginwindow`'s screensaver daemon fires on the machine-wide HID
///   idle clock and locks on top of it. `SessionIdleLock` removes that trigger,
///   so `idleTime=0` in this line means the lock was *not* the idle class.
/// - **disconnect** — Apple's host-side `ScreensharingAgent` locks the session
///   directly when the last viewer goes away. No screensaver setting is in that
///   path (measured: no `ScreenSaverEngine` exists in it on macOS 27), so the
///   same line reads `idleTime=0` next to a lock that just happened.
///
/// `askForPassword` and its delay are read, never written: whether a lock
/// accepts an unlock without the account's password is that account's own
/// setting, and this product must not change it (AGENTS.md §7). It is logged
/// because it decides what recovery is even possible — with a password required,
/// the only fix is a person signing in.
///
/// Every field that could not be read says so rather than guessing, which is why
/// this is a struct of optionals and not a string built at the call site.
public struct LockEvidence: Equatable, Sendable {
    /// `CGSSessionScreenIsLocked`, as the Worker saw it.
    public var screenIsLocked: Bool
    /// `CGSSessionScreenLockedTime` — how long the lock has already stood.
    public var lockedForSeconds: Int?
    /// `kCGSSessionSecureInputPID`: a pid here means something holds secure
    /// input, which is the unlock UI being up rather than a drivable desktop.
    public var secureInputPID: Int?
    /// `kCGSSessionOnConsoleKey`. An agent desktop must never be the console
    /// (`SESSION_IS_CONSOLE` refuses input for exactly that reason), so an
    /// answer of `yes` here is a safety fact, not just a cause of a lock.
    public var onConsole: Bool?
    /// The account's own `com.apple.screensaver`/`idleTime`, ByHost.
    public var screensaverIdleTime: Int?
    /// The account's own `askForPassword`.
    public var askForPassword: Int?
    /// The account's own `askForPasswordDelay`.
    public var askForPasswordDelay: Int?

    public init(
        screenIsLocked: Bool,
        lockedForSeconds: Int? = nil,
        secureInputPID: Int? = nil,
        onConsole: Bool? = nil,
        screensaverIdleTime: Int? = nil,
        askForPassword: Int? = nil,
        askForPasswordDelay: Int? = nil
    ) {
        self.screenIsLocked = screenIsLocked
        self.lockedForSeconds = lockedForSeconds
        self.secureInputPID = secureInputPID
        self.onConsole = onConsole
        self.screensaverIdleTime = screensaverIdleTime
        self.askForPassword = askForPassword
        self.askForPasswordDelay = askForPasswordDelay
    }

    /// One line, for `os_log`.
    public var line: String {
        [
            "screenIsLocked=\(yesNo(screenIsLocked))",
            "lockedFor=\(number(lockedForSeconds, unit: "s"))",
            "secureInputPID=\(number(secureInputPID))",
            "onConsole=\(yesNoUnknown(onConsole))",
            "idleTime=\(number(screensaverIdleTime))",
            "askForPassword=\(number(askForPassword))",
            "askForPasswordDelay=\(number(askForPasswordDelay))",
        ].joined(separator: " ")
    }

    private func number(_ value: Int?, unit: String = "") -> String {
        value.map { "\($0)\(unit)" } ?? "unset"
    }

    private func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }

    private func yesNoUnknown(_ value: Bool?) -> String {
        value.map { $0 ? "yes" : "no" } ?? "unknown"
    }
}
