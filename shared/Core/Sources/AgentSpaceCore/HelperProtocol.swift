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
    /// For `logoutSession`: the agent account's uid, cross-checked against the
    /// username's real passwd entry before anything is torn down.
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

    /// AgentAgent accounts are `_agentspace_` plus six lowercase hex characters.
    ///
    /// A *fixed* prefix and a *closed* character set is the whole defence here.
    /// It means an attacker cannot ask for an existing account (`root`,
    /// `_mbsetupuser`, the human's own), cannot smuggle a shell metacharacter,
    /// cannot traverse with `..`, cannot inject a second argv element, and cannot
    /// use a leading `-` to be read as a flag by `dscl` or `sysadminctl`. All of
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

    /// Is this a name the helper created, and therefore may modify or delete?
    public static func isAgentSpaceAccount(_ username: String) -> Bool {
        guard username.hasPrefix(accountPrefix) else { return false }
        let suffix = username.dropFirst(accountPrefix.count)
        guard suffix.count == suffixLength else { return false }
        guard suffix.allSatisfy({ allowedSuffix.contains($0) }) else { return false }
        return !protectedAccounts.contains(username)
    }

    /// A display name is a label shown in the login window. It is the one free-text
    /// field in the protocol, so it gets the tight treatment: bounded length, no
    /// newlines (which would let it forge a log line), no control characters, and
    /// — importantly — it is *never* passed as an argv element to a command whose
    /// meaning depends on it. It only ever reaches `sysadminctl -fullName`, and
    /// `HelperCommand` passes it as a single argv element with no shell involved.
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

    /// A password AgentSpace generated. Rejected if it contains anything that
    /// would be awkward in a command line or a log: the helper passes it to
    /// `sysadminctl` as an argv element, and although that is not a shell, keeping
    /// the character set closed means a password can never be misread as a flag.
    public static let passwordLength = 32

    public static func validatePassword(_ password: String) -> AgentSpaceError? {
        guard password.count == passwordLength else {
            return AgentSpaceError(
                code: .helperRejected,
                message: "the generated password must be exactly \(passwordLength) characters")
        }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        guard password.allSatisfy({ allowed.contains($0) }) else {
            return AgentSpaceError(
                code: .helperRejected,
                message: "the generated password must be alphanumeric so it can never be read as a command-line flag")
        }
        return nil
    }

    public static func generatePassword() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        // Rejection-free: 62 does not divide 256, so this is very slightly biased
        // toward the first 8 characters. That is irrelevant for a per-Space login
        // password that is stored in the Keychain and never typed by a human, and
        // it is cheaper than the alternative. The *session token* — the thing that
        // actually guards the socket — uses SecRandomCopyBytes and is unbiased.
        return String((0..<passwordLength).map { _ in alphabet.randomElement()! })
    }

    /// Is this a path that could be a Space's runtime root?
    public static func validateRuntimeRoot(_ root: String) -> AgentSpaceError? {
        guard root.hasPrefix("/") else {
            return AgentSpaceError(code: .helperRejected, message: "the runtime root must be an absolute path")
        }
        guard !root.contains("..") else {
            return AgentSpaceError(code: .helperRejected, message: "the runtime root must not contain '..'")
        }
        guard root.hasPrefix("/Users/Shared/") || root.hasPrefix("/tmp/") || root.hasPrefix("/private/tmp/") else {
            return AgentSpaceError(
                code: .helperRejected,
                message: "the runtime root must live under /Users/Shared or /tmp, not \(root), so that an agent cannot be pointed at a system directory")
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
            guard let username = request.username else {
                return AgentSpaceError(code: .helperRejected, message: "createUser requires a username")
            }
            guard isAgentSpaceAccount(username) else {
                return AgentSpaceError(
                    code: .helperRejected,
                    message: "\(username) is not an AgentSpace account name; the helper only creates accounts matching \(accountPrefix)<6 hex>")
            }
            guard !existingAccounts.contains(username) else {
                return AgentSpaceError(
                    code: .helperRejected,
                    message: "an account named \(username) already exists")
            }
            if let displayName = request.displayName, let problem = validateDisplayName(displayName) {
                return problem
            }
            guard let password = request.password else {
                return AgentSpaceError(code: .helperRejected, message: "createUser requires a generated password")
            }
            if let problem = validatePassword(password) { return problem }
            return nil

        case .deleteUser:
            guard let username = request.username else {
                return AgentSpaceError(code: .helperRejected, message: "deleteUser requires a username")
            }
            // The single most important check in this file. Everything else being
            // right does not matter if this one is wrong.
            guard isAgentSpaceAccount(username) else {
                return AgentSpaceError(
                    code: .helperRejected,
                    message: "refusing to delete \(username): the helper only ever deletes accounts it created, matching \(accountPrefix)<6 hex>. A human account, an Apple account or root can never be removed from here.")
            }
            guard existingAccounts.contains(username) else {
                return AgentSpaceError(
                    code: .helperRejected,
                    message: "there is no account named \(username) to delete")
            }
            return nil

        case .installWorker, .removeWorker:
            guard let username = request.username else {
                return AgentSpaceError(code: .helperRejected, message: "\(request.operation.rawValue) requires a username")
            }
            guard isAgentSpaceAccount(username) else {
                return AgentSpaceError(
                    code: .helperRejected,
                    message: "\(username) is not an AgentSpace account; the worker LaunchAgent is only ever installed into an AgentSpace account's home")
            }
            guard existingAccounts.contains(username) else {
                return AgentSpaceError(code: .helperRejected, message: "there is no account named \(username)")
            }
            if request.operation == .installWorker, let root = request.runtimeRoot,
               let problem = validateRuntimeRoot(root) {
                return problem
            }
            return nil

        case .prepareRuntimeDirectory:
            guard let spaceID = request.spaceID else {
                return AgentSpaceError(code: .helperRejected, message: "prepareRuntimeDirectory requires a space ID")
            }
            _ = spaceID  // A UUID is validated by being one; there is nothing to escape.
            guard let username = request.username, isAgentSpaceAccount(username) else {
                return AgentSpaceError(
                    code: .helperRejected,
                    message: "prepareRuntimeDirectory requires the agent's AgentSpace account")
            }
            guard existingAccounts.contains(username) else {
                return AgentSpaceError(code: .helperRejected, message: "there is no account named \(username)")
            }
            guard let mainUser = request.mainUser else {
                return AgentSpaceError(code: .helperRejected, message: "prepareRuntimeDirectory requires the main user, so it knows who to grant access to")
            }
            return validateMainUser(mainUser, existingAccounts: existingAccounts)

        case .startWorker, .stopWorker:
            guard let spaceID = request.spaceID else {
                return AgentSpaceError(code: .helperRejected, message: "\(request.operation.rawValue) requires a space ID")
            }
            _ = spaceID
            guard let username = request.username, isAgentSpaceAccount(username) else {
                return AgentSpaceError(
                    code: .helperRejected,
                    message: "\(request.operation.rawValue) requires the agent's AgentSpace account, so that only that agent's LaunchAgent can be started or stopped")
            }
            guard existingAccounts.contains(username) else {
                return AgentSpaceError(code: .helperRejected, message: "there is no account named \(username)")
            }
            return nil

        case .logoutSession:
            // §40: Logout ends the agent's whole GUI session (releasing its
            // WindowServer, frames and RAM) while keeping the account and its
            // home. It is `launchctl bootout gui/<uid>` — a root-only op, so
            // it belongs here and nowhere else. The uid must name an AgentSpace
            // account: a logout that could target the *main* user's session
            // would be a self-destruct button wearing a feature's clothes.
            guard let uid = request.uid, uid > 0 else {
                return AgentSpaceError(code: .helperRejected, message: "logoutSession requires the agent's uid")
            }
            guard let username = request.username, isAgentSpaceAccount(username) else {
                return AgentSpaceError(
                    code: .helperRejected,
                    message: "logoutSession is only answered for AgentAgent accounts")
            }
            guard existingAccounts.contains(username) else {
                return AgentSpaceError(code: .helperRejected, message: "there is no account named \(username)")
            }
            return nil

        case .sessionInfo:
            guard let username = request.username, isAgentSpaceAccount(username) else {
                return AgentSpaceError(
                    code: .helperRejected,
                    message: "sessionInfo is only answered for AgentAgent accounts")
            }
            return nil
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

    public static let sysadminctl = "/usr/sbin/sysadminctl"
    public static let dscl = "/usr/bin/dscl"
    public static let launchctl = "/bin/launchctl"
    public static let createhomedir = "/usr/bin/createhomedir"
    public static let chmod = "/bin/chmod"
    public static let chown = "/usr/sbin/chown"
    public static let mkdir = "/bin/mkdir"

    public static func createUser(_ request: HelperRequest) -> [[String]] {
        guard let username = request.username, let password = request.password else { return [] }
        let fullName = request.displayName ?? "AgentSpace \(username)"
        var commands: [[String]] = []
        // `sysadminctl` is the supported way to make a user with a password
        // non-interactively. The account is a *standard* user: no `-admin`, ever.
        // That single omission is what stops a compromised agent from becoming an
        // administrator, and it is deliberately not a parameter.
        commands.append([
            sysadminctl,
            "-addUser", username,
            "-fullName", fullName,
            "-password", password,
            "-home", "/Users/\(username)",
            "-shell", "/bin/zsh",
        ])
        // sysadminctl does not always create the home directory, and on macOS 26+
        // the `createhomedir` tool no longer exists at all (HelperService skips
        // it there). A missing home is not fatal: macOS creates it at the
        // account's first GUI login, which the flow requires anyway.
        commands.append([createhomedir, "-c", "-u", username])
        return commands
    }

    public static func deleteUser(_ request: HelperRequest) -> [[String]] {
        guard let username = request.username else { return [] }
        var commands: [[String]] = []
        if request.removeHome == true {
            // Only ever /Users/<the account we just validated>. Built from the
            // account name rather than taken from the request, so there is no
            // path field for an attacker to aim somewhere else.
            commands.append([sysadminctl, "-deleteUser", username, "-secure"])
            commands.append(["/bin/rm", "-rf", "/Users/\(username)"])
        } else {
            commands.append([sysadminctl, "-deleteUser", username])
        }
        commands.append([dscl, ".", "-delete", "/Users/\(username)"])
        return commands
    }

    /// The worker's LaunchAgent, as a property list.
    ///
    /// `LimitLoadToSessionType: Aqua` is the load-bearing line: it is why the
    /// worker starts inside the AgentSpace user's *GUI* session — the only place
    /// input and screenshots mean anything — and never in a background or ssh
    /// context, where it would refuse to run anyway (exit 69).
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
