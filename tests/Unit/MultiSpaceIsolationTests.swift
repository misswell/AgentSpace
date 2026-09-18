import XCTest
@testable import AgentSpaceCore

/// Multi-Space isolation — plan §29 and §48.
///
/// The architecture is 1:N from the first line of code, or it is not: §48 says to
/// remove every `singleUser` / `computeruse` / `defaultSession` assumption rather
/// than to add them and unpick them later. There is no way to *test* that a
/// hard-coded assumption is absent, but there is a way to test the consequences,
/// which is what this file does.
///
/// The specific danger is not a crash. It is two Spaces quietly sharing something
/// they must not share — a socket, a token, a working tree, a launchd label — so
/// that one agent's actions land in the other's desktop, or two agents edit the
/// same checkout. Nothing goes red; it just becomes true. These tests assert that
/// every derived name and path is **pairwise disjoint** across many Spaces, which
/// is the property that makes the shared-nothing design real.
final class MultiSpaceIsolationTests: XCTestCase {

    private let ids = (0..<8).map { _ in UUID() }

    private func spaces(_ count: Int) -> [AgentSpace] {
        (0..<count).map { index in
            AgentSpace(
                id: ids[index],
                name: "Space \(index)",
                username: HelperValidation.generateAccountName(),
                uid: uid_t(700 + index),
                state: .needsLogin)
        }
    }

    // MARK: - One-to-one correspondence (§29)

    func testEverySpaceGetsItsOwnSocketTokenAndRuntimeDirectory() throws {
        let spaces = spaces(8)
        var sockets = Set<String>(), tokens = Set<String>(), runtimes = Set<String>()

        for space in spaces {
            let paths = RuntimePaths(spaceID: space.id)
            sockets.insert(paths.socketPath)
            tokens.insert(paths.tokenPath)
            runtimes.insert(paths.directory)
        }

        // If any of these collapsed, two Spaces would be talking to one worker —
        // meaning one agent's clicks land on the other's desktop while the caller
        // believes it addressed a different Space.
        XCTAssertEqual(sockets.count, 8, "two Spaces share a socket")
        XCTAssertEqual(tokens.count, 8, "two Spaces share a token file")
        XCTAssertEqual(runtimes.count, 8, "two Spaces share a runtime directory")
    }

    func testEverySpaceGetsItsOwnAccountNameAndLaunchdLabel() throws {
        let spaces = spaces(8)
        XCTAssertEqual(Set(spaces.map(\.username)).count, 8, "two Spaces share an account name")

        var labels = Set<String>(), plists = Set<String>()
        for space in spaces {
            let label = HelperCommand.workerLabel(spaceID: space.id)
            labels.insert(label)
            plists.insert(HelperCommand.launchAgentPath(username: space.username))
            // A launchd label is a global namespace: two jobs with one label means
            // the second silently refuses to load, producing a Space whose worker
            // never starts and no error anywhere.
        }
        XCTAssertEqual(labels.count, 8, "two Spaces share a launchd label")
        XCTAssertEqual(plists.count, 8, "two Spaces share a LaunchAgent plist path")
    }

    func testEverySpaceGetsItsOwnUidSlot() throws {
        // Not a real guarantee — the helper asks the OS — but it does catch the
        // "everyone is uid 0 / nobody" placeholder that would make the resource
        // aggregation in §30 sum every Space together.
        let spaces = spaces(8)
        XCTAssertEqual(Set(spaces.map(\.uid)).count, 8)
        XCTAssertFalse(spaces.contains { $0.uid == 0 || $0.uid == 501 },
                       "a Space was given root or the main user's uid")
    }

    // MARK: - Paths that must fit, and must not collide

    func testEverySocketPathFitsInSunPath() throws {
        // `sockaddr_un.sun_path` is 104 bytes including the terminator. Exceeding it
        // fails at `bind` with a message that does not mention length; the plan's
        // default layout uses 83 bytes, leaving room for a `--root` that is longer
        // than expected but not unbounded.
        for space in spaces(8) {
            let path = RuntimePaths(spaceID: space.id).socketPath
            let bytes = path.utf8.count
            XCTAssertLessThan(bytes, 104, "\(path) is \(bytes) bytes and will not bind")
        }
    }

    func testTwoSpacesNeverGetTheSameWorktreeEvenWithTheSameName() throws {
        // This is the bug this file was written to catch. The worktree path used to
        // be derived from the Space's *name*, so two Spaces called `Test` and
        // `test` resolved to one directory — and on a case-insensitive filesystem
        // those are the same directory, so both agents would edit one checkout. That
        // is precisely what the worktree exists to prevent.
        let options = SpaceProvisioner.Options(
            root: "/Users/Shared/.AgentSpace",
            workspaceDirectory: "/Users/Shared/.AgentSpace/Worktrees/test",
            mainUser: "guofeng")

        let first = SpaceProvisioner.confined(
            .gitWorktree(repository: "/Users/me/Code/MyApp", branch: "agentspace/a", path: "/ignored"),
            spaceID: ids[0], options: options)
        let second = SpaceProvisioner.confined(
            .gitWorktree(repository: "/Users/me/Code/MyApp", branch: "agentspace/b", path: "/ignored"),
            spaceID: ids[1], options: options)

        guard case .gitWorktree(_, _, let firstPath) = first,
              case .gitWorktree(_, _, let secondPath) = second else {
            return XCTFail("confining a git worktree changed its kind")
        }
        XCTAssertNotEqual(firstPath, secondPath, "two Spaces were given the same working tree")
        XCTAssertTrue(firstPath.contains(ids[0].uuidString), firstPath)
        XCTAssertTrue(secondPath.contains(ids[1].uuidString), secondPath)
        // The caller's ignored path must not survive: a path built before the Space
        // existed cannot be trusted to be unique.
        XCTAssertFalse(firstPath.contains("/ignored"))
    }

    func testConfiningLeavesSharedFoldersAndNoWorkspaceAlone() throws {
        // A shared folder is a path the user chose. Rewriting it would silently
        // point the agent somewhere the user did not pick.
        let options = SpaceProvisioner.Options(root: "/r", workspaceDirectory: "/w", mainUser: "u")
        XCTAssertEqual(SpaceProvisioner.confined(.sharedFolders, spaceID: ids[0], options: options), .sharedFolders)
        XCTAssertEqual(SpaceProvisioner.confined(.none, spaceID: ids[0], options: options), .none)
    }

    func testCreatingTwoSpacesWithTheSameNameBothSucceed() throws {
        // End to end through the provisioner, with the helper doubled: the same
        // name twice must produce two usable, separate Spaces rather than the
        // second failing on a directory the first one made.
        let root = "/tmp/multi-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }

        let repository = root + "/repo"
        try FileManager.default.createDirectory(atPath: repository, withIntermediateDirectories: true)
        for command in [
            ["/usr/bin/git", "-C", repository, "init", "-q", "-b", "main"],
            ["/usr/bin/git", "-C", repository, "config", "user.email", "t@example.com"],
            ["/usr/bin/git", "-C", repository, "config", "user.name", "T"],
        ] {
            XCTAssertEqual(WorkspacePreparer.run(command).exitCode, 0, "\(command)")
        }
        try "x".write(toFile: repository + "/README.md", atomically: true, encoding: .utf8)
        XCTAssertEqual(WorkspacePreparer.run(["/usr/bin/git", "-C", repository, "add", "-A"]).exitCode, 0)
        XCTAssertEqual(WorkspacePreparer.run(["/usr/bin/git", "-C", repository, "commit", "-q", "-m", "i"]).exitCode, 0)

        let keychain = KeychainStore(service: "com.agentspace.AgentSpace.tests.multi.\(UUID().uuidString.prefix(8))")
        defer { for id in keychain.storedSpaceIDs() { try? keychain.delete(for: id) } }

        var registry = SpaceRegistry()
        let options = SpaceProvisioner.Options(
            root: root, workspaceDirectory: root + "/Worktrees", mainUser: "guofeng")

        func transport(_ request: HelperRequest) throws -> HelperResponse {
            switch request.operation {
            case .createUser:
                return HelperResponse(id: request.id, result: .obj([
                    "username": .string(request.username ?? ""), "uid": .int(800)]))
            case .prepareRuntimeDirectory:
                let directory = "\(request.runtimeRoot ?? root)/Runtime/\(request.spaceID?.uuidString ?? "x")"
                try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                return HelperResponse(id: request.id, result: .obj(["runtimeDirectory": .string(directory)]))
            case .installWorker:
                return HelperResponse(id: request.id, result: .obj(["label": .string("x")]))
            default:
                return HelperResponse(id: request.id, result: .obj(["ok": .bool(true)]))
            }
        }

        var created: [AgentSpace] = []
        var paths: [String] = []
        // "Test" and "test" — the case that used to collide.
        for (index, name) in ["Test", "test"].enumerated() {
            let outcome = SpaceProvisioner.create(
                name: name,
                workspace: .gitWorktree(
                    repository: repository,
                    branch: "agentspace/\(index)",
                    path: root + "/ignored/\(name)"),
                sharedFolders: [], options: options,
                transport: transport, registry: registry, keychain: keychain)
            XCTAssertTrue(outcome.ok, "\(name): \(outcome.error?.message ?? "")")
            let space = try XCTUnwrap(outcome.space)
            created.append(space)
            registry.upsert(space)

            guard case .gitWorktree(_, _, let path) = space.workspace else {
                return XCTFail("the workspace stopped being a worktree")
            }
            paths.append(path)
        }

        XCTAssertNotEqual(paths[0], paths[1], "the two Spaces share a working tree")
        XCTAssertEqual(Set(created.map(\.username)).count, 2)
        XCTAssertEqual(registry.spaces.count, 2, "the second Space overwrote the first")

        // Both worktrees are real, and both are on their own branch.
        for (index, path) in paths.enumerated() {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path + "/README.md"), path)
            let branch = WorkspacePreparer.run(["/usr/bin/git", "-C", path, "rev-parse", "--abbrev-ref", "HEAD"]).output
            XCTAssertEqual(branch.trimmingCharacters(in: .whitespacesAndNewlines), "agentspace/\(index)")
        }
        // And the user's own tree is still on main.
        let userBranch = WorkspacePreparer.run(["/usr/bin/git", "-C", repository, "rev-parse", "--abbrev-ref", "HEAD"]).output
        XCTAssertEqual(userBranch.trimmingCharacters(in: .whitespacesAndNewlines), "main")
    }

    // MARK: - Addressing (§29: no single-Space assumption)

    func testResolvingByNameIsUnambiguousOrRefuses() throws {
        // With two Spaces present, addressing must never silently pick one. A tool
        // that guesses is a tool that acts on the wrong desktop.
        let registry = SpaceRegistry(spaces: spaces(3))

        XCTAssertEqual(try registry.resolve("Space 1").get().id, ids[1])
        XCTAssertEqual(try registry.resolve(ids[2].uuidString).get().id, ids[2])
        XCTAssertEqual(try registry.resolve("space 0").get().id, ids[0], "exact and case-insensitive should both work")

        // Not found names the Spaces that *do* exist, so the caller can correct
        // itself without a second round trip.
        let missing = registry.resolve("nope")
        guard case .failure(let error) = missing else { return XCTFail("resolved a Space that does not exist") }
        XCTAssertTrue(error.message.contains("Space 0"), error.message)
    }

    func testAnAmbiguousNameRefusesAndOffersTheUUIDs() throws {
        // Reachable on a case-insensitive filesystem, and the failure mode if it
        // were guessed is that commands silently act on the wrong Space.
        var registry = SpaceRegistry()
        var first = AgentSpace(name: "Dev", username: "_agentspace_aaaaaa", uid: 1)
        var second = AgentSpace(name: "DEV", username: "_agentspace_bbbbbb", uid: 2)
        first.id = UUID(); second.id = UUID()
        registry.upsert(first)
        registry.upsert(second)

        // Both exact spellings work…
        XCTAssertEqual(try registry.resolve("Dev").get().id, first.id)
        XCTAssertEqual(try registry.resolve("DEV").get().id, second.id)

        // …and a third spelling that matches neither exactly is refused, naming
        // both UUIDs rather than choosing.
        guard case .failure(let error) = registry.resolve("dEv") else {
            return XCTFail("an ambiguous name was resolved to one Space")
        }
        XCTAssertTrue(error.message.contains(first.id.uuidString), error.message)
        XCTAssertTrue(error.message.contains(second.id.uuidString), error.message)
    }

    func testTheEmptyRegistrySaysWhatToDoRatherThanSomethingWentWrong() throws {
        // §21: no vague errors. The first-run message is the one a new user is
        // most likely to see.
        guard case .failure(let error) = SpaceRegistry().resolve("anything") else {
            return XCTFail("resolved a Space from an empty registry")
        }
        XCTAssertEqual(error.code, .sessionNotReady)
        XCTAssertTrue(error.message.contains("agentspace doctor"), error.message)
    }

    // MARK: - Accounts cannot collide with the system

    func testGeneratedAccountNamesNeverCollideWithProtectedAccounts() throws {
        // The helper refuses to delete anything outside `_agentspace_<6 hex>`, so a
        // generated name that fell inside the protected list would be an account
        // that can be created and never removed.
        for _ in 0..<200 {
            let name = HelperValidation.generateAccountName()
            XCTAssertFalse(HelperValidation.protectedAccounts.contains(name), name)
            XCTAssertTrue(HelperValidation.isAgentSpaceAccount(name), name)
        }
        for protected in HelperValidation.protectedAccounts {
            XCTAssertFalse(HelperValidation.isAgentSpaceAccount(protected),
                           "\(protected) would be treated as a deletable Space account")
        }
    }
}
