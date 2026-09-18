import Foundation

/// The §20 runtime trio's third file.
///
/// `worker.sock` and `worker.pid` appear as side effects of binding;
/// `status.json` is the worker's last-known self-description, for anything
/// that inspects a Space after the socket is gone — a crashed worker, a
/// stale pid, or the doctor deciding what to report. The worker writes
/// "running" right after bind and "stopped" on clean shutdown, so the
/// file always answers "what was the last thing this worker knew about
/// itself" — which for a SIGKILLed worker is still "running". That is the
/// honest limit of the format: it is last-known, never current.
///
/// The JSON is built here in Core as a pure function so the on-disk
/// contract — field names, types, the ISO-8601 UTC timestamp — is pinned
/// by tests rather than only by the worker's behaviour.
public enum StatusSnapshot {

    /// The two states a worker can record about itself. A crashed worker
    /// never gets to write "stopped"; readers must therefore treat the
    /// file as last-known, and live-ness is still established the same
    /// way it always was — by connecting to the socket.
    public enum Phase: String {
        case running
        case stopped
    }

    /// Build the status.json payload. Keys are sorted so the file is
    /// byte-stable for a given input, which makes it diffable in bug
    /// reports and hashable in tests.
    public static func json(
        phase: Phase,
        pid: Int32,
        uid: UInt32,
        spaceId: UUID,
        spaceName: String,
        verdict: String,
        at date: Date = Date()
    ) -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let object: [String: Any] = [
            "phase": phase.rawValue,
            "pid": Int(pid),
            "uid": Int(uid),
            "spaceId": spaceId.uuidString,
            "spaceName": spaceName,
            "verdict": verdict,
            "writtenAt": formatter.string(from: date),
        ]
        return (try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .prettyPrinted])) ?? Data("{}".utf8)
    }
}
