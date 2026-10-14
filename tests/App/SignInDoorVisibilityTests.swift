import XCTest
import AgentSpaceCore
@testable import AgentSpaceApp

/// Who the Screen Sharing door is offered to, and how it reads.
///
/// The bug this pins is the one the owner reported on 2026-10-14: the entry
/// appeared only while the account was offline or locked, so it vanished the
/// moment signing in worked — which is precisely when a person part-way through
/// three privacy grants needed it back. Approval must happen inside that
/// account's own session, and until Screen Recording is granted the built-in
/// viewer cannot show a frame of it, so the door is not a convenience.
final class SignInDoorVisibilityTests: XCTestCase {
    private func snapshot(
        state: SpaceState = .needsPermission,
        workerOnline: Bool,
        sessionVerdict: String? = "usable",
        desktopLocked: Bool = false
    ) -> SpaceSnapshot {
        var snapshot = SpaceSnapshot(space: AgentAccount(
            name: "Agent Use", username: "agentuse", uid: 503, state: state))
        snapshot.workerOnline = workerOnline
        snapshot.sessionVerdict = sessionVerdict
        snapshot.desktopLocked = desktopLocked
        return snapshot
    }

    /// The state the old condition hid the door in: signed in, answering,
    /// unlocked. Offered anyway — and no longer shouting.
    func testTheDoorStaysOfferedWhenTheAccountIsAlreadyUsable() {
        let ready = snapshot(workerOnline: true)
        XCTAssertTrue(ready.offersSignInDoor, "the door existed exactly when the account worked least, and vanished when it worked")
        XCTAssertFalse(ready.signInDoorIsUrgent, "an answering, unlocked desktop is a place to look, not a fault to fix")
    }

    /// Both halves of the old condition still read as urgent, and §374's rule
    /// keeps its shape: a locked account is offered the door *with* an online
    /// worker, because macOS locks a session that is otherwise perfectly alive.
    func testOfflineAndLockedBothKeepTheDoorAndRaiseIt() {
        let sleeping = snapshot(state: .needsLogin, workerOnline: false, sessionVerdict: nil)
        XCTAssertTrue(sleeping.offersSignInDoor)
        XCTAssertTrue(sleeping.signInDoorIsUrgent)

        let locked = snapshot(workerOnline: true, desktopLocked: true)
        XCTAssertTrue(locked.offersSignInDoor)
        XCTAssertTrue(locked.signInDoorIsUrgent, "a locked desktop cannot be approved in, whatever the worker says")
    }

    /// The one account with nowhere to sign in *to*: its session is the human's
    /// own physical console. `AccountLogin.permits` refuses it, and §3 forbids
    /// any path that drives that session instead.
    func testTheConsoleAccountIsNeverOfferedTheDoor() {
        let onDisplay = snapshot(workerOnline: true, sessionVerdict: "isConsole")
        XCTAssertEqual(onDisplay.effectiveState, .console)
        XCTAssertFalse(onDisplay.offersSignInDoor, "offering to Screen Share the person's own desktop is the fallback this product refuses to have")
    }
}
