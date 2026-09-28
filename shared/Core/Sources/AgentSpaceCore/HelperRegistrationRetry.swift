import Foundation
import ServiceManagement

/// Whether a refused `SMAppService.register()` is worth asking about again.
///
/// Measured on this machine: a registration 13 ms after an `unregister()` that had
/// already returned success answers `error: 1`, and the same call 2.7 s later
/// answers `error: 0`. launchd is still taking the old daemon down, and that
/// refusal is the app's to retry — it is the reason a person pressed
/// 「重新安装助手…」 in the first place.
///
/// A refusal they made is not. `-128` is `userCanceledErr`, and a second password
/// prompt aimed at someone who just typed "no" is nagging rather than persistence.
public enum HelperRegistrationRetry {
    /// `userCanceledErr`, which is also `NSUserCancelledError`.
    public static let cancelledCode = -128
    /// Five attempts one second apart, so the last question is asked about four
    /// seconds after the first refusal. The budget has to outlast what it is
    /// waiting for: the measured recovery here took 2.7 s, and a loop that gives
    /// up at one second reports launchd's own transient failure as the app's.
    public static let maximumAttempts = 5
    public static let interval: TimeInterval = 1

    /// - Parameter attempt: how many attempts have already been made, so `1` means
    ///   "the first one just failed".
    public static func shouldRetry(_ error: Error, attempt: Int, attempts: Int = maximumAttempts) -> Bool {
        guard attempt < attempts else { return false }
        // Deliberately keyed on the code alone. An unrelated domain that happens
        // to use -128 costs one visible failure; re-prompting someone who just
        // refused costs their trust, and the two are not symmetric.
        return (error as NSError).code != cancelledCode
    }
}

/// What a refused `SMAppService.register()` means for the person looking at it.
///
/// Measured on this machine, 2026-09-28: with the helper registered and waiting
/// for approval (`SMAppService.Status.requiresApproval`), every `register()`
/// answers `SMAppServiceErrorDomain` code 1 — "Operation not permitted" — and
/// macOS never re-prompts. The raw `localizedDescription` reads like a
/// permissions bug in the app and sends the person back to a button that can
/// never succeed, which is exactly the dead end this type exists to name: the
/// approval lives in System Settings → General → Login Items & Extensions, and
/// only the person at the machine can flip it.
public enum HelperRegistrationGuidance {

    /// The domain `SMAppService` registration failures arrive in. Spelled out
    /// rather than imported: the imported symbol is annotated macOS 15+ while
    /// this package targets 13, and the domain string is a stable part of the
    /// framework's error contract.
    public static let serviceErrorDomain = "SMAppServiceErrorDomain"

    /// The outcome of a refused registration, ready to present.
    public struct Refusal: Equatable, Sendable {
        public var message: String
        public var fix: String
        /// True when the only cure is the Login Items toggle, so the presenter
        /// should offer the button that opens that pane.
        public var approvalPending: Bool
    }

    /// - Parameters:
    ///   - error: what `register()` threw.
    ///   - status: `SMAppService`'s view *after* the failure, so a pending
    ///     approval is recognised even when the error arrives bare.
    public static func refusal(for error: Error, status: SMAppService.Status) -> Refusal {
        let nsError = error as NSError
        let refusedWhileHeldForApproval = nsError.domain == serviceErrorDomain && nsError.code == 1
        guard status == .requiresApproval || refusedWhileHeldForApproval else {
            return Refusal(
                message: error.localizedDescription,
                fix: NSLocalizedString(
                    "Open the AgentSpace app and choose “Install Helper”. macOS will ask for your password, because only an administrator can add a LaunchDaemon.",
                    comment: ""),
                approvalPending: false)
        }
        return Refusal(
            message: NSLocalizedString(
                "macOS is holding the helper for your approval, so the registration was refused.",
                comment: ""),
            fix: NSLocalizedString(
                "System Settings → General → Login Items & Extensions → turn on AgentSpace under “Allow in the Background”, then come back and press Recheck.",
                comment: ""),
            approvalPending: true)
    }
}
