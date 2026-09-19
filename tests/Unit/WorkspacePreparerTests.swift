import XCTest
@testable import AgentSpaceCore

/// Workspace planning and preparation — plan §14.
///
/// These tests use a **real** git repository in a temporary directory rather than
/// a stub, because the interesting failures here are git's, not ours: whether
/// `worktree add` accepts the argv we build, whether the branch really is created,
/// and whether the user's own checkout is genuinely untouched. A test that stubs
/// git would pass while the product failed.
final class WorkspacePreparerTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        // Short base path: git worktree writes absolute paths into
        // .git/worktrees/<name>/gitdir, and long temporary paths are awkward to
        // read in a failure message.
        root = URL(fileURLWithPath: "/tmp/wsp-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: - Fixtures

    /// A real repository with one commit, so `worktree add` has a HEAD to branch
    /// from. Without the commit git refuses, which is a different failure.
    private func makeRepository(named name: String = "repo") throws -> URL {
        let repository = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        for command in [
            ["git", "-C", repository.path, "init", "-q", "-b", "main"],
            ["git", "-C", repository.path, "config", "user.email", "test@example.com"],
            ["git", "-C", repository.path, "config", "user.name", "Test"],
        ] {
            let result = WorkspacePreparer.run(command)
            XCTAssertEqual(result.exitCode, 0, "\(command) failed: \(result.output)")
        }
        try "hello\n".write(to: repository.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        // Staging is not optional: without it `git commit` exits 1 with "On branch
        // main / nothing to commit", which reads like a complaint about branches.
        let staged = WorkspacePreparer.run(["git", "-C", repository.path, "add", "-A"])
        XCTAssertEqual(staged.exitCode, 0, "git add failed: \(staged.output)")
        let commit = WorkspacePreparer.run(["git", "-C", repository.path, "commit", "-q", "-m", "initial"])
        XCTAssertEqual(commit.exitCode, 0, "commit failed: \(commit.output)")
        return repository
    }

    private var workspaceDirectory: String { root.appendingPathComponent("space/Workspace").path }

    private func plan(
        workspace: Workspace,
        sharedFolders: [SharedFolder] = []
    ) -> Result<WorkspacePreparer.Plan, AgentSpaceError> {
        WorkspacePreparer.plan(
            workspace: workspace,
            sharedFolders: sharedFolders,
            spaceID: UUID(),
            workspaceDirectory: workspaceDirectory)
    }

    // MARK: - none

    func testNoWorkspaceConfinesNothingAndCreatesOnlyItsOwnDirectory() throws {
        let plan = try plan(workspace: .none).get()
        XCTAssertEqual(plan.directories, [WorkspacePreparer.standardize(workspaceDirectory)])
        XCTAssertTrue(plan.allowedRoots.isEmpty)
        XCTAssertTrue(plan.writableRoots.isEmpty)
        XCTAssertNil(plan.gitCommand)
        // The honest answer, not a reassuring one: with no roots declared the
        // worker reports confined: false, which is true.
        XCTAssertEqual(plan.spaceRecord["allowedRoots"] as? [String], [])
    }

    // MARK: - git worktree

    func testWorktreePlanAddsTheWorktreeReadsTheRepositoryAndWritesOnlyItsOwnCopy() throws {
        let repository = try makeRepository()
        let worktree = workspaceDirectory + "/App"
        let plan = try plan(workspace: .gitWorktree(
            repository: repository.path, branch: "agentspace/agent-1", path: worktree)).get()

        XCTAssertEqual(plan.gitCommand,
                       ["/usr/bin/git", "-C", repository.path, "worktree", "add", "-B", "agentspace/agent-1", worktree])

        // The repository is readable so the agent can diff and log, but NOT
        // writable: that is the promise the mode makes.
        XCTAssertTrue(plan.allowedRoots.contains(WorkspacePreparer.standardize(repository.path)))
        XCTAssertFalse(plan.writableRoots.contains(WorkspacePreparer.standardize(repository.path)))
        XCTAssertTrue(plan.writableRoots.contains(worktree))
        XCTAssertTrue(plan.allowedRoots.contains(worktree))
    }

    func testWritableRootsAreAlwaysASubsetOfAllowedRoots() throws {
        // The worker treats these as independent lists, so a writable root that is
        // not also allowed would be a hole rather than a mistake.
        let repository = try makeRepository()
        let shared = root.appendingPathComponent("shared")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)

        let plan = try plan(
            workspace: .gitWorktree(repository: repository.path, branch: "agentspace/x", path: workspaceDirectory + "/App"),
            sharedFolders: [
                SharedFolder(path: shared.path, access: .readWrite),
                SharedFolder(path: repository.path, access: .readOnly),
            ]).get()

        for writable in plan.writableRoots {
            XCTAssertTrue(plan.allowedRoots.contains(writable),
                          "\(writable) is writable but not allowed")
        }
    }

    func testApplyReallyCreatesAWorktreeWithoutTouchingTheUsersCheckout() throws {
        // The end-to-end claim for the whole mode. Real git, real filesystem.
        let repository = try makeRepository()
        let worktree = workspaceDirectory + "/App"
        let plan = try plan(workspace: .gitWorktree(
            repository: repository.path, branch: "agentspace/agent-1", path: worktree)).get()

        try WorkspacePreparer.apply(plan).get()

        let fileManager = FileManager.default
        XCTAssertTrue(fileManager.fileExists(atPath: worktree + "/README.md"),
                      "the worktree has no checkout in it")

        // The agent edits its own copy…
        try "changed by the agent\n".write(
            to: URL(fileURLWithPath: worktree + "/README.md"), atomically: true, encoding: .utf8)

        // …and the user's tree is untouched. This is the assertion that matters.
        let userCopy = try String(contentsOf: repository.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertEqual(userCopy, "hello\n", "the agent's edit leaked into the user's working tree")

        // And the branch exists in the repository's own namespace.
        let branches = WorkspacePreparer.run(["git", "-C", repository.path, "branch", "--list"])
        XCTAssertTrue(branches.output.contains("agentspace/agent-1"), branches.output)
    }

    func testRunningTheSamePlanTwiceIsRefusedRatherThanSilentlyConfusing() throws {
        let repository = try makeRepository()
        let worktree = workspaceDirectory + "/App"
        let plan = try plan(workspace: .gitWorktree(
            repository: repository.path, branch: "agentspace/agent-1", path: worktree)).get()
        try WorkspacePreparer.apply(plan).get()

        // The second run is what happens when a user creates a Space, something
        // goes wrong later, and they try again. It must produce a comprehensible
        // error rather than a half-state.
        let second = WorkspacePreparer.apply(plan)
        guard case .failure(let error) = second else {
            return XCTFail("a second apply of the same plan succeeded")
        }
        XCTAssertEqual(error.code, .workspaceInvalid)
        XCTAssertTrue(error.message.contains("git"), error.message)
    }

    // MARK: - refusals

    func testARepositoryThatIsNotARepositoryIsRefused() throws {
        let notARepository = root.appendingPathComponent("plain")
        try FileManager.default.createDirectory(at: notARepository, withIntermediateDirectories: true)

        let result = plan(workspace: .gitWorktree(
            repository: notARepository.path, branch: "agentspace/x", path: workspaceDirectory + "/App"))
        guard case .failure(let error) = result else {
            return XCTFail("a plain directory was accepted as a git repository")
        }
        XCTAssertEqual(error.code, .workspaceInvalid)
        XCTAssertTrue(error.message.contains("not a git repository"), error.message)
    }

    func testAMissingRepositoryIsRefusedBeforeAnythingIsCreated() throws {
        let result = plan(workspace: .gitWorktree(
            repository: root.appendingPathComponent("nope").path,
            branch: "agentspace/x", path: workspaceDirectory + "/App"))
        guard case .failure(let error) = result else { return XCTFail("a missing repository was accepted") }
        XCTAssertEqual(error.code, .workspaceInvalid)
    }

    func testABranchWithoutThePrefixIsRefused() throws {
        // The rule that stops an agent from being pointed at the user's own branch.
        let repository = try makeRepository()
        for branch in ["main", "master", "feature/x", "develop"] {
            let result = plan(workspace: .gitWorktree(
                repository: repository.path, branch: branch, path: workspaceDirectory + "/App"))
            guard case .failure(let error) = result else {
                return XCTFail("branch \(branch) was accepted, so an agent could commit to it")
            }
            XCTAssertEqual(error.code, .workspaceInvalid)
        }
    }

    func testMalformedBranchNamesAreRefused() throws {
        let repository = try makeRepository()
        let malformed = [
            "agentspace/",              // nothing after the prefix
            "agentspace//x",            // empty component
            "agentspace/../x",          // traversal
            "agentspace/x..y",
            "agentspace/x y",           // space
            "agentspace/x~y",
            "agentspace/x^y",
            "agentspace/x:y",
            "agentspace/x?y",
            "agentspace/x*y",
            "agentspace/x[y",
            "agentspace/x\\y",
            "agentspace/x@{y",
            "agentspace/x.",            // trailing dot
            "agentspace/x\u{7F}y",      // delete
            "agentspace/x\ny",          // newline
        ]
        for branch in malformed {
            let result = plan(workspace: .gitWorktree(
                repository: repository.path, branch: branch, path: workspaceDirectory + "/App"))
            guard case .failure = result else {
                return XCTFail("branch \(branch.debugDescription) was accepted")
            }
        }
    }

    func testAWorktreeOutsideTheSpacesOwnDirectoryIsRefused() throws {
        // Otherwise the agent would be creating directories in the user's tree,
        // which is exactly what a worktree exists to avoid.
        let repository = try makeRepository()
        for path in [
            repository.path + "/sub",
            root.appendingPathComponent("elsewhere").path,
            "/tmp/hijack",
            workspaceDirectory + "/../escape",
        ] {
            let result = plan(workspace: .gitWorktree(
                repository: repository.path, branch: "agentspace/x", path: path))
            guard case .failure(let error) = result else {
                return XCTFail("worktree path \(path) was accepted")
            }
            XCTAssertEqual(error.code, .workspaceInvalid)
        }
    }

    func testTheWorktreeCannotBeTheRepositoryItself() throws {
        // This would check out over the user's working tree — the single worst
        // outcome the mode could have.
        let repository = try makeRepository()
        let result = WorkspacePreparer.plan(
            workspace: .gitWorktree(repository: repository.path, branch: "agentspace/x", path: repository.path),
            sharedFolders: [], spaceID: UUID(),
            workspaceDirectory: root.path)   // wide enough to permit it on path grounds alone
        guard case .failure(let error) = result else {
            return XCTFail("the worktree was allowed to be the repository itself")
        }
        XCTAssertEqual(error.code, .workspaceInvalid)
    }

    // MARK: - shared folders

    func testSharedFoldersAreReadOnlyUnlessAllowed() throws {
        let shared = root.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)

        let readOnly = try plan(
            workspace: .sharedFolders,
            sharedFolders: [SharedFolder(path: shared.path, access: .readOnly)]).get()
        XCTAssertTrue(readOnly.allowedRoots.contains(shared.path))
        XCTAssertFalse(readOnly.writableRoots.contains(shared.path))

        let readWrite = try plan(
            workspace: .sharedFolders,
            sharedFolders: [SharedFolder(path: shared.path, access: .readWrite)]).get()
        XCTAssertTrue(readWrite.writableRoots.contains(shared.path))
    }

    func testSharingASystemDirectoryIsRefused() throws {
        // Nobody means to give an agent /System or /Users, and "I did not mean
        // that" is not recoverable once the agent has written there.
        for path in ["/", "/System", "/Library", "/usr", "/etc", "/Users", "/Applications", "/private", "/var"] {
            let result = plan(
                workspace: .sharedFolders,
                sharedFolders: [SharedFolder(path: path, access: .readWrite)])
            guard case .failure(let error) = result else {
                return XCTFail("sharing \(path) with an agent was allowed")
            }
            XCTAssertEqual(error.code, .workspaceInvalid)
        }
    }

    func testSensitiveHomePathsAreNeverShared() throws {
        // §25's "禁止默认开放" list, hardened to "never": the home itself, the
        // Library tree holding the Keychains, and ~/.ssh must not reach an
        // agent even when a user picks them explicitly. Desktop, Documents and
        // Downloads stay shareable — §25's own UI example shares a folder
        // under Documents.
        let home = "/Users/alice"
        func tryShare(_ path: String) -> Result<WorkspacePreparer.Plan, AgentSpaceError> {
            WorkspacePreparer.plan(
                workspace: .sharedFolders,
                sharedFolders: [SharedFolder(path: path, access: .readWrite)],
                spaceID: UUID(),
                workspaceDirectory: "/Users/_agentspace_x/Workspace",
                homeDirectory: home,
                fileExists: { _ in true })
        }
        for path in [home, home + "/Library", home + "/Library/Keychains", home + "/.ssh"] {
            guard case .failure(let error) = tryShare(path) else {
                return XCTFail("sharing \(path) with an agent was allowed")
            }
            XCTAssertEqual(error.code, .workspaceInvalid)
            XCTAssertTrue(error.message.contains("Share the specific project"),
                          "the refusal should point at the fix")
        }
        // The explicit-intent contrast: a folder under Documents is fine.
        guard case .success = tryShare(home + "/Documents/TestData") else {
            return XCTFail("a Documents subfolder must stay shareable")
        }
    }

    func testSharedFolderPathsAreValidated() throws {
        let missing = root.appendingPathComponent("nope").path
        for folder in ["relative/path", missing, "/tmp/../etc"] {
            let result = plan(
                workspace: .sharedFolders,
                sharedFolders: [SharedFolder(path: folder, access: .readOnly)])
            guard case .failure = result else {
                return XCTFail("shared folder \(folder) was accepted")
            }
        }
    }

    // MARK: - the space record

    func testTheSpaceRecordTurnsConfinementOn() throws {
        // `status.workspace.confined` reports `!allowedRoots.isEmpty`. A plan that
        // produced roots the worker could not read would leave the agent confined
        // in the UI and unconfined in fact.
        let repository = try makeRepository()
        let plan = try plan(workspace: .gitWorktree(
            repository: repository.path, branch: "agentspace/x", path: workspaceDirectory + "/App")).get()

        let record = plan.spaceRecord
        XCTAssertNotNil(record["allowedRoots"] as? [String])
        XCTAssertNotNil(record["writableRoots"] as? [String])
        XCTAssertEqual((record["allowedRoots"] as? [String])?.count, plan.allowedRoots.count)

        // Round-trip through JSON, because that is how the worker will read it.
        let data = try JSONSerialization.data(withJSONObject: record)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(decoded?["allowedRoots"] as? [String], plan.allowedRoots)
        XCTAssertEqual(Set(decoded?["writableRoots"] as? [String] ?? []), Set(plan.writableRoots))
    }

    func testThePlanJSONIsStableAndComplete() throws {
        let repository = try makeRepository()
        let plan = try plan(workspace: .gitWorktree(
            repository: repository.path, branch: "agentspace/x", path: workspaceDirectory + "/App")).get()
        guard case .object(let fields) = plan.json else { return XCTFail("plan.json is not an object") }
        XCTAssertEqual(Set(fields.keys), ["directories", "allowedRoots", "writableRoots", "gitCommand", "summary"])
    }

    // MARK: - missing git offers an in-app fix, not a terminal instruction

    /// A Mac without the Command Line Tools has no git. The plan's product
    /// rule (user's correction): privileged or system fixes are offered as
    /// buttons in the app — the user is never told to run a command. The
    /// error must carry the machine-readable hint and must NOT contain the
    /// command string.
    func testMissingGitCarriesInstallerHintAndNoTerminalInstruction() {
        let result = WorkspacePreparer.plan(
            workspace: .gitWorktree(
                repository: "/tmp/any-repository", branch: "agentspace/x", path: workspaceDirectory + "/App"),
            sharedFolders: [],
            spaceID: UUID(),
            workspaceDirectory: workspaceDirectory,
            fileExists: { _ in true },
            isGitRepository: { _ in true },
            resolve: { _ in nil })
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error.recoveryHint, RecoveryHint.installCommandLineTools)
        XCTAssertFalse(error.message.contains("xcode-select"),
            "error must not send the user to a terminal: \(error.message)")
    }
}
