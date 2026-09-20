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

    /// A Fusion proxy sees `move` actions while a person's cursor merely crosses
    /// it. Those must be the one input that cannot claim the lease, or hovering
    /// the window would keep the agent paused in five-second slices forever.
    func testOnlyPointerTravelIsExcludedFromClaimingTheHumanLease() {
        XCTAssertTrue(InputAction.move(x: 1, y: 1).isHover)
        XCTAssertFalse(InputAction.click(
            x: 1, y: 1, button: .left, count: 1, modifiers: []).isHover)
        XCTAssertFalse(InputAction.drag(
            fromX: 1, fromY: 1, toX: 9, toY: 9, button: .left, modifiers: []).isHover)
        XCTAssertFalse(InputAction.scroll(x: 1, y: 1, dx: 0, dy: -3).isHover)
        XCTAssertFalse(InputAction.key(combo: "cmd+c").isHover)
        XCTAssertFalse(InputAction.type(text: "hi").isHover)
    }
}
