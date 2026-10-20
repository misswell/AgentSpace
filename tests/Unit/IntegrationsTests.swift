import XCTest
@testable import AgentSpaceCore

/// MCP configuration generation and merging (plan §34).
///
/// The generated text is checked by *parsing it*, not by comparing strings: a
/// snippet that looks right but fails to parse is worse than none, because the user
/// discovers it only after their client refuses to start. Each shape below is a
/// different published schema — VS Code's `servers`, Zed's `context_servers`,
/// Amp's `amp.mcpServers`, Crush's `mcp` — so each is pinned by the keys its client
/// actually reads.
final class IntegrationsTests: XCTestCase {

    /// A path with a space in it, because app bundles can live anywhere and a
    /// quoting bug here produces a config that works on the developer's machine
    /// and nobody else's.
    private let binaryPath = "/Applications/My Apps/AgentSpace.app/Contents/Helpers/agentspace"

    private func root(_ target: Integrations.Target) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(Integrations.config(for: target, binaryPath: binaryPath).utf8)) as? [String: Any])
    }

    private func entry(_ target: Integrations.Target) throws -> [String: Any] {
        var cursor: Any? = try root(target)
        for key in keys(for: target) {
            cursor = (cursor as? [String: Any])?[key]
        }
        return try XCTUnwrap(cursor as? [String: Any], "\(target) lost its entry")
    }

    private func keys(for target: Integrations.Target) -> [String] {
        switch target.shape {
        case .plain, .miniMax: return ["mcpServers", "agentspace"]
        case .vsCode: return ["servers", "agentspace"]
        case .zed: return ["context_servers", "agentspace"]
        case .amp: return ["amp.mcpServers", "agentspace"]
        case .openCode, .crush: return ["mcp", "agentspace"]
        case .zcode: return ["mcp", "servers", "agentspace"]
        case .toml: return []
        }
    }

    // MARK: - Generation

    func testClaudeCodeConfigParsesAsJSONAndCarriesTheBinary() throws {
        let server = try entry(.claudeCode)
        XCTAssertEqual(server["command"] as? String, "npx")
        XCTAssertEqual(server["args"] as? [String], ["-y", "@agentspace/mcp"])
        XCTAssertEqual((server["env"] as? [String: String])?["AGENTSPACE_BIN"], binaryPath,
                       "the space in the path did not survive quoting")
    }

    func testOpenCodeConfigUsesOpenCodesShape() throws {
        let server = try entry(.openCode)
        // OpenCode takes an argv array and its own key for environment variables.
        // Getting this wrong produces a config the client silently ignores — the
        // server just never appears — which is why it is pinned here.
        XCTAssertEqual(server["type"] as? String, "local")
        XCTAssertEqual(server["command"] as? [String], ["npx", "-y", "@agentspace/mcp"])
        XCTAssertEqual((server["environment"] as? [String: String])?["AGENTSPACE_BIN"], binaryPath)
        XCTAssertEqual(server["enabled"] as? Bool, true)
    }

    func testZCodeConfigNestsUnderMcpServersWithStrictFields() throws {
        // Measured against the installed ZCode: its user config nests servers
        // under `mcp.servers`, and its schema is strict — an unknown key drops
        // the whole server, so exactly the documented fields are emitted.
        let server = try entry(.zcode)
        XCTAssertEqual(server["type"] as? String, "stdio")
        XCTAssertEqual(server["command"] as? String, "npx", "ZCode wants a scalar command, not an argv array")
        XCTAssertEqual(server["args"] as? [String], ["-y", "@agentspace/mcp"])
        XCTAssertEqual((server["env"] as? [String: String])?["AGENTSPACE_BIN"], binaryPath)
        XCTAssertEqual(server["enabled"] as? Bool, true)
        let zcodeRoot = try root(.zcode)
        XCTAssertNil(zcodeRoot["mcpServers"], "ZCode does not read the top-level mcpServers key")
    }

    func testKimiCodeConfigUsesTheStandardMcpServersShape() throws {
        // Measured against the installed Kimi Code: ~/.kimi-code/mcp.json carries
        // a top-level mcpServers object whose entries are claude-shaped.
        let server = try entry(.kimiCode)
        XCTAssertEqual(server["command"] as? String, "npx")
        XCTAssertEqual(server["args"] as? [String], ["-y", "@agentspace/mcp"])
        XCTAssertEqual((server["env"] as? [String: String])?["AGENTSPACE_BIN"], binaryPath)
    }

    func testMiMoConfigReusesOpenCodesShape() throws {
        // Measured against the installed Xiaomi MiMo (mimocode): its own config
        // carries `mcp` with `type: "local"` argv entries, exactly like OpenCode.
        let server = try entry(.mimoCode)
        XCTAssertEqual(server["type"] as? String, "local")
        XCTAssertEqual(server["command"] as? [String], ["npx", "-y", "@agentspace/mcp"])
        XCTAssertEqual((server["environment"] as? [String: String])?["AGENTSPACE_BIN"], binaryPath)
        XCTAssertEqual(server["enabled"] as? Bool, true)
    }

    func testVSCodeUsesItsOwnTopLevelServersKey() throws {
        // VS Code 1.99+ reads `servers`, not `mcpServers`; a wrong root key is
        // silently ignored, which looks exactly like "the server never starts".
        let server = try entry(.vsCode)
        XCTAssertEqual(server["type"] as? String, "stdio", "VS Code requires an explicit transport type")
        XCTAssertEqual(server["command"] as? String, "npx")
        XCTAssertEqual(server["command"] as? String, "npx")
        XCTAssertEqual((server["env"] as? [String: String])?["AGENTSPACE_BIN"], binaryPath)
        let vsCodeRoot = try root(.vsCode)
        XCTAssertNil(vsCodeRoot["mcpServers"])
    }

    func testZedUsesContextServersWithSourceCustom() throws {
        let server = try entry(.zed)
        XCTAssertEqual(server["source"] as? String, "custom", "Zed drops context servers without source=custom")
        XCTAssertEqual(server["command"] as? String, "npx")
        XCTAssertEqual((server["env"] as? [String: String])?["AGENTSPACE_BIN"], binaryPath)
    }

    func testAmpUsesTheDottedSettingsKey() throws {
        let data = try root(.amp)
        XCTAssertNotNil((data["amp.mcpServers"] as? [String: Any])?["agentspace"])
        XCTAssertNil(data["mcpServers"], "Amp reads its own dotted settings key, not the generic one")
        let server = try entry(.amp)
        XCTAssertEqual(server["command"] as? String, "npx")
    }

    func testCrushUsesItsMcpObjectWithAScalarCommand() throws {
        let server = try entry(.crush)
        XCTAssertEqual(server["type"] as? String, "stdio")
        XCTAssertEqual(server["command"] as? String, "npx", "Crush splits command and args")
        XCTAssertEqual(server["args"] as? [String], ["-y", "@agentspace/mcp"])
        XCTAssertEqual((server["env"] as? [String: String])?["AGENTSPACE_BIN"], binaryPath)
    }

    func testMiniMaxKeepsTypeAndEnabled() throws {
        let server = try entry(.minimax)
        XCTAssertEqual(server["type"] as? String, "stdio")
        XCTAssertEqual(server["enabled"] as? Bool, true, "MiniMax lists a disabled server nowhere")
        XCTAssertEqual((server["env"] as? [String: String])?["AGENTSPACE_BIN"], binaryPath)
    }

    func testCodexConfigIsTheRightTOMLShape() throws {
        let text = Integrations.config(for: .codex, binaryPath: binaryPath)
        XCTAssertTrue(text.hasPrefix("[mcp_servers.agentspace]"), text)
        XCTAssertTrue(text.contains("command = \"npx\""))
        XCTAssertTrue(text.contains("env = { AGENTSPACE_BIN = \"\(binaryPath)\" }"),
                      "the TOML inline table did not quote the path")
        // Header plus three keys, one per line, nothing else — TOML has no
        // comments here to drift out of date.
        XCTAssertEqual(text.split(separator: "\n").count, 4)
    }

    func testEveryTargetMentionsTheBinaryOnlyThroughAGENTSPACE_BIN() throws {
        // The env var is the mechanism; a path baked anywhere else would bypass the
        // TCC identity the variable exists to pin.
        for target in Integrations.Target.allCases {
            let text = Integrations.config(for: target, binaryPath: binaryPath)
            XCTAssertTrue(text.contains("AGENTSPACE_BIN"), "\(target) lost the env var")
            XCTAssertEqual(text.components(separatedBy: binaryPath).count - 1, 1,
                           "\(target) mentions the binary path \(text.components(separatedBy: binaryPath).count - 1) times")
        }
    }

    /// The list is the feature: a client in the menu must have a file to write,
    /// and the copy-only target must be the only one without.
    func testEveryListedClientHasAConfigPath() {
        XCTAssertEqual(Integrations.installableTargets.count,
                       Integrations.Target.allCases.count - 1)
        XCTAssertFalse(Integrations.installableTargets.contains(.generic))
        XCTAssertTrue(Integrations.Target.generic.configPath.isEmpty)
    }

    /// The menu is built by filtering the installable list per category. A target
    /// whose category nobody renders would vanish from "Install MCP Into…" with
    /// no build failure, so the partition is pinned: every group has members and
    /// the groups add up to the whole list exactly once.
    func testEveryInstallableClientAppearsInExactlyOneMenuCategory() {
        let groups = Integrations.Target.Category.allCases.map { category in
            Integrations.installableTargets.filter { $0.category == category }
        }
        XCTAssertEqual(groups.count, 4)
        for (category, members) in zip(Integrations.Target.Category.allCases, groups) {
            XCTAssertFalse(members.isEmpty, "\(category) would render an empty menu section")
        }
        XCTAssertEqual(groups.reduce(0) { $0 + $1.count },
                       Integrations.installableTargets.count,
                       "a target is missing from the menu or listed twice")
    }

    /// Two clients that share a display name are indistinguishable in the menu,
    /// and two that share a file would overwrite each other's entry.
    func testClientNamesAndConfigFilesAreUnique() {
        let names = Integrations.installableTargets.map(\.displayName)
        XCTAssertFalse(names.contains(where: \.isEmpty))
        XCTAssertEqual(Set(names).count, names.count, "duplicate display name in the menu")
        let paths = Integrations.installableTargets.map(\.configPath)
        XCTAssertEqual(Set(paths).count, paths.count, "two clients claim the same config file")
    }

    // MARK: - JSON merging

    func testMergingIntoAnAbsentFileCreatesAMinimalOne() throws {
        let merged = try JSONSerialization.jsonObject(with: try Integrations.merge(
            existing: nil, target: .claudeCode, binaryPath: binaryPath)) as? [String: Any]
        XCTAssertNotNil((merged?["mcpServers"] as? [String: Any])?["agentspace"])
        XCTAssertEqual(merged?.count, 1, "a fresh file gained keys it should not have")
    }

    func testMergingIntoAnEmptyObjectIsAllowed() throws {
        // `{}` is a valid, empty config — unlike an array, there is nothing to
        // damage by adding the one key.
        let merged = try JSONSerialization.jsonObject(with: try Integrations.merge(
            existing: Data("{}".utf8), target: .cursor, binaryPath: binaryPath)) as? [String: Any]
        XCTAssertNotNil((merged?["mcpServers"] as? [String: Any])?["agentspace"])
    }

    func testMergingPreservesEverythingElseInTheFile() throws {
        // The whole point of merging rather than writing: the user's other MCP
        // servers and preferences must survive byte-for-byte in value.
        let existing = """
        {
          "mcpServers": {
            "other": { "command": "uvx", "args": ["something-else"] }
          },
          "theme": "dark",
          "projects": { "/tmp/x": { "allowedTools": ["Bash"] } }
        }
        """
        let merged = try JSONSerialization.jsonObject(with: try Integrations.merge(
            existing: Data(existing.utf8), target: .claudeCode, binaryPath: binaryPath)) as? [String: Any]

        XCTAssertEqual(merged?["theme"] as? String, "dark")
        XCTAssertEqual((merged?["projects"] as? [String: Any])?.count, 1)
        let other = try XCTUnwrap((merged?["mcpServers"] as? [String: Any])?["other"] as? [String: Any])
        XCTAssertEqual(other["command"] as? String, "uvx", "another server's entry was damaged")
        XCTAssertNotNil((merged?["mcpServers"] as? [String: Any])?["agentspace"])
    }

    func testReRunningTheMergeIsIdempotentForEveryClient() throws {
        for target in Integrations.installableTargets {
            let once = try Integrations.merge(existing: nil, target: target, binaryPath: binaryPath)
            let twice = try Integrations.merge(existing: once, target: target, binaryPath: binaryPath)
            if target.shape == .toml {
                XCTAssertEqual(once, twice, "\(target): running the install twice changed the file")
            } else {
                let a = try XCTUnwrap(JSONSerialization.jsonObject(with: once) as? NSDictionary)
                let b = try XCTUnwrap(JSONSerialization.jsonObject(with: twice) as? NSDictionary)
                XCTAssertEqual(a, b, "\(target): running the install twice changed the file")
                // And the entry did not nest inside itself.
                XCTAssertEqual(a.count, 1, "\(target): a fresh file gained keys it should not have")
            }
        }
    }

    func testMergingIntoAFileThatIsNotAnObjectRefuses() throws {
        // Appending a key to, say, a JSON array would corrupt a file we do not
        // understand. Refusing and saying so is the only safe answer.
        XCTAssertThrowsError(try Integrations.merge(
            existing: Data("[1,2,3]".utf8), target: .claudeCode, binaryPath: binaryPath))
    }

    func testJSONCCommentsAreRefusedRatherThanDropped() throws {
        // Zed and VS Code legally allow `//` comments. Parsing and rewriting the
        // file would silently delete them, so the install refuses instead.
        let jsonc = """
        {
          // my editor theme
          "theme": "dark"
        }
        """
        XCTAssertThrowsError(try Integrations.merge(
            existing: Data(jsonc.utf8), target: .zed, binaryPath: binaryPath))
    }

    func testZCodeMergeBuildsTheNestedObjectAndPreservesSiblings() throws {
        // The real ZCode user config starts life carrying only `plugins`; it must
        // survive the merge, and a second run must not nest the object in itself.
        let existing = Data("{ \"plugins\": { \"enabled\": true } }".utf8)
        let once = try Integrations.merge(existing: existing, target: .zcode, binaryPath: binaryPath)
        let merged = try JSONSerialization.jsonObject(with: once) as? [String: Any]
        XCTAssertEqual((merged?["plugins"] as? [String: Any])?["enabled"] as? Bool, true)
        let serversOnce = try XCTUnwrap(((merged?["mcp"] as? [String: Any])?["servers"] as? [String: Any]))
        XCTAssertNotNil(serversOnce["agentspace"])

        let twice = try JSONSerialization.jsonObject(with: try Integrations.merge(
            existing: once, target: .zcode, binaryPath: binaryPath)) as? [String: Any]
        let servers = try XCTUnwrap(((twice?["mcp"] as? [String: Any])?["servers"] as? [String: Any]))
        XCTAssertEqual(servers.count, 1)
    }

    func testMiMoMergePreservesTheSchemaKeyTheirToolWrites() throws {
        // The installed MiMo writes a `$schema` key next to `mcp`; losing it would
        // strip the file of its validation anchor, and their own entries must
        // survive untouched.
        let existing = Data("""
        { "$schema": "https://mimo.xiaomi.com/mimocode/config.json",
          "mcp": { "node_repl": { "type": "local", "command": ["/bin/repl"], "enabled": false } } }
        """.utf8)
        let merged = try JSONSerialization.jsonObject(with: try Integrations.merge(
            existing: existing, target: .mimoCode, binaryPath: binaryPath)) as? [String: Any]
        XCTAssertEqual(merged?["$schema"] as? String, "https://mimo.xiaomi.com/mimocode/config.json")
        let nodeRepl = try XCTUnwrap(((merged?["mcp"] as? [String: Any])?["node_repl"] as? [String: Any]))
        XCTAssertEqual(nodeRepl["enabled"] as? Bool, false, "another server's entry was damaged")
        XCTAssertNotNil(((merged?["mcp"] as? [String: Any])?["agentspace"]))
    }

    func testVSCodeMergePreservesInputsAndOtherServers() throws {
        // VS Code's file carries `inputs` for secrets and other servers; both are
        // outside AgentSpace's key and must survive.
        let existing = Data("""
        {
          "inputs": [{ "id": "token", "type": "promptString", "password": true }],
          "servers": { "other": { "type": "http", "url": "https://example.com/mcp" } }
        }
        """.utf8)
        let merged = try JSONSerialization.jsonObject(with: try Integrations.merge(
            existing: existing, target: .vsCode, binaryPath: binaryPath)) as? [String: Any]
        XCTAssertEqual((merged?["inputs"] as? [[String: Any]])?.count, 1)
        XCTAssertNotNil(((merged?["servers"] as? [String: Any])?["other"]))
        XCTAssertNotNil(((merged?["servers"] as? [String: Any])?["agentspace"]))
    }

    func testZedMergePreservesOtherSettings() throws {
        let existing = Data("""
        { "theme": "One Dark", "context_servers": { "other": { "source": "custom", "command": "x" } } }
        """.utf8)
        let merged = try JSONSerialization.jsonObject(with: try Integrations.merge(
            existing: existing, target: .zed, binaryPath: binaryPath)) as? [String: Any]
        XCTAssertEqual(merged?["theme"] as? String, "One Dark")
        let servers = try XCTUnwrap(merged?["context_servers"] as? [String: Any])
        XCTAssertNotNil(servers["other"])
        XCTAssertNotNil(servers["agentspace"])
    }

    // MARK: - TOML merging

    func testTOMLInstallAppendsWhenAbsent() throws {
        let existing = Data("# codex config\nmodel = \"gpt-5\"\n".utf8)
        let merged = String(decoding: try Integrations.mergeTOMLConfig(existing: existing, binaryPath: binaryPath), as: UTF8.self)
        XCTAssertTrue(merged.hasPrefix("# codex config"), "the existing file was not kept first")
        XCTAssertTrue(merged.contains("model = \"gpt-5\""))
        XCTAssertTrue(merged.contains("[mcp_servers.agentspace]"))
        // Exactly one table, appended at the end.
        XCTAssertEqual(merged.components(separatedBy: "[mcp_servers.agentspace]").count - 1, 1)
    }

    func testTOMLInstallIsIdempotent() throws {
        let once = try Integrations.mergeTOMLConfig(existing: nil, binaryPath: binaryPath)
        let twice = try Integrations.mergeTOMLConfig(existing: once, binaryPath: binaryPath)
        XCTAssertEqual(String(decoding: once, as: UTF8.self), String(decoding: twice, as: UTF8.self),
                       "running the install twice changed the file")
    }

    func testTOMLInstallRefusesADifferentExistingBlockRatherThanEditingIt() throws {
        // The user configured something else under our name — a different command,
        // a wrapper script. Overwriting it silently would look like AgentSpace
        // broke their setup, so this is a refusal with a fix, not an edit.
        let existing = Data("[mcp_servers.agentspace]\ncommand = \"my-wrapper\"\n".utf8)
        XCTAssertThrowsError(try Integrations.mergeTOMLConfig(existing: existing, binaryPath: binaryPath)) { error in
            guard case Integrations.InstallError.conflictingEntry = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
    }

    // MARK: - Agent rules (§35)

    func testTheRulesStateThePreferencePolicy() throws {
        // These lines are plan §35 restated as the owner's preference policy
        // (2026-09-29): prefer AgentSpace, report, and only fall back out loud.
        // Each is asserted by its distinctive phrase so a rewording that quietly
        // weakens one of them fails here rather than shipping.
        let rules = Integrations.agentRules()
        XCTAssertTrue(rules.contains("优先使用 AgentSpace"), rules)
        XCTAssertTrue(rules.contains("agentspace_*"), "the rule must route the agent to the tools, not only forbid: \(rules)")
        XCTAssertTrue(rules.contains("不要在用户当前会话中直接启动 GUI 应用"), rules)
        XCTAssertTrue(rules.contains("把问题报告给用户"), rules)
        XCTAssertTrue(rules.contains("才回退到用户当前会话执行，并明确告知用户"), rules)
    }

    func testTheSectionIsMarkedSoInstallsAreIdempotent() throws {
        let section = Integrations.agentRulesSection()
        XCTAssertTrue(section.contains(Integrations.agentRulesMarkerBegin))
        XCTAssertTrue(section.contains(Integrations.agentRulesMarkerEnd))
        // Idempotence is what makes "install" safe to press twice: the second run
        // must be a no-op, not a second copy of the rules.
        let once = Integrations.mergeAgentRules(existing: nil)
        let twice = Integrations.mergeAgentRules(existing: once)
        XCTAssertEqual(String(decoding: once, as: UTF8.self), String(decoding: twice, as: UTF8.self))
        XCTAssertEqual(String(decoding: twice, as: UTF8.self).components(separatedBy: "## AgentSpace").count - 1, 1)
    }

    func testInstallingRulesAppendsAndPreservesTheUsersOwnText() throws {
        let existing = Data("# My project\n\nAlways run the full test suite before committing.\n".utf8)
        let merged = String(decoding: Integrations.mergeAgentRules(existing: existing), as: UTF8.self)

        XCTAssertTrue(merged.hasPrefix("# My project"), "the user's text must stay first")
        XCTAssertTrue(merged.contains("Always run the full test suite before committing."),
                      "the user's own instruction was lost")
        XCTAssertTrue(merged.contains("优先使用 AgentSpace"))

        // And an already-marked file is returned untouched — no reformatting of
        // the user's own writing.
        let again = String(decoding: Integrations.mergeAgentRules(existing: Data(merged.utf8)), as: UTF8.self)
        XCTAssertEqual(again, merged)
    }

    // MARK: - The default path

    func testTheDefaultPathIsTheShippedCLINotANonexistentOne() throws {
        // This test runs from the test bundle, not the app, so the exact answer
        // depends on the host. What must hold everywhere is that the answer exists
        // and is executable — the regression being pinned is the one where the GUI
        // copied `Contents/MacOS/agentspace`, a file the bundle has never had.
        let path = try XCTUnwrap(Integrations.defaultBinaryPath())
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path), path)
        XCTAssertFalse(path.hasSuffix("Contents/MacOS/agentspace"),
                       "the CLI does not ship there; this path cannot run")
    }

    func testInstructionsNameTheFileForEveryInstallableTarget() throws {
        for target in Integrations.installableTargets {
            let text = Integrations.instructions(for: target, binaryPath: binaryPath)
            XCTAssertTrue(text.contains(target.configPath), "\(target): \(text)")
        }
    }
}
