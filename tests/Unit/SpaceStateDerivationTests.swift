import Foundation
import XCTest
@testable import AgentSpaceCore

/// The §39 derivation: what the UI should *say* a Space is, versus what the
/// registry last recorded. The reboot scenario is the point — after a restart
/// the stored state may still read `running`, the worker is gone, nobody has
/// logged into the agent account, and the honest answer is Needs Login, not
/// "offline, try again".
final class SpaceStateDerivationTests: XCTestCase {

    // MARK: - §39: the reboot scenario

    /// Stored `running`, worker gone, and the agent account owns no processes:
    /// nobody ever logged in (or the machine rebooted). The fix is a human
    /// fast-user-switch, so the UI must say Needs Login.
    func testRebootedSpaceShowsNeedsLoginNotOffline() {
        XCTAssertEqual(
            SpaceState.effective(
                stored: .running, workerOnline: false, sessionVerdict: nil,
                permissionProblem: nil, hasGraphicalSession: false),
            .needsLogin)
        XCTAssertEqual(
            SpaceState.effective(
                stored: .ready, workerOnline: false, sessionVerdict: nil,
                permissionProblem: nil, hasGraphicalSession: false),
            .needsLogin)
    }

    /// The same stored state, but the account owns processes: a session IS
    /// alive and only the worker died. That is genuinely offline — retrying
    /// (restarting the LaunchAgent) is the right fix, and Needs Login would
    /// send the user through a pointless login.
    func testCrashedWorkerUnderALiveSessionShowsOffline() {
        XCTAssertEqual(
            SpaceState.effective(
                stored: .running, workerOnline: false, sessionVerdict: nil,
                permissionProblem: nil, hasGraphicalSession: true),
            .offline)
    }

    /// When the session lookup cannot be performed, the pre-existing behaviour
    /// (offline) is kept rather than guessed at. §2's fail-closed rule is about
    /// *acting* on a session; this is only about labelling one, and inventing a
    /// Needs Login the user cannot verify would be worse than the label it
    /// replaced.
    func testUnknownSessionStateKeepsOffline() {
        XCTAssertEqual(
            SpaceState.effective(
                stored: .running, workerOnline: false, sessionVerdict: nil,
                permissionProblem: nil, hasGraphicalSession: nil),
            .offline)
    }

    // MARK: - The other derivations are unchanged

    func testPermissionProblemsWinOverEverything() {
        for verdict in [nil, "isConsole", "isBackground"] {
            XCTAssertEqual(
                SpaceState.effective(
                    stored: .running, workerOnline: true, sessionVerdict: verdict,
                    permissionProblem: .accessibilityDenied, hasGraphicalSession: true),
                .needsPermission)
            XCTAssertEqual(
                SpaceState.effective(
                    stored: .running, workerOnline: true, sessionVerdict: verdict,
                    permissionProblem: .screenRecordingDenied, hasGraphicalSession: true),
                .needsPermission)
        }
    }

    func testConsoleVerdictWinsOverStoredState() {
        XCTAssertEqual(
            SpaceState.effective(
                stored: .running, workerOnline: true, sessionVerdict: "isConsole",
                permissionProblem: nil, hasGraphicalSession: true),
            .console)
    }

    func testHealthySpacesShowWhatWasStored() {
        for state in SpaceState.allCases {
            XCTAssertEqual(
                SpaceState.effective(
                    stored: state, workerOnline: true, sessionVerdict: "isBackground",
                    permissionProblem: nil, hasGraphicalSession: true),
                state)
        }
    }

    // MARK: - The session discriminator itself

    /// This test process runs inside the console user's session, so the uid it
    /// runs as owns many processes. An absurd high uid owns none. Both halves
    /// are asserted: a lookup that always said "true" or always said "false"
    /// would pass the derivation tests above while protecting nothing.
    func testHasLiveProcessesDistinguishesTheConsoleUserFromNobody() {
        let own = uid_t(getuid())
        XCTAssertTrue(SystemSessions.hasLiveProcesses(uid: own),
                      "the running user must own processes")
        XCTAssertFalse(SystemSessions.hasLiveProcesses(uid: 40000),
                       "a uid that owns no processes must report none")
    }

    // MARK: - §346: the record advances when reality outruns it

    /// Measured 2026-09-28: a first worker start outlived the attach's
    /// readiness probe, the record stayed `.offline`, and the sidebar read
    /// Sleeping over an answering worker. Reconciliation is what moves the
    /// record the moment any refresh proves it wrong.
    func testAnAnsweringWorkerAdvancesAnOfflineRecord() {
        XCTAssertEqual(
            SpaceState.reconciled(stored: .offline, workerOnline: true,
                                  accessibility: false, screenRecording: false),
            .needsPermission)
        XCTAssertEqual(
            SpaceState.reconciled(stored: .offline, workerOnline: true,
                                  accessibility: true, screenRecording: true),
            .ready)
        // A grant given after the record said Needs Permission advances it
        // too — the same refresh that proves the grants exist proves the
        // Sleeping/Needs-Permission label wrong.
        XCTAssertEqual(
            SpaceState.reconciled(stored: .needsPermission, workerOnline: true,
                                  accessibility: true, screenRecording: true),
            .ready)
    }

    func testReconciliationNeverMovesStatesItDoesNotOwn() {
        for stored in [SpaceState.created, .needsLogin, .ready, .running, .console, .error] {
            XCTAssertNil(
                SpaceState.reconciled(stored: stored, workerOnline: true,
                                      accessibility: true, screenRecording: true),
                "\(stored) is another writer's verdict; reconciliation only advances the two waiting states")
        }
        // A worker that is not answering proves nothing new.
        XCTAssertNil(
            SpaceState.reconciled(stored: .offline, workerOnline: false,
                                  accessibility: false, screenRecording: false))
        // An accurate record costs no write.
        XCTAssertNil(
            SpaceState.reconciled(stored: .needsPermission, workerOnline: true,
                                  accessibility: false, screenRecording: false))
    }
}
