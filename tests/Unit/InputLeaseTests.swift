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

    /// Pointer travel is decoration, not intent: it is only worth posting while
    /// a human already holds the lease, and asking about it must not extend the
    /// lease. Otherwise tracking the mouse across a proxy pauses the agent in
    /// five-second slices for as long as the cursor happens to sit there.
    func testHoverRidesAnExistingLeaseAndNeverTakesOne() {
        let lease = InputLeaseManager(duration: 5)
        let start = Date(timeIntervalSince1970: 500)

        XCTAssertFalse(lease.deliversHover(now: start), "a passive cursor owns nothing")
        lease.claimHuman(now: start)
        XCTAssertTrue(lease.deliversHover(now: start.addingTimeInterval(4)))

        // Asking across the whole lease leaves the expiry untouched.
        for second in 0..<4 { _ = lease.deliversHover(now: start.addingTimeInterval(Double(second))) }
        XCTAssertEqual(lease.remaining(now: start.addingTimeInterval(4.99)), 0.01, accuracy: 0.001)

        XCTAssertFalse(lease.deliversHover(now: start.addingTimeInterval(5)))
    }
}
