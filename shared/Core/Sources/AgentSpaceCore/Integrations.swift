import Foundation

/// One-click MCP configuration for the clients AgentSpace supports — plan §34.
///
/// The MCP server (`@agentspace/mcp`) is the same for every client; what differs is
/// the shape of each client's configuration file and where it lives. This module is
/// the single source of that truth, so the GUI's "Install MCP", the CLI's
/// `agentspace integrate` and this module's tests cannot drift apart.
///
/// Deliberately **not** a general config-file editor. Each merge below touches only
/// the one key AgentSpace owns (`mcpServers.agentspace`, `mcp.agentspace`,
/// `mcp.servers.agentspace`, `[mcp_servers.agentspace]`) and preserves everything
/// else, and the TOML path refuses rather than parsing, because shipping a TOML
/// parser to append one table is a way to corrupt a user's config file subtly
/// instead of obviously.
public enum Integrations {

    public enum Target: String, CaseIterable {
        case claudeCode = "claude"
        case codex = "codex"
        case openCode = "opencode"
        case zcode = "zcode"
        /// Kimi Code keeps its MCP servers in a dedicated `mcp.json`.
        case kimiCode = "kimi"
        /// Xiaomi MiMo (mimocode) is OpenCode-shaped but lives in its own directory.
        case mimoCode = "mimo"
        /// The shape most other clients accept (`mcpServers` at the top level).
        case generic = "generic"

        public var displayName: String {
            switch self {
            case .claudeCode: return "Claude Code"
            case .codex: return "Codex"
            case .openCode: return "OpenCode"
            case .zcode: return "ZCode"
            case .kimiCode: return "Kimi Code"
            case .mimoCode: return "Xiaomi MiMo"
            case .generic: return "Other MCP clients"
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
        public var configPath: String {
            switch self {
            case .claudeCode: return "~/.claude.json"
            case .codex: return "~/.codex/config.toml"
            case .openCode: return "~/.config/opencode/opencode.json"
            case .zcode: return "~/.zcode/cli/config.json"
            case .kimiCode: return "~/.kimi-code/mcp.json"
            case .mimoCode: return "~/.config/mimocode/mimocode.jsonc"
            case .generic: return ""
            }
        }
    }

    // MARK: - Generation

    /// The launch command for the MCP server: Node, this package, and which
    /// `agentspace` binary to drive.
    ///
    /// `AGENTSPACE_BIN` is not optional. The MCP server must run *this* install's
    /// CLI — a different copy of the binary would be a different TCC identity, so
    /// permissions granted to one would not apply to the other.
    public static func config(for target: Target, binaryPath: String) -> String {
        switch target {
        case .claudeCode, .kimiCode, .generic:
            return """
            {
              "mcpServers": {
                "agentspace": {
                  "command": "npx",
                  "args": ["-y", "@agentspace/mcp"],
                  "env": { "AGENTSPACE_BIN": \(quoted(binaryPath)) }
                }
              }
            }
            """
        case .codex:
            // TOML. `env` is an inline table; the path is a basic string, which
            // needs no escapes beyond the quotes because a bundle path cannot
            // contain one.
            return """
            [mcp_servers.agentspace]
            command = "npx"
            args = ["-y", "@agentspace/mcp"]
            env = { AGENTSPACE_BIN = \(quoted(binaryPath)) }
            """
        case .openCode, .mimoCode:
            return """
            {
              "mcp": {
                "agentspace": {
                  "type": "local",
                  "command": ["npx", "-y", "@agentspace/mcp"],
                  "environment": { "AGENTSPACE_BIN": \(quoted(binaryPath)) },
                  "enabled": true
                }
              }
            }
            """
        case .zcode:
            // ZCode's schema is strict — an unknown key drops the whole server —
            // and its servers nest one level deeper than the other JSON clients.
            // `type` and `enabled` are spelled out because the desktop client's
            // Settings → MCP page reads this file with less inference than the CLI.
            return """
            {
              "mcp": {
                "servers": {
                  "agentspace": {
                    "type": "stdio",
                    "command": "npx",
                    "args": ["-y", "@agentspace/mcp"],
                    "env": { "AGENTSPACE_BIN": \(quoted(binaryPath)) },
                    "enabled": true
                  }
                }
              }
            }
            """
        }
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
        case .openCode:
            return """
            Merge the "agentspace" entry below into the "mcp" object of \(Target.openCode.configPath),
            then restart OpenCode.
            """
        case .zcode:
            return """
            Merge the "agentspace" entry below into the "mcp.servers" object of \(Target.zcode.configPath),
            then restart the session. ZCode's schema is strict: keep exactly the keys shown.
            """
        case .kimiCode:
            return """
            Merge the "agentspace" entry below into the "mcpServers" object of \(Target.kimiCode.configPath),
            then restart Kimi Code.
            """
        case .mimoCode:
            return """
            Merge the "agentspace" entry below into the "mcp" object of \(Target.mimoCode.configPath),
            then restart MiMo.
            """
        case .generic:
            return """
            Merge the "agentspace" entry below into your client's "mcpServers" object.
            """
        }
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
    public static func mergeJSONConfig(
        existing: Data?,
        rootKey: String,
        binaryPath: String
    ) throws -> Data {
        var root: [String: Any] = existing.flatMap {
            (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
        } ?? [:]

        if existing != nil && root.isEmpty {
            // The file exists but is not an object. Refusing beats appending a key
            // to a file whose shape we do not understand.
            throw InstallError.unreadable(path: "(config)", "not a JSON object")
        }

        let entry: [String: Any] = [
            "command": "npx",
            "args": ["-y", "@agentspace/mcp"],
            "env": ["AGENTSPACE_BIN": binaryPath],
        ]

        switch rootKey {
        case "mcpServers":
            var servers = root["mcpServers"] as? [String: Any] ?? [:]
            servers["agentspace"] = entry
            root["mcpServers"] = servers
        case "mcp":
            var servers = root["mcp"] as? [String: Any] ?? [:]
            // OpenCode (and Xiaomi MiMo, which shares the shape) carry a type and
            // use an argv array.
            servers["agentspace"] = [
                "type": "local",
                "command": ["npx", "-y", "@agentspace/mcp"],
                "environment": ["AGENTSPACE_BIN": binaryPath],
                "enabled": true,
            ]
            root["mcp"] = servers
        case "mcp.servers":
            // ZCode nests one level deeper and its schema is strict: exactly the
            // fields it documents, with `type` spelled out.
            var mcp = root["mcp"] as? [String: Any] ?? [:]
            var servers = mcp["servers"] as? [String: Any] ?? [:]
            servers["agentspace"] = [
                "type": "stdio",
                "command": "npx",
                "args": ["-y", "@agentspace/mcp"],
                "env": ["AGENTSPACE_BIN": binaryPath],
                "enabled": true,
            ]
            mcp["servers"] = servers
            root["mcp"] = mcp
        default:
            throw InstallError.unreadable(path: "(config)", "unknown root key \(rootKey)")
        }

        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
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

    private static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
