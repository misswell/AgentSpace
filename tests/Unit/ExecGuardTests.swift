import XCTest
import AgentSpaceCore

final class ExecGuardTests: XCTestCase {

    // MARK: Refusals

    func testRefusesPrivilegeEscalation() {
        for command in ["sudo rm -rf /", "sudo -i", "FOO=1 sudo whoami", "sudo"] {
            let error = ExecGuard.refusal(for: command)
            XCTAssertNotNil(error, "'\(command)' should be refused")
            XCTAssertEqual(error?.code, .execDenied)
        }
    }

    func testRefusesMachineLevelChanges() {
        let commands = [
            "installer -pkg foo.pkg -target /",
            "diskutil erase /dev/disk2",
            "launchctl bootstrap system /Library/LaunchDaemons/x.plist",
            "dscl create /Users/evil",
            "sysadminctl -addUser evil",
            "rm -rf /",
            "shutdown -h now",
            "reboot",
            "csrutil disable",
            "nvram boot-args=x",
            "tccutil reset All",
            "kextload /tmp/x.kext",
            "mkfs.ext4 /dev/disk2",
            "dd if=/dev/zero of=/dev/disk2",
        ]
        for command in commands {
            let error = ExecGuard.refusal(for: command)
            XCTAssertNotNil(error, "'\(command)' should be refused")
            XCTAssertEqual(error?.code, .execDenied, "'\(command)'")
        }
    }

    func testRefusalMessageQuotesTheRule() {
        let error = ExecGuard.refusal(for: "sudo whoami")
        XCTAssertNotNil(error)
        XCTAssertTrue(error!.message.contains("sudo"), error!.message)
    }

    func testRefusalIsNotMarkedRecoverable() {
        // Retrying an identical refused command can never succeed, so the error
        // must not invite a retry loop.
        XCTAssertEqual(ExecGuard.refusal(for: "sudo x")?.recoverable, false)
    }

    // MARK: Normalisation

    func testWhitespaceIsNormalisedBeforeMatching() {
        XCTAssertNotNil(ExecGuard.refusal(for: "rm    -rf     /"))
        XCTAssertNotNil(ExecGuard.refusal(for: "shutdown\t-h\tnow"))
        XCTAssertNotNil(ExecGuard.refusal(for: "diskutil   erase   /dev/disk2"))
    }

    func testCaseInsensitiveMatching() {
        XCTAssertNotNil(ExecGuard.refusal(for: "SUDO whoami"))
        XCTAssertNotNil(ExecGuard.refusal(for: "REBOOT"))
    }

    func testPathQualifiedExecutableIsStillRefused() {
        XCTAssertNotNil(ExecGuard.refusal(for: "/usr/bin/sudo whoami"))
        XCTAssertNotNil(ExecGuard.refusal(for: "/usr/sbin/sysadminctl -addUser x"))
    }

    // MARK: Allowed

    func testAllowsOrdinaryDevelopmentCommands() {
        let allowed = [
            "npm test",
            "npm install",
            "git status",
            "xcodebuild -scheme App build",
            "ls -la",
            "python3 -m pytest",
            "echo hello",
            "open -a Safari",
            "xcrun simctl list",
            "swift build",
            "mkdir -p build && cd build && cmake ..",
        ]
        for command in allowed {
            XCTAssertNil(ExecGuard.refusal(for: command), "'\(command)' should be allowed")
        }
    }

    /// The list is a guardrail, not a containment mechanism, and the code says
    /// so. This test documents an evasion so nobody later mistakes the list for
    /// a sandbox.
    func testQuotingEvadesTheListByDesign() {
        XCTAssertNil(ExecGuard.refusal(for: "s''udo whoami"),
                     "the refusal list is documented as evadable; containment is the uid")
    }

    // MARK: Workspace confinement

    func testPathInsideAllowedRootIsAccepted() {
        XCTAssertNil(WorkspaceGuard.check(
            path: "/tmp/ws/project/src/main.swift",
            allowedRoots: ["/tmp/ws/project"]))
    }

    func testPathOutsideAllowedRootIsRefused() {
        let error = WorkspaceGuard.check(
            path: "/Users/someone/.ssh/id_rsa",
            allowedRoots: ["/tmp/ws/project"])
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.code, .workspaceDenied)
    }

    func testNoRootsMeansEverythingIsRefused() {
        let error = WorkspaceGuard.check(path: "/tmp/anything", allowedRoots: [])
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.code, .workspaceDenied)
    }

    /// The attack the resolution step exists for: a symlink whose *string*
    /// starts with an allowed prefix but whose *target* is elsewhere.
    func testSymlinkEscapeIsRefused() throws {
        let base = NSTemporaryDirectory() + "/agentspace-symlink-\(UUID().uuidString)"
        let workspace = base + "/workspace"
        let secret = base + "/secret"
        try FileManager.default.createDirectory(atPath: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: secret, withIntermediateDirectories: true)
        try Data("private".utf8).write(to: URL(fileURLWithPath: secret + "/key.txt"))
        defer { try? FileManager.default.removeItem(atPath: base) }

        let link = workspace + "/escape"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: secret)

        // The literal string is inside the workspace...
        XCTAssertTrue(WorkspaceGuard.contains(link + "/key.txt", workspace))
        // ...but resolution sees the real target, so the check refuses.
        let error = WorkspaceGuard.check(
            path: link + "/key.txt",
            allowedRoots: [workspace])
        XCTAssertNotNil(error, "a symlink must not be a way out of the workspace")
        XCTAssertEqual(error?.code, .workspaceDenied)
    }

    func testSiblingPrefixIsNotTreatedAsInside() {
        XCTAssertFalse(WorkspaceGuard.contains("/tmp/ws-evil/x", "/tmp/ws"))
        XCTAssertTrue(WorkspaceGuard.contains("/tmp/ws/x", "/tmp/ws"))
        XCTAssertTrue(WorkspaceGuard.contains("/tmp/ws", "/tmp/ws"))
    }

    func testWriteRequiresAWritableRoot() {
        let readOnly = "/tmp/ws/readonly"
        let writable = "/tmp/ws/writable"
        // Neither exists on disk, so resolution falls back to string handling.
        let refused = WorkspaceGuard.check(
            path: readOnly + "/file.txt",
            allowedRoots: [readOnly, writable],
            requireWrite: true,
            writableRoots: [writable])
        XCTAssertNotNil(refused)
        XCTAssertEqual(refused?.code, .workspaceDenied)
        XCTAssertTrue(refused!.message.contains("read-only"), refused!.message)

        XCTAssertNil(WorkspaceGuard.check(
            path: writable + "/file.txt",
            allowedRoots: [readOnly, writable],
            requireWrite: true,
            writableRoots: [writable]))
    }

    func testDeepestMatchingRootWins() {
        // When roots nest, the most specific one decides writability.
        let outer = "/tmp/ws"
        let inner = "/tmp/ws/inner"
        let error = WorkspaceGuard.check(
            path: inner + "/f.txt",
            allowedRoots: [outer, inner],
            requireWrite: true,
            writableRoots: [inner])
        XCTAssertNil(error, "the inner root is writable even though the outer one is not")
    }

    func testRelativePathIsResolvedAgainstCwd() {
        let resolved = WorkspaceGuard.resolve("relative/path")
        XCTAssertTrue(resolved.hasPrefix("/"), resolved)
    }

    func testTildeIsExpanded() {
        let resolved = WorkspaceGuard.resolve("~/Documents")
        XCTAssertTrue(resolved.hasPrefix(NSHomeDirectory()), resolved)
        XCTAssertFalse(resolved.contains("~"), resolved)
    }

    func testTrailingSlashIsNormalised() {
        XCTAssertEqual(WorkspaceGuard.resolve("/tmp/ws/"), WorkspaceGuard.resolve("/tmp/ws"))
    }
}
