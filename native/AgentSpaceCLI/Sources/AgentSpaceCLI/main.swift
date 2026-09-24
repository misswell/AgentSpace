import Foundation
import AgentSpaceCore

// agentspace — the CLI.
//
// Talks to a Space's worker over the same unix socket the GUI and the MCP
// server use, so there is one core API rather than three implementations
// (plan §49).
//
// The rule this file must never break (plan §2): if the worker is not there,
// print why and stop. There is no code path here that runs a GUI command
// locally "because the background session was unavailable".

let cliVersion = "0.1.41"

// MARK: - Argument parsing

/// A usage error. A dedicated type because `Result`'s failure must be an
/// `Error`, and "the user typed the wrong flag" deserves to be distinguishable
/// from "the worker said no".
struct ArgumentError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

struct ParsedArgs {
    var positionals: [String] = []
    var flags: [String: String] = [:]
    var booleans: Set<String> = []
    /// Repeated flags, e.g. `--env A=1 --env B=2`.
    var repeated: [String: [String]] = [:]

    func flag(_ name: String) -> String? { flags[name] }
    func bool(_ name: String) -> Bool { booleans.contains(name) }
    func list(_ name: String) -> [String] { repeated[name] ?? [] }

    func int(_ name: String) -> Int? { flags[name].flatMap(Int.init) }
}

/// Flags that take a value, so the parser knows whether to consume the next
/// argument.
/// Flags that take a value.
let valueFlags: Set<String> = [
    "root", "out", "max-width", "display", "cwd", "timeout", "env",
    "file", "pid", "role", "title", "identifier", "action", "reason",
    "max-depth", "max-nodes", "fps", "query", "limit",
    // Attach workspace flags. Declared here or the parser refuses them as
    // unknown before the command ever sees them.
    "repo", "branch", "share", "share-rw", "config",
]

/// Flags that stand alone. `--json` belongs here, not above: listing it as a
/// value flag made `agentspace status --json` demand an argument.
let booleanFlags: Set<String> = [
    "help", "version", "json", "double", "right", "force", "inline",
    "interesting", "no-interesting", "all", "resources", "quiet",
    "remove-home", "install", "start", "frame", "stop", "stats",
    // `apps --available`: the installed-app list, which nothing else asks for.
    "available", "icons",
]

/// Flags that may appear more than once.
let repeatableFlags: Set<String> = ["env", "share", "share-rw"]

func parseArgs(_ argv: [String]) -> Result<ParsedArgs, ArgumentError> {
    var parsed = ParsedArgs()
    var index = 0
    var afterSeparator = false
    while index < argv.count {
        let argument = argv[index]
        if afterSeparator {
            parsed.positionals.append(argument)
            index += 1
            continue
        }
        if argument == "--" {
            afterSeparator = true
            index += 1
            continue
        }
        if argument.hasPrefix("--") {
            let body = String(argument.dropFirst(2))
            let name = body.split(separator: "=", maxSplits: 1).first.map(String.init) ?? body
            if let equalsIndex = body.firstIndex(of: "=") {
                let value = String(body[body.index(after: equalsIndex)...])
                parsed.flags[name] = value
                index += 1
                continue
            }
            if booleanFlags.contains(name) {
                parsed.booleans.insert(name)
                index += 1
                continue
            }
            if valueFlags.contains(name) {
                guard index + 1 < argv.count else {
                    return .failure(ArgumentError("--\(name) requires a value"))
                }
                let value = argv[index + 1]
                if repeatableFlags.contains(name) {
                    parsed.repeated[name, default: []].append(value)
                } else {
                    parsed.flags[name] = value
                }
                index += 2
                continue
            }
            return .failure(ArgumentError("unknown flag --\(name)"))
        }
        parsed.positionals.append(argument)
        index += 1
    }
    return .success(parsed)
}

// MARK: - Output

struct Emitter {
    let json: Bool

    /// Print a successful result.
    func success(_ value: JSONValue, human: String? = nil, exitCode: Int32 = 0) -> Never {
        if json {
            print(pretty(value))
        } else if let human {
            print(human)
        } else {
            print(pretty(value))
        }
        exit(exitCode)
    }

    /// Print a failure and stop.
    ///
    /// Two shapes on purpose. In `--json` mode the envelope is the *whole*
    /// answer, so a script can branch on it. In human mode the code, the
    /// message and the fix are all shown: a bare "failed" is what makes a tool
    /// unusable.
    func failure(_ error: AgentSpaceError, exitCode: Int32 = 1) -> Never {
        if json {
            var object: [String: JSONValue] = [
                "status": .string("unavailable"),
                "reason": .string(UnavailableStatus.Reason(error.code).rawValue),
                "ok": .bool(false),
                "error": .obj([
                    "code": .string(error.code.rawValue),
                    "message": .string(error.message),
                    "recoverable": .bool(error.recoverable),
                ]),
            ]
            object["fix"] = .string(error.code.remediation)
            print(pretty(.object(object)))
        } else {
            FileHandle.standardError.write(Data("agentspace: \(error.code.rawValue): \(error.message)\n".utf8))
            FileHandle.standardError.write(Data("  → \(error.code.remediation)\n".utf8))
        }
        exit(exitCode)
    }

    func pretty(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}

// MARK: - Space resolution

/// Resolve a Space reference, or stop with a helpful message.
///
/// Never guesses: an unknown name lists what does exist.
func resolveSpace(_ reference: String?, root: String?, emitter: Emitter) -> (AgentAccount, SpaceConnection) {
    // The caller's emitter, not a fresh human-mode one: in --json mode the error
    // envelope is the whole answer, and a script branching on it must not
    // receive prose. Exit 66 is the documented not-found code; the catch-all
    // default would have made "no such Space" indistinguishable from a generic
    // failure — found by the first run of the integration suite.
    let registry = SpaceRegistry.load(root: root)
    let space: AgentAccount
    if let reference {
        switch registry.resolve(reference) {
        case .success(let found): space = found
        case .failure(let error): emitter.failure(error, exitCode: 66)
        }
    } else {
        guard let first = registry.first() else {
            emitter.failure(AgentSpaceError(
                code: .sessionNotReady,
                message: "no agent accounts are connected yet, and no name was given. Connect an existing standard macOS account in the AgentSpace app first."))
        }
        space = first
    }
    return (space, SpaceConnection(space: space))
}

/// Send a request to a Space's worker, mapping transport failures onto the
/// typed envelope. This is where "the worker is not there" becomes
/// `WORKER_OFFLINE` rather than an exception a caller might swallow.
func call(_ connection: SpaceConnection, _ method: String, _ params: JSONValue) -> JSONValue {
    do {
        let response = try connection.client.call(method: method, params: params, token: connection.token)
        if response.ok {
            return response.result ?? .object([:])
        }
        if let error = response.error {
            Emitter(json: false).failure(error)
        }
        Emitter(json: false).failure(AgentSpaceError(
            code: .internalError,
            message: "worker replied without a result or an error"))
    } catch let error as AgentSpaceError {
        Emitter(json: false).failure(error)
    } catch {
        Emitter(json: false).failure(AgentSpaceError(
            code: .workerOffline,
            message: "could not reach the worker for '\(connection.space.name)' at \(connection.paths.socketPath): \(error)"))
    }
}

func callJSON(_ emitter: Emitter, _ connection: SpaceConnection, _ method: String, _ params: JSONValue) -> JSONValue {
    do {
        let response = try connection.client.call(method: method, params: params, token: connection.token)
        if response.ok { return response.result ?? .object([:]) }
        if let error = response.error { emitter.failure(error) }
        emitter.failure(AgentSpaceError(code: .internalError, message: "worker replied without a result or an error"))
    } catch let error as AgentSpaceError {
        emitter.failure(error)
    } catch {
        emitter.failure(AgentSpaceError(
            code: .workerOffline,
            message: "could not reach the worker for '\(connection.space.name)': \(error)"))
    }
}

// MARK: - Single-action input helpers

func inputParams(_ actions: [JSONValue]) -> JSONValue {
    .obj(["actions": .array(actions)])
}

func number(_ value: Double) -> JSONValue { .double(value) }

func usage() -> String {
    """
    agentspace \(cliVersion) — give every AI agent its own macOS account and desktop

    USAGE:
      agentspace <command> [account] [arguments] [--json]

    AGENT ACCOUNTS
      accounts                        List agent accounts (alias: list)
      list                            Same as accounts
      status [account]                Session, permissions and resource state
      doctor                          Diagnose this machine's readiness
      diagnostics                     Export a redacted support bundle
      helper                          Privileged helper: installed? answering?

    MANAGEMENT (changes the machine; needs the privileged helper)
      integrate <target>              Print MCP config for claude|codex|opencode
                                      [--install writes it, backing up first]
                                      agentspace integrate rules       Agent safety rules (§35)
      attach <username>               Connect an existing standard macOS user
      detach <account>                Remove AgentSpace worker/runtime only;
                                      keep the macOS user and home

    OBSERVE
      screenshot <account>            Capture the agent's desktop
      open <account>                  Open the agent's desktop in the app
                                      (alias: desktop)
      preview <account> --start | --frame | --stats | --stop
                                      Drive the live preview stream (§52 debug)
                                      --start [--fps N] opens the screenshot
                                      preview, --stats asks the frame engine
                                      what its open streams are doing
      apps <account>                  Apps running in the agent session
      ax <account> snapshot           Accessibility tree of the frontmost app
      ax <account> frontmost          Frontmost app and focused element
      ax <account> windows            Windows of the frontmost app

    ACT
      move <account> X Y              Move the pointer (points, not pixels)
      click <account> X Y             Click  [--double] [--right]
      type <account> TEXT             Type text
      key <account> COMBO             Press a key combo, e.g. cmd+l
      scroll <account> DX DY [X Y]    Scroll  (X Y = where; without it nothing moves)
      drag <account> X1 Y1 X2 Y2      Drag
      input <account> --file F | -    Submit a batch of actions as JSON
      launch <account> APP            Launch an app in the agent session
      activate <account> APP          Bring an app to the front
      quit <account> APP              Quit  [--force]
      exec <account> COMMAND          Run a shell command as the agent user
                                      [--cwd DIR] [--timeout MS] [--env K=V]

    MANAGE
      start|stop|restart <account>    Control the agent's worker

    GLOBAL
      --json                          Machine-readable output on every command
      --root PATH                     Use an alternate AgentSpace root
      --version, --help

    AgentSpace never creates or deletes macOS users. Attach/detach only manage
    the worker and runtime through the typed privileged helper. The CLI never
    runs sudo.
    """
}

// MARK: - Entry point

let argv = Array(CommandLine.arguments.dropFirst())

let parsedResult = parseArgs(argv)
let parsed: ParsedArgs
switch parsedResult {
case .success(let value): parsed = value
case .failure(let error):
    FileHandle.standardError.write(Data("agentspace: \(error.message)\n\n".utf8))
    FileHandle.standardError.write(Data((usage() + "\n").utf8))
    exit(2)
}

// `--version` has to be answered before the empty-command check below, because
// `agentspace --version` has no positional command and would otherwise be treated
// as a usage error and dump the help text. (`--help` was already handled here,
// but `--version` was not; both are now.)
if parsed.bool("version") {
    if parsed.bool("json") {
        print("""
        {
          "cli" : "\(cliVersion)",
          "protocol" : \(agentSpaceProtocolVersion)
        }
        """)
    } else {
        print("agentspace \(cliVersion) (protocol \(agentSpaceProtocolVersion))")
    }
    exit(0)
}

if parsed.bool("help") || parsed.positionals.isEmpty {
    print(usage())
    exit(parsed.positionals.isEmpty && !parsed.bool("help") ? 2 : 0)
}

// `--root` must take effect before anything reads the environment.
if let root = parsed.flag("root") {
    setenv("AGENTSPACE_ROOT", root, 1)
}
let rootOverride = parsed.flag("root")

let emitter = Emitter(json: parsed.bool("json"))

// Compatibility aliases. V3's primary account-lifecycle words are attach and
// detach; old create/delete spellings intentionally resolve to the same safe
// existing-account operations and never regain directory-service semantics.
var command = parsed.positionals[0]
var rest = Array(parsed.positionals.dropFirst())
if command == "create" {
    if rest.first == "account" { rest.removeFirst() }
    command = "attach"
}
if command == "delete" { command = "detach" }
if command == "open" { command = "desktop" }
if command == "accounts" { command = "list" }

switch command {

case "version":
    emitter.success(.obj([
        "cli": .string(cliVersion),
        "protocol": .int(agentSpaceProtocolVersion),
    ]), human: "agentspace \(cliVersion) (protocol \(agentSpaceProtocolVersion))")

case "attach":
    let username = rest.first ?? ""
    guard !username.isEmpty else {
        emitter.failure(AgentSpaceError(code: .badRequest, message: "usage: agentspace attach <existing-username> [--repo PATH] [--branch agentspace/x] [--share PATH] [--share-rw PATH]"), exitCode: 64)
    }
    guard let local = AccountDiscovery.find(username: username) else {
        emitter.failure(AgentSpaceError(code: .helperRejected, message: "\(username) is not an unattached standard local user (the current user and administrators are excluded)"), exitCode: 66)
    }

    var workspace: Workspace = .none
    var sharedFolders: [SharedFolder] = []
    if parsed.flag("repo") != nil || parsed.flag("branch") != nil {
        guard let repository = parsed.flag("repo") else {
            emitter.failure(AgentSpaceError(code: .badRequest, message: "a git workspace needs --repo PATH"), exitCode: 64)
        }
        let branch = parsed.flag("branch") ?? "agentspace/\(username.lowercased())"
        // The worktree lives under the controller-managed runtime root rather than
        // inside the attached account's home, so the main user can review it.
        //
        // The path is left empty on purpose. The attach service fills it in once it
        // has a Space id, which is the only thing that makes it unique — a path
        // derived from the name collides for two Spaces called `Test` and `test`.
        workspace = .gitWorktree(
            repository: (repository as NSString).expandingTildeInPath,
            branch: branch,
            path: "")
    }
    for path in parsed.list("share") {
        sharedFolders.append(SharedFolder(path: (path as NSString).expandingTildeInPath, access: .readOnly))
    }
    for path in parsed.list("share-rw") {
        sharedFolders.append(SharedFolder(path: (path as NSString).expandingTildeInPath, access: .readWrite))
    }

    let resolvedRoot = rootOverride ?? AgentSpaceEnvironment.rootOverride ?? RuntimePaths.root
    let attachOptions = AccountAttachService.Options(
        root: resolvedRoot,
        workspaceDirectory: "\(resolvedRoot)/Worktrees",
        mainUser: NSUserName())

    let outcome = AccountAttachService.attach(
        account: local,
        displayName: local.displayName,
        workspace: workspace,
        sharedFolders: sharedFolders,
        options: attachOptions,
        transport: { try HelperClient.call($0) },
        registry: SpaceRegistry.load(root: resolvedRoot))

    if emitter.json {
        print(emitter.pretty(.obj([
            "ok": .bool(outcome.ok),
            "space": outcome.account.map { space in
                .obj([
                    "id": .string(space.id.uuidString),
                    "name": .string(space.name),
                    "username": .string(space.username),
                    "uid": .int(Int(space.uid)),
                    "state": .string(space.state.rawValue),
                ])
            } ?? .null,
            "error": outcome.error.map { .obj([
                "code": .string($0.code.rawValue),
                "message": .string($0.message),
            ]) } ?? .null,
            "steps": .array(outcome.steps.map { step in
                .obj([
                    "name": .string(step.name),
                    "detail": .string(step.detail),
                    "outcome": .string(String(describing: step.outcome)),
                ])
            }),
        ])))
    } else {
        for step in outcome.steps {
            let mark: String
            switch step.outcome {
            case .done: mark = "  ✓"
            case .skipped: mark = "  ~"
            case .failed, .rollbackFailed: mark = "  ✗"
            case .rolledBack: mark = "  ↩"
            }
            let detail = step.detail.isEmpty ? "" : "  \(step.detail)"
            print("\(mark) \(step.name)\(detail)")
            if case .skipped(let reason) = step.outcome, !reason.isEmpty {
                print("      \(reason)")
            }
            if case .rolledBack(let reason) = step.outcome, !reason.isEmpty {
                print("      \(reason)")
            }
            if case .rollbackFailed(let reason) = step.outcome, !reason.isEmpty {
                print("      \(reason)")
            }
            if case .failed(let reason) = step.outcome, !reason.isEmpty {
                print("      \(reason)")
            }
        }
        if let space = outcome.account {
            print("")
            print("Connected \(space.name) (macOS user \(space.username), uid \(space.uid)).")
            print("Sign in to that account once and grant Accessibility and Screen Recording to agentspace-worker.")
        }
    }
    if let error = outcome.error {
        FileHandle.standardError.write(Data("\(error.message)\n\(error.code.remediation)\n".utf8))
        exit(error.code == .helperUnavailable ? 69 : 1)
    }
    exit(0)

case "detach":
    let registry = SpaceRegistry.load(root: rootOverride)
    guard let target = rest.first else {
        emitter.failure(AgentSpaceError(code: .badRequest, message: "usage: agentspace detach <account>"), exitCode: 64)
    }
    let space: AgentAccount
    switch registry.resolve(target) {
    case .success(let found): space = found
    case .failure(let error):
        emitter.failure(error, exitCode: 66)
    }
    let outcome = AccountAttachService.detach(
        account: space,
        options: AccountAttachService.Options(
            root: rootOverride ?? AgentSpaceEnvironment.rootOverride ?? space.runtimeRoot ?? RuntimePaths.root,
            registryRoot: rootOverride ?? AgentSpaceEnvironment.rootOverride ?? RuntimePaths.root,
            workspaceDirectory: "\(rootOverride ?? AgentSpaceEnvironment.rootOverride ?? RuntimePaths.root)/Worktrees",
            mainUser: NSUserName()),
        transport: { try HelperClient.call($0) },
        registry: registry)
    if emitter.json {
        let stepValues: [JSONValue] = outcome.steps.map { step in
            let fields: [String: JSONValue] = [
                "name": .string(step.name),
                "detail": .string(step.detail),
                "outcome": .string(String(describing: step.outcome)),
            ]
            return .obj(fields)
        }
        var payload: [String: JSONValue] = [
            "ok": .bool(outcome.error == nil),
            "space": .string(space.name),
            "keptMacOSUser": .bool(true),
            "steps": .array(stepValues),
        ]
        if let error = outcome.error {
            payload["error"] = .obj([
                "code": .string(error.code.rawValue),
                "message": .string(error.message),
            ])
        } else {
            payload["error"] = .null
        }
        print(emitter.pretty(.obj(payload)))
    } else {
        for step in outcome.steps {
            print("  \(step.isFailure ? "✗" : "✓") \(step.name)\(step.detail.isEmpty ? "" : "  \(step.detail)")")
        }
    }
    if let error = outcome.error {
        FileHandle.standardError.write(Data("\(error.message)\n".utf8))
        exit(1)
    }
    exit(0)

case "integrate":
    // Plan §34: one-click MCP configuration for Claude Code, Codex and OpenCode.
    //
    // The default prints the config for the user to paste; `--install` writes it,
    // touching only the key AgentSpace owns. Installing is a deliberate flag rather
    // than a default because it edits a file another tool owns.
    guard let targetName = rest.first else {
        emitter.failure(AgentSpaceError(code: .badRequest, message: "usage: agentspace integrate <claude|codex|opencode|generic> [--install]"), exitCode: 64)
    }
    if targetName == "rules" {
        // Plan §35: the safety rules recommended for any agent driving AgentSpace.
        // They are printed by default; --install appends them to CLAUDE.md inside
        // AgentSpace's own markers, leaving the user's text alone.
        if parsed.bool("install") {
            let path = ((parsed.flag("config") ?? "~/CLAUDE.md") as NSString).expandingTildeInPath
            let existing = FileManager.default.contents(atPath: path)
            let merged = Integrations.mergeAgentRules(existing: existing)
            let directory = (path as NSString).deletingLastPathComponent
            do {
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                if let existing, !FileManager.default.fileExists(atPath: path + ".agentspace.bak") {
                    try existing.write(to: URL(fileURLWithPath: path + ".agentspace.bak"))
                }
                try merged.write(to: URL(fileURLWithPath: path))
            } catch {
                emitter.failure(AgentSpaceError(code: .internalError, message: "\(error)"), exitCode: 70)
            }
            if emitter.json {
                emitter.success(.obj([
                    "target": .string("rules"), "path": .string(path),
                    "alreadyPresent": .bool(existing.map { String(decoding: $0, as: UTF8.self).contains(Integrations.agentRulesMarkerBegin) } ?? false),
                ]))
            }
            print("Agent rules written to \(path)")
            exit(0)
        }
        if emitter.json {
            emitter.success(.obj([
                "target": .string("rules"),
                "rules": .string(Integrations.agentRules()),
                "section": .string(Integrations.agentRulesSection()),
            ]))
        }
        print("Recommended for AGENTS.md / CLAUDE.md (append only with the user's consent — plan §35):")
        print("")
        print(Integrations.agentRulesSection())
        exit(0)
    }

    guard let target = Integrations.Target(rawValue: targetName) else {
        emitter.failure(AgentSpaceError(code: .badRequest, message: "unknown target '\(targetName)'. Targets: rules, \(Integrations.Target.allCases.map(\.rawValue).joined(separator: ", "))"), exitCode: 64)
    }

    guard let binaryPath = Integrations.defaultBinaryPath() else {
        emitter.failure(AgentSpaceError(code: .internalError, message: "could not locate the agentspace CLI to point the MCP server at"), exitCode: 70)
    }

    if parsed.bool("install") {
        guard !target.configPath.isEmpty else {
            emitter.failure(AgentSpaceError(code: .badRequest, message: "the generic shape has no single config file; use --json to copy it into your client's configuration"), exitCode: 64)
        }
        // `--config` exists so the write can be aimed somewhere other than the
        // real home — non-standard installs, and tests. Never assume a HOME
        // redirect works: tilde expansion ignores it (measured, validation.md §18).
        let chosen = parsed.flag("config") ?? target.configPath
        let expanded = (chosen as NSString).expandingTildeInPath
        let existing = FileManager.default.contents(atPath: expanded)
        do {
            let merged: Data
            switch target {
            case .codex:
                merged = try Integrations.mergeTOMLConfig(existing: existing, binaryPath: binaryPath)
            case .claudeCode:
                merged = try Integrations.mergeJSONConfig(existing: existing, rootKey: "mcpServers", binaryPath: binaryPath)
            case .openCode:
                merged = try Integrations.mergeJSONConfig(existing: existing, rootKey: "mcp", binaryPath: binaryPath)
            case .generic:
                exit(64) // unreachable: guarded above
            }
            let directory = (expanded as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            // A backup before the first write to an existing file: the undo for
            // editing a file another tool owns, costing one copy.
            if let existing, !FileManager.default.fileExists(atPath: expanded + ".agentspace.bak") {
                try existing.write(to: URL(fileURLWithPath: expanded + ".agentspace.bak"))
            }
            try merged.write(to: URL(fileURLWithPath: expanded))

            if emitter.json {
                emitter.success(.obj([
                    "target": .string(target.rawValue),
                    "path": .string(expanded),
                    "binary": .string(binaryPath),
                    "created": .bool(existing == nil),
                    "backup": .string(existing == nil ? "" : expanded + ".agentspace.bak"),
                ]))
            }
            print("Configured \(target.displayName): \(expanded)")
            print("  AGENTSPACE_BIN = \(binaryPath)")
            if existing != nil { print("  previous contents saved to \(expanded).agentspace.bak") }
            print("Restart \(target.displayName) to pick up the new server.")
            exit(0)
        } catch let error as Integrations.InstallError {
            let message: String
            if case Integrations.InstallError.conflictingEntry = error {
                message = "\(expanded) \(error)"
            } else {
                message = "\(error)"
            }
            emitter.failure(AgentSpaceError(code: .workspaceDenied, message: message), exitCode: 65)
        } catch {
            emitter.failure(AgentSpaceError(code: .internalError, message: "\(error)"), exitCode: 70)
        }
    }

    let snippet = Integrations.config(for: target, binaryPath: binaryPath)
    if emitter.json {
        emitter.success(.obj([
            "target": .string(target.rawValue),
            "binary": .string(binaryPath),
            "configPath": .string(target.configPath),
            "config": .string(snippet),
        ]))
    }
    print(Integrations.instructions(for: target, binaryPath: binaryPath))
    print("")
    print(snippet)
    exit(0)

case "helper":
    // The privileged helper, from the outside. Read-only: registering the
    // LaunchDaemon is a thing only the app can do (SMAppService needs the app's
    // own bundle), and it deliberately needs the user's password, so this command
    // reports state and never offers to change it.
    let state = HelperInstallation.inspect()
    let payload: JSONValue = .obj([
        "installed": .bool(state.plistInBundle != nil),
        "reachable": .bool(state.isReachable),
        "summary": .string(state.summary),
        "helperVersion": state.helperVersionIfKnown.map { .string($0) } ?? .null,
        "expectedVersion": .string(helperVersion),
        "plistInBundle": state.plistInBundle.map { .string($0.path) } ?? .null,
        "fix": state.fix.map { .string($0) } ?? .null,
        // Stated explicitly, because it is the question people actually have.
        "neededFor": .array([
            .string("creating a Space"),
            .string("deleting a Space"),
            .string("installing or removing a Space's worker"),
        ]),
        "notNeededFor": .array([
            .string("driving an existing Space"),
            .string("screenshots, input, apps, exec, accessibility"),
        ]),
    ])
    if emitter.json {
        print(emitter.pretty(payload))
    } else {
        print("agentspace-helper — \(state.summary)")
        if let plist = state.plistInBundle { print("  bundle plist:  \(plist.path)") }
        if let version = state.helperVersionIfKnown { print("  version:       \(version)") }
        if state.isReachable {
            print("  status:        answerable; creating and deleting Spaces will work")
        } else {
            print("  status:        not answerable. Creating and deleting Spaces will")
            print("                 fail with HELPER_UNAVAILABLE; driving an existing")
            print("                 Space is unaffected.")
            if let fix = state.fix { print("  fix:           \(fix)") }
        }
    }
    // Exit 0 when the helper answers, 3 when it does not — so a script can branch
    // without parsing text, and an unavailable helper is never mistaken for a pass.
    exit(state.isReachable ? 0 : 3)

case "diagnostics":
    // §37: a support bundle safe to hand out. Two controls, both enforced in
    // Core: whitelist collection (no token contents, no frames, no input) and
    // a redaction pass over everything that does get collected.
    let bundle = Diagnostics.collect(root: rootOverride)
    if parsed.bool("json") {
        emitter.success(.obj(["bundle": .string(bundle)]), human: nil)
    } else if let out = parsed.flags["out"] {
        do {
            try bundle.write(toFile: out, atomically: true, encoding: .utf8)
            emitter.success(.obj(["path": .string(out)]), human: "wrote \(out)")
        } catch {
            emitter.failure(AgentSpaceError(code: .internalError, message: "could not write \(out): \(error)"))
        }
    } else {
        emitter.success(.obj(["bundle": .string(bundle)]), human: bundle)
    }

case "doctor":
    // The orphan-account check needs the helper, the only thing that can
    // enumerate AgentSpace-named macOS accounts. A CLI the helper refuses —
    // an unsigned dev build, say — yields nil here, and the check is omitted
    // rather than reported as a pass it did not verify.
    let report = Doctor.run(root: rootOverride, orphanedAccounts: HelperClient.agentSpaceAccounts())
    if emitter.json {
        print(emitter.pretty(report.json))
    } else {
        print(report.render())
    }
    exit(report.ok ? 0 : 1)

case "list":
    let registry = SpaceRegistry.load(root: rootOverride)
    var rows: [JSONValue] = []
    for space in registry.spaces {
        let connection = SpaceConnection(space: space)
        var reachable = false
        var session: JSONValue = .null
        if FileManager.default.fileExists(atPath: connection.paths.socketPath),
           let response = try? connection.client.call(method: Method.hello, token: nil, timeout: 3),
           let result = response.result {
            reachable = true
            session = result["session"] ?? .null
        }
        rows.append(.obj([
            "id": .string(space.id.uuidString),
            "name": .string(space.name),
            "username": .string(space.username),
            "uid": .int(Int(space.uid)),
            "state": .string(space.state.rawValue),
            "stateLabel": .string(space.state.displayName),
            "worker": .bool(reachable),
            "session": session,
            "workspace": .string(space.workspace.displayName),
        ]))
    }
    if emitter.json {
        print(emitter.pretty(.obj([
            "count": .int(rows.count),
            "accounts": .array(rows),
            "spaces": .array(rows),
        ])))
    } else if rows.isEmpty {
        print("No agent accounts yet. Open the AgentSpace app to create one.")
    } else {
        for space in registry.spaces {
            let connection = SpaceConnection(space: space)
            let reachable = FileManager.default.fileExists(atPath: connection.paths.socketPath)
            let marker = reachable ? "●" : "○"
            print("\(marker) \(space.name)  [\(space.state.displayName)]  uid \(space.uid)  \(space.username)")
        }
    }
    exit(0)

case "status":
    let (space, connection) = resolveSpace(rest.first, root: rootOverride, emitter: emitter)
    let result = callJSON(emitter, connection, Method.status,
                          .obj(["resources": parsed.bool("resources") ? .string("full") : .string("summary")]))
    if emitter.json {
        var object = result.objectValue ?? [:]
        object["space"] = .string(space.name)
        print(emitter.pretty(.object(object)))
    } else {
        let state = result["stateLabel"]?.stringValue ?? "?"
        print("\(space.name) — \(state)")
        print("  uid            \(result["uid"]?.intValue ?? -1) (\(result["user"]?.stringValue ?? "?"))")
        print("  worker         \(result["worker"]?.boolValue == true ? "running" : "offline") (pid \(result["workerPid"]?.intValue ?? -1))")
        print("  session        \(result["session"]?["verdict"]?.stringValue ?? "?")")
        print("  accessibility  \(result["accessibility"]?.boolValue == true ? "granted" : "MISSING")")
        print("  screen record  \(result["screenRecording"]?.boolValue == true ? "granted" : "MISSING")")
        // Three states, because "an older worker never looked" is not the same
        // claim as "this account denied it" — and this one is optional anyway.
        let fileAccessText: String
        switch result["fileAccess"]?.boolValue {
        case .some(true):
            fileAccessText = "granted"
        case .some(false):
            fileAccessText = "not granted (optional) — without Full Disk Access this account's Desktop, Documents, Downloads and other apps' data stay closed"
        case nil:
            fileAccessText = "unknown — this worker predates the probe; update it from the AgentSpace app"
        }
        print("  file access    \(fileAccessText)")
        print("  display        \(result["display"]?["width"]?.intValue ?? 0)x\(result["display"]?["height"]?.intValue ?? 0) points, scale \(result["display"]?["scale"]?.intValue ?? 1)")
        if let resources = result["resources"] {
            print("  cpu            \(resources["cpuPercent"]?.doubleValue ?? 0)%")
            print("  memory         \(ByteCountFormatter.string(fromByteCount: Int64(resources["memoryBytes"]?.intValue ?? 0), countStyle: .memory))")
            print("  processes      \(resources["processCount"]?.intValue ?? 0)")
        }
    }
    exit(0)

case "screenshot":
    let (_, connection) = resolveSpace(rest.first, root: rootOverride, emitter: emitter)
    var params: [String: JSONValue] = [:]
    if let maxWidth = parsed.int("max-width") { params["maxWidth"] = .int(maxWidth) }
    if let display = parsed.int("display") { params["display"] = .int(display) }
    if let out = parsed.flag("out") { params["path"] = .string(out) }
    if parsed.bool("inline") { params["inline"] = .bool(true) }
    let result = callJSON(emitter, connection, Method.screenshot, .object(params))
    if emitter.json {
        print(emitter.pretty(result))
    } else {
        print(result["path"]?.stringValue ?? "(no path)")
        print("  \(result["width"]?.intValue ?? 0)x\(result["height"]?.intValue ?? 0) px, scale \(result["scale"]?.intValue ?? 1) — divide pixel coordinates by scale to get input points")
    }
    exit(0)


case "desktop":
    // §31: put a Space's Desktop Viewer in front of the user. This is
    // deliberately a deep link into the app, not a CLI screenshot loop: the
    // viewer is the app's §52 pull-model stream with its own lifecycle, and
    // duplicating it here would be a second reason for the machine to keep
    // capturing. The CLI checks that the Space exists (SPACE_NOT_FOUND, exit
    // 66, otherwise), then hands the app the link. The worker does not need to
    // be online for this — the app shows the offline state honestly.
    guard rest.first != nil else {
        emitter.failure(AgentSpaceError(
            code: .badRequest,
            message: "usage: agentspace open <account>"), exitCode: 64)
    }
    let (desktopSpace, _) = resolveSpace(rest.first, root: rootOverride, emitter: emitter)
    let link = AppDeepLink.url(forSpaceID: desktopSpace.id)
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = [link.absoluteString]
    try open.run()
    open.waitUntilExit()
    guard open.terminationStatus == 0 else {
        emitter.failure(AgentSpaceError(
            code: .helperUnavailable,
            message: "could not open the AgentSpace app (exit \(open.terminationStatus)). Is it in /Applications or built in dist/?"), exitCode: 69)
    }
    emitter.success(
        [
            "opened": .bool(true),
            "account": .string(desktopSpace.name),
            "space": .string(desktopSpace.name),
            "url": .string(link.absoluteString),
        ],
        human: "opening the Desktop Viewer for \(desktopSpace.name) — \(link.absoluteString)")

case "preview":
    // §52's live preview from the command line: --start opens the stream,
    // --frame pulls the newest frame (base64), --stop closes it, and --stats asks
    // the frame engine what its open streams are doing. The GUI runs the same
    // methods directly over the socket; the CLI exists so the stream can be
    // exercised and debugged without the app.
    let (_, connection) = resolveSpace(rest.first, root: rootOverride, emitter: emitter)
    if parsed.bool("start") {
        let fps = parsed.int("fps") ?? 5
        let result = callJSON(emitter, connection, Method.previewStart, .obj(["maxFPS": .int(fps)]))
        emitter.success(result, human: "preview streaming at \(result["fps"]?.intValue ?? fps) fps")
    } else if parsed.bool("frame") {
        let result = callJSON(emitter, connection, Method.previewFrame, .obj([:]))
        emitter.success(result, human: "got a frame (\(result["inline"]?.stringValue?.count ?? 0) base64 chars)")
    } else if parsed.bool("stop") {
        let result = callJSON(emitter, connection, Method.previewStop, .obj([:]))
        emitter.success(result, human: "preview stopped")
    } else if parsed.bool("stats") {
        // The frame engine's own report, for the streams this worker has open —
        // which are normally the app's, not the terminal's. No stream ID means
        // "all of them", because a UUID belonging to somebody else's window is
        // not something a diagnosis should have to guess.
        let result = callJSON(emitter, connection, Method.frameStats, .obj([:]))
        let streams = result["streams"]?.arrayValue ?? []
        emitter.success(result, human: streams.isEmpty
            ? "no frame stream is open (\(result["openStreams"]?.intValue ?? 0))"
            : "\(streams.count) frame stream(s): " + streams.map { "\($0["frameMode"]?.stringValue ?? "?") \($0["publishFPS"]?.doubleValue ?? 0)fps" }.joined(separator: ", "))
    } else {
        emitter.failure(AgentSpaceError(code: .badRequest, message: "usage: agentspace preview <space> --start [--fps N] | --frame | --stats | --stop"))
    }

case "input":
    let (_, connection) = resolveSpace(rest.first, root: rootOverride, emitter: emitter)
    let payload: Data
    if let file = parsed.flag("file") {
        if file == "-" {
            payload = FileHandle.standardInput.readDataToEndOfFile()
        } else {
            guard let data = FileManager.default.contents(atPath: file) else {
                emitter.failure(AgentSpaceError(code: .badRequest, message: "could not read actions from \(file)"))
            }
            payload = data
        }
    } else {
        payload = FileHandle.standardInput.readDataToEndOfFile()
    }
    guard let actions = try? JSONDecoder().decode(JSONValue.self, from: payload) else {
        emitter.failure(AgentSpaceError(code: .badRequest, message: "actions payload is not valid JSON"))
    }
    // Accept either a bare array or {"actions": [...]}.
    let array = actions.arrayValue ?? actions["actions"]?.arrayValue
    guard let array else {
        emitter.failure(AgentSpaceError(code: .badRequest, message: #"expected a JSON array of actions, or {"actions": [...]}"#))
    }
    let result = callJSON(emitter, connection, Method.input, inputParams(array))
    emitter.success(result, human: "performed \(result["performed"]?.intValue ?? 0) action(s)")

case "move":
    guard rest.count >= 3, let x = Double(rest[1]), let y = Double(rest[2]) else {
        emitter.failure(AgentSpaceError(code: .badRequest, message: "usage: agentspace move <space> X Y"))
    }
    let (_, connection) = resolveSpace(rest[0], root: rootOverride, emitter: emitter)
    let result = callJSON(emitter, connection, Method.input,
                          inputParams([.obj(["type": .string("move"), "x": number(x), "y": number(y)])]))
    emitter.success(result, human: "moved to \(x), \(y)")

case "click":
    guard rest.count >= 3, let x = Double(rest[1]), let y = Double(rest[2]) else {
        emitter.failure(AgentSpaceError(code: .badRequest, message: "usage: agentspace click <space> X Y [--double] [--right]"))
    }
    let (_, connection) = resolveSpace(rest[0], root: rootOverride, emitter: emitter)
    var action: [String: JSONValue] = [
        "type": .string(parsed.bool("double") ? "doubleClick" : (parsed.bool("right") ? "rightClick" : "click")),
        "x": number(x), "y": number(y),
    ]
    if parsed.bool("right") { action["button"] = .string("right") }
    let result = callJSON(emitter, connection, Method.input, inputParams([.object(action)]))
    emitter.success(result, human: "clicked \(Int(x)), \(Int(y))")

case "type":
    guard rest.count >= 2 else {
        emitter.failure(AgentSpaceError(code: .badRequest, message: "usage: agentspace type <space> TEXT"))
    }
    let (_, connection) = resolveSpace(rest[0], root: rootOverride, emitter: emitter)
    let text = rest.dropFirst().joined(separator: " ")
    let result = callJSON(emitter, connection, Method.input,
                          inputParams([.obj(["type": .string("type"), "text": .string(text)])]))
    emitter.success(result, human: "typed \(text.count) character(s)")

case "key":
    guard rest.count >= 2 else {
        emitter.failure(AgentSpaceError(code: .badRequest, message: "usage: agentspace key <space> COMBO"))
    }
    let (_, connection) = resolveSpace(rest[0], root: rootOverride, emitter: emitter)
    let combo = rest.dropFirst().joined(separator: " ")
    let result = callJSON(emitter, connection, Method.input,
                          inputParams([.obj(["type": .string("key"), "key": .string(combo)])]))
    emitter.success(result, human: "pressed \(combo)")

case "scroll":
    guard rest.count >= 3, let dx = Int(rest[1]), let dy = Int(rest[2]) else {
        emitter.failure(AgentSpaceError(code: .badRequest, message: "usage: agentspace scroll <space> DX DY [X Y]"))
    }
    // The anchor is the difference between a scroll and nothing: without a point
    // the worker can only post a wheel event, and a posted wheel event enters a
    // background session's stream without ever reaching an app (§315). A lone X is
    // a typo, and answering it by dropping the anchor quietly is exactly how this
    // verb stayed at zero pixels for a whole release.
    var x: Double?
    var y: Double?
    var anchorText = ""
    switch rest.count {
    case 3:
        break
    case 5:
        guard let anchorX = Double(rest[3]), let anchorY = Double(rest[4]) else {
            emitter.failure(AgentSpaceError(code: .badRequest, message: "usage: agentspace scroll <space> DX DY [X Y] — X and Y are display points"))
        }
        x = anchorX
        y = anchorY
        anchorText = " at \(Int(anchorX)),\(Int(anchorY))"
    default:
        emitter.failure(AgentSpaceError(code: .badRequest, message: "usage: agentspace scroll <space> DX DY [X Y] — an anchor needs both X and Y"))
    }
    // Encoded by Core, so the CLI, the GUI and the MCP server cannot disagree with
    // the worker's parser about what an anchored scroll is called on the wire.
    let action = InputAction.scroll(x: x, y: y, dx: dx, dy: dy).wireValue
    let (_, connection) = resolveSpace(rest[0], root: rootOverride, emitter: emitter)
    let result = callJSON(emitter, connection, Method.input, inputParams([action]))
    // An anchored scroll that came back on the wheel channel moved nothing an app
    // can see: the event is posted into the session's stream and the window server
    // does not dispatch it to an app (§315). Reporting only "scrolled" there is the
    // same silent degradation this verb was fixed for in 0.1.28 — the anchor is
    // what makes a scroll work, so a run where the anchor could not be used has to
    // say so rather than describe the gesture that was intended.
    var note = ""
    if x != nil, result["channels"]?.arrayValue?.first?.stringValue == "scrolledViaWheel" {
        note = "\n  → no scroll area was found at that point, so a wheel event was posted instead, and a posted wheel event does not reach an app in a session that is not on the console. Nothing at that point was scrolled."
    }
    emitter.success(result, human: "scrolled \(dx), \(dy)\(anchorText)\(note)")

case "drag":
    guard rest.count >= 5,
          let x1 = Double(rest[1]), let y1 = Double(rest[2]),
          let x2 = Double(rest[3]), let y2 = Double(rest[4]) else {
        emitter.failure(AgentSpaceError(code: .badRequest, message: "usage: agentspace drag <space> X1 Y1 X2 Y2"))
    }
    let (_, connection) = resolveSpace(rest[0], root: rootOverride, emitter: emitter)
    let action: JSONValue = .obj([
        "type": .string("drag"),
        "fromX": number(x1), "fromY": number(y1),
        "toX": number(x2), "toY": number(y2),
    ])
    let result = callJSON(emitter, connection, Method.input, inputParams([action]))
    emitter.success(result, human: "dragged \(x1),\(y1) → \(x2),\(y2)")

case "launch", "activate":
    guard rest.count >= 2 else {
        emitter.failure(AgentSpaceError(code: .badRequest, message: "usage: agentspace \(command) <space> APP"))
    }
    let (_, connection) = resolveSpace(rest[0], root: rootOverride, emitter: emitter)
    let app = rest.dropFirst().joined(separator: " ")
    let method = command == "launch" ? Method.launch : Method.activate
    let result = callJSON(emitter, connection, method, .obj(["app": .string(app)]))
    emitter.success(result, human: "\(command == "launch" ? "launched" : "activated") \(result["name"]?.stringValue ?? app) (pid \(result["pid"]?.intValue ?? -1))")

case "quit":
    guard rest.count >= 2 else {
        emitter.failure(AgentSpaceError(code: .badRequest, message: "usage: agentspace quit <space> APP [--force]"))
    }
    let (_, connection) = resolveSpace(rest[0], root: rootOverride, emitter: emitter)
    let app = rest.dropFirst().joined(separator: " ")
    let method = parsed.bool("force") ? Method.forceQuit : Method.quit
    let result = callJSON(emitter, connection, method, .obj(["app": .string(app)]))
    emitter.success(result, human: "quit \(result["name"]?.stringValue ?? app) (pid \(result["pid"]?.intValue ?? -1))")

case "apps":
    let (_, connection) = resolveSpace(rest.first, root: rootOverride, emitter: emitter)
    // `--available` is the other half of the same question. `apps` answers "what
    // is running in this session", which is only useful once something is;
    // `apps.available` answers "what could be launched", which is what an agent
    // needs first — and what the Fusion app picker shows. Additive at protocol
    // version 1: `apps` keeps answering exactly what it always has.
    if parsed.bool("available") {
        var params: [String: JSONValue] = [:]
        if let query = parsed.flag("query") { params["query"] = .string(query) }
        if let limit = parsed.int("limit") { params["limit"] = .int(limit) }
        // Text output cannot show a picture, and a couple of hundred base64
        // icons is a reply nobody reads: they are asked for only on request.
        params["icons"] = .bool(parsed.bool("icons"))
        // By default the reply is the regular apps — the ones a person can open
        // and then look at. `--all` adds the menu-bar agents and background
        // services, which is 372 entries on this Mac and no window to fuse.
        params["all"] = .bool(parsed.bool("all"))
        let result = callJSON(emitter, connection, Method.appsAvailable, .object(params))
        if emitter.json {
            print(emitter.pretty(result))
            exit(0)
        }
        let list = result["apps"]?.arrayValue ?? []
        if list.isEmpty { print("No applications found in this AgentSpace.") }
        for app in list {
            let name = app["name"]?.stringValue ?? "(unnamed)"
            let identifier = app["bundleId"]?.stringValue ?? "-"
            let version = app["version"]?.stringValue.map { "  \($0)" } ?? ""
            let path = app["path"]?.stringValue ?? ""
            let running = app["pid"] != nil ? "  ←running" : ""
            print("\(name)\t\(identifier)\(version)\t\(path)\(running)")
        }
        if let count = result["count"]?.intValue, let total = result["total"]?.intValue,
           count < total {
            FileHandle.standardError.write(Data(
                "\(count) of \(total) applications; narrow it with --query TEXT\n".utf8))
        }
        exit(0)
    }
    let result = callJSON(emitter, connection, Method.apps, .object([:]))
    if emitter.json {
        print(emitter.pretty(result))
    } else {
        let list = result["apps"]?.arrayValue ?? []
        if list.isEmpty { print("No apps running in this AgentSpace.") }
        for app in list {
            let name = app["name"]?.stringValue ?? "(unnamed)"
            let pid = app["pid"]?.intValue ?? -1
            let policy = app["policy"]?.stringValue ?? "?"
            let active = app["active"]?.boolValue == true ? "  ←front" : ""
            print("\(pid)\t\(name)\t[\(policy)]\(active)")
        }
    }
    exit(0)

case "exec":
    guard rest.count >= 2 else {
        emitter.failure(AgentSpaceError(code: .badRequest, message: "usage: agentspace exec <space> COMMAND [--cwd DIR] [--timeout MS]"))
    }
    let (_, connection) = resolveSpace(rest[0], root: rootOverride, emitter: emitter)
    let shellCommand = rest.dropFirst().joined(separator: " ")
    var params: [String: JSONValue] = ["command": .string(shellCommand)]
    if let cwd = parsed.flag("cwd") { params["cwd"] = .string(cwd) }
    if let timeout = parsed.int("timeout") { params["timeoutMs"] = .int(timeout) }
    let envPairs = parsed.list("env")
    if !envPairs.isEmpty {
        var env: [String: JSONValue] = [:]
        for pair in envPairs {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                emitter.failure(AgentSpaceError(code: .badRequest, message: "--env expects KEY=VALUE, got '\(pair)'"))
            }
            env[parts[0]] = .string(parts[1])
        }
        params["env"] = .object(env)
    }
    let result = callJSON(emitter, connection, Method.exec, .object(params))
    if emitter.json {
        print(emitter.pretty(result))
        exit(result["exitCode"]?.intValue == 0 ? 0 : 1)
    } else {
        if let stdout = result["stdout"]?.stringValue, !stdout.isEmpty {
            FileHandle.standardOutput.write(Data(stdout.utf8))
        }
        if let stderr = result["stderr"]?.stringValue, !stderr.isEmpty {
            FileHandle.standardError.write(Data(stderr.utf8))
        }
        let code = result["exitCode"]?.intValue
        let duration = result["duration"]?.intValue ?? 0
        FileHandle.standardError.write(Data("exit \(code.map(String.init) ?? "signal \(result["signal"]?.stringValue ?? "?")") (\(duration)ms)\n".utf8))
        exit(code == 0 ? 0 : 1)
    }

case "ax":
    guard rest.count >= 2 else {
        emitter.failure(AgentSpaceError(code: .badRequest, message: "usage: agentspace ax <space> snapshot|frontmost|windows|perform"))
    }
    let (_, connection) = resolveSpace(rest[0], root: rootOverride, emitter: emitter)
    let subcommand = rest[1]
    var params: [String: JSONValue] = [:]
    if let pid = parsed.int("pid") { params["pid"] = .int(pid) }

    let method: String
    switch subcommand {
    case "snapshot":
        method = Method.axSnapshot
        if let depth = parsed.int("max-depth") { params["maxDepth"] = .int(depth) }
        if let nodes = parsed.int("max-nodes") { params["maxNodes"] = .int(nodes) }
        params["interestingOnly"] = .bool(!parsed.bool("all"))
    case "frontmost":
        method = Method.axFrontmost
    case "windows":
        method = Method.axWindows
    case "perform", "click":
        method = Method.axPerform
        if subcommand == "click" { params["click"] = .bool(true) }
        if let action = parsed.flag("action") { params["action"] = .string(action) }
        if let role = parsed.flag("role") { params["role"] = .string(role) }
        if let title = parsed.flag("title") { params["titleContains"] = .string(title) }
        if let identifier = parsed.flag("identifier") { params["identifier"] = .string(identifier) }
    default:
        emitter.failure(AgentSpaceError(code: .badRequest, message: "unknown ax subcommand '\(subcommand)'"))
    }
    let result = callJSON(emitter, connection, method, .object(params))
    print(emitter.pretty(result))
    exit(0)

case "start", "stop", "restart":
    guard let reference = rest.first else {
        emitter.failure(AgentSpaceError(code: .badRequest, message: "usage: agentspace \(command) <space>"))
    }
    let (space, connection) = resolveSpace(reference, root: rootOverride, emitter: emitter)
    switch command {
    case "stop":
        let result = callJSON(emitter, connection, Method.shutdown, .obj(["reason": .string("agentspace stop")]))
        emitter.success(result, human: "stopped \(space.name)")
    case "restart":
        // Best effort: a worker that is not running has nothing to stop.
        if FileManager.default.fileExists(atPath: connection.paths.socketPath) {
            _ = try? connection.client.call(method: Method.shutdown, params: .object([:]), token: connection.token, timeout: 5)
        }
        fallthrough
    default:
        // Starting a worker needs launchd and the agent user's own session, so
        // the CLI hands it to the helper rather than trying to `sudo` anything.
        emitter.failure(AgentSpaceError(
            code: .workerOffline,
            message: "starting a worker is the privileged helper's job; the CLI does not run launchd or sudo. The AgentSpace user must be logged in through the GUI at least once.",
            recoverable: true))
    }

default:
    FileHandle.standardError.write(Data("agentspace: unknown command '\(command)'\n\n".utf8))
    FileHandle.standardError.write(Data((usage() + "\n").utf8))
    exit(2)
}
