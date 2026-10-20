import Foundation

/// One-click MCP configuration for the clients AgentSpace supports — plan §34.
///
/// The MCP server is the same for every client; what differs is the shape of each
/// client's configuration file and where it lives. This module is the single source
/// of that truth, so the GUI's "Install MCP", the CLI's `agentspace integrate` and
/// this module's tests cannot drift apart.
///
/// The client list is deliberately larger than the first six: every entry below was
/// checked against that client's own documentation and, where the client was
/// installed, against the file it actually reads. A path that a client does not
/// read is worse than no target at all — the user sees "Configured", restarts, and
/// still has no tools — so a client whose location this project could not pin down
/// (Trae's two IDE variants, Continue's YAML preference, Roo/Kilo's renamed file)
/// is left to the `generic` copy flow instead of being guessed at.
///
/// Deliberately **not** a general config-file editor. Each merge below touches only
/// the one key AgentSpace owns (`mcpServers.agentspace`, `servers.agentspace`,
/// `context_servers.agentspace`, `mcp.agentspace`, `mcp.servers.agentspace`,
/// `amp.mcpServers.agentspace`, `[mcp_servers.agentspace]`) and preserves everything
/// else, and the TOML path refuses rather than parsing, because shipping a TOML
/// parser to append one table is a way to corrupt a user's config file subtly
/// instead of obviously.
public enum Integrations {

    public enum Target: String, CaseIterable {
        // Command-line agents.
        case claudeCode = "claude"
        case codex = "codex"
        case openCode = "opencode"
        case zcode = "zcode"
        /// Kimi Code keeps its MCP servers in a dedicated `mcp.json`.
        case kimiCode = "kimi"
        /// Xiaomi MiMo (mimocode) is OpenCode-shaped but lives in its own directory.
        case mimoCode = "mimo"
        case gemini = "gemini"
        case qwen = "qwen"
        case qoder = "qoder"
        case amazonQ = "amazonq"
        case copilot = "copilot"
        case crush = "crush"
        case amp = "amp"
        case factory = "factory"
        case minimax = "minimax"

        // Editors.
        case cursor = "cursor"
        case windsurf = "windsurf"
        case vsCode = "vscode"
        case zed = "zed"
        case kiro = "kiro"
        case antigravity = "antigravity"

        // Desktop apps.
        case claudeDesktop = "claude-desktop"
        case lmStudio = "lmstudio"

        // Editor extensions.
        case cline = "cline"

        /// The shape most other clients accept (`mcpServers` at the top level).
        case generic = "generic"

        public var displayName: String {
            switch self {
            case .claudeCode: return "Claude Code"
            case .claudeDesktop: return "Claude Desktop"
            case .codex: return "Codex"
            case .openCode: return "OpenCode"
            case .zcode: return "ZCode"
            case .kimiCode: return "Kimi Code"
            case .mimoCode: return "Xiaomi MiMo"
            case .gemini: return "Gemini CLI"
            case .qwen: return "Qwen Code"
            case .qoder: return "Qoder CLI"
            case .amazonQ: return "Amazon Q Developer"
            case .copilot: return "GitHub Copilot CLI"
            case .crush: return "Crush"
            case .amp: return "Amp"
            case .factory: return "Factory Droid"
            case .minimax: return "MiniMax Code"
            case .cursor: return "Cursor"
            case .windsurf: return "Windsurf"
            case .vsCode: return "VS Code (Copilot)"
            case .zed: return "Zed"
            case .kiro: return "Kiro"
            case .antigravity: return "Antigravity"
            case .lmStudio: return "LM Studio"
            case .cline: return "Cline"
            case .generic: return "Other MCP clients"
            }
        }

        /// A menu-sized grouping. The raw-value order above is the order inside
        /// each group; the GUI reads this rather than keeping its own list.
        public enum Category: CaseIterable {
            case terminal
            case editor
            case desktop
            case editorExtension
        }

        public var category: Category {
            switch self {
            case .claudeCode, .codex, .openCode, .zcode, .kimiCode, .mimoCode,
                 .gemini, .qwen, .qoder, .amazonQ, .copilot, .crush, .amp,
                 .factory, .minimax, .generic:
                return .terminal
            case .cursor, .windsurf, .vsCode, .zed, .kiro, .antigravity:
                return .editor
            case .claudeDesktop, .lmStudio:
                return .desktop
            case .cline:
                return .editorExtension
            }
        }

        /// The file this target reads. `~`-relative on purpose: it is expanded at
        /// install time, not here, so the generated snippet can be shown anywhere.
        ///
        /// **Not** expanded with `NSString.expandingTildeInPath` in tests: that
        /// expands against the passwd-entry home and *ignores* the HOME
        /// environment variable, so a test that set HOME to a sandbox silently
        /// wrote the real user's config file. The CLI takes an explicit
        /// `--config PATH` for anything that must not hit the real home.
        ///
        /// Paths are macOS paths because AgentSpace is a macOS product. VS Code's
        /// and Cline's live under Application Support rather than a dotfile.
        public var configPath: String {
            switch self {
            case .claudeCode: return "~/.claude.json"
            case .claudeDesktop: return "~/Library/Application Support/Claude/claude_desktop_config.json"
            case .codex: return "~/.codex/config.toml"
            case .openCode: return "~/.config/opencode/opencode.json"
            case .zcode: return "~/.zcode/cli/config.json"
            case .kimiCode: return "~/.kimi-code/mcp.json"
            case .mimoCode: return "~/.config/mimocode/mimocode.jsonc"
            case .gemini: return "~/.gemini/settings.json"
            case .qwen: return "~/.qwen/settings.json"
            case .qoder: return "~/.qoder/settings.json"
            case .amazonQ: return "~/.aws/amazonq/mcp.json"
            case .copilot: return "~/.copilot/mcp-config.json"
            case .crush: return "~/.config/crush/crush.json"
            case .amp: return "~/.config/amp/settings.json"
            case .factory: return "~/.factory/mcp.json"
            case .minimax: return "~/.minimax/mcp.json"
            case .cursor: return "~/.cursor/mcp.json"
            case .windsurf: return "~/.codeium/windsurf/mcp_config.json"
            case .vsCode: return "~/Library/Application Support/Code/User/mcp.json"
            case .zed: return "~/.config/zed/settings.json"
            case .kiro: return "~/.kiro/settings/mcp.json"
            case .antigravity: return "~/.gemini/config/mcp_config.json"
            case .lmStudio: return "~/.lmstudio/mcp.json"
            case .cline: return "~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json"
            case .generic: return ""
            }
        }

        var shape: Shape {
            switch self {
            case .codex:
                return .toml
            case .openCode, .mimoCode:
                return .openCode
            case .zcode:
                return .zcode
            case .crush:
                return .crush
            case .amp:
                return .amp
            case .minimax:
                return .miniMax
            case .vsCode:
                return .vsCode
            case .zed:
                return .zed
            case .claudeCode, .claudeDesktop, .kimiCode, .gemini, .qwen, .qoder,
                 .amazonQ, .copilot, .factory, .cursor, .windsurf, .kiro,
                 .antigravity, .lmStudio, .cline, .generic:
                return .plain
            }
        }
    }

    /// How a client spells "start this local server". Every branch below is a
    /// different published schema, not a preference: the wrong key is silently
    /// ignored by some clients and drops the whole entry in others.
    enum Shape {
        /// `mcpServers` → `{ command, args, env }`: Claude Code, Claude Desktop,
        /// Cursor, Windsurf, Kiro, Gemini CLI, Qwen Code, Antigravity, Qoder CLI,
        /// Amazon Q, Copilot CLI, Cline, Factory, LM Studio, Kimi Code.
        case plain
        /// `servers` → `{ type: "stdio", command, args, env }` (VS Code, 1.99+).
        case vsCode
        /// `context_servers` → `{ source: "custom", command, args, env }` (Zed).
        case zed
        /// `amp.mcpServers` → `{ command, args, env }` (Amp's settings.json).
        case amp
        /// `mcp` → `{ type: "local", command: [argv], environment, enabled }`
        /// (OpenCode and Xiaomi MiMo).
        case openCode
        /// `mcp.servers` → `{ type: "stdio", command, args, env, enabled }`
        /// (ZCode; its schema is strict about exactly these keys).
        case zcode
        /// `mcp` → `{ type: "stdio", command, args, env }` (Crush).
        case crush
        /// `mcpServers` → `{ type: "stdio", command, args, env, enabled }`
        /// (MiniMax Code).
        case miniMax
        /// `[mcp_servers.agentspace]` (Codex).
        case toml
    }

    /// Every target that owns a configuration file. `.generic` is copy-only.
    public static let installableTargets: [Target] = Target.allCases.filter {
        !$0.configPath.isEmpty
    }

    // MARK: - Generation

    /// The launch command for the MCP server: Node, this package, and which
    /// `agentspace` binary to drive.
    ///
    /// `AGENTSPACE_BIN` is not optional. The MCP server must run *this* install's
    /// CLI — a different copy of the binary would be a different TCC identity, so
    /// permissions granted to one would not apply to the other.
    public static func config(for target: Target, binaryPath: String) -> String {
        let root: [String: Any]
        switch target.shape {
        case .toml:
            return tomlConfig(binaryPath: binaryPath)
        case .plain, .vsCode, .zed, .amp, .openCode, .zcode, .crush, .miniMax:
            root = jsonRoot(for: target.shape, binaryPath: binaryPath)
        }
        let data = Data(prettyJSON(root).utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// How to apply the configuration by hand, for the "Copy Config" flow.
    public static func instructions(for target: Target, binaryPath: String) -> String {
        switch target {
        case .claudeCode:
            return """
            Run, from a terminal:

              claude mcp add-json agentspace '\(config(for: target, binaryPath: binaryPath).replacingOccurrences(of: "\n", with: " "))'

            or paste the JSON into the "mcpServers" object of \(Target.claudeCode.configPath).
            """
        case .codex:
            return """
            Append the block below to \(Target.codex.configPath), then restart Codex.
            If it already contains an [mcp_servers.agentspace] table, replace that table.
            """
        case .generic:
            return """
            Merge the "agentspace" entry below into your client's "mcpServers" object.
            """
        default:
            return """
            Merge the "agentspace" entry below into the \(keyDescription(for: target)) object of \(target.configPath),
            then restart \(target.displayName).\(shapeNote(for: target))
            """
        }
    }

    private static func keyDescription(for target: Target) -> String {
        switch target.shape {
        case .plain: return "\"mcpServers\""
        case .vsCode: return "\"servers\""
        case .zed: return "\"context_servers\""
        case .amp: return "\"amp.mcpServers\""
        case .openCode, .crush: return "\"mcp\""
        case .zcode: return "\"mcp.servers\""
        case .miniMax: return "\"mcpServers\""
        case .toml: return "[mcp_servers.agentspace]"
        }
    }

    private static func shapeNote(for target: Target) -> String {
        switch target.shape {
        case .zcode:
            return " ZCode's schema is strict: keep exactly the keys shown."
        case .miniMax:
            return " MiniMax needs the type and enabled fields shown."
        case .zed:
            return " Zed's settings file may use // comments; a file with comments is edited by hand so they survive."
        default:
            return ""
        }
    }

    private static func jsonRoot(for shape: Shape, binaryPath: String) -> [String: Any] {
        var root: [String: Any] = [:]
        insert(jsonEntry(for: shape, binaryPath: binaryPath),
               at: keyPath(for: shape), into: &root)
        return root
    }

    private static func keyPath(for shape: Shape) -> [String] {
        switch shape {
        case .plain, .miniMax: return ["mcpServers"]
        case .vsCode: return ["servers"]
        case .zed: return ["context_servers"]
        case .amp: return ["amp.mcpServers"]
        case .openCode, .crush: return ["mcp"]
        case .zcode: return ["mcp", "servers"]
        case .toml: return []
        }
    }

    private static func jsonEntry(for shape: Shape, binaryPath: String) -> [String: Any] {
        let launch = mcpLaunch(binaryPath: binaryPath)
        let env = ["AGENTSPACE_BIN": binaryPath]
        let command: [String: Any] = [
            "command": launch.command,
            "args": launch.args,
            "env": env,
        ]
        switch shape {
        case .plain:
            return command
        case .vsCode, .crush:
            var entry = command
            entry["type"] = "stdio"
            return entry
        case .miniMax:
            var entry = command
            entry["type"] = "stdio"
            entry["enabled"] = true
            return entry
        case .zcode:
            var entry = command
            entry["type"] = "stdio"
            entry["enabled"] = true
            return entry
        case .zed:
            var entry = command
            entry["source"] = "custom"
            return entry
        case .amp:
            return command
        case .openCode:
            // OpenCode carries argv as one array and its own environment key.
            return [
                "type": "local",
                "command": [launch.command] + launch.args,
                "environment": env,
                "enabled": true,
            ]
        case .toml:
            return [:]
        }
    }

    /// Walk `keys`, creating objects as needed, and put AgentSpace's entry in the
    /// last one. Only that entry is replaced; siblings survive untouched.
    private static func insert(_ entry: [String: Any], at keys: [String],
                               into root: inout [String: Any]) {
        guard let key = keys.first else { return }
        if keys.count == 1 {
            var servers = root[key] as? [String: Any] ?? [:]
            servers["agentspace"] = entry
            root[key] = servers
        } else {
            var child = root[key] as? [String: Any] ?? [:]
            insert(entry, at: Array(keys.dropFirst()), into: &child)
            root[key] = child
        }
    }

    private static func tomlConfig(binaryPath: String) -> String {
        let launch = mcpLaunch(binaryPath: binaryPath)
        let arguments = "[" + launch.args.map(quoted).joined(separator: ", ") + "]"
        // TOML. `env` is an inline table; the path is a basic string, which needs
        // no escapes beyond the quotes because a bundle path cannot contain one.
        return """
        [mcp_servers.agentspace]
        command = \(quoted(launch.command))
        args = \(arguments)
        env = { AGENTSPACE_BIN = \(quoted(binaryPath)) }
        """
    }

    // MARK: - Agent rules (plan §35)

    /// The marker that brackets AgentSpace's section in a user's instructions file.
    ///
    /// Anything between these lines is AgentSpace's and may be replaced; anything
    /// outside them is the user's and is never touched. Idempotent installs need
    /// the markers to recognise their own work.
    public static let agentRulesMarkerBegin = "<!-- agentspace:rules begin -->"
    public static let agentRulesMarkerEnd = "<!-- agentspace:rules end -->"

    /// The safety rules recommended for any agent driving AgentSpace — plan §35,
    /// restated as a preference policy.
    ///
    /// Plan §35's original four lines were absolute: never touch the console.
    /// The owner revised that on 2026-09-29 — 「倒也不必"永远不要回退到用户的
    /// 控制台会话"，只是尽量使用AgentSpace，如果AgentSpace可用的话」 — so the
    /// rules now state a preference with a declared fallback, in Chinese (the
    /// instructions files they land in are read by Chinese-first agents), and
    /// the first line says what to do, not only what not to do. The
    /// architectural boundary is unchanged and is what actually enforces it:
    /// the worker's console guard still refuses AgentSpace-mediated input
    /// aimed at the user's session no matter what any instructions file says.
    /// Generated, never hardcoded at call sites, so the wording has exactly
    /// one source of truth.
    public static func agentRules() -> String {
        """
        - 优先使用 AgentSpace：任何需要图形界面、会打开可见 macOS 窗口的操作，尽量用 AgentSpace 提供的 `agentspace_*` 工具（或 `agentspace` 命令行）在 Agent 桌面上执行。
        - AgentSpace 可用时，不要在用户当前会话中直接启动 GUI 应用。
        - 如果 AgentSpace 报告后台会话不可用，把问题报告给用户，不要无声地改用其他方式。
        - AgentSpace 不可用或确实无法完成时，才回退到用户当前会话执行，并明确告知用户。
        """
    }

    /// The rules as a markdown section, ready to append to `AGENTS.md` or
    /// `CLAUDE.md`, wrapped in the markers above.
    public static func agentRulesSection() -> String {
        """
        \(agentRulesMarkerBegin)
        ## AgentSpace 使用规则（Agent 桌面）

        \(agentRules())

        \(agentRulesMarkerEnd)
        """
    }

    /// Append the rules to an existing instructions file's contents.
    ///
    /// Idempotent: a file that already carries the section comes back unchanged.
    /// The user's own content stays exactly where it was — the section is
    /// **appended**, never spliced into the middle, because instructions files are
    /// read top-to-bottom by the agent and the user's own ordering means something
    /// to them.
    public static func mergeAgentRules(existing: Data?) -> Data {
        let current = existing.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        if current.contains(agentRulesMarkerBegin) {
            return existing ?? Data()
        }
        var updated = current
        if !updated.isEmpty && !updated.hasSuffix("\n") { updated += "\n" }
        if !updated.isEmpty { updated += "\n" }
        updated += agentRulesSection() + "\n"
        return Data(updated.utf8)
    }

    // MARK: - Install

    public enum InstallError: Error, CustomStringConvertible {
        /// The target file already configures `agentspace` differently. Refusing is
        /// correct here: silently replacing a user's own entry (different command,
        /// different env) would look like AgentSpace broke their setup.
        ///
        /// Carries no path, because only the caller knows which file it actually
        /// wrote to — hardcoding the default here produced a refusal that named a
        /// file the user had deliberately redirected away from.
        case conflictingEntry
        case unreadable(path: String, String)

        public var description: String {
            switch self {
            case .conflictingEntry:
                return "already contains an [mcp_servers.agentspace] table with different contents. Edit it by hand or remove it, then run the install again."
            case .unreadable(let path, let detail):
                return "could not read \(path): \(detail)"
            }
        }
    }

    /// Merge AgentSpace's entry into one client, dispatching on its schema.
    public static func merge(existing: Data?, target: Target,
                             binaryPath: String) throws -> Data {
        switch target.shape {
        case .toml:
            return try mergeTOMLConfig(existing: existing, binaryPath: binaryPath)
        case .plain, .vsCode, .zed, .amp, .openCode, .zcode, .crush, .miniMax:
            return try mergeJSONConfig(existing: existing, shape: target.shape,
                                       binaryPath: binaryPath)
        }
    }

    /// Merge AgentSpace's entry into an existing JSON config, changing nothing else.
    ///
    /// Only the single key AgentSpace owns is written. **Values** elsewhere are
    /// preserved exactly — but the file is re-serialized, so its formatting
    /// normalises and a diff will show the whole file as touched. There is no way
    /// to edit one key of a JSON file in place without a span editor, which is not
    /// worth the complexity here; what matters, and what is tested, is that no
    /// *value* changes. Keys are deliberately **not** sorted: keeping the parsed
    /// order makes the rewrite as close to the original as JSONSerialization can
    /// produce.
    ///
    /// A file that does not parse as strict JSON is refused, never rewritten. Some
    /// of these files (Zed, VS Code) legally carry `//` comments; rewriting them
    /// through a parser would silently delete the user's comments, so the honest
    /// answer is a refusal and the by-hand path in `instructions(for:)`.
    static func mergeJSONConfig(existing: Data?, shape: Shape,
                                binaryPath: String) throws -> Data {
        let root: [String: Any]
        if let existing {
            guard let parsed = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] else {
                throw InstallError.unreadable(
                    path: "(config)",
                    "not a JSON object; a file using // comments must be edited by hand so its comments survive")
            }
            root = parsed
        } else {
            root = [:]
        }

        var merged = root
        insert(jsonEntry(for: shape, binaryPath: binaryPath),
               at: keyPath(for: shape), into: &merged)
        return Data(prettyJSON(merged).utf8)
    }

    /// Merge into a TOML config by **appending** our table.
    ///
    /// Appending is safe only when the table is not already there: TOML forbids
    /// redefining a table, and a duplicate `[mcp_servers.agentspace]` would make
    /// the whole file unparseable — taking Codex's MCP configuration down with it.
    /// So an existing table is a refusal, not an edit.
    public static func mergeTOMLConfig(existing: Data?, binaryPath: String) throws -> Data {
        let current = existing.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        if current.contains("[mcp_servers.agentspace]") {
            let ours = config(for: .codex, binaryPath: binaryPath)
            // Identical is fine: re-running the install must be idempotent.
            if current.contains(ours) { return Data(current.utf8) }
            let legacy = """
            [mcp_servers.agentspace]
            command = "npx"
            args = ["-y", "@agentspace/mcp"]
            env = { AGENTSPACE_BIN = \(quoted(binaryPath)) }
            """
            if current.contains(legacy) {
                return Data(current.replacingOccurrences(of: legacy, with: ours).utf8)
            }
            throw InstallError.conflictingEntry
        }
        var updated = current
        if !updated.isEmpty && !updated.hasSuffix("\n") { updated += "\n" }
        if !updated.isEmpty { updated += "\n" }
        updated += config(for: .codex, binaryPath: binaryPath) + "\n"
        return Data(updated.utf8)
    }

    // MARK: - Paths

    /// Where the CLI this install should drive actually lives.
    ///
    /// Inside the app bundle the CLI ships at `Contents/Helpers/agentspace` —
    /// deliberately *not* `Contents/MacOS/agentspace`, which does not exist and
    /// would hand the MCP server a path that cannot run. Outside a bundle (a
    /// development build) the CLI is its own executable.
    public static func defaultBinaryPath() -> String? {
        guard let executable = Bundle.main.executableURL else { return nil }

        if let bundle = containingAppBundle(of: executable) {
            let helper = bundle.appendingPathComponent("Contents/Helpers/agentspace")
            if FileManager.default.isExecutableFile(atPath: helper.path) {
                return helper.path
            }
        }
        return executable.path
    }

    private static func containingAppBundle(of url: URL) -> URL? {
        var directory = url.deletingLastPathComponent()
        for _ in 0..<8 {
            if directory.pathExtension == "app" { return directory }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }

    /// Prefer the MCP service shipped with this exact install. The legacy npm
    /// spelling remains for callers pointing at an older, external CLI.
    public static func mcpLaunch(binaryPath: String) -> (command: String, args: [String]) {
        let executable = URL(fileURLWithPath: binaryPath)
        if let bundle = containingAppBundle(of: executable) {
            let launcher = bundle.appendingPathComponent("Contents/Resources/agentspace-mcp/launch.sh").path
            if FileManager.default.isExecutableFile(atPath: launcher) { return (launcher, []) }
        }
        var directory = executable.deletingLastPathComponent()
        for _ in 0..<8 {
            let launcher = directory.appendingPathComponent("packages/agentspace-mcp/launch.sh").path
            let entry = directory.appendingPathComponent("packages/agentspace-mcp/dist/index.js").path
            if FileManager.default.isExecutableFile(atPath: launcher), FileManager.default.fileExists(atPath: entry) {
                return (launcher, [])
            }
            directory = directory.deletingLastPathComponent()
        }
        return ("npx", ["-y", "@agentspace/mcp"])
    }

    /// A small, deterministic JSON writer for the snippets above.
    ///
    /// `JSONSerialization` escapes `/` and spreads an empty array over three
    /// lines. The escaped slashes broke the path comparisons this module and its
    /// scanner rely on, and the empty `args` is what most clients get when the
    /// bundled launcher is used, so both are worth writing out exactly.
    private static func prettyJSON(_ value: Any, indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        let childPad = String(repeating: "  ", count: indent + 1)
        if let object = value as? [String: Any] {
            guard !object.isEmpty else { return "{}" }
            let lines = object.keys.sorted().map { key in
                "\(childPad)\(quoted(key)): \(prettyJSON(object[key]!, indent: indent + 1))"
            }
            return "{\n" + lines.joined(separator: ",\n") + "\n\(pad)}"
        }
        if let array = value as? [Any] {
            guard !array.isEmpty else { return "[]" }
            if array.allSatisfy({ !($0 is [String: Any]) && !($0 is [Any]) }) {
                return "[" + array.map { prettyJSON($0) }.joined(separator: ", ") + "]"
            }
            let lines = array.map { "\(childPad)\(prettyJSON($0, indent: indent + 1))" }
            return "[\n" + lines.joined(separator: ",\n") + "\n\(pad)]"
        }
        if let string = value as? String { return quoted(string) }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if let number = value as? NSNumber { return number.stringValue }
        return "null"
    }

    private static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
