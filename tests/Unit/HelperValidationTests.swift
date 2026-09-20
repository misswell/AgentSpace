import XCTest
@testable import AgentSpaceCore

/// Adversarial tests for the helper's validation — the security boundary.
///
/// The helper is the only root component in AgentSpace, and it is the one part
/// that cannot be exercised without a second machine state. That is exactly the
/// combination that lets a claim go quietly unverified, so the rules it applies
/// were put in Core as a pure function and are attacked here instead.
///
/// These tests are written from the attacker's side: each one is a specific thing
/// somebody might try, not a description of the code. A test named
/// `testValidateUsername` proves nothing; `testDeleteUserRefusesTheHumanAccount`
/// is a claim about what cannot happen.
final class HelperValidationTests: XCTestCase {

    /// A plausible machine: one human account and one Space.
    private let machine: Set<String> = ["root", "daemon", "nobody", "_mbsetupuser", "guofeng", "_agentspace_a1b2c3"]

    // MARK: - Account naming

    func testGeneratedNamesAreAlwaysAccepted() {
        // Whatever the RNG produces must pass the check that gates deletion. If
        // these two ever disagreed, the helper would create accounts it then
        // refused to delete — which is a Space that can never be removed.
        for _ in 0..<2000 {
            let name = HelperValidation.generateAccountName()
            XCTAssertTrue(
                HelperValidation.isAgentSpaceAccount(name),
                "generateAccountName produced \(name), which isAgentSpaceAccount rejects")
        }
    }

    func testAccountNameShape() {
        let name = HelperValidation.generateAccountName()
        XCTAssertTrue(name.hasPrefix("_agentspace_"))
        XCTAssertEqual(name.count, "_agentspace_".count + 6)
    }

    func testHumanAndSystemAccountsAreNeverAgentSpaceAccounts() {
        let forbidden = [
            "guofeng", "root", "daemon", "nobody", "_mbsetupuser", "admin",
            "staff", "user", "_windowserver", "_securityagent",
        ]
        for name in forbidden {
            XCTAssertFalse(HelperValidation.isAgentSpaceAccount(name), "\(name) must never be treated as a Space")
        }
    }

    func testNamesThatLookCloseButAreNot() {
        // Every one of these is an attempt to get past the prefix test.
        let rejected = [
            "_agentspace_",              // no suffix
            "_agentspace_a1b2c",         // five characters
            "_agentspace_a1b2c34",       // seven
            "_agentspace_A1B2C3",        // uppercase
            "_agentspace_a1b2c-",        // punctuation
            "_agentspace_a1b2c ",        // trailing space
            " _agentspace_a1b2c3",       // leading space
            "_agentspace_a1b2c3 ",       // trailing space
            "agentspace_a1b2c3",         // no leading underscore
            "_AGENTSPACE_a1b2c3",        // case
            "x_agentspace_a1b2c3",       // prefix not at the start
            "_agentspace_/bin/sh",       // a path
            "_agentspace_..",            // traversal
            "_agentspace_$(id)",         // command substitution
            "_agentspace_;id",           // command separator
            "_agentspace_|id",           // pipe
            "_agentspace_a1b2c3\n",      // newline (log forging)
            "_agentspace_a1b2c3\t",      // tab
            "_agentspace_💥💥💥💥💥💥",       // non-ASCII
            "",                          // empty
        ]
        for name in rejected {
            XCTAssertFalse(HelperValidation.isAgentSpaceAccount(name), "\(name.debugDescription) must be rejected")
        }
    }

    func testAShellMetacharacterCannotSurviveIntoAnAccountName() {
        // The point of the closed alphabet, stated once as its own claim: there is
        // no character left in a valid name that any shell or argv parser would
        // treat specially. This is why a single rule is enough here.
        let shellSpecial = CharacterSet(charactersIn: " \t\n;|&$`'\"\\<>(){}[]*?!#~^%:,-=+/@")
        for _ in 0..<500 {
            let name = HelperValidation.generateAccountName()
            for scalar in name.unicodeScalars {
                XCTAssertFalse(shellSpecial.contains(scalar), "\(name) contains \(scalar)")
            }
        }
    }

    // MARK: - worker teardown and legacy session operation

    func testWorkerOperationsAcceptAnExistingStandardAccountButNotTheCurrentUser() {
        let attach = HelperRequest(
            operation: .installWorker,
            spaceID: UUID(),
            username: "agentdev",
            mainUser: "guofeng",
            runtimeRoot: "/Users/Shared/.AgentSpace")
        let current = HelperRequest(
            operation: .installWorker,
            spaceID: UUID(),
            username: "guofeng",
            mainUser: "guofeng",
            runtimeRoot: "/Users/Shared/.AgentSpace")
        let accounts = machine.union(["agentdev"])

        XCTAssertNil(HelperValidation.validate(attach, existingAccounts: accounts))
        XCTAssertNotNil(HelperValidation.validate(current, existingAccounts: accounts))
    }

    func testTeardownShapeSurvivesAnExternallyDeletedAccount() {
        let request = HelperRequest(
            operation: .removeRuntimeDirectory,
            spaceID: UUID(),
            username: "agentdev",
            mainUser: "guofeng",
            runtimeRoot: RuntimePaths.root,
            uid: 502)
        XCTAssertNil(HelperValidation.validate(request, existingAccounts: machine))

        var unbound = request
        unbound.uid = nil
        XCTAssertNotNil(HelperValidation.validate(unbound, existingAccounts: machine))
    }

    func testLegacyLogoutSessionIsAlwaysRefusedInV3() {
        let request = HelperRequest(
            operation: .logoutSession,
            username: "_agentspace_a1b2c3",
            uid: 502)
        XCTAssertEqual(
            HelperValidation.validate(request, existingAccounts: machine)?.code,
            .helperRejected)
    }

    // MARK: - legacy account mutation operations

    func testV3AlwaysRefusesCreateAndDeleteUser() {
        let create = HelperRequest(
            operation: .createUser,
            username: "_agentspace_9f8e7d",
            displayName: "Space 1",
            password: "legacy-wire-value")
        let delete = HelperRequest(
            operation: .deleteUser,
            username: "_agentspace_a1b2c3",
            removeHome: true)

        XCTAssertEqual(HelperValidation.validate(create, existingAccounts: machine)?.code, .helperRejected)
        XCTAssertEqual(HelperValidation.validate(delete, existingAccounts: machine)?.code, .helperRejected)
        XCTAssertTrue(HelperValidation.validate(create, existingAccounts: machine)?.message.contains("never creates") == true)
        XCTAssertTrue(HelperValidation.validate(delete, existingAccounts: machine)?.message.contains("never deletes") == true)
    }

    // MARK: - display names (the one free-text field)

    func testDisplayNameAcceptsOrdinaryText() {
        // Including non-ASCII, which is the common case for a real user.
        for name in ["Frontend", "Frontend Test", "前端测试", "Café — dev", "a"] {
            XCTAssertNil(HelperValidation.validateDisplayName(name), "\(name) was rejected")
        }
    }

    func testDisplayNameRejectsControlCharactersAndOverlongInput() {
        XCTAssertNotNil(HelperValidation.validateDisplayName(""))
        XCTAssertNotNil(HelperValidation.validateDisplayName("   "))
        XCTAssertNotNil(HelperValidation.validateDisplayName("a\nb"), "a newline could forge a log line")
        XCTAssertNotNil(HelperValidation.validateDisplayName("a\rb"))
        XCTAssertNotNil(HelperValidation.validateDisplayName("a\u{0}b"), "a NUL must not reach an argv element")
        XCTAssertNotNil(HelperValidation.validateDisplayName("a\u{7F}b"))
        XCTAssertNotNil(HelperValidation.validateDisplayName("a\u{2028}b"), "a line separator")
        XCTAssertNotNil(HelperValidation.validateDisplayName(String(repeating: "x", count: 65)))
    }

    func testDisplayNameIsBounded() {
        XCTAssertNil(HelperValidation.validateDisplayName(String(repeating: "x", count: 64)))
    }

    // MARK: - deleteUser — the check that matters most

    func testDeleteUserRefusesTheHumanAccount() {
        // If this test ever fails, AgentAccount can delete the user's own account.
        let request = HelperRequest(operation: .deleteUser, username: "guofeng", removeHome: true)
        let error = HelperValidation.validate(request, existingAccounts: machine)
        XCTAssertNotNil(error, "the helper agreed to delete the human's account")
        XCTAssertEqual(error?.code, .helperRejected)
    }

    func testDeleteUserRefusesEveryAccountItDidNotCreate() {
        for name in ["root", "daemon", "nobody", "_mbsetupuser", "guofeng", "_windowserver", "admin", ""] {
            let request = HelperRequest(operation: .deleteUser, username: name, removeHome: true)
            XCTAssertNotNil(
                HelperValidation.validate(request, existingAccounts: machine),
                "deleteUser would have accepted \(name.debugDescription)")
        }
    }

    func testDeleteUserRefusesProtectedAccountsEvenIfTheyMatchThePattern() {
        // A future change to the naming scheme must not quietly make these
        // deletable, so the protected list is checked independently of the prefix.
        for name in HelperValidation.protectedAccounts {
            XCTAssertFalse(HelperValidation.isAgentSpaceAccount(name), "\(name) is protected but passed the pattern")
        }
    }

    func testDeleteUserRefusesANonexistentAccount() {
        let request = HelperRequest(operation: .deleteUser, username: "_agentspace_ffffff")
        XCTAssertNotNil(HelperValidation.validate(request, existingAccounts: machine))
    }

    func testDeleteUserRefusesLegacyAgentSpaceAccounts() {
        let request = HelperRequest(operation: .deleteUser, username: "_agentspace_a1b2c3", removeHome: true)
        XCTAssertNotNil(HelperValidation.validate(request, existingAccounts: machine))
    }

    func testAWorkerLaunchAgentIsAquaOnlyAndRunsAsTheSpace() {
        // `LimitLoadToSessionType: Aqua` is why the worker lands in the Space's GUI
        // session. Without it the worker would start in a context with no window
        // server and refuse to run (exit 69) — a failure that looks like a bug in
        // the worker rather than a mistake in this plist.
        let spaceID = UUID()
        let plist = HelperCommand.workerLaunchAgent(
            spaceID: spaceID, username: "_agentspace_a1b2c3",
            workerPath: "/Users/_agentspace_a1b2c3/Library/LaunchAgents/agentspace-worker",
            runtimeRoot: "/Users/Shared/.AgentSpace")
        XCTAssertTrue(plist.contains("<key>LimitLoadToSessionType</key>"))
        XCTAssertTrue(plist.contains("<string>Aqua</string>"))
        XCTAssertTrue(plist.contains("<key>UserName</key>"))
        XCTAssertTrue(plist.contains("<string>_agentspace_a1b2c3</string>"))
        XCTAssertTrue(plist.contains(spaceID.uuidString))
    }

    func testInstalledWorkerPathIsRootOwnedAndOutsideTheAgentHome() {
        let path = HelperCommand.workerInstallPath(version: "0.1.0")

        XCTAssertEqual(
            path,
            "/Library/Application Support/AgentSpace/Worker/versions/0.1.0/agentspace-worker")
        XCTAssertFalse(path.hasPrefix("/Users/"))
        XCTAssertEqual(
            HelperCommand.workerExecutionPath,
            "/Library/Application Support/AgentSpace/Worker/active/agentspace-worker")
        XCTAssertFalse(HelperCommand.workerExecutionPath.contains("0.1.0"))
    }

    func testStartingWorkerReloadsTheLaunchAgentBeforeKickstart() {
        let spaceID = UUID(uuidString: "6EA2FB6B-2B91-4BEE-B7D0-7E76CA28C9A1")!
        let plist = HelperCommand.canonicalWorkerLaunchAgentPath(spaceID: spaceID)
        let commands = HelperCommand.workerReloadCommands(
            uid: 503, spaceID: spaceID, plistPath: plist)

        XCTAssertEqual(commands.bootout,
                       [HelperCommand.launchctl, "bootout", "gui/503/\(HelperCommand.workerLabel(spaceID: spaceID))"])
        XCTAssertEqual(commands.bootstrap,
                       [HelperCommand.launchctl, "bootstrap", "gui/503", plist])
        XCTAssertEqual(commands.kickstart,
                       [HelperCommand.launchctl, "kickstart", "-k", "gui/503/\(HelperCommand.workerLabel(spaceID: spaceID))"])
        XCTAssertTrue(plist.hasPrefix("/Library/Application Support/AgentSpace/Worker/"))
    }

    func testTheWorkerLaunchAgentPlistIsValidXML() {
        // A malformed plist would make launchd refuse the job, and the error the
        // user saw would be "the Space never starts" with nothing to go on.
        let plist = HelperCommand.workerLaunchAgent(
            spaceID: UUID(), username: "_agentspace_a1b2c3",
            workerPath: "/tmp/agentspace-worker", runtimeRoot: "/Users/Shared/.AgentSpace")
        guard let data = plist.data(using: .utf8) else { return XCTFail("not UTF-8") }
        var format = PropertyListSerialization.PropertyListFormat.xml
        XCTAssertNoThrow(
            try PropertyListSerialization.propertyList(from: data, options: [], format: &format),
            "the generated LaunchAgent is not a valid property list")
    }

    func testTheLaunchAgentLogPathsMatchRuntimePaths() {
        // §114a: a hand-written copy of the log paths here once diverged into a
        // phantom worker.log. The plist must take its paths from RuntimePaths —
        // and they must land inside the Space's runtime directory, which is
        // where doctor's fix text (and the layout list) says they are.
        let spaceID = UUID()
        let plist = HelperCommand.workerLaunchAgent(
            spaceID: spaceID, username: "_agentspace_a1b2c3",
            workerPath: "/tmp/agentspace-worker", runtimeRoot: "/Users/Shared/.AgentSpace")
        let paths = RuntimePaths(spaceID: spaceID, root: "/Users/Shared/.AgentSpace")
        XCTAssertTrue(plist.contains(paths.workerOutLogPath),
                      "plist stdout must be RuntimePaths.workerOutLogPath (\(paths.workerOutLogPath))")
        XCTAssertTrue(plist.contains(paths.workerErrLogPath),
                      "plist stderr must be RuntimePaths.workerErrLogPath (\(paths.workerErrLogPath))")
        XCTAssertFalse(plist.contains("worker.log"),
                       "the phantom worker.log must not come back")
    }

    func testTheLaunchDaemonPlistIsValidAndMatchesTheMachServiceName() throws {
        // The shipped daemon plist and the name the client connects to are two
        // files that must agree. A mismatch produces a silent timeout, which is
        // the hardest possible thing to debug, so it is asserted here instead.
        let path = "apps/AgentSpace/Resources/com.agentspace.AgentSpace.Helper.plist"
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else {
            throw XCTSkip("run from the repository root to check the shipped plist")
        }
        var format = PropertyListSerialization.PropertyListFormat.xml
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        let dictionary = try XCTUnwrap(plist as? [String: Any])

        XCTAssertEqual(dictionary["Label"] as? String, "com.agentspace.AgentSpace.Helper")
        XCTAssertEqual(dictionary["BundleProgram"] as? String, "Contents/Library/LaunchDaemons/agentspace-helper")
        let machServices = try XCTUnwrap(dictionary["MachServices"] as? [String: Any])
        XCTAssertNotNil(machServices[helperMachServiceName],
                        "the plist advertises \(machServices.keys.sorted()) but the client connects to \(helperMachServiceName)")
        XCTAssertEqual(dictionary["LimitLoadToSessionType"] as? String, "System")
        XCTAssertNil(dictionary["KeepAlive"], "KeepAlive would hide a crashing helper from a security review")
    }

    // MARK: - runtime directory

    func testRuntimeRootMustNotPointAtASystemDirectory() {
        // The helper chowns and chmods this path as root. A caller who could point
        // it at /System or /usr would be handing the helper a way to damage the OS.
        for bad in ["/", "/System", "/usr", "/etc", "/Users/guofeng", "/var/root", "/Library", "relative/path", "/Users/Shared/../.."] {
            XCTAssertNotNil(HelperValidation.validateRuntimeRoot(bad), "runtime root \(bad) was accepted")
        }
    }

    func testRuntimeRootAcceptsTheDocumentedLocations() {
        XCTAssertNil(HelperValidation.validateRuntimeRoot(RuntimePaths.root))
        XCTAssertNil(HelperValidation.validateRuntimeRoot("/Users/Shared/.AgentSpace"))
        XCTAssertNotNil(HelperValidation.validateRuntimeRoot("/tmp/as-test"))
        XCTAssertNotNil(HelperValidation.validateRuntimeRoot("/private/tmp/as-test"))
    }

    // MARK: - main user

    func testMainUserMustBeARealHumanAccount() {
        XCTAssertNil(HelperValidation.validateMainUser("guofeng", existingAccounts: machine))
        for bad in ["", "root", "_mbsetupuser", "_agentspace_a1b2c3", "nosuchuser", "-x", "a/b", ".."] {
            XCTAssertNotNil(
                HelperValidation.validateMainUser(bad, existingAccounts: machine),
                "main user \(bad.debugDescription) was accepted")
        }
    }

    func testASpaceCanNeverBeGrantedAccessToAnotherSpace() {
        // Granting an AgentSpace account access to a sibling's runtime directory
        // would hand over a socket carrying a live session token.
        let request = HelperRequest(
            operation: .prepareRuntimeDirectory,
            spaceID: UUID(),
            username: "_agentspace_a1b2c3",
            mainUser: "_agentspace_a1b2c3",
            runtimeRoot: "/Users/Shared/.AgentSpace")
        XCTAssertNotNil(HelperValidation.validate(request, existingAccounts: machine))
    }

    // MARK: - worker control

    func testWorkerControlRequiresBothASpaceIDAndItsAccount() {
        let missingID = HelperRequest(operation: .startWorker, username: "_agentspace_a1b2c3")
        XCTAssertNotNil(HelperValidation.validate(missingID, existingAccounts: machine))

        let missingUser = HelperRequest(operation: .startWorker, spaceID: UUID())
        XCTAssertNotNil(HelperValidation.validate(missingUser, existingAccounts: machine))

        let humanAccount = HelperRequest(operation: .startWorker, spaceID: UUID(), username: "guofeng")
        XCTAssertNotNil(HelperValidation.validate(humanAccount, existingAccounts: machine))

        let good = HelperRequest(operation: .startWorker, spaceID: UUID(), username: "_agentspace_a1b2c3")
        XCTAssertNil(HelperValidation.validate(good, existingAccounts: machine))
    }

    // MARK: - sessionInfo

    func testSessionInfoIsOnlyAnsweredForSpaceAccounts() {
        XCTAssertNil(HelperValidation.validate(
            HelperRequest(operation: .sessionInfo, username: "_agentspace_a1b2c3"),
            existingAccounts: machine))
        XCTAssertNotNil(HelperValidation.validate(
            HelperRequest(operation: .sessionInfo, username: "guofeng"),
            existingAccounts: machine))
    }

    // MARK: - helperStatus

    func testStatusNeedsNoArguments() {
        // The one operation the app can call before anything exists, so the UI can
        // ask "are you there?" without a Space.
        XCTAssertNil(HelperValidation.validate(
            HelperRequest(operation: .helperStatus), existingAccounts: []))
    }

    /// Split `prepareRuntimeDirectory` into its words, so a test can ask about
    /// components rather than accident-prone substrings.
    static func camelCaseWords(_ name: String) -> [String] {
        var words: [String] = []
        var current = ""
        for character in name {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    func testTheCamelCaseSplitterWorks() {
        // Otherwise the test above could pass vacuously.
        XCTAssertEqual(Self.camelCaseWords("prepareRuntimeDirectory"),
                       ["prepare", "Runtime", "Directory"])
        XCTAssertEqual(Self.camelCaseWords("createUser"), ["create", "User"])
        XCTAssertEqual(Self.camelCaseWords("deleteUser"), ["delete", "User"])
    }

    // MARK: - the operation list is closed

    func testThereIsNoGenericEscapeHatchInTheProtocol() {
        // A review question, encoded as a test: is there an operation whose name
        // suggests arbitrary execution, or one that carries a path or a command?
        // Whole words, not substrings: "prepareRuntimeDirectory" contains "run"
        // inside "Runtime", which says nothing about whether it is an escape
        // hatch. Matching substrings here would have forced a rename to satisfy a
        // test rather than to fix a problem.
        let forbidden: Set<String> = [
            "exec", "shell", "run", "spawn", "command", "eval", "script",
            "write", "read", "chmod", "chown", "file", "path", "arbitrary",
        ]
        for operation in HelperOperation.allCases {
            for word in Self.camelCaseWords(operation.rawValue) {
                XCTAssertFalse(forbidden.contains(word.lowercased()),
                               "operation \(operation.rawValue) has a '\(word)' component, which suggests a generic escape hatch")
            }
        }
        // The compatibility logout verb remains decodable but is refused; the
        // active V3 surface is worker/runtime management only.
        XCTAssertEqual(HelperOperation.allCases.count, 11)
    }

    func testNoRequestFieldCanCarryAnArbitraryCommand() {
        // The request has named, typed fields. This test fails the day somebody
        // adds a `command` or `path` field, which is the day the helper stops
        // being reviewable by reading one enum.
        // Every field populated, because JSONEncoder omits nil optionals and an
        // empty request would describe almost none of the shape.
        let request = HelperRequest(
            id: "x", operation: .helperStatus, spaceID: UUID(), username: "_agentspace_a1b2c3",
            displayName: "x", password: "x", removeHome: true, mainUser: "guofeng",
            runtimeRoot: "/tmp/x")
        let encoded = try! JSONEncoder().encode(request)
        let json = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        let allowed: Set<String> = [
            "id", "operation", "spaceID", "username", "displayName",
            "password", "removeHome", "mainUser", "runtimeRoot",
        ]
        XCTAssertEqual(Set(json.keys), allowed,
                       "the wire format gained a field; confirm it cannot carry a command")
    }
}
