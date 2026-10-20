import Foundation

/// Whether `launchctl print gui/<uid>` says that account has a live Aqua session.
///
/// This is the one question the sign-in flow must not get wrong, and it was
/// answered wrong on macOS 27: the probe looked for the service names
/// `com.apple.uisecd` / `ATTRS` inside the printed domain. Measured 2026-10-10 on
/// the Mac where the sign-in never finished — a live session's print is 108,928
/// bytes (`gui/503 = {`, `type = login`, its `loginwindow` the domain's creator,
/// 457 services) and contains **no** `uisec` and **no** `ATTR`; the same is true
/// of the console account's own print (145,268 bytes, same two zero counts). The
/// sniff therefore never returned true here, and every sign-in was reported as a
/// login that had not happened.
///
/// What launchd actually answers with, measured minutes apart on one machine:
///
/// * a domain that exists → exit 0, and its own type line `type = login`;
/// * a uid with no GUI domain → exit **112**, `Bad request.` /
///   `Could not find domain for user gui: <uid>`;
/// * a domain it will not show the caller → exit 1, `Could not print domain: 1:
///   Operation not permitted`.
///
/// The first two are answers to the question. The third is not an answer at all,
/// so it is returned as its own case instead of being read as "no session" —
/// reporting Apple's silence as a statement about Apple is how this was
/// misdiagnosed for three rounds.
public enum LaunchdDomain {
    /// The line every printed login domain starts with, after the `gui/<uid> = {`
    /// header. Required rather than trusted: it is a stricter question than the
    /// two service names were, and it distinguishes a GUI login domain from any
    /// other domain that might answer exit 0.
    static let loginTypeMarker = "type = login"

    /// launchd's status for "there is no such domain" (measured above).
    public static let absentDomainExitCode: Int32 = 112

    /// launchd's status for "this job is already registered" (EEXIST). A
    /// bootout returns before launchd has finished removing the job, so a
    /// bootstrap that arrives first is answered with this even though removal
    /// is under way.
    public static let alreadyLoadedExitCode: Int32 = 17

    /// launchd's status for "this domain will not take that action".
    ///
    /// Measured on this Mac 2026-10-20: `launchctl print gui/0` and
    /// `launchctl bootstrap gui/0 …` both answer exit 125 with this message.
    /// The product met it as the intermittent `start failed: Bootstrap failed:
    /// 125: Domain does not support specified action` after a remote login;
    /// pressing the button again later worked, which is what waiting inside
    /// one press replaces (§390).
    public static let unsupportedActionExitCode: Int32 = 125

    /// How long one call waits for launchd to settle, and how often it asks.
    /// Ten seconds covers a domain finishing its login transition; every
    /// pause is bounded so an unavailable desktop still fails promptly.
    public static let retryPause: TimeInterval = 0.25
    public static let retryWindow: TimeInterval = 10
    /// Defensive cap: launchctl refusals can return in milliseconds, and a
    /// tight loop inside the helper is not a substitute for waiting.
    public static let maximumRetryAttempts = 40

    /// Whether asking launchd again can change this answer. 17 and 112 are
    /// launchd still moving a job or a domain; 125 is a domain that exists but
    /// is not ready for the action yet. A malformed plist, a refused caller or
    /// a killed process will answer the same way every time.
    public static func isTransientStatus(_ exitCode: Int32) -> Bool {
        exitCode == alreadyLoadedExitCode
            || exitCode == absentDomainExitCode
            || exitCode == unsupportedActionExitCode
    }

    /// How long to wait before the next attempt, or `nil` when the status is
    /// final or the budget is spent. `attempts` counts attempts already made;
    /// `elapsed` is measured from the first one.
    public static func retryDelay(
        exitCode: Int32,
        attempts: Int,
        elapsed: TimeInterval
    ) -> TimeInterval? {
        guard isTransientStatus(exitCode),
              attempts < maximumRetryAttempts,
              elapsed < retryWindow else { return nil }
        return retryPause
    }

    public enum Verdict: Equatable, Sendable {
        case graphical
        /// launchd says this account has no GUI domain. That is the answer the
        /// sign-in sheet is actually waiting for.
        case absent
        /// launchd refused, timed out, or printed something with no type line in
        /// it. Nothing may be concluded about the account from this.
        case unusable(detail: String)

        /// The value of the `sessionDomain` field on a `sessionInfo` answer, so a
        /// caller can tell `absent` from `unusable` without reading prose.
        public var wireValue: String {
            switch self {
            case .graphical: return "graphical"
            case .absent: return "absent"
            case .unusable: return "unusable"
            }
        }

        /// A one-line description of *how* the question was answered, for logs and
        /// for the `detail` field. Prose nobody parses: `wireValue` is the field a
        /// caller branches on.
        public func detail(domain: String, bytes: Int) -> String {
            switch self {
            case .graphical: return "\(domain) printed \(bytes) bytes"
            case .absent: return "\(domain) has no GUI domain (launchd exit \(LaunchdDomain.absentDomainExitCode))"
            case .unusable(let reason): return "\(domain): \(reason)"
            }
        }
    }

    /// `exitCode`, standard output and standard error of the print, passed
    /// through rather than re-derived, so this is testable without a Mac per
    /// answer.
    public static func verdict(exitCode: Int32, output: String, errorOutput: String) -> Verdict {
        if exitCode == 0 {
            guard output.contains(loginTypeMarker) else {
                return .unusable(detail: "printed \(output.utf8.count) bytes with no "
                    + "‘\(loginTypeMarker)’ line")
            }
            return .graphical
        }
        if exitCode == absentDomainExitCode { return .absent }
        let reason = errorOutput.isEmpty ? "no message"
            : errorOutput.split(separator: "\n").last.map(String.init) ?? "no message"
        return .unusable(detail: "refused with exit \(exitCode): \(reason)")
    }
}
