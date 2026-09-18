import XCTest
@testable import AgentSpaceCore

/// Creating and deleting a Space, with the helper replaced by a scripted double.
///
/// The rollback path is the reason this file exists. It only runs when something
/// fails half way through, which is exactly the code that never gets exercised by
/// hand and therefore ships broken. Driving it here means failing at *every* step
/// in turn and checking that the machine is left clean, or — when it cannot be —
/// that the leftover is visible to the user instead of invisible.
final class SpaceProvisionerTests: XCTestCase {

    private var root: URL!
    private var keychain: KeychainStore!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: "/tmp/prov-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // A separate Keychain namespace, so a test can never read or delete a real
        // Space password — and so a stale test item cannot make a real one look
        // like it exists.
        keychain = KeychainStore(service: "com.agentspace.AgentSpace.tests.\(UUID().uuidString.prefix(8))")
    }

    override func tearDownWithError() throws {
        if let keychain, let root {
            for id in keychain.storedSpaceIDs() { try? keychain.delete(for: id) }
            _ = root
        }
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: - The fake helper

    /// Records every call and can be told to fail specific operations.
    final class FakeHelper {
        var calls: [HelperRequest] = []
        /// Operations that should fail, and what they should say.
        var failures: [HelperOperation: String] = [:]
        /// Operations that should fail only on the *n*th call, for retry cases.
        var failAfter: Int?
        private var counts: [HelperOperation: Int] = [:]
        var uid: Int = 601

        func transport(_ request: HelperRequest) throws -> HelperResponse {
            calls.append(request)
            let seen = (counts[request.operation] ?? 0) + 1
            counts[request.operation] = seen

            if let message = failures[request.operation] {
                return HelperResponse(id: request.id, error: AgentSpaceError(
                    code: .helperRejected, message: message))
            }
            if let limit = failAfter, calls.count > limit {
                return HelperResponse(id: request.id, error: AgentSpaceError(
                    code: .helperRejected, message: "scripted failure after \(limit) calls"))
            }

            switch request.operation {
            case .createUser:
                return HelperResponse(id: request.id, result: .obj([
                    "username": .string(request.username ?? ""),
                    "uid": .int(uid),
                    "home": .string("/Users/\(request.username ?? "")"),
                    "isAdmin": .bool(false),
                ]))
            case .prepareRuntimeDirectory:
                let directory = "\(request.runtimeRoot ?? "/tmp")/Runtime/\(request.spaceID?.uuidString ?? "x")"
                try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                return HelperResponse(id: request.id, result: .obj([
                    "runtimeDirectory": .string(directory),
                ]))
            case .installWorker:
                return HelperResponse(id: request.id, result: .obj([
                    "label": .string(HelperCommand.workerLabel(spaceID: request.spaceID ?? UUID())),
                ]))
            case .deleteUser:
                return HelperResponse(id: request.id, result: .obj([
                    "username": .string(request.username ?? ""),
                    "removed": .bool(true),
                ]))
            case .removeWorker, .stopWorker:
                return HelperResponse(id: request.id, result: .obj(["ok": .bool(true)]))
            case .helperStatus:
                return HelperResponse(id: request.id, result: .obj(["isRoot": .bool(true)]))
            case .startWorker, .sessionInfo:
                return HelperResponse(id: request.id, result: .obj(["ok": .bool(true)]))
            }
        }

        func operationsCalled() -> [HelperOperation] { calls.map(\.operation) }
        func count(_ operation: HelperOperation) -> Int {
            calls.filter { $0.operation == operation }.count
        }
    }

    private func options(workspaceDirectory: String? = nil) -> SpaceProvisioner.Options {
        SpaceProvisioner.Options(
            root: root.appendingPathComponent("runtime").path,
            workspaceDirectory: workspaceDirectory ?? root.appendingPathComponent("space/Workspace").path,
            mainUser: "guofeng")
    }

    private func create(
        helper: FakeHelper,
        name: String = "Frontend Test",
        workspace: Workspace = .none,
        sharedFolders: [SharedFolder] = []
    ) -> SpaceProvisioner.Outcome {
        SpaceProvisioner.create(
            name: name, workspace: workspace, sharedFolders: sharedFolders,
            options: options(), transport: helper.transport,
            registry: SpaceRegistry(), keychain: keychain)
    }

    // MARK: - The happy path

    func testCreateMakesTheAccountThenTheRuntimeThenTheWorker() throws {
        let helper = FakeHelper()
        let outcome = create(helper: helper)

        XCTAssertTrue(outcome.ok, outcome.error?.message ?? "")
        // Order matters and is asserted, not assumed: the worker's LaunchAgent
        // points its log files into the runtime directory, and launchd refuses to
        // spawn a job whose log file it cannot open. Worker-before-runtime produces
        // a worker that never starts, with no error anyone can see.
        XCTAssertEqual(helper.operationsCalled(), [.createUser, .prepareRuntimeDirectory, .installWorker])

        let space = try XCTUnwrap(outcome.space)
        XCTAssertEqual(space.name, "Frontend Test")
        XCTAssertTrue(HelperValidation.isAgentSpaceAccount(space.username), space.username)
        XCTAssertEqual(space.uid, 601)
        // Created, but not logged in: reporting `ready` would make the UI offer a
        // desktop that does not exist yet.
        XCTAssertEqual(space.state, .needsLogin)
    }

    func testTheGeneratedAccountMatchesTheRuleThatGatesDeletion() throws {
        // If these two ever disagreed, the helper would create accounts it then
        // refused to delete — a Space that can never be removed.
        for _ in 0..<50 {
            let helper = FakeHelper()
            let outcome = create(helper: helper)
            let space = try XCTUnwrap(outcome.space)
            XCTAssertTrue(HelperValidation.isAgentSpaceAccount(space.username), space.username)
        }
    }

    func testThePasswordGoesToTheKeychainAndNowhereElse() throws {
        let helper = FakeHelper()
        let outcome = create(helper: helper)
        let space = try XCTUnwrap(outcome.space)

        let stored = try XCTUnwrap(try keychain.password(for: space.id))
        XCTAssertTrue(SpacePassword(value: stored).isGenerated, "the stored password is not one we generated")

        // It reached the helper exactly once, on createUser.
        let passwordCalls = helper.calls.filter { $0.password != nil }
        XCTAssertEqual(passwordCalls.count, 1)
        XCTAssertEqual(passwordCalls.first?.operation, .createUser)

        // And it is not in the registry on disk. This is the plan's §9 requirement
        // stated as a test rather than a promise.
        let registryFile = root.appendingPathComponent("runtime/Spaces/index.json")
        if let contents = try? String(contentsOf: registryFile, encoding: .utf8) {
            XCTAssertFalse(contents.contains(stored), "the password was written to the registry file")
        }
    }

    func testCreatingASpaceWritesARecordItsWorkerCanUseToStayConfined() throws {
        // Without this file the worker reports `confined: false` — honest, but not
        // what the user chose when they picked a workspace.
        let helper = FakeHelper()
        let outcome = create(helper: helper)
        let space = try XCTUnwrap(outcome.space)

        let record = root.appendingPathComponent("runtime/Runtime/\(space.id.uuidString)/space.json")
        let data = try Data(contentsOf: record)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["allowedRoots"])
        XCTAssertNotNil(json["writableRoots"])
        XCTAssertEqual(json["mainUser"] as? String, "guofeng")
        XCTAssertEqual(json["spaceName"] as? String, "Frontend Test")
    }

    // MARK: - Refusing before touching the machine

    func testABadWorkspaceIsRefusedBeforeTheHelperIsCalledAtAll() throws {
        // A typo in a repository path must not leave half a Space behind.
        let helper = FakeHelper()
        let outcome = SpaceProvisioner.create(
            name: "Test",
            workspace: .gitWorktree(
                repository: root.appendingPathComponent("nope").path,
                branch: "agentspace/x",
                path: root.appendingPathComponent("space/Workspace/App").path),
            sharedFolders: [], options: options(),
            transport: helper.transport, registry: SpaceRegistry(), keychain: keychain)

        XCTAssertFalse(outcome.ok)
        XCTAssertEqual(outcome.error?.code, .workspaceInvalid)
        XCTAssertTrue(helper.calls.isEmpty, "the helper was called for a Space that could not be created: \(helper.operationsCalled())")
    }

    func testABranchWithoutThePrefixIsRefusedBeforeAnythingIsCreated() throws {
        let repository = try makeRepository()
        let helper = FakeHelper()
        let outcome = SpaceProvisioner.create(
            name: "Test",
            workspace: .gitWorktree(
                repository: repository.path, branch: "main",
                path: root.appendingPathComponent("space/Workspace/App").path),
            sharedFolders: [], options: options(),
            transport: helper.transport, registry: SpaceRegistry(), keychain: keychain)

        XCTAssertEqual(outcome.error?.code, .workspaceInvalid)
        XCTAssertTrue(helper.calls.isEmpty)
    }

    // MARK: - Rollback

    /// Fail each step in turn and check what is left behind.
    func testEveryFailureRollsBackWhatItAlreadyDid() throws {
        let cases: [(HelperOperation, String)] = [
            (.createUser, "the account could not be created"),
            (.prepareRuntimeDirectory, "the runtime directory could not be made"),
            (.installWorker, "the worker could not be installed"),
        ]

        for (operation, message) in cases {
            let helper = FakeHelper()
            helper.failures[operation] = message
            let outcome = create(helper: helper)

            XCTAssertFalse(outcome.ok, "\(operation) was scripted to fail but create succeeded")
            XCTAssertEqual(outcome.error?.code, .helperRejected, "\(operation)")

            // Nothing that exists may be left unremoved. The interesting assertion
            // is the *negative* one: no leftover account.
            if operation != .createUser {
                XCTAssertEqual(helper.count(.deleteUser), 1,
                               "\(operation) failed but the created account was not rolled back")
            }
            // No removeWorker is expected when installWorker itself failed: the
            // worker was never installed, so there is nothing to undo. Asserting a
            // removal here would have demanded a bug.
            XCTAssertEqual(helper.count(.removeWorker), 0,
                           "\(operation) failed and the worker was removed anyway")
            // A clean rollback must not leave a Space in the registry, because the
            // user would then see a Space whose account does not exist.
            XCTAssertFalse(outcome.leftPartialState, "\(operation) left partial state: \(outcome.steps)")
        }
    }

    func testTheKeychainIsCleanedUpWhenCreationFails() throws {
        let helper = FakeHelper()
        helper.failures[.installWorker] = "no"
        _ = create(helper: helper)

        // Nothing may be left in the Keychain for a Space that does not exist.
        let stored = keychain.storedSpaceIDs()
        XCTAssertTrue(stored.isEmpty, "left \(stored.count) Keychain item(s) behind for a failed Space")
    }

    func testAFailedRollbackIsRecordedAsPartialStateAndTheSpaceStaysVisible() throws {
        // The nastiest case: the account was made, a later step failed, and the
        // cleanup could not remove the account. The user now has an
        // `_agentspace_…` user they did not ask for. It must be *visible*.
        let helper = FakeHelper()
        helper.failures[.installWorker] = "the helper refused"
        helper.failures[.deleteUser] = "the account could not be removed"

        let outcome = create(helper: helper)
        XCTAssertFalse(outcome.ok)
        XCTAssertTrue(outcome.leftPartialState, "an unremovable leftover account was reported as a clean failure")

        // The leftover is in the registry as an errored Space, so the app can show
        // it and offer to delete it again.
        let registry = SpaceRegistry.load(root: root.appendingPathComponent("runtime").path)
        XCTAssertEqual(registry.spaces.count, 1, "the orphan account is invisible to the app")
        XCTAssertEqual(registry.spaces.first?.state, .error)
        XCTAssertTrue(HelperValidation.isAgentSpaceAccount(registry.spaces.first?.username ?? ""))
    }

    func testAnUnreachableHelperIsReportedAsUnavailableRatherThanRetried() throws {
        // There is no unprivileged path to creating a macOS account, so a transport
        // failure must say HELPER_UNAVAILABLE rather than looking like a refusal.
        let outcome = SpaceProvisioner.create(
            name: "Test", workspace: .none, sharedFolders: [], options: options(),
            transport: { _ in throw HelperClientError.notInstalled },
            registry: SpaceRegistry(), keychain: keychain)

        XCTAssertFalse(outcome.ok)
        XCTAssertEqual(outcome.error?.code, .helperUnavailable)
        XCTAssertTrue(outcome.error?.message.contains("not installed") == true, outcome.error?.message ?? "")
    }

    // MARK: - Delete

    func testDeleteRemovesEverythingAndKeepsTheUsersRepository() throws {
        let repository = try makeRepository()
        let worktree = root.appendingPathComponent("space/Workspace/App").path
        let helper = FakeHelper()
        let created = SpaceProvisioner.create(
            name: "Test",
            workspace: .gitWorktree(repository: repository.path, branch: "agentspace/a", path: worktree),
            sharedFolders: [], options: options(),
            transport: helper.transport, registry: SpaceRegistry(), keychain: keychain)
        let space = try XCTUnwrap(created.space)
        // Read the path back rather than using the one passed in: the provisioner
        // scopes it under the Space's id, and asserting on a guessed path would
        // test nothing.
        guard case .gitWorktree(_, _, let worktree) = space.workspace else {
            return XCTFail("the workspace stopped being a worktree")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktree + "/README.md"))

        let deleted = SpaceProvisioner.delete(
            space: space, removeHome: false, options: options(),
            transport: helper.transport,
            registry: SpaceRegistry.load(root: root.appendingPathComponent("runtime").path),
            keychain: keychain)

        XCTAssertNil(deleted.error, deleted.error?.message ?? "")
        XCTAssertEqual(helper.operationsCalled().suffix(2), [.removeWorker, .deleteUser])

        // The worktree is gone…
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktree),
                       "the worktree was left behind")
        // …the user's repository is untouched, and the branch — which is where the
        // agent's commits live — survives.
        let userCopy = try String(contentsOf: repository.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertEqual(userCopy, "hello\n", "deleting a Space disturbed the user's repository")
        let branches = WorkspacePreparer.run(["git", "-C", repository.path, "branch", "--list"]).output
        XCTAssertTrue(branches.contains("agentspace/a"), "the agent's branch was destroyed: \(branches)")

        // Nothing left in the Keychain or the registry.
        XCTAssertNil(try keychain.password(for: space.id))
        XCTAssertTrue(SpaceRegistry.load(root: root.appendingPathComponent("runtime").path).spaces.isEmpty)
    }

    func testDeleteKeepsTheHomeUnlessAskedNotTo() throws {
        let helper = FakeHelper()
        let created = create(helper: helper)
        let space = try XCTUnwrap(created.space)

        _ = SpaceProvisioner.delete(
            space: space, removeHome: false, options: options(),
            transport: helper.transport, registry: SpaceRegistry(), keychain: keychain)

        let deleteCall = try XCTUnwrap(helper.calls.last { $0.operation == .deleteUser })
        XCTAssertNotEqual(deleteCall.removeHome, true,
                          "the home was removed without the user asking")
    }

    func testDeleteAsksForTheHomeWhenTheUserSaidSo() throws {
        let helper = FakeHelper()
        let created = create(helper: helper)
        let space = try XCTUnwrap(created.space)

        _ = SpaceProvisioner.delete(
            space: space, removeHome: true, options: options(),
            transport: helper.transport, registry: SpaceRegistry(), keychain: keychain)

        let deleteCall = try XCTUnwrap(helper.calls.last { $0.operation == .deleteUser })
        XCTAssertEqual(deleteCall.removeHome, true)
    }

    func testAFailedAccountDeletionLeavesTheSpaceInTheMessage() throws {
        let helper = FakeHelper()
        let created = create(helper: helper)
        let space = try XCTUnwrap(created.space)
        helper.failures[.deleteUser] = "the account is in use"

        let deleted = SpaceProvisioner.delete(
            space: space, removeHome: true, options: options(),
            transport: helper.transport, registry: SpaceRegistry(), keychain: keychain)

        XCTAssertNotNil(deleted.error)
        // The message must name the account, because the user's next move is to
        // look for it, and the registry entry is already gone.
        XCTAssertTrue(deleted.error?.message.contains(space.username) == true,
                      deleted.error?.message ?? "")
    }

    func testDeleteWarnsRatherThanFailingWhenTheWorktreeIsDirty() throws {
        // Losing the Space must not be blocked by a worktree git refuses to remove.
        // The account is the important part; a directory the user can delete by
        // hand is a much better outcome than an account that cannot be removed.
        let repository = try makeRepository()
        let worktree = root.appendingPathComponent("space/Workspace/App").path
        let helper = FakeHelper()
        let created = SpaceProvisioner.create(
            name: "Test",
            workspace: .gitWorktree(repository: repository.path, branch: "agentspace/a", path: worktree),
            sharedFolders: [], options: options(),
            transport: helper.transport, registry: SpaceRegistry(), keychain: keychain)
        let space = try XCTUnwrap(created.space)
        guard case .gitWorktree(_, _, let worktree) = space.workspace else {
            return XCTFail("the workspace stopped being a worktree")
        }

        // Lock the worktree, which is the documented reason `git worktree remove`
        // refuses even with --force. Deleting the directory by hand does NOT work:
        // --force overrides dirtiness, and git then succeeds by pruning.
        let locked = WorkspacePreparer.run([
            "git", "-C", repository.path, "worktree", "lock", worktree,
        ])
        XCTAssertEqual(locked.exitCode, 0, "could not lock the worktree: \(locked.output)")

        let deleted = SpaceProvisioner.delete(
            space: space, removeHome: false, options: options(),
            transport: helper.transport,
            registry: SpaceRegistry.load(root: root.appendingPathComponent("runtime").path),
            keychain: keychain)

        XCTAssertNil(deleted.error, "a worktree problem blocked the deletion: \(deleted.error?.message ?? "")")
        XCTAssertEqual(helper.count(.deleteUser), 1, "the account was not deleted after the worktree warning")
        let warning = deleted.steps.first { $0.name == "remove git worktree" }
        XCTAssertNotNil(warning)
        if case .skipped(let text)? = warning?.outcome {
            XCTAssertTrue(text.contains("untouched"), text)
        } else {
            XCTFail("expected a skip with an explanation, got \(String(describing: warning?.outcome))")
        }
    }

    // MARK: - Fixtures

    private func makeRepository() throws -> URL {
        let repository = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        for command in [
            ["git", "-C", repository.path, "init", "-q", "-b", "main"],
            ["git", "-C", repository.path, "config", "user.email", "test@example.com"],
            ["git", "-C", repository.path, "config", "user.name", "Test"],
        ] {
            XCTAssertEqual(WorkspacePreparer.run(command).exitCode, 0, "\(command) failed")
        }
        try "hello\n".write(to: repository.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(WorkspacePreparer.run(["git", "-C", repository.path, "add", "-A"]).exitCode, 0)
        XCTAssertEqual(WorkspacePreparer.run(["git", "-C", repository.path, "commit", "-q", "-m", "initial"]).exitCode, 0)
        return repository
    }
}
