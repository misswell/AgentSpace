import Foundation

/// Turns a method refusal from an older worker into an actionable, in-app fix.
///
/// The worker is intentionally versioned independently from the GUI process:
/// launchd can keep the old LaunchAgent alive after an app update. In that
/// window the new GUI receives `METHOD_NOT_FOUND` for a method it knows about.
/// Only the method being attempted is eligible for this recovery; unrelated
/// unknown-method errors must remain honest protocol failures.
public enum WorkerCompatibility {
    public enum VersionWaitResult: Equatable {
        case ready
        case unavailable
        case mismatched(String)
    }

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

    public static func version(from response: RPCResponse?) -> String? {
        guard response?.ok == true else { return nil }
        return response?.result?["worker"]?["version"]?.stringValue
    }

    /// Polls the unauthenticated hello method until the expected worker image
    /// actually answers. A successful launchctl command is not sufficient:
    /// launchd may still be starting the process, or a stale image may own the
    /// socket briefly while jobs are replaced.
    public static func waitForVersion(
        expected: String,
        attempts: Int,
        pause: () -> Void,
        probe: () -> RPCResponse?
    ) -> VersionWaitResult {
        precondition(attempts > 0)
        var lastObserved: String?
        for attempt in 0..<attempts {
            if let version = version(from: probe()) {
                if version == expected { return .ready }
                lastObserved = version
            }
            if attempt + 1 < attempts { pause() }
        }
        if let lastObserved { return .mismatched(lastObserved) }
        return .unavailable
    }
}
