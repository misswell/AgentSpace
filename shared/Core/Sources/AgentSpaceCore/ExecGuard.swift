import Foundation

/// Product-level refusal list for `exec`. Plan §36.
///
/// Stated plainly, because the plan is explicit that this must not be
/// oversold: **this is not a sandbox.** The real security boundary is that the
/// worker is a standard, non-admin user with its own uid, its own home and no
/// sudo. This list exists to stop an agent from *trying* the handful of
/// commands that would either fail confusingly or, on a machine where the
/// agent account was accidentally made an admin, do real damage. It is a
/// guardrail against mistakes and prompt injection, not a containment
/// mechanism.
public enum ExecGuard {

    /// A pattern and why it is refused.
    public struct Rule: Sendable {
        public let pattern: String
        public let reason: String
    }

    /// Substring rules, matched case-insensitively against the command line.
    public static let rules: [Rule] = [
        Rule(pattern: "sudo", reason: "privilege escalation is out of scope for an agent session"),
        Rule(pattern: "installer", reason: "installing system packages modifies the machine, not the Space"),
        Rule(pattern: "diskutil erase", reason: "erases a volume"),
        Rule(pattern: "diskutil erasevolume", reason: "erases a volume"),
        Rule(pattern: "diskutil reformat", reason: "erases a volume"),
        Rule(pattern: "diskutil unmount", reason: "detaches volumes the user may be using"),
        Rule(pattern: "launchctl bootstrap system", reason: "installs a system-wide daemon"),
        Rule(pattern: "launchctl bootout system", reason: "removes a system-wide daemon"),
        Rule(pattern: "dscl create", reason: "modifies the directory service / creates accounts"),
        Rule(pattern: "dscl delete", reason: "modifies the directory service / deletes accounts"),
        Rule(pattern: "dseditgroup", reason: "modifies group membership"),
        Rule(pattern: "sysadminctl", reason: "creates or modifies user accounts"),
        Rule(pattern: "rm -rf /", reason: "recursive delete from the filesystem root"),
        Rule(pattern: "rm -rf /*", reason: "recursive delete from the filesystem root"),
        Rule(pattern: "shutdown", reason: "powers off the machine the human is using"),
        Rule(pattern: "reboot", reason: "restarts the machine the human is using"),
        Rule(pattern: "halt", reason: "powers off the machine the human is using"),
        Rule(pattern: "nvram", reason: "modifies firmware variables"),
        Rule(pattern: "csrutil", reason: "modifies System Integrity Protection"),
        Rule(pattern: "spctl --master-disable", reason: "disables Gatekeeper"),
        Rule(pattern: "kextload", reason: "loads a kernel extension"),
        Rule(pattern: "tccutil", reason: "manipulates the TCC permission database"),
        Rule(pattern: "security authorizationdb", reason: "modifies the authorization database"),
        Rule(pattern: "chmod -R 777 /", reason: "opens the whole filesystem"),
        Rule(pattern: ":(){:|:&};:", reason: "fork bomb"),
        Rule(pattern: "mkfs", reason: "formats a filesystem"),
        Rule(pattern: "dd if=", reason: "raw device write; can destroy a disk"),
        Rule(pattern: "> /dev/disk", reason: "raw device write"),
    ]

    /// Commands whose *effect* depends on being root are refused by name when
    /// they appear as the first word, even though the standard user could not do
    /// anything with them anyway. Refusing early gives a clear error instead of
    /// a permission-denied the agent might retry.
    public static let refusedExecutables: Set<String> = [
        "su", "sudo", "doas", "dscl", "dseditgroup", "sysadminctl",
        "shutdown", "reboot", "halt", "csrutil", "nvram", "kextload", "kextunload",
    ]

    /// Check a command line. Returns the refusal, or nil when it is allowed.
    ///
    /// Matching is on the raw command string, which means it can be evaded by
    /// quoting (`s""udo`). That is accepted and documented: the point is to stop
    /// the ordinary case, and the containment is the uid. Claiming otherwise
    /// would be the dishonest part.
    public static func refusal(for command: String) -> AgentSpaceError? {
        let lower = command.lowercased()

        // Normalise whitespace so `rm   -rf   /` matches the same rule.
        let collapsed = lower.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .joined(separator: " ")

        for rule in rules where collapsed.contains(rule.pattern) {
            return AgentSpaceError(
                code: .execDenied,
                message: "refused: this command matches the AgentSpace refusal rule '\(rule.pattern)' (\(rule.reason)). AgentSpace's exec runs as the Space's standard user and does not perform machine-level changes.")
        }

        // First word of the command, allowing for a path prefix.
        if let first = collapsed.split(separator: " ").first {
            let name = String(first).split(separator: "/").last.map(String.init) ?? String(first)
            if refusedExecutables.contains(name) {
                return AgentSpaceError(
                    code: .execDenied,
                    message: "refused: '\(name)' is on AgentSpace's list of executables an agent session may not invoke.")
            }
        }

        // A leading `sudo` hidden behind env assignments: `FOO=1 sudo ...`.
        if collapsed.contains(" sudo ") || collapsed.hasPrefix("sudo ") {
            return AgentSpaceError(
                code: .execDenied,
                message: "refused: 'sudo' is not available inside an AgentSpace.")
        }
        return nil
    }
}

/// Workspace confinement. Plan §24 / §25 / §56 (`WorkspaceCannotEscapeAllowedPath`).
///
/// The agent session's shell is not chrooted — it cannot be, cheaply, on macOS
/// — so confinement is enforced where it actually matters: on the paths
/// AgentSpace itself hands to the worker (exec `cwd`, screenshot output, file
/// arguments), and by giving the agent account no access to the main user's
/// home in the first place.
public enum WorkspaceGuard {

    /// Resolve a path and confirm it is inside one of the allowed roots.
    ///
    /// Symlinks are resolved *before* the prefix test, which is the whole point:
    /// `/tmp/evil -> /Users/me/.ssh` must not pass because the string started
    /// with an allowed prefix.
    public static func check(
        path: String,
        allowedRoots: [String],
        requireWrite: Bool = false,
        writableRoots: Set<String> = []
    ) -> AgentSpaceError? {
        guard !allowedRoots.isEmpty else {
            return AgentSpaceError(
                code: .workspaceDenied,
                message: "this Space has no workspace or shared folders configured, so there is no path it may touch. Add one in the Space's settings.")
        }
        let resolved = resolve(path)
        guard let match = allowedRoots
            .map({ (root: $0, resolved: resolve($0)) })
            .filter({ contains(resolved, $0.resolved) })
            .max(by: { $0.resolved.count < $1.resolved.count })
        else {
            return AgentSpaceError(
                code: .workspaceDenied,
                message: "path '\(path)' (resolved: \(resolved)) is outside this Space's allowed roots: \(allowedRoots.joined(separator: ", "))")
        }
        if requireWrite {
            let writable = writableRoots.map { resolve($0) }
            let ok = writable.contains { contains(resolved, $0) }
            if !ok {
                return AgentSpaceError(
                    code: .workspaceDenied,
                    message: "path '\(path)' is inside '\(match.root)', which this Space has read-only access to. Enable Read & Write for that folder to write here.")
            }
        }
        return nil
    }

    /// Canonicalise: expand `~`, make absolute, resolve symlinks on the longest
    /// existing prefix, and strip a trailing slash. A path that does not exist
    /// yet still gets its existing prefix resolved, so the "create a file in a
    /// symlinked directory" case is covered too.
    public static func resolve(_ path: String) -> String {
        var p = (path as NSString).expandingTildeInPath
        if !p.hasPrefix("/") {
            p = FileManager.default.currentDirectoryPath + "/" + p
        }
        p = URL(fileURLWithPath: p).standardized.path
        let fm = FileManager.default
        if fm.fileExists(atPath: p) {
            return URL(fileURLWithPath: p).resolvingSymlinksInPath().standardized.path
        }
        // Walk up to the deepest existing ancestor and resolve that.
        var components = p.split(separator: "/").map(String.init)
        var suffix: [String] = []
        while !components.isEmpty {
            let candidate = "/" + components.joined(separator: "/")
            if fm.fileExists(atPath: candidate) {
                let resolved = URL(fileURLWithPath: candidate)
                    .resolvingSymlinksInPath().standardized.path
                return ([resolved] + suffix.reversed()).joined(separator: "/")
            }
            suffix.append(components.removeLast())
        }
        return p
    }

    /// Is `path` equal to or below `root`? Compares on path-component
    /// boundaries so `/a/bc` is not treated as inside `/a/b`.
    public static func contains(_ path: String, _ root: String) -> Bool {
        if path == root { return true }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix)
    }
}
