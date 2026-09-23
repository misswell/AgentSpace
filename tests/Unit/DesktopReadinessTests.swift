import XCTest
import AgentSpaceCore

/// The rule behind "no `CGEvent` into a session that is not ready".
///
/// A live session can only be in one state at a time, so every combination that
/// matters is pinned here instead: the worker posts events into whichever
/// session it happens to be running in, and a wrong answer is not visible until
/// somebody's click lands nowhere.
final class DesktopReadinessTests: XCTestCase {

    private func facts(
        readable: Bool = true,
        login: Bool? = true,
        graphic: Bool? = true,
        dock: Bool = true,
        finder: Bool = true,
        locked: Bool = false
    ) -> DesktopFacts {
        DesktopFacts(
            sessionDictionaryReadable: readable, loginDone: login, hasGraphicAccess: graphic,
            dockRunning: dock, finderRunning: finder, screenLocked: locked)
    }

    func testAFullyUpBackgroundSessionIsReady() {
        // The measured shape of the agent account's session on 2026-09-23:
        // login done, graphic access true, Dock pid 25866 and Finder pid 25870
        // running, not locked, not on the console.
        let readiness = DesktopReadinessCheck.evaluate(facts())
        XCTAssertTrue(readiness.isReady, readiness.summary)
        XCTAssertEqual(readiness.summary, "desktop ready")
    }

    func testADesktopMissingItsShellIsRefusedAndSaysWhichPart() {
        XCTAssertEqual(
            DesktopReadinessCheck.evaluate(facts(dock: false)).gaps, [.dock])
        XCTAssertEqual(
            DesktopReadinessCheck.evaluate(facts(finder: false)).gaps, [.finder])
        XCTAssertEqual(
            DesktopReadinessCheck.evaluate(facts(dock: false, finder: false)).gaps, [.dock, .finder])
    }

    func testAMidLoginSessionIsNotReady() {
        XCTAssertEqual(DesktopReadinessCheck.evaluate(facts(login: false)).gaps, [.login])
        // And a login nobody could read about is not a finished login.
        XCTAssertEqual(DesktopReadinessCheck.evaluate(facts(login: nil)).gaps, [.login])
    }

    func testAnUnreadableSessionOrWindowServerProbeIsAGapNotAPass() {
        XCTAssertEqual(
            DesktopReadinessCheck.evaluate(facts(readable: false)).gaps, [.sessionDictionary])
        XCTAssertEqual(
            DesktopReadinessCheck.evaluate(facts(graphic: false)).gaps, [.windowServer])
        XCTAssertEqual(
            DesktopReadinessCheck.evaluate(facts(graphic: nil)).gaps, [.windowServer],
            "a probe that cannot answer must not read as 'there is a window server'")
    }

    func testALockedSessionIsNotReady() {
        XCTAssertEqual(DesktopReadinessCheck.evaluate(facts(locked: true)).gaps, [.locked])
    }

    func testTheGapOrderIsStableSoTheMessageReadsFromTheOutsideIn() {
        let readiness = DesktopReadinessCheck.evaluate(
            facts(readable: false, login: nil, graphic: nil, dock: false, finder: false, locked: true))
        XCTAssertEqual(readiness.gaps,
                       [.sessionDictionary, .windowServer, .login, .locked, .dock, .finder])
        XCTAssertEqual(
            readiness.summary,
            "desktop not ready: the session dictionary could not be read, this session has no window server, "
                + "the desktop login has not finished, the session's screen is locked, the Dock is not running, "
                + "Finder is not running")
    }

    func testTheRefusalNamesTheGapAndTheFix() {
        let readiness = DesktopReadinessCheck.evaluate(facts(dock: false))
        let refusal = DesktopReadinessCheck.refusal(readiness, spaceName: "AgentUse")
        XCTAssertEqual(refusal?.code, .sessionNotReady)
        XCTAssertTrue(refusal?.message.contains("the Dock is not running") == true)
        XCTAssertTrue(refusal?.message.contains("AgentUse") == true)
        XCTAssertTrue(refusal?.message.contains("Log the agent account in") == true,
                      "a refusal has to name what to do about it")
    }

    func testAReadyDesktopHasNothingToRefuse() {
        XCTAssertNil(DesktopReadinessCheck.refusal(DesktopReadinessCheck.evaluate(facts()), spaceName: "x"))
    }
}
