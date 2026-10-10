import Foundation

/// What AgentSpace does to the agent account's own two lock preferences.
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
/// - **disconnect** — Apple's host-side `ScreensharingAgent` asks
///   `SACScreenLockEnabled:` and, when loginwindow answers 1, calls
///   `SACLockScreenImmediate:` as the last viewer goes away. Measured 2026-10-10
///   09:56:11 with `idleTime=0` already in place, so no screensaver is involved
///   and the interval changes nothing for it — the inference that has been
///   standing since 2026-10-09 is now observed rather than reasoned. The gate is
///   one number: `-[SessionAgentCom SACScreenLockEnabled:]` answers
///   `-[LWKeybagSupport calculatedPasswordDelayFromPrefs] != INT_MAX`, and
///   loginwindow's own string on that path reads `Lock on, but int_max, setting
///   to NO`. So this class *is* preventable, and the lever is the account's
///   "require password after a lock" delay: at `INT_MAX` the answer is NO and no
///   lock is ever requested.
///
/// So: while a Worker is installed for an account, that account's screensaver is
/// set to never *and* its password-required delay is set to never. Restoring the
/// previous values when the Worker stops is what keeps this from being a
/// permanent change to an account AgentSpace no longer manages — and because
/// `detach` stops the Worker first, disconnecting an account restores it without
/// detach knowing about it.
///
/// What the second key costs, said plainly: "never require the password again
/// after a lock" is also "this account's lock screen stops demanding its
/// password", for as long as its Worker is installed. That is the price of a
/// desktop that survives closing the Screen Sharing window, and it is the
/// owner's decision, recorded in AGENTS.md §8. `askForPassword` is still never
/// written — it is not the key that gates the disconnect lock, and §8 keeps it
/// outside AgentSpace regardless.
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

    /// The value that means "never ask for the password again after a lock".
    ///
    /// `INT_MAX` rather than a large number: that is the sentinel loginwindow
    /// itself installs when there is nothing to demand (a guest, a machine still
    /// in Setup Assistant, an account with `askForPassword` off), and
    /// `-[SessionAgentCom SACScreenLockEnabled:]` compares against it exactly —
    /// `calculatedPasswordDelayFromPrefs != INT_MAX`. Any other value locks now
    /// and asks later; only this one means the disconnect lock is never requested.
    public static let passwordDelayNever = Int(Int32.max)

    /// The writes a Worker makes to an account, in the order it makes them.
    ///
    /// One list rather than two call sites: the second key is the one with a
    /// security cost, so a future reader of the *caller* has to be able to see
    /// both at once.
    public static let policy: [ManagedPreference] = [
        ManagedPreference(key: "idleTime", never: never),
        ManagedPreference(key: "askForPasswordDelay", never: passwordDelayNever),
    ]

    /// A `com.apple.screensaver` key AgentSpace pins, and the value that means
    /// "this trigger never fires".
    public struct ManagedPreference: Hashable, Sendable {
        public let key: String
        public let never: Int

        public init(key: String, never: Int) {
            self.key = key
            self.never = never
        }

        /// The write that pins this key, or `unchanged` when it already says never.
        ///
        /// `unchanged` matters twice over: a Worker that rewrote the same value on
        /// every start would produce a preference write per launch, and only a real
        /// write gets a record to undo.
        public func apply(current: Int?) -> ScreensaverWrite {
            current == never ? .unchanged : .value(never)
        }
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
