import XCTest
import AgentSpaceCore

final class BundledMCPTests: XCTestCase {
    private func withBundle(_ body: (String, String) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("as-mcp-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("App with spaces.app")
        let launcher = app.appendingPathComponent("Contents/Resources/agentspace-mcp/launch.sh")
        try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/bash\nexit 0\n".utf8).write(to: launcher)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        try body(app.appendingPathComponent("Contents/Helpers/agentspace").path, launcher.path)
    }

    func testBundleConfigUsesItsOwnServiceForEveryClient() throws {
        try withBundle { binary, launcher in
            let launch = Integrations.mcpLaunch(binaryPath: binary)
            XCTAssertEqual(launch.command, launcher)
            XCTAssertEqual(launch.args, [])
            for target in Integrations.Target.allCases {
                let config = Integrations.config(for: target, binaryPath: binary)
                XCTAssertTrue(config.contains(launcher), "\(target)")
                XCTAssertFalse(config.contains("@agentspace/mcp"), "\(target)")
                XCTAssertTrue(config.contains(binary), "\(target)")
            }
        }
    }

    func testUpgradeOnlyReplacesTheKnownGeneratedTOMLBlock() throws {
        try withBundle { binary, _ in
            let legacy = """
            [mcp_servers.agentspace]
            command = "npx"
            args = ["-y", "@agentspace/mcp"]
            env = { AGENTSPACE_BIN = "\(binary)" }
            """
            let before = "model = \"keep\"\n\n" + legacy + "\n\n[mcp_servers.other]\ncommand = \"keep\"\n"
            let after = try Integrations.mergeTOMLConfig(existing: Data(before.utf8), binaryPath: binary)
            let expected = before.replacingOccurrences(of: legacy, with: Integrations.config(for: .codex, binaryPath: binary))
            XCTAssertEqual(String(decoding: after, as: UTF8.self), expected)
            XCTAssertEqual(try Integrations.mergeTOMLConfig(existing: after, binaryPath: binary), after)
            let custom = before.replacingOccurrences(of: "command = \"npx\"", with: "command = \"my-custom-launcher\"")
            XCTAssertThrowsError(try Integrations.mergeTOMLConfig(existing: Data(custom.utf8), binaryPath: binary))
        }
    }

    func testJSONMergesKeepOtherServersAndUseBundledLauncher() throws {
        try withBundle { binary, launcher in
            let before = Data(#"{"mcpServers":{"other":{"command":"keep"}},"setting":"keep"}"#.utf8)
            let data = try Integrations.merge(existing: before, target: .claudeCode, binaryPath: binary)
            let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(result["setting"] as? String, "keep")
            let servers = try XCTUnwrap(result["mcpServers"] as? [String: [String: Any]])
            XCTAssertEqual(servers["other"]?["command"] as? String, "keep")
            XCTAssertEqual(servers["agentspace"]?["command"] as? String, launcher)
            XCTAssertEqual(servers["agentspace"]?["args"] as? [String], [])
        }
    }
}
