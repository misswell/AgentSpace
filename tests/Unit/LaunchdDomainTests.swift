import XCTest
@testable import AgentSpaceCore

/// Fixtures taken verbatim from the Mac where sign-in never completed
/// (2026-10-10): `launchctl print gui/<uid>` answers three different questions,
/// and only two of them are answers.
final class LaunchdDomainTests: XCTestCase {
    /// The first lines of a live login domain. The real print for the console
    /// account was 145,268 bytes and for the agent account 108,928; both contain
    /// this shape, and neither contains `com.apple.uisecd` or `ATTRS` — which is
    /// what `sessionInfo` used to require, and why it never saw a session here.
    private static let liveDomain = """
        gui/501 = {
        \ttype = login
        \thandle = 100020
        \tactive count = 493
        \tservice count = 492
        \tactive service count = 235
        \tcreator = loginwindow[415]
        \tcreator euid = 0
        """

    /// What launchd writes for a uid with no GUI domain, measured as exit 112.
    private static let absentDomainError = """
        Bad request.
        Could not find domain for user gui: 99
        """

    /// Measured asking for *another* account's domain without root: launchd
    /// refuses. That is not evidence about whether the account is signed in.
    private static let refusalError = "Could not print domain: 1: Operation not permitted"

    private func verdict(_ exitCode: Int32, _ output: String = LaunchdDomainTests.liveDomain,
                         _ error: String = "") -> LaunchdDomain.Verdict {
        LaunchdDomain.verdict(exitCode: exitCode, output: output, errorOutput: error)
    }

    func testAPrintedLoginDomainIsASessionAndTheOldServiceNamesAreNotNeeded() {
        XCTAssertEqual(verdict(0), .graphical)
        XCTAssertFalse(Self.liveDomain.contains("uisec"))
        XCTAssertFalse(Self.liveDomain.contains("ATTR"))
        // A domain of some other kind is not a GUI login, even on exit 0.
        guard case .unusable(let detail) = verdict(0, "gui/501 = {\n\thandle = 7\n}") else {
            return XCTFail("a print with no type line must not answer the question")
        }
        XCTAssertTrue(detail.contains("no ‘type = login’ line"), detail)
    }

    func testAbsenceOfADomainIsAnAnswerButRefusalIsNot() {
        XCTAssertEqual(verdict(112, "", Self.absentDomainError), .absent)
        switch verdict(1, "", Self.refusalError) {
        case .unusable(let detail):
            XCTAssertTrue(detail.contains("exit 1"), detail)
            XCTAssertTrue(detail.contains("Operation not permitted"), detail)
        default:
            XCTFail("a refusal must not be reported as either a session or its absence")
        }
        // The distinction the whole round is about: only one of these means
        // "keep waiting for macOS".
        XCTAssertNotEqual(verdict(112, "", Self.absentDomainError), verdict(1, "", Self.refusalError))
    }

    /// The wire values are what a caller branches on, so they must stay stable
    /// even if the prose in `detail` is reworded.
    func testTheWireValuesCarryTheThreeOutcomes() {
        XCTAssertEqual(verdict(0).wireValue, "graphical")
        XCTAssertEqual(verdict(112, "", Self.absentDomainError).wireValue, "absent")
        XCTAssertEqual(verdict(1, "", Self.refusalError).wireValue, "unusable")
        XCTAssertTrue(verdict(0).detail(domain: "gui/501", bytes: 145268).contains("145268"))
    }

    /// Only the statuses that can change by themselves may be waited out.
    /// Measured on this Mac 2026-10-20: `launchctl print gui/0` and
    /// `launchctl bootstrap gui/0 …` both answer 125, the status the product
    /// met between a remote login and a ready desktop.
    func testOnlyLaunchdStatusesThatCanChangeAreRetried() {
        for code in [LaunchdDomain.alreadyLoadedExitCode,
                     LaunchdDomain.absentDomainExitCode,
                     LaunchdDomain.unsupportedActionExitCode] {
            XCTAssertTrue(LaunchdDomain.isTransientStatus(code), "exit \(code)")
            XCTAssertNotNil(
                LaunchdDomain.retryDelay(exitCode: code, attempts: 1, elapsed: 0),
                "exit \(code) was treated as final, so the person presses again")
        }
        for code: Int32 in [0, 1, 5, 113, -2] {
            XCTAssertFalse(LaunchdDomain.isTransientStatus(code), "exit \(code)")
            XCTAssertNil(LaunchdDomain.retryDelay(exitCode: code, attempts: 1, elapsed: 0),
                         "exit \(code) will answer the same way however long the helper waits")
        }
    }

    /// The wait is bounded twice: by the clock a person would spend watching,
    /// and by a cap that stops a millisecond-fast refusal from spinning.
    func testTheRetryBudgetEnds() {
        let busy = LaunchdDomain.unsupportedActionExitCode
        XCTAssertEqual(LaunchdDomain.retryDelay(exitCode: busy, attempts: 1, elapsed: 0),
                       LaunchdDomain.retryPause)
        XCTAssertNotNil(LaunchdDomain.retryDelay(
            exitCode: busy,
            attempts: LaunchdDomain.maximumRetryAttempts - 1,
            elapsed: LaunchdDomain.retryWindow - 0.1))
        XCTAssertNil(LaunchdDomain.retryDelay(
            exitCode: busy,
            attempts: LaunchdDomain.maximumRetryAttempts,
            elapsed: 0))
        XCTAssertNil(LaunchdDomain.retryDelay(
            exitCode: busy,
            attempts: 1,
            elapsed: LaunchdDomain.retryWindow))
        XCTAssertGreaterThanOrEqual(
            LaunchdDomain.retryWindow, 5,
            "the budget must outlast a GUI login transition; a shorter one turns the same press into an alert")
    }
}
