import Foundation
import AgentSpaceCore

/// Everything the worker knows about itself and the Space it serves.
///
/// Resolved once at startup from the process's *own* identity, never from
/// anything a caller sent. A caller cannot talk this worker into believing it
/// is a different user or a different Space.
public final class WorkerContext {
    public let spaceID: UUID
    public let spaceName: String
    public let token: SessionToken
    public let paths: RuntimePaths
    public let sessionInfo: SessionInfoSource
    public let startedAt: Date
    /// Optional record written by the privileged helper: who else may reach
    /// this runtime directory.
    public let mainUser: String?
    /// Roots the Space is allowed to touch (its worktree + shared folders),
    /// and the subset of those it may write to. Empty means "no confinement
    /// declared" — the worker then refuses to confine rather than inventing
    /// rules, and says so in `status`. See docs/security.md.
    public let allowedRoots: [String]
    public let writableRoots: Set<String>

    public let uid: uid_t
    public let username: String
    public let home: String
    /// The live desktop probe. One instance per worker: it keeps the last
    /// logged verdict so a startup wait is a few lines rather than a poll log.
    /// Internal — `DesktopSessionMonitor` is this module's, and callers ask
    /// `desktopReadiness()` rather than reaching for the probe.
    let desktopMonitor: DesktopSessionMonitor

    public init?(
        spaceID: UUID,
        spaceName: String,
        token: SessionToken,
        paths: RuntimePaths,
        sessionInfo: SessionInfoSource = SystemSessionInfo()
    ) {
        guard let pw = getpwuid(getuid()), let namePtr = pw.pointee.pw_name else {
            return nil
        }
        self.spaceID = spaceID
        self.spaceName = spaceName
        self.token = token
        self.paths = paths
        self.sessionInfo = sessionInfo
        self.desktopMonitor = DesktopSessionMonitor(source: sessionInfo)
        self.startedAt = Date()
        self.uid = getuid()
        self.username = String(cString: namePtr)
        let record = WorkerContext.readSpaceRecord(paths: paths)
        self.mainUser = record?["mainUser"] as? String
        self.allowedRoots = (record?["allowedRoots"] as? [String]) ?? []
        self.writableRoots = Set((record?["writableRoots"] as? [String]) ?? [])
        // The helper records the account's home at creation, which is the
        // authoritative answer; `NSHomeDirectory()` is the fallback for a worker
        // started before that field existed.
        //
        // Safe to honour from the record: the walk it feeds reads only file
        // metadata, runs as this Space's own user, and is budget-bounded — so a
        // tampered path costs the worker a slow stat walk, not a privilege
        // boundary. And space.json is written by root into a directory this user
        // cannot write to.
        self.home = (record?["home"] as? String).flatMap {
            $0.isEmpty ? nil : $0
        } ?? NSHomeDirectory()
    }

    /// The helper writes `<runtime>/space.json` at creation time.
    private static func readSpaceRecord(paths: RuntimePaths) -> [String: Any]? {
        let path = paths.directory + "/space.json"
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    /// Where screenshots land: inside the Space's runtime directory, which is
    /// ACL'd for both the main user and the agent user. Deliberately not inside
    /// the agent's home — the main user and the CLI could not read it there.
    public var screenshotsDirectory: String { paths.directory + "/screenshots" }

    /// The live verdict on this session. Recomputed per request: a session can
    /// become the console at any moment (the human fast-user-switches into it),
    /// and a cached "not on console" is exactly the stale answer that would post
    /// events onto someone's real screen.
    public func sessionVerdict() -> SessionVerdict {
        SessionGuard.verdict(using: sessionInfo)
    }

    /// Is this session's *desktop* up — Dock, Finder, login finished, window
    /// server present? Asked on every input call rather than cached at startup:
    /// a session that finishes coming up, or gets locked, must be picked up
    /// without a worker restart, and the whole probe is one dictionary read plus
    /// two process lookups.
    public func desktopReadiness() -> DesktopReadiness {
        desktopMonitor.readiness()
    }
}
