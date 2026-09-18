import XCTest
@testable import AgentSpaceCore

/// MCP configuration generation and merging (plan §34).
///
/// The generated text is checked by *parsing it*, not by comparing strings: a
/// snippet that looks right but fails to parse is worse than none, because the user
/// discovers it only after their client refuses to start.
final class IntegrationsTests: XCTestCase {

    /// A path with a space in it, because app bundles can live anywhere and a
    /// quoting bug here produces a config that works on the developer's machine
    /// and nobody else's.
    private let binaryPath = "/Applications/My Apps/AgentSpace.app/Contents/Helpers/agentspace"

    // MARK: - Generation

    func testClaudeCodeConfigParsesAsJSONAndCarriesTheBinary() throws {
        let data = try JSONSerialization.jsonObject(with: Data(
            Integrations.config(for: .claudeCode, binaryPath: binaryPath).utf8)) as? [String: Any]
        let server = try XCTUnwrap((data?["mcpServers"] as? [String: Any])?["agentspace"] as? [String: Any])
        XCTAssertEqual(server["command"] as? String, "npx")
        XCTAssertEqual(server["args"] as? [String], ["-y", "@agentspace/mcp"])
        XCTAssertEqual((server["env"] as? [String: String])?["AGENTSPACE_BIN"], binaryPath,
                       "the space in the path did not survive quoting")
    }

    func testOpenCodeConfigUsesOpenCodesShape() throws {
        let data = try JSONSerialization.jsonObject(with: Data(
            Integrations.config(for: .openCode, binaryPath: binaryPath).utf8)) as? [String: Any]
        let server = try XCTUnwrap((data?["mcp"] as? [String: Any])?["agentspace"] as? [String: Any])
        // OpenCode takes an argv array and its own key for environment variables.
        // Getting this wrong produces a config the client silently ignores — the
        // server just never appears — which is why it is pinned here.
        XCTAssertEqual(server["type"] as? String, "local")
        XCTAssertEqual(server["command"] as? [String], ["npx", "-y", "@agentspace/mcp"])
        XCTAssertEqual((server["environment"] as? [String: String])?["AGENTSPACE_BIN"], binaryPath)
        XCTAssertEqual(server["enabled"] as? Bool, true)
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

    // MARK: - JSON merging

    func testMergingIntoAnAbsentFileCreatesAMinimalOne() throws {
        let merged = try JSONSerialization.jsonObject(with: try Integrations.mergeJSONConfig(
            existing: nil, rootKey: "mcpServers", binaryPath: binaryPath)) as? [String: Any]
        XCTAssertNotNil((merged?["mcpServers"] as? [String: Any])?["agentspace"])
        XCTAssertEqual(merged?.count, 1, "a fresh file gained keys it should not have")
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
        let merged = try JSONSerialization.jsonObject(with: try Integrations.mergeJSONConfig(
            existing: Data(existing.utf8), rootKey: "mcpServers", binaryPath: binaryPath)) as? [String: Any]

        XCTAssertEqual(merged?["theme"] as? String, "dark")
        XCTAssertEqual((merged?["projects"] as? [String: Any])?.count, 1)
        let other = try XCTUnwrap((merged?["mcpServers"] as? [String: Any])?["other"] as? [String: Any])
        XCTAssertEqual(other["command"] as? String, "uvx", "another server's entry was damaged")
        XCTAssertNotNil((merged?["mcpServers"] as? [String: Any])?["agentspace"])
    }

    func testReRunningTheMergeIsIdempotent() throws {
        let once = try Integrations.mergeJSONConfig(existing: nil, rootKey: "mcpServers", binaryPath: binaryPath)
        let twice = try Integrations.mergeJSONConfig(existing: once, rootKey: "mcpServers", binaryPath: binaryPath)
        let a = try JSONSerialization.jsonObject(with: once) as? [String: Any]
        let b = try JSONSerialization.jsonObject(with: twice) as? [String: Any]
        XCTAssertEqual(a?.count, b?.count)
        // And the entry did not nest inside itself.
        let servers = try XCTUnwrap(b?["mcpServers"] as? [String: Any])
        XCTAssertEqual(servers.count, 1)
    }

    func testMergingIntoAFileThatIsNotAnObjectRefuses() throws {
        // Appending a key to, say, a JSON array would corrupt a file we do not
        // understand. Refusing and saying so is the only safe answer.
        XCTAssertThrowsError(try Integrations.mergeJSONConfig(
            existing: Data("[1,2,3]".utf8), rootKey: "mcpServers", binaryPath: binaryPath))
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
        for target in [Integrations.Target.claudeCode, .codex, .openCode] {
            let text = Integrations.instructions(for: target, binaryPath: binaryPath)
            XCTAssertFalse(target.configPath.isEmpty)
            XCTAssertTrue(text.contains(target.configPath), "\(target): \(text)")
        }
    }
}
