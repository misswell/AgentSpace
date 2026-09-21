import Foundation

/// The names the update channel has to agree with the build about.
///
/// These are written down rather than read from the running bundle, because an
/// update candidate has to be checked against what AgentSpace *is* — not against
/// what the candidate's own Info.plist claims.
public enum AgentSpaceIdentity {
    public static let githubRepository = "misswell/AgentSpace"
    public static let bundleIdentifier = "com.agentspace.AgentSpace"
    public static let appBundleName = "AgentSpace.app"
    public static let executableName = "AgentSpace"
    public static let updaterExecutableName = "agentspace-updater"

    /// The developer team every distributable AgentSpace is signed by.
    ///
    /// `AgentSpaceUpdaterTeamPinningTests` asserts this is the same value the
    /// privileged helper enforces for its callers. The two checks are the same
    /// question — "is this AgentSpace, signed by us?" — asked from two sides,
    /// and drift between them means either an update that a healthy helper
    /// refuses or a helper that accepts an update the app should have rejected.
    public static let developerTeamIdentifier = "U8U443D7ZL"

    /// The release asset `scripts/release.sh` produces for a version.
    public static func archiveName(for version: String) -> String {
        "AgentSpace-\(version).dmg"
    }

    /// Code that must be inside the bundle for AgentSpace to work at all: the
    /// helper installs the worker from a path relative to itself, the MCP
    /// integration names the CLI, and an app without its updater can never
    /// update again. Checked against an update candidate, and asserted against
    /// `scripts/bundle-app.sh` by `SoftwareUpdateDriftTests`.
    public static var nestedCodePaths: [String] {
        [
            "Contents/MacOS/agentspace-worker",
            "Contents/Helpers/agentspace",
            "Contents/Helpers/" + updaterExecutableName,
            "Contents/Library/LaunchDaemons/agentspace-helper",
        ]
    }

    public static func isKnownBundleIdentifier(_ identifier: String?) -> Bool {
        identifier == bundleIdentifier
    }
}
