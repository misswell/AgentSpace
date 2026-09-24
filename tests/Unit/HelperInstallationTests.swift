import XCTest
@testable import AgentSpaceCore

/// The stale-helper verdict is the difference between "the UI lies green while
/// launchd serves a pre-update binary" and a reinstall prompt. The comparison
/// itself is pure; the hash readers are checked against each other on the
/// process this suite actually runs in.
final class HelperInstallationTests: XCTestCase {

    private func pingResult(_ fields: [String: JSONValue]) -> HelperResponse {
        HelperResponse(id: "ping", result: .obj(fields))
    }

    func testStaleVerdictNeedsAnExpectedHash() {
        // No helper in the bundle to compare against: no verdict is claimed.
        XCTAssertFalse(HelperInstallation.isHelperStale(reportedCDHash: nil, expectedCDHash: nil))
        XCTAssertFalse(HelperInstallation.isHelperStale(reportedCDHash: "aa", expectedCDHash: nil))
    }

    func testSilentHelperIsStaleAndMismatchIsStale() {
        // A helper predating selfCDHash reports nothing — that is an old build.
        XCTAssertTrue(HelperInstallation.isHelperStale(reportedCDHash: nil, expectedCDHash: "aa"))
        XCTAssertTrue(HelperInstallation.isHelperStale(reportedCDHash: "bb", expectedCDHash: "aa"))
        XCTAssertFalse(HelperInstallation.isHelperStale(reportedCDHash: "aa", expectedCDHash: "aa"))
    }

    func testStateSummaryAndFixTellTheStaleTruth() {
        let stale = state(ping: pingResult(["helperVersion": .string("0.1.0")]), isStale: true)
        XCTAssertEqual(stale.summary, "installed and answering, but running an older build")
        XCTAssertNotNil(stale.fix, "a stale helper must carry its one-button fix text")

        let current = state(ping: pingResult(["helperVersion": .string("0.1.0")]), isStale: false)
        XCTAssertEqual(current.summary, "installed and answering (version 0.1.0)")
        XCTAssertNil(current.fix)
    }

    private func state(ping: HelperResponse, isStale: Bool) -> HelperInstallation.State {
        HelperInstallation.State(ping: ping, isStaleBinary: isStale)
    }

    /// The two hash readers must agree on one and the same binary, or the
    /// comparison in `inspect` compares nothing real.
    func testRunningImageHashMatchesItsOwnFile() throws {
        let executable = Bundle.main.executableURL
        guard let executable else { throw XCTSkip("no executable URL for this test binary") }
        guard let live = HelperInstallation.currentProcessCDHash(),
              let onDisk = HelperInstallation.fileCDHash(executable) else {
            throw XCTSkip("code-signing information unavailable in this environment")
        }
        XCTAssertEqual(live, onDisk,
                       "the running image and its file must hash identically")
    }

    /// The app checks the helper by process rather than believing the helper's
    /// own account — which is the whole point: a helper that measures itself
    /// through the Security framework re-reads its own (replaced) file and
    /// swears it is current, so only an outside view of the running task catches
    /// it. The query must therefore work for a process that is not this one.
    func testRunningImageHashWorksForAnotherProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["5"]
        try process.run()
        defer { process.terminate() }

        let live = HelperInstallation.runningImageCDHash(ofProcessID: process.processIdentifier)
        process.waitUntilExit()
        XCTAssertEqual(live?.count, 40, "the kernel query returned no cdhash for a live process")

        // The self query is the same kernel query with this process's id.
        XCTAssertEqual(HelperInstallation.currentProcessCDHash(),
                       HelperInstallation.runningImageCDHash(ofProcessID: getpid()))
        // A process that is not there yields nothing, not a guess.
        XCTAssertNil(HelperInstallation.runningImageCDHash(ofProcessID: -1))
    }
}

/// The restart residue rule: launchd can only replace a job it manages, so a
/// worker started outside launchd survives an install+start and keeps the
/// runtime lock (§336 row 968). The scan parses `ps -axo pid=,uid=,command=`
/// output and is narrow by construction — the account's own uid, a command
/// line under one of the helper's own worker paths.
final class UnmanagedWorkerPidScanTests: XCTestCase {

    private let activePath = HelperCommand.workerExecutionPath
    private let versionsRoot = HelperCommand.workerInstallRoot + "/"

    func testFindsOnlyTheAccountOwnWorkerUnderHelperPaths() {
        let output = """
        \(1)  \(0) /sbin/launchd
        \(44421)  \(503) \(activePath) --space-id 6EA2FB6B-2B91-4BEE-B7D0-7E76CA28C9A1 --quiet
        \(21433)  \(503) \(versionsRoot)0.1.43/agentspace-worker --space-id 6EA2FB6B-2B91-4BEE-B7D0-7E76CA28C9A1
        \(86272)  \(501) \(activePath) --space-id 6EA2FB6B-2B91-4BEE-B7D0-7E76CA28C9A1
        \(555)  \(503) /Applications/Safari.app/Contents/MacOS/Safari
        \(600)  \(503) \(versionsRoot)../elsewhere/agentspace-worker
        garbage line without fields
        """
        let pids = HelperCommand.unmanagedWorkerPids(output, uid: 503,
                                                     executionPathPrefixes: [activePath, versionsRoot])
        XCTAssertEqual(pids, [600, 21433, 44421].sorted())
    }

    func testSameBinaryUnderAnotherUsersUidIsNeverTouched() {
        let output = "\(86272)  \(501) \(activePath) --quiet\n"
        XCTAssertTrue(HelperCommand.unmanagedWorkerPids(output, uid: 503,
                                                        executionPathPrefixes: [activePath]).isEmpty)
    }

    func testMalformedLinesAreSkippedRatherThanGuessed() {
        let output = "no-number here /path\n44421 not-a-uid \(activePath)\n44421 503\n"
        XCTAssertTrue(HelperCommand.unmanagedWorkerPids(output, uid: 503,
                                                        executionPathPrefixes: [activePath]).isEmpty)
    }
}
