import XCTest
@testable import AgentSpaceCore

/// The human lease is what lets travel reach the agent, and only an explicit
/// claim renews it: hovering never extends it, because a cursor merely crossing
/// somebody else's picture must not keep an agent paused (`InputLeaseTests` pins
/// that rule from the worker's side). The other half of the rule lives here.
///
/// A person who has *captured* a surface is driving it, so their movement has to
/// keep the lease alive. Without that, a captured desktop stops following five
/// seconds in — every later move is refused as a leftover hover while the cursor
/// stays hidden and presses keep working, which is exactly the field report in
/// `docs/validation.md` §342: 「接管了，但不跟随，点击仍有效」.
final class CapturedTravelLeaseTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// The image fills the view, so every point below is over the picture.
    private var surface: PreviewMapping {
        PreviewMapping(imageWidth: 1920, imageHeight: 1080,
                       displayWidth: 1920, displayHeight: 1080,
                       viewWidth: 960, viewHeight: 540)
    }

    /// Thirty seconds of moving over a captured desktop, wired exactly the way
    /// `RemoteSurfaceNSView.mouseMoved` wires it: renew when the tracker says a
    /// renewal is due, then post the travel. Every single move has to be
    /// deliverable — `deliversHover` is the worker's own predicate for
    /// `refusedLease`, the refusal that dropped the pointer in the field.
    func testCapturedTravelNeverLetsTheLeaseLapse() {
        var tracker = RemotePointerGestureTracker()
        let lease = InputLeaseManager(duration: 5)
        tracker.beginControl(rawPhases: true)
        lease.claimHuman(now: start)

        var now = start
        while now.timeIntervalSince(start) < 30 {
            if tracker.moveRenewalDue(now: now) { lease.claimHuman(now: now) }
            let gesture = tracker.pointerMoved(to: CGPoint(x: 480, y: 270), in: surface, now: now)
            let elapsed = now.timeIntervalSince(start)
            XCTAssertNotNil(gesture, "captured travel produced no gesture at +\(elapsed)s")
            XCTAssertTrue(lease.deliversHover(now: now),
                          "travel would be refused as refusedLease at +\(elapsed)s")
            now = now.addingTimeInterval(0.5)
        }
    }

    /// The defect this file exists for, kept as a red reminder: with no renewal
    /// the same session loses the lease at five seconds, and every move after it
    /// is refused — while a press is not lease-gated at all, which is why the
    /// field saw a frozen pointer and working clicks at the same time.
    func testWithoutARenewalTravelIsRefusedFromTheSixthSecond() {
        var tracker = RemotePointerGestureTracker()
        let lease = InputLeaseManager(duration: 5)
        tracker.beginControl(rawPhases: true)
        lease.claimHuman(now: start)

        var refused = 0
        var now = start
        while now.timeIntervalSince(start) < 8 {
            _ = tracker.pointerMoved(to: CGPoint(x: 480, y: 270), in: surface, now: now)
            if !lease.deliversHover(now: now) { refused += 1 }
            now = now.addingTimeInterval(0.5)
        }
        XCTAssertGreaterThan(refused, 0,
                             "the unrenewed lease must still lapse, or this test no longer describes the defect")
        XCTAssertEqual(refused, 6, "refused from +5.0s to +7.5s inclusive: six of the sixteen samples")
    }

    /// The renewal interval has to be shorter than the lease, or driving would
    /// lapse in the middle of driving.
    func testTheRenewalIntervalIsShorterThanTheLeaseItProtects() {
        XCTAssertLessThan(RemotePointerGestureTracker.leaseRenewalSeconds,
                          RemotePointerGestureTracker.humanLeaseSeconds)
    }

    /// A renewal is asked for at the drag renewal's own rate, not once per mouse
    /// event: travel reports at the panel's rate, and a renewal packet per event
    /// would be the request/reply shape this channel exists to remove.
    func testCapturedRenewalKeepsTheDragRenewalRate() {
        var tracker = RemotePointerGestureTracker()
        tracker.beginControl(rawPhases: true)
        XCTAssertTrue(tracker.moveRenewalDue(now: start))
        XCTAssertFalse(tracker.moveRenewalDue(now: start.addingTimeInterval(0.5)))
        XCTAssertFalse(tracker.moveRenewalDue(now: start.addingTimeInterval(1.99)))
        XCTAssertTrue(tracker.moveRenewalDue(now: start.addingTimeInterval(2)),
                      "two seconds later a renewal is due again")

        tracker.endControl()
        XCTAssertFalse(tracker.moveRenewalDue(now: start.addingTimeInterval(10)),
                       "a surface that is no longer captured renews nothing")
    }

    /// The invariant the worker's own rule protects: a picture the person has
    /// not captured must not have its travel renew anything, however engaged the
    /// tracker is by a deliberate action.
    func testOnlyACapturedSurfaceRenewsOnMovement() {
        var tracker = RemotePointerGestureTracker()
        let click = start
        _ = tracker.beganPress(at: CGPoint(x: 480, y: 270), button: .left, modifiers: [],
                               in: surface, now: click)
        _ = tracker.endedPress(at: CGPoint(x: 480, y: 270), clickCount: 1, in: surface, now: click)

        // The click bought five seconds of meaningful travel…
        XCTAssertTrue(tracker.isEngaged(at: click.addingTimeInterval(3)))
        // …and none of it may extend the lease.
        XCTAssertFalse(tracker.moveRenewalDue(now: click.addingTimeInterval(3)))

        tracker.beginControl(rawPhases: true)
        XCTAssertTrue(tracker.moveRenewalDue(now: click.addingTimeInterval(3)),
                      "the same movement, over a surface this person captured, is what keeps the lease alive")
    }
}
