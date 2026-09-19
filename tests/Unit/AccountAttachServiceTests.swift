import XCTest
@testable import AgentSpaceCore

final class AccountAttachServiceTests: XCTestCase {
    func testAttachOnlyPreparesRuntimeAndInstallsWorker() throws {
        let root = "/tmp/attach-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        var calls: [HelperRequest] = []
        let account = LocalAccount(
            username: "agentdev",
            uid: 502,
            displayName: "Agent Dev",
            homeDirectory: "/Users/agentdev",
            isAdministrator: false)

        let outcome = AccountAttachService.attach(
            account: account,
            displayName: "Coding Agent",
            workspace: .none,
            sharedFolders: [],
            options: .init(root: root, workspaceDirectory: root + "/Worktrees", mainUser: "guofeng"),
            transport: { request in
                calls.append(request)
                switch request.operation {
                case .prepareRuntimeDirectory:
                    let directory = root + "/Runtime/" + request.spaceID!.uuidString
                    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                    return HelperResponse(id: request.id, result: .obj(["runtimeDirectory": .string(directory)]))
                case .installWorker:
                    return HelperResponse(id: request.id, result: .obj(["label": .string("worker")]))
                case .startWorker:
                    return HelperResponse(id: request.id, result: .obj(["started": .bool(true)]))
                default:
                    return HelperResponse(id: request.id, error: AgentSpaceError(code: .helperRejected, message: "unexpected operation"))
                }
            })

        XCTAssertTrue(outcome.ok, outcome.error?.message ?? "")
        XCTAssertEqual(calls.map(\.operation), [.prepareRuntimeDirectory, .installWorker, .startWorker])
        XCTAssertTrue(calls.allSatisfy { $0.username == "agentdev" && $0.mainUser == "guofeng" })
        XCTAssertEqual(outcome.account?.username, "agentdev")
    }

    func testDetachNeverDeletesOrLogsOutTheMacOSUser() throws {
        let root = "/tmp/detach-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        let account = AgentAccount(name: "Coding Agent", username: "agentdev", uid: 502, state: .ready)
        var registry = SpaceRegistry()
        registry.upsert(account)
        try registry.save(root: root)
        var calls: [HelperRequest] = []

        let outcome = AccountAttachService.detach(
            account: account,
            options: .init(root: root, workspaceDirectory: root + "/Worktrees", mainUser: "guofeng"),
            transport: { request in
                calls.append(request)
                return HelperResponse(id: request.id, result: .obj(["ok": .bool(true)]))
            },
            registry: registry)

        XCTAssertNil(outcome.error, outcome.error?.message ?? "")
        XCTAssertEqual(calls.map(\.operation), [.stopWorker, .removeWorker, .removeRuntimeDirectory])
        XCTAssertFalse(calls.contains { $0.operation == .deleteUser || $0.operation == .logoutSession })
        XCTAssertTrue(SpaceRegistry.load(root: root).spaces.isEmpty)
    }

    func testFailedWorkerInstallRollsBackThePreparedRuntime() throws {
        let root = "/tmp/attach-rollback-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        let account = LocalAccount(
            username: "agentdev",
            uid: 502,
            displayName: "Agent Dev",
            homeDirectory: "/Users/agentdev",
            isAdministrator: false)
        var calls: [HelperOperation] = []

        let outcome = AccountAttachService.attach(
            account: account,
            displayName: "Coding Agent",
            workspace: .none,
            sharedFolders: [],
            options: .init(root: root, workspaceDirectory: root + "/Worktrees", mainUser: "guofeng"),
            transport: { request in
                calls.append(request.operation)
                switch request.operation {
                case .prepareRuntimeDirectory:
                    let directory = root + "/Runtime/" + request.spaceID!.uuidString
                    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                    return HelperResponse(id: request.id, result: .obj(["runtimeDirectory": .string(directory)]))
                case .installWorker:
                    return HelperResponse(id: request.id, error: AgentSpaceError(code: .helperRejected, message: "test refusal"))
                case .removeWorker:
                    return HelperResponse(id: request.id, result: .obj(["removed": .array([])]))
                case .removeRuntimeDirectory:
                    return HelperResponse(id: request.id, result: .obj(["removed": .bool(true)]))
                default:
                    return HelperResponse(id: request.id, error: AgentSpaceError(code: .helperRejected, message: "unexpected operation"))
                }
            })

        XCTAssertFalse(outcome.ok)
        XCTAssertEqual(calls, [.prepareRuntimeDirectory, .installWorker, .removeWorker, .removeRuntimeDirectory])
        XCTAssertTrue(outcome.steps.contains { if case .rolledBack = $0.outcome { return true }; return false })
    }

    func testDetachStopsBeforeDeletingRuntimeWhenWorkerRemovalFails() throws {
        let root = "/tmp/detach-failure-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        let account = AgentAccount(name: "Coding Agent", username: "agentdev", uid: 502, runtimeRoot: root, state: .ready)
        let registry = SpaceRegistry(spaces: [account])
        try registry.save(root: root)
        var calls: [HelperOperation] = []

        let outcome = AccountAttachService.detach(
            account: account,
            options: .init(root: root, workspaceDirectory: root + "/Worktrees", mainUser: "guofeng"),
            transport: { request in
                calls.append(request.operation)
                if request.operation == .removeWorker {
                    return HelperResponse(id: request.id, error: AgentSpaceError(code: .helperRejected, message: "still installed"))
                }
                return HelperResponse(id: request.id, result: .obj(["ok": .bool(true)]))
            },
            registry: registry)

        XCTAssertNotNil(outcome.error)
        XCTAssertEqual(calls, [.stopWorker, .removeWorker])
        XCTAssertEqual(SpaceRegistry.load(root: root).spaces.map(\.id), [account.id])
    }
}
