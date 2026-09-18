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
        self.startedAt = Date()
        self.uid = getuid()
        self.username = String(cString: namePtr)
        self.home = NSHomeDirectory()
        let record = WorkerContext.readSpaceRecord(paths: paths)
        self.mainUser = record?["mainUser"] as? String
        self.allowedRoots = (record?["allowedRoots"] as? [String]) ?? []
        self.writableRoots = Set((record?["writableRoots"] as? [String]) ?? [])
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
}
