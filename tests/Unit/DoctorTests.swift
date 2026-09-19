import XCTest
@testable import AgentSpaceCore

/// Doctor's check list — plan §38.
///
/// The orphan-account check is the one that came out of a real failure: a
/// create was interrupted after the account record existed, the helper's own
/// cleanup did not remove it, and the result was an account the app could
/// neither list nor delete. These tests pin the three states that matter —
/// unknown (helper unreachable), confirmed none, and confirmed orphans — and
/// the promise that only the fix that has an action carries a button.
final class DoctorTests: XCTestCase {

    private func orphanChecks(_ report: Doctor.Report) -> [Doctor.Check] {
        report.checks.filter { $0.name.contains("Orphaned") }
    }

    /// A caller that could not reach the helper must get *no* orphan check.
    /// Claiming a pass would be a lie, and claiming a failure would be worse.
    func testUnreachableHelperOmitsTheOrphanCheckEntirely() {
        let report = Doctor.run(orphanedAccounts: nil)
        XCTAssertTrue(orphanChecks(report).isEmpty)
    }

    func testNoOrphansIsAPassWithNoButton() {
        let report = Doctor.run(orphanedAccounts: [])
        guard let check = orphanChecks(report).first else { return XCTFail("expected an orphan check") }
        XCTAssertEqual(check.status, .pass)
        XCTAssertNil(check.actionHint, "a passing check must not offer a delete button")
        XCTAssertNil(check.fix)
    }

    func testOrphansFailAndNameEveryAccount() {
        let orphans = ["_agentspace_a5b707", "_agentspace_000001"]
        let report = Doctor.run(orphanedAccounts: orphans)
        guard let check = orphanChecks(report).first else { return XCTFail("expected an orphan check") }
        XCTAssertEqual(check.status, .fail)
        for name in orphans {
            XCTAssertTrue(check.detail.contains(name), "\(name) missing from: \(check.detail)")
        }
        XCTAssertNotNil(check.fix)
        XCTAssertNil(check.actionHint, "V3 never offers to delete a macOS user")
    }

    /// The inverse promise: only checks whose action the app actually
    /// implements may carry a hint. V3 retains only helper reinstall; legacy
    /// account records are reviewed in System Settings and never deleted here.
    func testOnlyChecksWithImplementedActionsCarryAnActionHint() {
        let report = Doctor.run(orphanedAccounts: ["_agentspace_a5b707"])
        let hinted = Set(report.checks.compactMap(\.actionHint))
        XCTAssertEqual(hinted, ["reinstallHelper"])
    }
}
