import Foundation

/// Turns a Space's workspace settings into files on disk, and into the access
/// rules the worker enforces.
///
/// Plan §14. A Space's workspace is one of three things:
///
/// - **none** — the agent works inside its own home and can reach nothing of the
///   user's.
/// - **git worktree** — a real `git worktree` cut from a repository onto an
///   `agentspace/…` branch. The agent gets its own checkout, so it can edit and
///   commit freely without ever touching the tree the user has open. This is the
///   reason the product can be used on a repository you are actively working in.
/// - **shared folders** — specific host directories, read-only unless the user
///   says otherwise.
///
/// Everything here is a pure computation except `git worktree add`, which is run
/// through `git` with an argv array. Nothing is inferred: a repository that is not
/// a repository is an error, not a directory that gets created anyway and fails
/// later somewhere confusing.
public enum WorkspacePreparer {

    /// The prefix every AgentSpace branch must carry.
    ///
    /// Enforced so an agent can never be pointed at `main` and told to commit
    /// there. The branch is visible in `git branch`, which is what makes it
    /// reviewable before it is merged.
    public static let branchPrefix = "agentspace/"

    /// The plan for one Space: what to create, and what the worker may touch.
    public struct Plan: Equatable, Sendable {
        /// Directories to create before the worker starts.
        public var directories: [String]
        /// Roots the agent may read. Empty means "nothing outside its own home".
        public var allowedRoots: [String]
        /// Roots the agent may write. Always a subset of `allowedRoots`.
        public var writableRoots: [String]
        /// The `git worktree add` invocation, if there is one.
        public var gitCommand: [String]?
        /// Human-readable summary for the UI and the log.
        public var summary: String

        /// The `space.json` the worker reads at startup.
        ///
        /// `allowedRoots` being non-empty is what turns workspace confinement on:
        /// the worker's `status.workspace.confined` reports the truth either way,
        /// and an empty list honestly means "not confined", which is what a Space
        /// with no workspace should say rather than pretending.
        public var spaceRecord: [String: Any] {
            [
                "allowedRoots": allowedRoots,
                "writableRoots": writableRoots,
            ]
        }

        public var json: JSONValue {
            .obj([
                "directories": .array(directories.map { .string($0) }),
                "allowedRoots": .array(allowedRoots.map { .string($0) }),
                "writableRoots": .array(writableRoots.map { .string($0) }),
                "gitCommand": gitCommand.map { .array($0.map { .string($0) }) } ?? .null,
                "summary": .string(summary),
            ])
        }
    }

    // MARK: - Plan

    /// Compute the plan. Pure: no filesystem writes, no processes.
    ///
    /// `workspaceDirectory` is where a worktree may live — normally
    /// `/Users/<space-account>/Workspace`, created by the helper.
    public static func plan(
        workspace: Workspace,
        sharedFolders: [SharedFolder],
        spaceID: UUID,
        workspaceDirectory: String,
        homeDirectory: String = NSHomeDirectory(),
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        isGitRepository: (String) -> Bool = { isGitRepository(at: $0) },
        resolve: (String) -> String? = { resolveExecutable($0) }
    ) -> Result<Plan, AgentSpaceError> {

        var directories: [String] = [workspaceDirectory]
        var allowed: [String] = []
        var writable: [String] = []
        var gitCommand: [String]?
        var summary: String

        switch workspace {
        case .none:
            summary = NSLocalizedString("No workspace: the agent can reach nothing of yours.", comment: "")

        case .sharedFolders:
            summary = sharedFolders.isEmpty
                ? NSLocalizedString("No shared folders configured yet.", comment: "")
                : NSLocalizedString("Shared folders only.", comment: "")

        case .gitWorktree(let repository, let branch, let path):
            // 1. The repository must exist and actually be a repository. Creating
            //    a worktree from something that is not one produces a confusing
            //    git error much later, and an agent that silently has no checkout.
            guard fileExists(repository) else {
                return .failure(AgentSpaceError(
                    code: .workspaceInvalid,
                    message: "there is nothing at \(repository)"))
            }
            guard isGitRepository(repository) else {
                return .failure(AgentSpaceError(
                    code: .workspaceInvalid,
                    message: "\(repository) is not a git repository"))
            }

            // 2. The branch must carry the prefix. An agent told to work on `main`
            //    in the user's own tree is the failure this whole mode exists to
            //    prevent, so it is refused rather than quietly renamed.
            guard branch.hasPrefix(branchPrefix) else {
                return .failure(AgentSpaceError(
                    code: .workspaceInvalid,
                    message: "the branch must start with \"\(branchPrefix)\" so it can never be your own branch; \"\(branch)\" does not"))
            }
            // `git check-ref-format` rules, reduced to the ones that matter here:
            // no spaces, no `..`, no leading/trailing slash, no control characters.
            guard isValidBranchName(branch) else {
                return .failure(AgentSpaceError(
                    code: .workspaceInvalid,
                    message: "\"\(branch)\" is not a valid git branch name"))
            }

            // 3. The worktree must live inside the Space's own workspace directory.
            //    Anywhere else and the agent would be creating directories in the
            //    user's tree, which is exactly what a worktree is meant to avoid.
            let resolved = standardize(path)
            let base = standardize(workspaceDirectory)
            guard resolved == base || resolved.hasPrefix(base + "/") else {
                return .failure(AgentSpaceError(
                    code: .workspaceInvalid,
                    message: "the worktree path must be inside \(workspaceDirectory); \(path) is not"))
            }
            guard path != repository, standardize(repository) != resolved else {
                return .failure(AgentSpaceError(
                    code: .workspaceInvalid,
                    message: "the worktree cannot be the repository itself"))
            }

            directories.append(resolved)
            // The worktree is the agent's own checkout: readable and writable.
            allowed.append(resolved)
            writable.append(resolved)
            // The repository is readable so the agent can `git log`, diff against
            // the base branch, and see what it is changing. It is *not* writable:
            // the whole point is that the user's working tree is untouched, and
            // `git worktree` already keeps its bookkeeping in .git/worktrees, which
            // git itself updates.
            allowed.append(standardize(repository))

            // Absolute, and checked: a Mac without the Command Line Tools has no
            // git, and "worktree add failed" would send the user looking in the
            // wrong place. The hint tells the GUI to offer the installer as a
            // button — the user never types the command.
            guard let git = resolve("git") else {
                return .failure(AgentSpaceError(
                    code: .workspaceInvalid,
                    message: "git is not installed, so a worktree workspace cannot be created. Install the Xcode Command Line Tools, or choose a different workspace kind.",
                    recoveryHint: .installCommandLineTools))
            }
            gitCommand = [
                git, "-C", repository, "worktree", "add",
                "-B", branch, resolved,
            ]
            summary = String(format: NSLocalizedString("Git worktree: %@ in %@, read from %@.", comment: ""),
                             branch, resolved, repository)
        }

        // Shared folders apply whatever the workspace kind is: an agent with a
        // worktree can also be given a test-data directory.
        for folder in sharedFolders {
            guard folder.path.hasPrefix("/") else {
                return .failure(AgentSpaceError(
                    code: .workspaceInvalid,
                    message: "shared folder \(folder.path) is not an absolute path"))
            }
            guard !folder.path.contains("..") else {
                return .failure(AgentSpaceError(
                    code: .workspaceInvalid,
                    message: "shared folder \(folder.path) must not contain \"..\""))
            }
            let resolved = standardize(folder.path)
            guard fileExists(resolved) else {
                return .failure(AgentSpaceError(
                    code: .workspaceInvalid,
                    message: "there is nothing at \(resolved)"))
            }
            // Refuse to share something whose loss would be catastrophic, and
            // refuse the AgentSpace user's own home (which would be circular).
            guard !isDangerousRoot(resolved) else {
                return .failure(AgentSpaceError(
                    code: .workspaceInvalid,
                    message: "refusing to share \(resolved): sharing a system directory with an agent is never what was meant"))
            }
            guard !isSensitiveHomePath(resolved, homeDirectory: homeDirectory) else {
                return .failure(AgentSpaceError(
                    code: .workspaceInvalid,
                    message: "refusing to share \(resolved): the home directory, your Library and Keychains, and ~/.ssh are never shared with an agent. Share the specific project or data folder instead."))
            }
            allowed.append(resolved)
            if folder.access == .readWrite { writable.append(resolved) }
        }

        // Deduplicate while keeping order, so the plan is stable and diffable.
        var seen = Set<String>()
        let allowedUnique = allowed.filter { seen.insert($0).inserted }
        let writableUnique = Array(Set(writable)).sorted()

        return .success(Plan(
            directories: Array(Set(directories)).sorted(),
            allowedRoots: allowedUnique,
            writableRoots: writableUnique,
            gitCommand: gitCommand,
            summary: summary))
    }

    // MARK: - Execution

    /// Run the plan. Creates directories, then the worktree.
    ///
    /// The worktree is created **last**, after the directories exist, because
    /// `git worktree add` requires the parent to be there. Doing it in the other
    /// order produces "cannot mkdir" for a reason that looks unrelated.
    public static func apply(
        _ plan: Plan,
        runCommand: ([String]) -> (exitCode: Int32, output: String) = run
    ) -> Result<Void, AgentSpaceError> {
        for directory in plan.directories {
            do {
                try FileManager.default.createDirectory(
                    atPath: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
            } catch {
                return .failure(AgentSpaceError(
                    code: .workspaceInvalid,
                    message: "could not create \(directory): \(error.localizedDescription)"))
            }
        }

        guard let command = plan.gitCommand else { return .success(()) }

        let result = runCommand(command)
        guard result.exitCode == 0 else {
            // The exit code is included because git's own message is sometimes
            // empty (it writes to stderr, which is captured) and sometimes says
            // "already exists" for a branch, which is the common second run.
            let trimmed = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(AgentSpaceError(
                code: .workspaceInvalid,
                message: "git worktree failed (exit \(result.exitCode)): \(trimmed.isEmpty ? command.joined(separator: " ") : trimmed)"))
        }
        return .success(())
    }

    // MARK: - Helpers

    public static func standardize(_ path: String) -> String {
        ((path as NSString).expandingTildeInPath as NSString).standardizingPath
    }

    static func isValidBranchName(_ branch: String) -> Bool {
        guard !branch.isEmpty, branch.count <= 200 else { return false }
        if branch.hasPrefix("/") || branch.hasSuffix("/") || branch.hasSuffix(".") { return false }
        if branch.contains("..") || branch.contains("//") || branch.contains("@{") { return false }
        let forbidden = CharacterSet(charactersIn: " ~^:?*[\\\u{7F}")
        for scalar in branch.unicodeScalars {
            if forbidden.contains(scalar) { return false }
            if scalar.value < 0x20 { return false }
        }
        return true
    }

    /// Home locations that must never be shared with an agent, even
    /// explicitly (§25's "禁止默认开放" list, hardened to "never"): the home
    /// itself, the Library tree that holds the user's Keychains, and `~/.ssh`.
    /// Desktop, Documents and Downloads stay shareable — §25's own UI example
    /// shares a folder under Documents — because a user picking one of those
    /// is expressing a specific, bounded intent.
    static func isSensitiveHomePath(_ path: String, homeDirectory: String) -> Bool {
        let sensitive = [
            homeDirectory,
            homeDirectory + "/Library",
            homeDirectory + "/Library/Keychains",
            homeDirectory + "/.ssh",
        ]
        return sensitive.contains(path)
    }

    /// Directories whose sharing would be a mistake no matter what the user meant.
    static func isDangerousRoot(_ path: String) -> Bool {
        let dangerous: Set<String> = [
            "/", "/System", "/Library", "/usr", "/bin", "/sbin", "/etc",
            "/var", "/private", "/private/etc", "/private/var", "/Applications",
            "/Users", "/Volumes", "/dev", "/cores", "/Network",
        ]
        return dangerous.contains(path)
    }

    public static func isGitRepository(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        // A `.git` entry is enough for `git worktree add` on a normal clone, and
        // covers both a directory (a normal clone) and a file (a worktree or a
        // submodule). A bare repository has neither in the same shape, so it is
        // asked directly rather than guessed at.
        if FileManager.default.fileExists(atPath: path + "/.git") { return true }
        let result = run(["/usr/bin/git", "-C", path, "rev-parse", "--git-dir"])
        return result.exitCode == 0
    }

    /// Resolve an executable name the way a shell would.
    ///
    /// `Process.executableURL` does **not** search `PATH`: a bare name is resolved
    /// relative to the working directory, so `git` becomes `./git` and fails with
    /// "no such file". That failure is easy to miss because the error message names
    /// git, not the resolution. Doing the lookup explicitly also means the failure
    /// says which name could not be found.
    public static func resolveExecutable(_ name: String) -> String? {
        if name.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }
        let path = ProcessInfo.processInfo.environment["PATH"]
            ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in path.split(separator: ":") {
            let candidate = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        // git on macOS lives here through the Command Line Tools shim, and a
        // stripped PATH would otherwise make an installed git look absent.
        for fallback in ["/usr/bin/\(name)", "/usr/local/bin/\(name)", "/opt/homebrew/bin/\(name)"] {
            if FileManager.default.isExecutableFile(atPath: fallback) { return fallback }
        }
        return nil
    }

    public static func run(_ arguments: [String]) -> (exitCode: Int32, output: String) {
        guard let name = arguments.first else { return (-1, "no executable") }
        guard let executable = resolveExecutable(name) else {
            return (-1, "could not find \(name) on PATH")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(arguments.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        // A git command can prompt (for credentials, on a remote), which would
        // hang the app forever with a modal nobody can see.
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_ASKPASS"] = "/usr/bin/true"
        process.environment = environment
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
