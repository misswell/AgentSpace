import Foundation

/// Where a Space's runtime files live. Plan §20.
///
/// Layout:
/// ```
/// /Library/Application Support/AgentSpace/
///   Runtime/
///     <space-uuid>/
///       worker.sock     the unix socket the worker listens on
///       frame.sock      the binary capture channel
///       input.sock      the persistent binary input channel
///       worker.pid      pid of the listening worker
///       token           the 256-bit session secret, mode 0600
///       status.json     last known status, written by the worker
///       worker.lock     flock'd by bind() so a second worker fails fast
///       worker.out.log  the worker's stdout, via the LaunchAgent
///       worker.err.log  the worker's stderr, via the LaunchAgent
///       space.json      written by the privileged helper (roots, main user)
///       screenshots/    where captures land by default
///   Spaces/
///     index.json        the Space registry (main user's view)
///   Logs/
/// ```
///
/// Chosen deliberately over a `localhost` HTTP port: a unix socket cannot be
/// reached from off the machine, and its directory ACL is the second lock
/// behind the token.
public struct RuntimePaths: Sendable {
    /// Root-owned installation state. The helper creates it; only the per-account
    /// runtime receives a two-user ACL for the controller and attached account.
    public static let root = "/Library/Application Support/AgentSpace"
    /// V2 location, read only as an upgrade source by `SpaceRegistry`.
    public static let legacyRoot = "/Users/Shared/.AgentSpace"

    public let spaceID: UUID
    /// The `<...>/.AgentSpace` root this instance resolves against.
    public let root: String
    /// Optional explicit socket path, used by tests and by `--socket`.
    public let explicitSocketPath: String?

    public init(spaceID: UUID, root: String = RuntimePaths.root, socketPath: String? = nil) {
        self.spaceID = spaceID
        self.root = root
        self.explicitSocketPath = socketPath
    }

    /// The default installation's runtime root. Present as a static so code
    /// that only wants the *conventional* path (help text, diagnostics) does not
    /// have to invent a throwaway UUID to ask.
    public static var defaultRuntimeRoot: String { root + "/Runtime" }

    public var runtimeRoot: String { root + "/Runtime" }
    public var spacesRoot: String { root + "/Spaces" }
    public var logsRoot: String { root + "/Logs" }
    public var registryPath: String { spacesRoot + "/index.json" }

    public var directory: String {
        runtimeRoot + "/" + spaceID.uuidString
    }

    public var socketPath: String { explicitSocketPath ?? (directory + "/worker.sock") }
    public var frameSocketPath: String { directory + "/frame.sock" }
    /// The persistent binary input channel. A separate endpoint from
    /// `worker.sock` on purpose: the RPC socket answers one request per
    /// connection and is the right shape for a CLI or an agent, while a hand
    /// moving a mouse is a state that must not pay a connect, an encode and a
    /// reply per event.
    public var inputSocketPath: String { directory + "/input.sock" }
    public var pidPath: String { directory + "/worker.pid" }
    public var tokenPath: String { directory + "/token" }
    public var statusPath: String { directory + "/status.json" }
    /// The LaunchAgent routes the worker's stdout/stderr here (HelperProtocol's
    /// plist template), which is why they live in the runtime directory itself.
    public var workerOutLogPath: String { directory + "/worker.out.log" }
    public var workerErrLogPath: String { directory + "/worker.err.log" }

    /// `sockaddr_un.sun_path` is 104 bytes on Darwin including the terminator.
    /// Checked rather than assumed, because an over-long path truncates
    /// silently and would produce a socket nobody can find.
    public static let maxSocketPathBytes = 103

    public static func socketPathFits(_ path: String) -> Bool {
        path.utf8.count <= maxSocketPathBytes
    }

    public var socketPathFits: Bool { RuntimePaths.socketPathFits(socketPath) }
    public var frameSocketPathFits: Bool { RuntimePaths.socketPathFits(frameSocketPath) }
    public var inputSocketPathFits: Bool { RuntimePaths.socketPathFits(inputSocketPath) }

    // MARK: Directory preparation

    /// Create the runtime directory tree with the ACL the plan requires:
    /// **main user, agent user and root only**.
    ///
    /// Returns an error rather than throwing so the caller can turn it into a
    /// typed RPC failure.
    public func prepare(mainUser: String, agentUser: String) -> AgentSpaceError? {
        let fm = FileManager.default
        for dir in [root, runtimeRoot, spacesRoot, logsRoot, directory] {
            do {
                try fm.createDirectory(
                    atPath: dir,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o755])
            } catch {
                return AgentSpaceError(
                    code: .internalError,
                    message: "could not create \(dir): \(error.localizedDescription)")
            }
        }
        // 0700 on the per-Space directory: the ACL below widens it to exactly
        // two named users, and nothing else can traverse it.
        do {
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory)
        } catch {
            return AgentSpaceError(
                code: .internalError,
                message: "could not restrict \(directory): \(error.localizedDescription)")
        }
        return applyACL(mainUser: mainUser, agentUser: agentUser)
    }

    /// Apply the two-user ACL to the runtime directory.
    ///
    /// `chmod +a` is invoked directly rather than through a shell: the arguments
    /// are fixed and the only variables are two account names that the helper
    /// has already validated against the directory service.
    public func applyACL(mainUser: String, agentUser: String) -> AgentSpaceError? {
        let entries = [
            "user:\(mainUser) allow read,write,execute,delete,append,readattr,writeattr,readextattr,writeextattr,readsecurity,file_inherit,directory_inherit",
            "user:\(agentUser) allow read,write,execute,delete,append,readattr,writeattr,readextattr,writeextattr,readsecurity,file_inherit,directory_inherit",
        ]
        for entry in entries {
            let status = ACLRunner.apply(entry, to: directory)
            if status != 0 {
                return AgentSpaceError(
                    code: .internalError,
                    message: "chmod +a '\(entry)' on \(directory) exited \(status)")
            }
        }
        return nil
    }
}

/// Runs `/bin/chmod +a`. Isolated so tests can substitute a recorder, and so
/// the one place a subprocess is spawned with a caller-influenced account name
/// is easy to audit.
public enum ACLRunner {
    /// Overridable for tests.
    public static var runner: (String, String) -> Int32 = { entry, path in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+a", entry, path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    /// Public because the worker applies a per-socket ACL on top of the
    /// directory ACL the helper already made.
    public static func apply(_ entry: String, to path: String) -> Int32 { runner(entry, path) }
}
