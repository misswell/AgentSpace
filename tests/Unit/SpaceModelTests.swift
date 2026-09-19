import XCTest
import AgentSpaceCore

final class SpaceModelTests: XCTestCase {

    // MARK: State machine

    /// `console` is the important one. It is not an error, it is a refusal, and
    /// it must never be the state from which input is sent.
    func testOnlyReadyAndRunningAcceptInput() {
        for state in SpaceState.allCases {
            switch state {
            case .ready, .running:
                XCTAssertTrue(state.acceptsInput, "\(state) should accept input")
            case .created, .needsLogin, .needsPermission, .offline, .console, .error:
                XCTAssertFalse(state.acceptsInput, "\(state) must not accept input")
            }
        }
    }

    func testEveryStateHasADisplayName() {
        for state in SpaceState.allCases {
            XCTAssertFalse(state.displayName.isEmpty, "\(state) has no display name")
        }
    }

    func testStateRawValuesAreStableForTheUIRegistry() {
        // The raw values land in index.json, so changing one is a migration.
        XCTAssertEqual(SpaceState.needsLogin.rawValue, "needsLogin")
        XCTAssertEqual(SpaceState.needsPermission.rawValue, "needsPermission")
        XCTAssertEqual(SpaceState.console.rawValue, "console")
    }

    // MARK: Permissions

    func testPermissionStateReportsMissingGrantsInSetupOrder() {
        let none = PermissionState()
        XCTAssertFalse(none.allGranted)
        XCTAssertEqual(none.missing, ["Accessibility", "Screen Recording"])

        let partial = PermissionState(screenRecording: true, accessibility: false)
        XCTAssertEqual(partial.missing, ["Accessibility"])

        let full = PermissionState(screenRecording: true, accessibility: true)
        XCTAssertTrue(full.allGranted)
        XCTAssertTrue(full.missing.isEmpty)
    }

    // MARK: Shared folders

    func testSharedFolderDefaultsToReadOnly() {
        let folder = SharedFolder(path: "/Users/me/Documents/TestData")
        XCTAssertEqual(folder.access, .readOnly)
        XCTAssertEqual(folder.id, folder.path)
    }

    func testSharedFolderAccessDisplayNames() {
        XCTAssertEqual(SharedFolder.Access.readOnly.displayName, "Read Only")
        XCTAssertEqual(SharedFolder.Access.readWrite.displayName, "Read & Write")
    }

    // MARK: Workspace

    func testWorkspaceRoundTripThroughCodable() throws {
        let original = Workspace.gitWorktree(
            repository: "/Users/me/Code/MyApp",
            branch: "agentspace/a",
            path: "/Users/agent/.agentspace/worktrees/abc/MyApp")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Workspace.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertTrue(original.displayName.contains("agentspace/a"))
    }

    func testWorkspaceNoneAndSharedFoldersRoundTrip() throws {
        for workspace in [Workspace.none, Workspace.sharedFolders] {
            let data = try JSONEncoder().encode(workspace)
            XCTAssertEqual(try JSONDecoder().decode(Workspace.self, from: data), workspace)
        }
    }

    func testUnknownWorkspaceKindDecodesToNoneRatherThanFailing() throws {
        // Forward compatibility: a newer build may write a kind this one does
        // not know. Losing the workspace is survivable; failing to load the
        // whole registry is not.
        let data = Data(#"{"kind":"futureThing"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(Workspace.self, from: data), .none)
    }

    // MARK: Resources

    func testResourceFormatting() {
        let usage = ResourceUsage(cpuPercent: 8.4, memoryBytes: 1_460_000_000, processCount: 47)
        XCTAssertEqual(usage.processCount, 47)
        XCTAssertFalse(usage.memoryDisplay.isEmpty)
        XCTAssertFalse(usage.diskDisplay.isEmpty)
    }

    // MARK: Registry

    private func temporaryRoot() throws -> String {
        let root = NSTemporaryDirectory() + "/agentspace-registry-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        return root
    }

    func testRegistrySaveLoadRoundTrip() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }

        var registry = SpaceRegistry()
        let space = AgentAccount(
            name: "Frontend Test",
            username: "_agentspace_a37f91",
            uid: 502,
            workspace: .gitWorktree(repository: "/tmp/repo", branch: "agentspace/a", path: "/tmp/wt"),
            sharedFolders: [SharedFolder(path: "/tmp/data", access: .readWrite)])
        registry.upsert(space)
        try registry.save(root: root)

        let loaded = SpaceRegistry.load(root: root)
        XCTAssertEqual(loaded.spaces.count, 1)
        XCTAssertEqual(loaded.spaces[0].name, "Frontend Test")
        XCTAssertEqual(loaded.spaces[0].username, "_agentspace_a37f91")
        XCTAssertEqual(loaded.spaces[0].sharedFolders.count, 1)
        XCTAssertEqual(loaded.spaces[0].sharedFolders[0].access, .readWrite)
    }

    func testMissingRegistryIsAnEmptyRegistryNotACrash() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        XCTAssertTrue(SpaceRegistry.load(root: root).spaces.isEmpty)
    }

    func testResolveByNameUUIDAndCaseInsensitively() {
        let space = AgentAccount(name: "Frontend Test", username: "_agentspace_a", uid: 502)
        let other = AgentAccount(name: "Safari Test", username: "_agentspace_b", uid: 503)
        let registry = SpaceRegistry(spaces: [space, other])

        XCTAssertEqual(try? registry.resolve("Frontend Test").get().id, space.id)
        XCTAssertEqual(try? registry.resolve(space.id.uuidString).get().id, space.id)
        XCTAssertEqual(try? registry.resolve("frontend test").get().id, space.id)
        XCTAssertEqual(try? registry.resolve("SAFARI TEST").get().id, other.id)
    }

    func testResolveUnknownNameListsWhatExists() {
        let registry = SpaceRegistry(spaces: [
            AgentAccount(name: "Frontend Test", username: "_a", uid: 502),
        ])
        guard case .failure(let error) = registry.resolve("Nope") else {
            return XCTFail("should not resolve")
        }
        XCTAssertTrue(error.message.contains("Frontend Test"), error.message)
    }

    func testResolveAmbiguousNameIsRefusedRatherThanGuessed() {
        let a = AgentAccount(name: "Test", username: "_a", uid: 502)
        let b = AgentAccount(name: "test", username: "_b", uid: 503)
        let registry = SpaceRegistry(spaces: [a, b])
        guard case .failure(let error) = registry.resolve("TEST") else {
            return XCTFail("an ambiguous name must not resolve")
        }
        XCTAssertTrue(error.message.contains("matches 2"), error.message)
    }

    func testResolveEmptyRegistryExplainsWhatToDo() {
        guard case .failure(let error) = SpaceRegistry().resolve("anything") else {
            return XCTFail("should not resolve")
        }
        XCTAssertTrue(error.message.contains("no agent accounts exist yet"), error.message)
    }

    func testUpsertReplacesRatherThanDuplicates() {
        var registry = SpaceRegistry()
        var space = AgentAccount(name: "A", username: "_a", uid: 502)
        registry.upsert(space)
        space.name = "A renamed"
        registry.upsert(space)
        XCTAssertEqual(registry.spaces.count, 1)
        XCTAssertEqual(registry.spaces[0].name, "A renamed")
    }

    func testRemove() {
        var registry = SpaceRegistry()
        let space = AgentAccount(name: "A", username: "_a", uid: 502)
        registry.upsert(space)
        registry.remove(id: space.id)
        XCTAssertTrue(registry.spaces.isEmpty)
    }

    func testRegistryPersistsWorkspaceWithoutSecrets() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }

        var registry = SpaceRegistry()
        registry.upsert(AgentAccount(name: "A", username: "_a", uid: 502))
        try registry.save(root: root)

        // Plan §9: the account password lives in the Keychain and the session
        // token lives in the runtime directory. Neither may appear in the
        // registry, which is world-readable inside the shared root.
        let contents = try String(contentsOfFile: SpaceRegistry.path(root: root), encoding: .utf8)
        for forbidden in ["password", "passwd", "token", "secret", "keychain"] {
            XCTAssertFalse(contents.lowercased().contains(forbidden),
                           "the registry contains '\(forbidden)'")
        }
    }
}


// MARK: - plan(v2) §3/§5: AgentAccount vocabulary and purpose

extension SpaceModelTests {

    /// The registry JSON written by pre-V2 builds must decode unchanged: no
    /// purpose, no migration step, no missing-field failure.
    func testLegacyRegistryRecordDecodesAsAgentAccount() throws {
        let legacy = """
        {
          "autoStartWorker" : true,
          "createdAt" : "2026-09-01T00:00:00Z",
          "id" : "1B2C3D4E-5F60-4A2B-8C3D-000000000001",
          "name" : "Frontend Test",
          "permissions" : { "accessibility" : false, "screenRecording" : false },
          "sharedFolders" : [ ],
          "state" : "needsLogin",
          "uid" : 502,
          "username" : "_agentspace_a1b2c3",
          "workspace" : { "kind" : "none" }
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let account = try decoder.decode(AgentAccount.self, from: Data(legacy.utf8))
        XCTAssertEqual(account.displayName, "Frontend Test")
        XCTAssertEqual(account.macOSUsername, "_agentspace_a1b2c3")
        XCTAssertEqual(account.status, .needsLogin)
        XCTAssertNil(account.purpose)
    }

    func testPurposeRoundTripsAndOmitsWhenAbsent() throws {
        var account = AgentAccount(name: "Coding Agent", username: "_agentspace_def123", uid: 503)
        XCTAssertNil(account.purpose)
        account.purpose = .development

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(account)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["purpose"] as? String, "development")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AgentAccount.self, from: data)
        XCTAssertEqual(decoded.purpose, .development)

        // An account without a purpose must not carry the key at all, so the
        // registry file does not grow a field for every old record it touches.
        account.purpose = nil
        let bare = try encoder.encode(account)
        let bareObject = try JSONSerialization.jsonObject(with: bare) as? [String: Any]
        XCTAssertNil(bareObject?["purpose"])
    }
}
