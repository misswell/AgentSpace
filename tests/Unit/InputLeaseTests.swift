import XCTest
@testable import AgentSpaceCore

final class InputLeaseTests: XCTestCase {
    func testHumanInputBlocksAutomationForFiveSecondsAndRenewsOnActivity() {
        let lease = InputLeaseManager(duration: 5)
        let start = Date(timeIntervalSince1970: 100)

        lease.claimHuman(now: start)
        XCTAssertFalse(lease.automationAllowed(now: start.addingTimeInterval(4.99)))

        lease.claimHuman(now: start.addingTimeInterval(4))
        XCTAssertFalse(lease.automationAllowed(now: start.addingTimeInterval(8.99)))
        XCTAssertTrue(lease.automationAllowed(now: start.addingTimeInterval(9)))
    }

    func testExplicitAgentControlEndsTheHumanLease() {
        let lease = InputLeaseManager(duration: 5)
        let now = Date(timeIntervalSince1970: 100)
        lease.claimHuman(now: now)
        lease.releaseHuman()
        XCTAssertTrue(lease.automationAllowed(now: now))
    }
}
