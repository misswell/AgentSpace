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
}
