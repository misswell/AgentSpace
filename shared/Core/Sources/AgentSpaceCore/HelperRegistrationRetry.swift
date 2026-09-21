import Foundation

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
