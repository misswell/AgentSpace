import Foundation

/// Can an AI client actually reach this AgentSpace? (§384)
///
/// This is a *different fact* from the one the account page prints as 就绪, and the
/// first does not imply the second. A client starts the MCP server named in **its
/// own** config file; if that command cannot start, the client simply has zero
/// `agentspace_*` tools, says "there is no AgentSpace available", and — exactly as
/// `Integrations.agentRules()` permits — falls back to driving the human's own
/// session. Measured on 2026-10-12: an account that `agentspace accounts --json`
/// reported `ready` / `usable` / `permitsInput=true` while the client asked to
/// upgrade an app had no AgentSpace tool at all, because its registration still
/// read `npx -y @agentspace/mcp` and that package has never been published
/// (validation row 826).
///
/// So the scan answers the client's question, not the desktop's: it reads the
/// configuration each client will read at its next launch and reports whether the
/// command in it can run *here*. It never writes anything, and it never calls a
/// client reachable because AgentSpace itself is healthy.
public enum MCPClients {

    /// What one client's `agentspace` entry would do at launch.
    public enum Verdict: Equatable {
        /// No `agentspace` entry, or no config file at all. The client has no
        /// AgentSpace tools — nothing is broken, nothing is connected either.
        case absent
        /// Points at this install's MCP service. The intended state.
        case current
        /// Runs `npx -y @agentspace/mcp` or an equivalent. The package was never
        /// published, so this fails at launch and the client gets zero tools.
        case packageNeverPublished
        /// The command named in the entry does not exist on this machine — a
        /// deleted bundle, an old dev checkout, a rebuilt machine.
        case commandMissing(String)
        /// `AGENTSPACE_BIN` points at a CLI that is not executable, so the server
        /// starts and then fails *every* call with its own explanation.
        case agentCLIMissing(String)
        /// A command that exists but is not this install's service — a second copy,
        /// a dev checkout, a wrapper. Reachable, and named as such.
        case other(String)
        /// The file exists and carries an `agentspace` entry this scan cannot read,
        /// so its state is unknown rather than assumed.
        case unreadable(String)

        public var isReachable: Bool {
            switch self {
            case .current, .other: return true
            default: return false
            }
        }

        /// One line a person can act on. Shared by `doctor` and the account page so
        /// the two cannot describe the same state differently.
        public var explanation: String {
            switch self {
            case .absent:
                return NSLocalizedString("no entry", comment: "")
            case .current:
                return NSLocalizedString("this install", comment: "")
            case .packageNeverPublished:
                return NSLocalizedString("runs `npx -y @agentspace/mcp`, and that package was never published — it cannot start", comment: "")
            case .commandMissing(let command):
                return String(format: NSLocalizedString("runs %@, which is not on this machine", comment: ""), command)
            case .agentCLIMissing(let path):
                return String(format: NSLocalizedString("sets AGENTSPACE_BIN to %@, which is not executable", comment: ""), path)
            case .other(let command):
                return String(format: NSLocalizedString("runs %@, which is reachable but not this install", comment: ""), command)
            case .unreadable(let reason):
                return reason
            }
        }
    }

    public struct Registration: Equatable {
        public var target: Integrations.Target
        public var path: String
        public var verdict: Verdict

        public init(target: Integrations.Target, path: String, verdict: Verdict) {
            self.target = target
            self.path = path
            self.verdict = verdict
        }
    }

    // MARK: - Scanning

    /// The clients worth looking at: every target with a config file of its own.
    /// `.generic` has no path, so it is not scanned.
    public static let scannableTargets: [Integrations.Target] = Integrations.Target.allCases.filter {
        !$0.configPath.isEmpty
    }

    /// Read every client's config and classify its `agentspace` entry.
    ///
    /// `home` is a parameter rather than a `~` expansion done deep inside: the
    /// config paths are `~`-relative, and resolving them through
    /// `expandingTildeInPath` reads the *passwd* home and ignores a redirected
    /// `HOME` — the same trap `Integrations` documents for installs.
    public static func scan(home: String,
                            binaryPath: String,
                            path: [String] = searchPath) -> [Registration] {
        scannableTargets.map { target in
            let relative = target.configPath.hasPrefix("~/")
                ? String(target.configPath.dropFirst(2))
                : target.configPath
            let file = (home as NSString).appendingPathComponent(relative)
            let data = FileManager.default.fileExists(atPath: file)
                ? (try? Data(contentsOf: URL(fileURLWithPath: file)))
                : nil
            return Registration(target: target, path: file,
                                verdict: classify(data: data, target: target,
                                                 binaryPath: binaryPath, path: path))
        }
    }

    /// The one command that repairs an entry this scan can name.
    public static func repairCommand(for target: Integrations.Target) -> String {
        "agentspace integrate \(target.rawValue) --install"
    }

    // MARK: - Summary

    /// Every client's verdict, grouped by what a human has to do about it.
    public struct Summary: Equatable {
        public var registrations: [Registration]

        public init(registrations: [Registration]) { self.registrations = registrations }

        /// Configured and able to start: the client will have `agentspace_*` tools.
        public var reachable: [Registration] { registrations.filter { $0.verdict.isReachable } }
        /// Configured in a way that cannot work. This is the group that produces
        /// "there is no AgentSpace" from a desktop that is in fact ready.
        public var broken: [Registration] {
            registrations.filter { $0.verdict != .absent && !$0.verdict.isReachable }
        }
        public var configured: [Registration] { registrations.filter { $0.verdict != .absent } }
    }

    public static func summary(home: String, binaryPath: String,
                               path: [String] = searchPath) -> Summary {
        Summary(registrations: scan(home: home, binaryPath: binaryPath, path: path))
    }

    private static func containsAgentspace(_ data: Data) -> Bool {
        String(decoding: data, as: UTF8.self).contains("agentspace")
    }

    // MARK: - Classification

    static func classify(data: Data?, target: Integrations.Target, binaryPath: String,
                         path: [String] = searchPath) -> Verdict {
        guard let data else { return .absent }
        let unreadable: (String) -> Verdict = { reason in
            .unreadable("\(target.displayName): \(reason)")
        }
        let parsed = entry(in: data, target: target)
        // A file that does not even mention agentspace has no entry; one that does
        // is a shape this scan must not guess about.
        if case .unreadable = parsed, !containsAgentspace(data) { return .absent }
        switch parsed {
        case .noEntry:
            return .absent
        case .unreadable:
            return unreadable(NSLocalizedString("could not be read as this client's expected format", comment: ""))
        case .entry(let entry):
            guard let command = entry.command, !command.isEmpty else {
                return unreadable(NSLocalizedString("the agentspace entry has no command", comment: ""))
            }
            let args = entry.args ?? []
            if isNPMRunner(command, args: args) {
                return .packageNeverPublished
            }
            if !runs(command, args: args, path: path) {
                return .commandMissing(command)
            }
            if let bin = entry.agentSpaceBin, !isExecutableFile(bin) {
                return .agentCLIMissing(bin)
            }
            return command == Integrations.mcpLaunch(binaryPath: binaryPath).command
                ? .current : .other(command)
        }
    }

    /// `npx -y @agentspace/mcp` and its npm/pnpm/yarn/bun spellings.
    ///
    /// Named by runner *and* package, so a client that runs `npx` against some
    /// other published tool is not reported as broken.
    static func isNPMRunner(_ command: String, args: [String]) -> Bool {
        guard ["npx", "npm", "pnpm", "yarn", "bunx", "bun"].contains((command as NSString).lastPathComponent) else {
            return false
        }
        return args.contains { $0.contains("@agentspace/mcp") }
    }

    /// Can this command actually be started?
    ///
    /// `node <path>/dist/index.js` is judged on the script, because that is what a
    /// development checkout looks like; a bare name is judged on `PATH`, which is
    /// what the client resolves it against.
    static func runs(_ command: String, args: [String], path: [String]) -> Bool {
        let name = (command as NSString).lastPathComponent
        if command.hasPrefix("/") && !isExecutableFile(command) { return false }
        if name == "node" {
            // Without its entry script the runner starts and immediately exits.
            return args.first.map { FileManager.default.fileExists(atPath: $0) } ?? false
        }
        if command.hasPrefix("/") { return true }
        return path.contains { isExecutableFile(($0 as NSString).appendingPathComponent(command)) }
    }

    private static func isExecutableFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    /// The directories a launched client would search. Read once: the app's own
    /// `PATH` is whatever it inherited, and that is the closest answer available
    /// without spawning a shell per client.
    public static var searchPath: [String] {
        (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
    }

    // MARK: - Reading one entry

    /// The three fields this scan cares about, whatever shape the client uses.
    struct Entry: Equatable {
        var command: String?
        var args: [String]?
        var agentSpaceBin: String?
    }

    /// `noEntry` = the file was read and carries no `agentspace` entry;
    /// `unreadable` = this scan could not read the file's format at all. The two are
    /// different answers, and reporting the second as the first would tell a user
    /// their client is not configured when it is.
    enum Parsed: Equatable {
        case noEntry
        case entry(Entry)
        case unreadable
    }

    /// Pull the client's `agentspace` entry out of its own config.
    ///
    /// The key path and the entry shape are owned by `Integrations.Target`, so a
    /// client added there is scanned here without a second list to keep in step.
    static func entry(in data: Data, target: Integrations.Target) -> Parsed {
        switch target.shape {
        case .toml:
            return tomlEntry(String(decoding: data, as: UTF8.self)).map(Parsed.entry) ?? .noEntry
        case .plain, .miniMax:
            return jsonEntry(parsedJSON(data), through: ["mcpServers", "agentspace"])
        case .vsCode:
            return jsonEntry(parsedJSON(data), through: ["servers", "agentspace"])
        case .zed:
            return jsonEntry(parsedJSON(data), through: ["context_servers", "agentspace"])
        case .amp:
            return jsonEntry(parsedJSON(data), through: ["amp.mcpServers", "agentspace"])
        case .openCode, .crush:
            return jsonEntry(parsedJSON(data), through: ["mcp", "agentspace"])
        case .zcode:
            return jsonEntry(parsedJSON(data), through: ["mcp", "servers", "agentspace"])
        }
    }

    private static func parsedJSON(_ data: Data) -> [String: Any]? {
        jsonRoot(data) ?? jsonRoot(strippingJSONComments(data))
    }

    private static func jsonRoot(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Drop whole-line `//` comments and trailing commas.
    ///
    /// Only lines that *start* with `//` are removed: a naive "strip from the first
    /// `//`" would eat the slashes in a `https://` value and turn a readable config
    /// into a broken one.
    private static func strippingJSONComments(_ data: Data) -> Data {
        let text = String(decoding: data, as: UTF8.self)
        let kept = text
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        return Data(kept.replacingOccurrences(of: ",\\s*([}\\]])", with: "$1",
                                             options: .regularExpression).utf8)
    }

    private static func jsonEntry(_ root: [String: Any]?, through keys: [String]) -> Parsed {
        guard let root else { return .unreadable }
        var cursor: Any? = root
        for key in keys {
            guard let next = (cursor as? [String: Any])?[key] else { return .noEntry }
            cursor = next
        }
        guard let object = cursor as? [String: Any] else { return .unreadable }
        var entry = Entry()
        // OpenCode and MiMo carry argv as one array; everyone else splits
        // command/args. Both spellings mean the same launch.
        if let array = object["command"] as? [String] {
            entry.command = array.first
            entry.args = Array(array.dropFirst())
        } else {
            entry.command = object["command"] as? String
            entry.args = object["args"] as? [String]
        }
        let env = (object["env"] ?? object["environment"]) as? [String: Any]
        entry.agentSpaceBin = env?["AGENTSPACE_BIN"] as? String
        return .entry(entry)
    }

    /// The one table this tool writes, read line by line.
    ///
    /// Deliberately not a TOML parser: `Integrations.mergeTOMLConfig` refuses to
    /// ship one, because a parser that appends one table is a way to corrupt a
    /// user's config file subtly instead of obviously. Reading one table back needs
    /// no such machinery.
    static func tomlEntry(_ text: String) -> Entry? {
        guard let start = text.range(of: "[mcp_servers.agentspace]") else { return nil }
        var entry = Entry()
        for line in text[start.upperBound...].split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { break }
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<equals]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "command": entry.command = unquote(value)
            case "args": entry.args = stringArray(value)
            case "env": entry.agentSpaceBin = inlineTable(value)?["AGENTSPACE_BIN"]
            default: break
            }
        }
        return entry
    }

    private static func unquote(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: " \""))
    }

    private static func stringArray(_ value: String) -> [String] {
        guard let open = value.firstIndex(of: "["), let close = value.lastIndex(of: "]") else { return [] }
        return value[value.index(after: open)..<close]
            .components(separatedBy: ",")
            .map(unquote)
            .filter { !$0.isEmpty }
    }

    private static func inlineTable(_ value: String) -> [String: String]? {
        guard let open = value.firstIndex(of: "{"), let close = value.lastIndex(of: "}") else { return nil }
        var result: [String: String] = [:]
        for pair in value[value.index(after: open)..<close].components(separatedBy: ",") {
            guard let equals = pair.firstIndex(of: "=") else { continue }
            result[pair[..<equals].trimmingCharacters(in: .whitespaces)] =
                unquote(String(pair[pair.index(after: equals)...]))
        }
        return result
    }
}
