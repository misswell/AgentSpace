import Foundation

/// The privileged helper's typed interface — plan §6.
///
/// There is deliberately **no** `runShell(command)` and no `executeAnything`.
/// The helper is the only root component in AgentSpace, so the worst a
/// compromised caller can do must be the worst thing on this list, and the list
/// is short and enumerable. A generic escape hatch would turn any
/// code-execution bug anywhere in the app into root.
///
/// Every operation is a value type with named, validated fields. Nothing here is
/// ever interpolated into a command string: `HelperCommand` builds argv arrays
/// and the daemon spawns with `posix_spawn`, so there is no quoting layer for an
/// attacker to escape.
public enum HelperOperation: String, Codable, Sendable, CaseIterable {
    case createUser
    case deleteUser
    case installWorker
    case removeWorker
    case prepareRuntimeDirectory
    case removeRuntimeDirectory
    case startWorker
    case stopWorker
    case logoutSession
    case sessionInfo
    case helperStatus
}

// MARK: - Requests

/// One helper request. `id` correlates the reply.
public struct HelperRequest: Codable, Equatable, Sendable {
    public var id: String
    public var operation: HelperOperation
    public var spaceID: UUID?
    public var username: String?
    public var displayName: String?
    /// Only ever a password AgentSpace generated itself. Never a user's.
    public var password: String?
    /// For `deleteUser`: whether to remove the home directory as well.
    public var removeHome: Bool?
    /// For `prepareRuntimeDirectory`: the main user who needs access.
    public var mainUser: String?
    /// For `installWorker`: the space's runtime root.
    public var runtimeRoot: String?
    /// For teardown: the attached account's recorded uid. It lets V3 clean up
    /// an attachment even if that account was later removed externally.
    public var uid: uid_t?

    public init(
        id: String = UUID().uuidString,
        operation: HelperOperation,
        spaceID: UUID? = nil,
        username: String? = nil,
        displayName: String? = nil,
        password: String? = nil,
        removeHome: Bool? = nil,
        mainUser: String? = nil,
        runtimeRoot: String? = nil,
        uid: uid_t? = nil
    ) {
        self.id = id
        self.operation = operation
        self.spaceID = spaceID
        self.username = username
        self.displayName = displayName
        self.password = password
        self.removeHome = removeHome
        self.mainUser = mainUser
        self.runtimeRoot = runtimeRoot
        self.uid = uid
    }
}

public struct HelperResponse: Codable, Equatable, Sendable {
    public var id: String
    public var ok: Bool
    public var error: AgentSpaceError?
    /// Operation-specific payload. Kept as JSON so the protocol can grow without
    /// every version of the helper understanding every field.
    public var result: JSONValue?

    public init(id: String, result: JSONValue) {
        self.id = id; self.ok = true; self.error = nil; self.result = result
    }
    public init(id: String, error: AgentSpaceError) {
        self.id = id; self.ok = false; self.error = error; self.result = nil
    }
}

extension HelperResponse {
    /// The accounts a `helperStatus` reply says are on this machine, or `nil`
    /// when the reply is not a status payload. Its readers check an after-state
    /// rather than believing one operation's verdict, which is what validation
    /// §269 learned when every removal command exited 0 while the account stayed.
    public var reportedAccounts: [String]? {
        guard case .object(let fields)? = result,
              case .array(let values)? = fields["spaceAccounts"] else { return nil }
        return values.compactMap { value in
            if case .string(let name) = value { return name }
            return nil
        }
    }
}

// MARK: - Validation

/// Every rule the helper applies before it touches anything.
///
/// This is the security boundary, so it lives in Core rather than in the daemon:
/// it is pure, it needs no root to run, and it can therefore be attacked by tests
/// on every machine instead of only on one where the helper happens to be
/// installed. `HelperValidationTests` does exactly that, adversarially.
///
/// The daemon re-runs all of this itself. Nothing is trusted because the client
/// already checked it — the client is the part that might be compromised.
public enum HelperValidation {

    /// Legacy V1/V2 accounts are `_agentspace_` plus six lowercase hex characters.
    ///
    /// A *fixed* prefix and a *closed* character set is the whole defence here.
    /// It means an attacker cannot ask for an existing account (`root`,
    /// `_mbsetupuser`, the human's own), cannot smuggle a shell metacharacter,
    /// cannot traverse with `..`, cannot inject a second argv element, and cannot
    /// use a leading `-` to be read as a flag by a system utility. All of
    /// those are the same rule, which is the point: one rule that is obviously
    /// complete rather than five that each cover a case somebody thought of.
    public static let accountPrefix = "_agentspace_"
    private static let suffixLength = 6
    private static let allowedSuffix = Set("0123456789abcdef")

    /// Accounts the helper must never touch, whatever it is asked.
    ///
    /// Even a correct-looking `_agentspace_…` name is refused if it is one of
    /// these, so a future change to the naming scheme cannot quietly make
    /// `root` deletable.
    public static let protectedAccounts: Set<String> = [
        "root", "daemon", "nobody", "sysadmin", "_mbsetupuser", "_unknown",
        "_assetcache", "_windowserver", "_securityagent", "_spotlight",
        "_lp", "_uucp", "_taskgated", "_appleevents", "_locationd",
    ]

    public static func generateAccountName() -> String {
        let alphabet = Array("0123456789abcdef")
        return accountPrefix + String((0..<suffixLength).map { _ in alphabet.randomElement()! })
    }

    /// Is this a legacy AgentSpace-generated name? Used only for compatibility;
    /// V3 never creates, modifies or deletes the account.
    public static func isAgentSpaceAccount(_ username: String) -> Bool {
        guard username.hasPrefix(accountPrefix) else { return false }
        let suffix = username.dropFirst(accountPrefix.count)
        guard suffix.count == suffixLength else { return false }
        guard suffix.allSatisfy({ allowedSuffix.contains($0) }) else { return false }
        return !protectedAccounts.contains(username)
    }

    /// A display name is a label shown in AgentSpace. It is free text, so it gets
    /// the tight treatment: bounded length, no
    /// newlines (which would let it forge a log line), no control characters, and
    /// — importantly — it is never passed to a privileged system command.
    public static func validateDisplayName(_ name: String) -> AgentSpaceError? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AgentSpaceError(code: .helperRejected, message: "the display name is empty")
        }
        guard trimmed.count <= 64 else {
            return AgentSpaceError(
                code: .helperRejected,
                message: "the display name is \(trimmed.count) characters; the maximum is 64")
        }
        // Scalar-level, not Character-level: combining sequences are fine, control
        // characters and line separators are not.
        for scalar in trimmed.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F {
                return AgentSpaceError(
                    code: .helperRejected,
                    message: "the display name contains a control character (U+\(String(scalar.value, radix: 16, uppercase: true))), which could forge a log line")
            }
            if scalar.properties.generalCategory == .lineSeparator
                || scalar.properties.generalCategory == .paragraphSeparator {
                return AgentSpaceError(
                    code: .helperRejected,
                    message: "the display name contains a line separator")
            }
        }
        return nil
    }

    /// Is this a path that could be a Space's runtime root?
    public static func validateRuntimeRoot(_ root: String) -> AgentSpaceError? {
        guard root.hasPrefix("/") else {
            return AgentSpaceError(code: .helperRejected, message: "the runtime root must be an absolute path")
        }
        guard !root.contains("..") else {
            return AgentSpaceError(code: .helperRejected, message: "the runtime root must not contain '..'")
        }
        guard root == RuntimePaths.root || root == RuntimePaths.legacyRoot else {
            return AgentSpaceError(
                code: .helperRejected,
                message: "the runtime root must be an exact AgentSpace runtime root, not \(root)")
        }
        return nil
    }

    /// The main user who is granted access to a Space's runtime directory.
    ///
    /// Must be a real, non-system, non-AgentSpace account: granting the wrong
    /// principal access to a socket that carries a live session token would hand
    /// over the agent.
    public static func validateMainUser(_ user: String, existingAccounts: Set<String>) -> AgentSpaceError? {
        guard !user.isEmpty, !user.hasPrefix("_"), user != "root" else {
            return AgentSpaceError(
                code: .helperRejected,
                message: "\(user) is not a normal user account, so it cannot be the main user")
        }
        guard !user.contains("/"), !user.contains(".."), !user.hasPrefix("-") else {
            return AgentSpaceError(code: .helperRejected, message: "\(user) is not a plain account name")
        }
        guard existingAccounts.contains(user) else {
            return AgentSpaceError(
                code: .helperRejected,
                message: "there is no local account named \(user), so there is nobody to grant access to")
        }
        guard !isAgentSpaceAccount(user) else {
            return AgentSpaceError(
                code: .helperRejected,
                message: "\(user) is an AgentSpace account; the main user must be a human's account")
        }
        return nil
    }

    /// Validate an existing account selected for attachment. Legacy
    /// `_agentspace_<hex>` users remain accepted so existing registries continue
    /// to work, while new attachments must be ordinary, non-current users.
    public static func validateAttachedUser(
        _ username: String,
        mainUser: String?,
        existingAccounts: Set<String>
    ) -> AgentSpaceError? {
        guard existingAccounts.contains(username) else {
            return AgentSpaceError(code: .helperRejected, message: "there is no account named \(username)")
        }
        if isAgentSpaceAccount(username) { return nil }
        guard !username.isEmpty,
              !username.hasPrefix("_"),
              !username.hasPrefix("-"),
              !username.contains("/"),
              !username.contains(".."),
              !protectedAccounts.contains(username) else {
            return AgentSpaceError(code: .helperRejected, message: "\(username) is not an attachable local account")
        }
        guard let mainUser else {
            return AgentSpaceError(code: .helperRejected, message: "attaching an existing account requires the current main user")
        }
        guard username != mainUser else {
            return AgentSpaceError(code: .helperRejected, message: "refusing to attach the current user's own account")
        }
        return validateMainUser(mainUser, existingAccounts: existingAccounts)
    }

    /// Teardown must remain possible after the user was deleted or promoted in
    /// System Settings. In that case the helper additionally verifies its
    /// root-owned attachment record before touching anything; this layer only
    /// validates the closed request shape.
    private static func validateTeardownUser(
        _ request: HelperRequest,
        existingAccounts: Set<String>
    ) -> AgentSpaceError? {
        guard let username = request.username else {
            return AgentSpaceError(code: .helperRejected, message: "teardown requires the attached account")
        }
        if existingAccounts.contains(username) {
            return validateAttachedUser(username, mainUser: request.mainUser, existingAccounts: existingAccounts)
        }
        guard !username.isEmpty, !username.hasPrefix("-"), !username.contains("/"),
              !username.contains(".."), !protectedAccounts.contains(username),
              let uid = request.uid, uid >= 500 else {
            return AgentSpaceError(code: .helperRejected, message: "the detached account identity is invalid")
        }
        guard let mainUser = request.mainUser else {
            return AgentSpaceError(code: .helperRejected, message: "teardown requires the main user")
        }
        return validateMainUser(mainUser, existingAccounts: existingAccounts)
    }

    /// A complete check of one request, with no side effects.
    ///
    /// Returns the first problem found. `existingAccounts` is injected so this can
    /// be tested without creating accounts, and so the daemon can pass the real
    /// list it just read.
    public static func validate(
        _ request: HelperRequest,
        existingAccounts: Set<String>
    ) -> AgentSpaceError? {

        switch request.operation {
        case .helperStatus:
            // The one operation that needs no arguments. It exists so the app can
            // ask "are you there and what version are you?" before offering a
            // button that needs root.
            return nil

        case .createUser:
            return AgentSpaceError(
                code: .helperRejected,
                message: "createUser is unavailable: AgentSpace connects existing macOS accounts and never creates users")

        case .deleteUser:
            return AgentSpaceError(
                code: .helperRejected,
                message: "deleteUser is unavailable: disconnecting AgentSpace never deletes a macOS account or home directory")

        case .installWorker:
            guard let username = request.username else {
                return AgentSpaceError(code: .helperRejected, message: "\(request.operation.rawValue) requires a username")
            }
            if let problem = validateAttachedUser(username, mainUser: request.mainUser, existingAccounts: existingAccounts) { return problem }
            guard let root = request.runtimeRoot else {
                return AgentSpaceError(code: .helperRejected, message: "installWorker requires the runtime root")
            }
            if let problem = validateRuntimeRoot(root) { return problem }
            return nil

        case .removeWorker:
            if let problem = validateTeardownUser(request, existingAccounts: existingAccounts) { return problem }
            guard let root = request.runtimeRoot else {
                return AgentSpaceError(code: .helperRejected, message: "removeWorker requires the runtime root")
            }
            return validateRuntimeRoot(root)

        case .prepareRuntimeDirectory:
            guard let spaceID = request.spaceID else {
                return AgentSpaceError(code: .helperRejected, message: "\(request.operation.rawValue) requires a space ID")
            }
            _ = spaceID  // A UUID is validated by being one; there is nothing to escape.
            guard let username = request.username else {
                return AgentSpaceError(code: .helperRejected, message: "\(request.operation.rawValue) requires the attached account")
            }
            if let problem = validateAttachedUser(username, mainUser: request.mainUser, existingAccounts: existingAccounts) { return problem }
            guard let mainUser = request.mainUser else {
                return AgentSpaceError(code: .helperRejected, message: "\(request.operation.rawValue) requires the main user")
            }
            if let problem = validateMainUser(mainUser, existingAccounts: existingAccounts) { return problem }
            if let root = request.runtimeRoot, let problem = validateRuntimeRoot(root) { return problem }
            return nil


        case .removeRuntimeDirectory:
            guard request.spaceID != nil else {
                return AgentSpaceError(code: .helperRejected, message: "removeRuntimeDirectory requires a space ID")
            }
            if let problem = validateTeardownUser(request, existingAccounts: existingAccounts) { return problem }
            guard let root = request.runtimeRoot else {
                return AgentSpaceError(code: .helperRejected, message: "removeRuntimeDirectory requires the runtime root")
            }
            return validateRuntimeRoot(root)

        case .startWorker:
            guard let spaceID = request.spaceID else {
                return AgentSpaceError(code: .helperRejected, message: "\(request.operation.rawValue) requires a space ID")
            }
            _ = spaceID
            guard let username = request.username else {
                return AgentSpaceError(code: .helperRejected, message: "\(request.operation.rawValue) requires the attached account")
            }
            if let problem = validateAttachedUser(username, mainUser: request.mainUser, existingAccounts: existingAccounts) { return problem }
            return nil


        case .stopWorker:
            guard request.spaceID != nil else {
                return AgentSpaceError(code: .helperRejected, message: "stopWorker requires a space ID")
            }
            if let problem = validateTeardownUser(request, existingAccounts: existingAccounts) { return problem }
            guard let root = request.runtimeRoot else {
                return AgentSpaceError(code: .helperRejected, message: "stopWorker requires the runtime root")
            }
            return validateRuntimeRoot(root)

        case .logoutSession:
            return AgentSpaceError(
                code: .helperRejected,
                message: "logoutSession is unavailable in V3: AgentSpace manages its worker and runtime, not the macOS login session")

        case .sessionInfo:
            guard let username = request.username else {
                return AgentSpaceError(code: .helperRejected, message: "sessionInfo requires the attached account")
            }
            return validateAttachedUser(username, mainUser: request.mainUser, existingAccounts: existingAccounts)
        }
    }
}

// MARK: - Command construction

/// Turns a validated request into an argument vector.
///
/// Every command is an **array**, and the daemon spawns it with `posix_spawn`.
/// There is no shell anywhere in the helper, so there is no quoting layer, no
/// globbing, no `$( )` and no argument splitting. A display name containing a
/// space or a quote is simply one argv element, which is what it should always
/// have been.
///
/// Separated from the daemon so the exact argv can be asserted in tests without
/// root: a security review of "what can this actually run?" should be readable
/// from one file, and checkable by a test that runs everywhere.
public enum HelperCommand {

    public static let dscl = "/usr/bin/dscl"
    public static let launchctl = "/bin/launchctl"
    public static let chmod = "/bin/chmod"
    public static let chown = "/usr/sbin/chown"
    public static let mkdir = "/bin/mkdir"
    public static let workerInstallRoot = "/Library/Application Support/AgentSpace/Worker/versions"
    public static let workerExecutionRoot = "/Library/Application Support/AgentSpace/Worker/active"
    public static let workerExecutionPath = "\(workerExecutionRoot)/agentspace-worker"
    public static let workerLaunchAgentRoot = "/Library/Application Support/AgentSpace/Worker/LaunchAgents"

    /// Root-owned, versioned worker location. The version is a build constant,
    /// never request data; keeping it in the path lets an updated helper install
    /// atomically without a user-writable `current` symlink.
    public static func workerInstallPath(version: String) -> String {
        precondition(!version.isEmpty && version.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "." || $0 == "-"
        })
        return "\(workerInstallRoot)/\(version)/agentspace-worker"
    }

    public static func workerLaunchAgent(
        spaceID: UUID,
        username: String,
        workerPath: String,
        runtimeRoot: String
    ) -> String {
        let label = workerLabel(spaceID: spaceID)
        // The log paths come from RuntimePaths so there is one source of
        // truth; a hand-written copy here is how a phantom worker.log almost
        // shipped (§114a).
        let paths = RuntimePaths(spaceID: spaceID, root: runtimeRoot)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(workerPath)</string>
                <string>--space-id</string>
                <string>\(spaceID.uuidString)</string>
                <string>--runtime-dir</string>
                <string>\(runtimeRoot)</string>
                <string>--quiet</string>
            </array>
            <key>LimitLoadToSessionType</key>
            <string>Aqua</string>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key>
                <false/>
            </dict>
            <!-- The worker refuses to run as root (exit 77); this is belt and
                 braces so a future edit cannot accidentally raise it. -->
            <key>UserName</key>
            <string>\(username)</string>
            <key>EnvironmentVariables</key>
            <dict>
                <key>AGENTSPACE_ROOT</key>
                <string>\(runtimeRoot)</string>
            </dict>
            <key>StandardOutPath</key>
            <string>\(paths.workerOutLogPath)</string>
            <key>StandardErrorPath</key>
            <string>\(paths.workerErrLogPath)</string>
            <key>ProcessType</key>
            <string>Interactive</string>
        </dict>
        </plist>
        """
    }

    public static func workerLabel(spaceID: UUID) -> String {
        "\(BundleIdentifiers.worker).\(spaceID.uuidString)"
    }

    /// Reloads a worker LaunchAgent from its on-disk plist before starting it.
    ///
    /// `launchctl kickstart -k` only restarts the configuration already cached
    /// by launchd. After an AgentSpace update that cached configuration can
    /// still point at an older versioned worker path, even though installWorker
    /// has written a new plist. Booting out and bootstrapping the plist is what
    /// makes the newly installed worker version authoritative.
    public struct WorkerReloadCommands: Equatable {
        public let bootout: [String]
        public let bootstrap: [String]
        public let kickstart: [String]
    }

    public static func workerReloadCommands(
        uid: uid_t,
        spaceID: UUID,
        plistPath: String
    ) -> WorkerReloadCommands {
        let label = workerLabel(spaceID: spaceID)
        let userDomain = "gui/\(uid)"
        let serviceDomain = "\(userDomain)/\(label)"
        return WorkerReloadCommands(
            bootout: [launchctl, "bootout", serviceDomain],
            bootstrap: [launchctl, "bootstrap", userDomain, plistPath],
            kickstart: [launchctl, "kickstart", "-k", serviceDomain])
    }

    public static func canonicalWorkerLaunchAgentPath(spaceID: UUID) -> String {
        "\(workerLaunchAgentRoot)/\(workerLabel(spaceID: spaceID)).plist"
    }

    /// The exact path a worker LaunchAgent is written to inside a Space's home.
    ///
    /// Derived from the validated account name rather than from anything in the
    /// request, so there is no path an attacker can redirect.
    public static func launchAgentPath(username: String) -> String {
        "/Users/\(username)/Library/LaunchAgents"
    }

    public static func runtimeDirectory(_ request: HelperRequest) -> String? {
        guard let spaceID = request.spaceID, let root = request.runtimeRoot else { return nil }
        return "\(root)/Runtime/\(spaceID.uuidString)"
    }
}
