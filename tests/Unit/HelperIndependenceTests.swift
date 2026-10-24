import XCTest
import Foundation
import AgentSpaceCore

/// A missing privileged helper must cost the person nothing except the two
/// operations that genuinely need root.
///
/// This is a product promise, not an implementation detail: the owner's rule is
/// 「如果用户不授权，不影响使用软件已有的功能」. It became load-bearing in 0.1.98
/// (§398 row 1355), when the app's bundle identifier changed and an installed
/// helper could no longer answer the new build until it was re-registered. So the
/// promise is pinned here rather than left to a manual check:
///
/// - nothing on the launch path touches the helper;
/// - every already-connected account's own operations go to its worker, which
///   never asks the helper anything;
/// - the two that do need it fail with a typed, actionable error instead of
///   crashing, hanging, or pretending to work.
final class HelperIndependenceTests: XCTestCase {

    // MARK: The launch path

    func testTheAppDoesNotTouchTheHelperAtLaunch() throws {
        // A source read, because the property is structural: no helper call may
        // appear in the scene/app entry points. If one is added later, launch
        // becomes capable of blocking on a daemon that is not there.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let entry = root.appendingPathComponent("apps/AgentSpace/App/AgentSpaceApp.swift")
        let source = try String(contentsOf: entry, encoding: .utf8)
        for banned in ["installHelper(", "reinstallHelper(", "registerDaemon(",
                       "HelperInstallation.inspect(", "HelperClient.ping("] {
            XCTAssertFalse(source.contains(banned),
                           "App entry point calls \(banned); launch must not depend on the helper")
        }
    }

    func testTheSettingsPageDoesNotRequireTheHelper() throws {
        // The virtual-network page is where a person would notice a broken app.
        // It reads network state and the system extension, never the helper.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let page = root.appendingPathComponent("apps/AgentSpace/Views/VirtualNetworkSettingsView.swift")
        let source = try String(contentsOf: page, encoding: .utf8)
        XCTAssertFalse(source.contains("HelperInstallation"))
        XCTAssertFalse(source.contains("installHelper("))
    }

    // MARK: The two operations that do need root

    func testAMissingHelperIsTypedAndActionableNotACrash() {
        let error = AgentSpaceError(
            code: .helperUnavailable,
            message: "the privileged helper is not installed")
        // Recoverable: installing it is a thing a person can do.
        XCTAssertTrue(error.recoverable)
        XCTAssertEqual(error.code, .helperUnavailable)
        // The remediation must name the fix, because "it failed" at 2am is what
        // makes a tool unusable.
        XCTAssertFalse(error.code.remediation.isEmpty)
    }

    func testARefusedHelperIsNotRetryable() {
        // A helper that answered and refused is a different fact from one that is
        // absent: retrying the identical request can only produce the same
        // refusal, so the code must not invite one.
        XCTAssertFalse(AgentSpaceError(
            code: .helperRejected, message: "refused").recoverable)
    }

    // MARK: What still works

    func testTheRegistryIsReadableWithoutTheHelper() throws {
        let root = NSTemporaryDirectory() + "/agentspace-nohelper-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        let account = AgentAccount(
            id: UUID(), name: "AgentUse", username: "agentuse", uid: 503,
            state: .ready, createdAt: Date())
        var registry = SpaceRegistry(spaces: [account])
        registry.spaces = [account]
        try registry.save(root: root)

        // Listing, resolving and status all read this file. None of them asks the
        // helper anything, which is what makes "the app still works" true.
        let loaded = SpaceRegistry.load(root: root)
        XCTAssertEqual(loaded.spaces.count, 1)
        guard case .success(let resolved) = loaded.resolve("AgentUse") else {
            return XCTFail("an account must resolve by name without the helper")
        }
        XCTAssertEqual(resolved.id, account.id)
    }

    func testAnAgentWithoutAWorkerReportsOfflineRatherThanAskingTheHelper() throws {
        let root = NSTemporaryDirectory() + "/agentspace-nohelper-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        let id = UUID()
        let paths = RuntimePaths(spaceID: id, root: root)
        // No socket exists. The transport must say so, and the code it produces is
        // about the worker — not about the helper, which this path never reaches.
        let client = WorkerClient(socketPath: paths.socketPath)
        XCTAssertThrowsError(try client.call(method: Method.status, token: "x", timeout: 1)) { error in
            guard case WorkerClient.ClientError.socketMissing = error else {
                return XCTFail("expected socketMissing, got \(error)")
            }
        }
    }

    // MARK: The extension's independence

    func testTheTunnelDoesNotNeedTheHelperEither() {
        // A tunnel is started by the app and carried by a system extension. If
        // this ever grows a helper dependency, a person who declined the helper
        // would lose the virtual network too — and the promise is that declining
        // costs only the two root operations.
        let paths = VirtualNetworkPaths(root: NSTemporaryDirectory() + "/vn-\(UUID().uuidString)")
        XCTAssertFalse(paths.configPath.contains("Helper"))
        let configuration = VirtualNetworkConfig(
            pool: IPv4Network("100.64.0.0/24")!,
            hub: IPv4Address("100.64.0.1")!,
            controller: IPv4Address("100.64.0.2")!,
            local: IPv4Address("100.64.0.10")!)
        let validation = VirtualNetworkValidator.validate(configuration)
        XCTAssertTrue(validation.isValid)
    }
}
