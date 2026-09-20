import Foundation

/// Turns a method refusal from an older worker into an actionable, in-app fix.
///
/// The worker is intentionally versioned independently from the GUI process:
/// launchd can keep the old LaunchAgent alive after an app update. In that
/// window the new GUI receives `METHOD_NOT_FOUND` for a method it knows about.
/// Only the method being attempted is eligible for this recovery; unrelated
/// unknown-method errors must remain honest protocol failures.
public enum WorkerCompatibility {
    public static func recovery(
        for error: AgentSpaceError?,
        method: String
    ) -> AgentSpaceError? {
        guard let error else { return nil }
        guard method == Method.openSystemSettings,
              error.code == .methodNotFound else { return error }
        return AgentSpaceError(
            code: .methodNotFound,
            message: "the connected account's worker is older and does not support \(method)",
            recoverable: true,
            recoveryHint: .reinstallWorker)
    }
}
