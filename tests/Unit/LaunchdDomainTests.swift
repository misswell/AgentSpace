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
}
