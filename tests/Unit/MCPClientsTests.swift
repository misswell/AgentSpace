import XCTest
@testable import AgentSpaceCore

/// §384 — the scan that answers "can an AI client actually reach this desktop?".
///
/// The bug this suite pins: on 2026-10-12 an account reported `ready` / `usable` /
/// `permitsInput=true` while the client that had been asked to upgrade an app
/// answered "当前环境没有可用的 AgentSpace" and fell back to the human's own
/// session. Its `~/.codex/config.toml` still read `npx -y @agentspace/mcp`, and that
/// package has never been published, so the client had zero AgentSpace tools.
final class MCPClientsTests: XCTestCase {
    private var root: URL!
    private var binary: String!
    private var launcher: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("as-mcpclients-\(UUID())")
        let app = root.appendingPathComponent("App with spaces.app")
        launcher = app.appendingPathComponent("Contents/Resources/agentspace-mcp/launch.sh").path
        binary = app.appendingPathComponent("Contents/Helpers/agentspace").path
        for file in [launcher!, binary!] {
            try FileManager.default.createDirectory(atPath: (file as NSString).deletingLastPathComponent,
                                                    withIntermediateDirectories: true)
            try Data("#!/bin/bash\nexit 0\n".utf8).write(to: URL(fileURLWithPath: file))
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func verdict(_ text: String, for target: Integrations.Target,
                         path: [String] = []) -> MCPClients.Verdict {
        MCPClients.classify(data: Data(text.utf8), target: target, binaryPath: binary, path: path)
    }

    // MARK: - The bug

    /// The exact bytes the owner's machine carried (validation §384).
    func testTheStaleCodexBlockIsReportedAsUnpublishable() {
        let stale = """
        [mcp_servers.agentspace]
        command = "npx"
        args = ["-y", "@agentspace/mcp"]
        env = { AGENTSPACE_BIN = "\(binary!)" }
        """
        XCTAssertEqual(verdict(stale, for: .codex), .packageNeverPublished)

        // `npx` for a *published* package is a different thing, and must not be
        // reported as this failure: the scan only knows about @agentspace/mcp.
        let other = stale.replacingOccurrences(of: "@agentspace/mcp", with: "some-other-mcp")
        XCTAssertNotEqual(verdict(other, for: .codex), .packageNeverPublished)
    }

    /// Whatever the installer writes is what the scan must call `current` — for
    /// every client, in the file that client actually reads.
    func testEveryGeneratedConfigIsRecognisedAsCurrent() {
        for target in MCPClients.scannableTargets {
            let config = Integrations.config(for: target, binaryPath: binary)
            XCTAssertEqual(verdict(config, for: target), .current, "\(target.rawValue)")
        }
    }

    // MARK: - The other ways a registration is dead

    func testEntryPointingAtADeletedBundleIsReportedMissing() {
        let gone = root.appendingPathComponent("Uninstalled.app/Contents/Resources/agentspace-mcp/launch.sh").path
        let config = Integrations.config(for: .claudeCode, binaryPath: binary)
            .replacingOccurrences(of: launcher, with: gone)
        XCTAssertEqual(verdict(config, for: .claudeCode), .commandMissing(gone))
    }

    func testAnAgentCLIThatDoesNotExistIsReportedSeparately() {
        let goneCLI = root.appendingPathComponent("helpers/agentspace").path
        let config = Integrations.config(for: .codex, binaryPath: binary)
            .replacingOccurrences(of: binary, with: goneCLI)
        XCTAssertEqual(verdict(config, for: .codex), .agentCLIMissing(goneCLI))
    }

    /// A dev checkout's `node …/dist/index.js` is reachable when the script is
    /// there, and dead when it is not — the two answers a person needs.
    func testNodeRunnerIsJudgedOnItsEntryScript() throws {
        let script = root.appendingPathComponent("packages/agentspace-mcp/dist/index.js")
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("// entry\n".utf8).write(to: script)
        let config = """
        {"mcpServers":{"agentspace":{"command":"node","args":["\(script.path)"],"env":{"AGENTSPACE_BIN":"\(binary!)"}}}}
        """
        XCTAssertEqual(verdict(config, for: .claudeCode), .other("node"))

        try FileManager.default.removeItem(at: script)
        XCTAssertEqual(verdict(config, for: .claudeCode), .commandMissing("node"))
    }

    // MARK: - Absent, not broken

    func testNoEntryIsAbsent() {
        XCTAssertEqual(verdict(#"{"mcpServers":{"other":{"command":"keep"}}}"#, for: .claudeCode), .absent)
        XCTAssertEqual(MCPClients.classify(data: nil, target: .codex, binaryPath: binary), .absent)
    }

    /// Garbage that never mentions agentspace is absence; garbage that does is a
    /// shape the scan refuses to guess about. Reporting the second as "absent"
    /// would tell a user their client is unconfigured when it is not.
    func testUnreadableOnlyWhenTheFileMentionsAgentspace() {
        XCTAssertEqual(verdict("not json at all", for: .claudeCode), .absent)

        guard case .unreadable(let named) = verdict("not json, but it names agentspace somewhere",
                                                    for: .claudeCode) else {
            return XCTFail("a file that names agentspace cannot be reported as absent")
        }
        XCTAssertTrue(named.contains("Claude Code"), named)
        // An entry that is not even an object is a shape this scan will not guess
        // at; an entry that is an object without a command is the narrower case.
        guard case .unreadable(let malformed) = verdict(#"{"mcpServers":{"agentspace":"nonsense"}}"#,
                                                        for: .claudeCode) else {
            return XCTFail("an entry that is not an object has no state to report")
        }
        XCTAssertTrue(malformed.contains("expected format"), malformed)
        guard case .unreadable(let commandless) = verdict(#"{"mcpServers":{"agentspace":{"args":[]}}}"#,
                                                          for: .claudeCode) else {
            return XCTFail("an entry without a command has no state to report")
        }
        XCTAssertTrue(commandless.contains("no command"), commandless)
    }

    // MARK: - The four shapes

    func testOpenCodeArrayCommandShape() throws {
        let config = Integrations.config(for: .openCode, binaryPath: binary)
        XCTAssertEqual(verdict(config, for: .openCode), .current)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any])
        let server = try XCTUnwrap((root["mcp"] as? [String: Any])?["agentspace"] as? [String: Any])
        XCTAssertEqual(server["type"] as? String, "local")
        XCTAssertTrue(server["command"] is [String], "OpenCode takes argv as one array")
    }

    func testZCodeNestedShape() throws {
        let config = Integrations.config(for: .zcode, binaryPath: binary)
        XCTAssertEqual(verdict(config, for: .zcode), .current)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any])
        XCTAssertNotNil(((root["mcp"] as? [String: Any])?["servers"] as? [String: Any])?["agentspace"])
    }

    /// Each client is scanned through the key *it* reads. A working Claude-shaped
    /// entry is therefore not evidence that VS Code, Zed or Amp can see it: those
    /// clients read different roots, and reporting them reachable would send a
    /// person back to a client that still has no tools.
    func testEachShapeIsInvisibleToTheOthers() {
        let standard = Integrations.config(for: .claudeCode, binaryPath: binary)
        XCTAssertEqual(verdict(standard, for: .vsCode), .absent)
        XCTAssertEqual(verdict(standard, for: .zed), .absent)
        XCTAssertEqual(verdict(standard, for: .amp), .absent)
        XCTAssertEqual(verdict(standard, for: .zcode), .absent)

        let vsCode = Integrations.config(for: .vsCode, binaryPath: binary)
        XCTAssertEqual(verdict(vsCode, for: .claudeCode), .absent)
    }

    /// MiMo keeps `.jsonc`: comments and a trailing comma are legal there, so a
    /// strict parse would call a working configuration unreadable.
    func testMiMoJSONCIsRead() {
        let jsonc = """
        {
          // MiMo's own comment style
          "mcp": {
            "agentspace": {
              "type": "local",
              "command": ["\(launcher!)"],
              "environment": { "AGENTSPACE_BIN": "\(binary!)" },
              "enabled": true,
            },
          }
        }
        """
        XCTAssertEqual(verdict(jsonc, for: .mimoCode), .current)
    }

    /// A `//` inside a value is not a comment: stripping from the first `//` would
    /// eat the rest of the line and turn a readable config into a broken one.
    func testACommentMarkerInsideAValueSurvives() {
        let config = """
        {
          "mcpServers": {
            "agentspace": {
              "command": "\(launcher!)",
              "args": [],
              "env": { "AGENTSPACE_BIN": "\(binary!)", "NOTE": "https://example.com/x" }
            }
          }
        }
        """
        XCTAssertEqual(verdict(config, for: .claudeCode), .current)
    }

    // MARK: - The scan and its summary

    func testScanReadsEachClientsDocumentedPath() throws {
        let home = root.appendingPathComponent("home")
        for target in MCPClients.scannableTargets {
            let path = (home.path as NSString).appendingPathComponent(String(target.configPath.dropFirst(2)))
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                    withIntermediateDirectories: true)
            try Data(Integrations.config(for: target, binaryPath: binary).utf8).write(to: URL(fileURLWithPath: path))
        }
        let scanned = MCPClients.scan(home: home.path, binaryPath: binary)
        XCTAssertEqual(scanned.count, MCPClients.scannableTargets.count)
        for registration in scanned {
            XCTAssertEqual(registration.verdict, .current, registration.target.rawValue)
            let expected = (home.path as NSString)
                .appendingPathComponent(String(registration.target.configPath.dropFirst(2)))
            XCTAssertEqual(registration.path, expected)
        }
    }

    func testSummarySeparatesReachableFromBroken() throws {
        let home = root.appendingPathComponent("home2")
        let codex = (home.path as NSString).appendingPathComponent(".codex/config.toml")
        let claude = (home.path as NSString).appendingPathComponent(".claude.json")
        try FileManager.default.createDirectory(atPath: (codex as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try Data("""
        [mcp_servers.agentspace]
        command = "npx"
        args = ["-y", "@agentspace/mcp"]
        env = { AGENTSPACE_BIN = "\(binary!)" }
        """.utf8).write(to: URL(fileURLWithPath: codex))
        try Data(Integrations.config(for: .claudeCode, binaryPath: binary).utf8)
            .write(to: URL(fileURLWithPath: claude))

        let summary = MCPClients.summary(home: home.path, binaryPath: binary)
        XCTAssertEqual(summary.reachable.map(\.target), [.claudeCode])
        XCTAssertEqual(summary.broken.map(\.target), [.codex])
        XCTAssertEqual(MCPClients.repairCommand(for: .codex), "agentspace integrate codex --install")
    }
}
