import Foundation

/// What AgentSpace does to the agent account's own screensaver interval.
///
/// An agent desktop is a real Aqua session, so macOS runs its normal idle
/// sequence in it, and a locked desktop is one an agent cannot drive and nobody
/// can recover without the account's password — which this product must never
/// hold (AGENTS.md §7). Two classes were measured in the AgentUse account on
/// 2026-10-09. They raise the same `CGSSessionScreenIsLocked` bit and are not the
/// same problem:
///
/// - **idle** — `loginwindow` (uid 503) took a wallpaper assertion with
///   `contentType: screenSaver` at 09:24:17 and 32 seconds later raised the lock
///   UI with `enqueueUnlockScreenRequest reason: 4` =
///   `kLWLockFromScreenSaverOtherLaunch`. Its trigger is the screensaver's own
///   idle clock, and `idleTime` absent means macOS' default 1200 seconds. This is
///   the class this type prevents: setting the account's interval to "never"
///   removes the trigger, and it is the same lever System Settings → Lock Screen
///   → "Start Screen Saver when inactive" writes.
/// - **disconnect** — Apple's host-side `ScreensharingAgent` calls
///   `SACScreenLockEnabled:` (answers 1) and then `SACLockScreenImmediate:` when
///   the last viewer goes away. No screensaver is involved: measured 2026-10-09,
///   no `ScreenSaverEngine` exists anywhere in that path on macOS 27, so
///   "launch screen saver" is loginwindow's own lock UI and an interval of 0
///   changes nothing for it. The answer there is recovery rather than prevention
///   — the desktop viewer's locked overlay offers sign-in again.
///
/// So: while a Worker is installed for an account, that account's screensaver is
/// set to never. Restoring the previous value when the Worker stops is what keeps
/// this from being a permanent change to an account AgentSpace no longer manages —
/// and because `detach` stops the Worker first, disconnecting an account restores
/// it without detach knowing about it.
///
/// Two measured constraints on the mechanism:
///
/// - It is the **agent user's own** preference, written from inside that user's
///   session. No root, no helper operation, no password.
/// - The screensaver's idle clock is the machine-wide HID clock
///   (`IOHIDSystem`'s `HIDIdleTime`), not a per-session one, so a test of this
///   behaviour needs genuine input silence on the whole Mac — an interval of 60
///   seconds was observed not to fire while a keyboard was ticking over.
public enum SessionIdleLock {
    /// The value that means "never start the screensaver".
    public static let never = 0

    /// The write that turns the account's screensaver off.
    ///
    /// `unchanged` when the key already says never: a Worker that rewrites the
    /// same value on every start would produce a preference write per launch,
    /// and `unchanged` is also what makes the recorded original meaningful —
    /// only a real write gets a record to undo.
    public static func apply(current: Int?) -> ScreensaverWrite {
        current == never ? .unchanged : .value(never)
    }

    /// The write that puts the account back the way it was found.
    ///
    /// A recorded `nil` means the key did not exist before AgentSpace, so
    /// restoring means removing it rather than inventing a value.
    public static func restore(recorded: Int?) -> ScreensaverWrite {
        guard let recorded else { return .removeKey }
        return .value(recorded)
    }
}

/// A write to the screensaver preference, or the decision not to make one.
public enum ScreensaverWrite: Equatable, Sendable {
    case value(Int)
    case removeKey
    case unchanged
}
