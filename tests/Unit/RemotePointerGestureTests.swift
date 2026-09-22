import XCTest
@testable import AgentSpaceCore

/// What a remote surface has to conclude about a hand. Every case here is
/// something the desktop viewer could not do before this type existed: hover,
/// select text, drag a slider, or scroll slowly.
final class RemotePointerGestureTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// A 1920x1080 image in a 960x540 view: the same aspect ratio, so the image
    /// fills the view and every fraction below is about the gesture rather than
    /// about the letterbox.
    private var square: PreviewMapping {
        PreviewMapping(imageWidth: 1920, imageHeight: 1080,
                       displayWidth: 1920, displayHeight: 1080,
                       viewWidth: 960, viewHeight: 540)
    }
    /// The same image in a tall view: the picture occupies top-left rows 450…990,
    /// so the bars above and below belong to the window, not to the desktop.
    private var letterboxed: PreviewMapping {
        PreviewMapping(imageWidth: 1920, imageHeight: 1080,
                       displayWidth: 1920, displayHeight: 1080,
                       viewWidth: 960, viewHeight: 1440)
    }

    private func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    /// The isolation rule: the main user's cursor crossing a picture of another
    /// session is not that person taking over. Forwarding it would activate the
    /// agent's app and move its pointer mid-task.
    func testPassiveCrossingForwardsNothing() {
        var tracker = RemotePointerGestureTracker()
        XCTAssertNil(tracker.pointerMoved(to: point(100, 100), in: square, now: start))
        XCTAssertNil(tracker.pointerMoved(to: point(500, 300), in: square, now: start.addingTimeInterval(1)))
        XCTAssertFalse(tracker.isEngaged(at: start.addingTimeInterval(1)))
    }

    /// A deliberate action buys one lease length of travel — the same five seconds
    /// the worker grants, and the worker decides either way.
    func testAClickMakesTheTravelThatFollowsItMeaningfulAndThatExpires() {
        var tracker = RemotePointerGestureTracker()
        XCTAssertTrue(tracker.beganPress(at: point(480, 270), button: .left, modifiers: [],
                                        in: square, now: start))
        _ = tracker.endedPress(at: point(480, 270), clickCount: 1, in: square, now: start)

        XCTAssertEqual(tracker.pointerMoved(to: point(240, 405), in: square, now: start.addingTimeInterval(4)),
                       .hover(u: 0.25, v: 0.25))
        XCTAssertNil(tracker.pointerMoved(to: point(240, 405), in: square, now: start.addingTimeInterval(6)),
                     "travel stops meaning something when the lease it was bought with runs out")
    }

    /// Press and release in the same place is a click *where it went down* — which
    /// is why the gesture is resolved on release rather than on press, and why the
    /// release point is not what the remote gets.
    func testAPressThatBarelyMovesIsAClickAtThePress() {
        var tracker = RemotePointerGestureTracker()
        tracker.beganPress(at: point(480, 270), button: .left, modifiers: [], in: square, now: start)
        XCTAssertEqual(tracker.endedPress(at: point(482, 271), clickCount: 1, in: square, now: start),
                       .click(u: 0.5, v: 0.5, button: .left, count: 1, modifiers: []))
    }

    /// The regression this change is about: selecting text, moving a slider knob and
    /// drawing a marquee all need the button held between two points, which a click
    /// followed by moves cannot express.
    func testAPressThatTravelsIsADragFromThePressToTheRelease() {
        var tracker = RemotePointerGestureTracker()
        tracker.beganPress(at: point(240, 405), button: .left, modifiers: [], in: square, now: start)
        _ = tracker.dragged(to: point(500, 300), now: start.addingTimeInterval(0.1))
        XCTAssertEqual(tracker.endedPress(at: point(720, 135), clickCount: 1, in: square,
                                         now: start.addingTimeInterval(0.2)),
                       .drag(fromU: 0.25, fromV: 0.25, toU: 0.75, toV: 0.75,
                             button: .left, modifiers: []))
    }

    /// Three points of jitter is still a click; four is a drag. Both surfaces have
    /// to agree on where that line is, or the same hand means different things in
    /// a viewer and in a proxy.
    func testTheDragThresholdIsTheSameOnBothSidesOfIt() {
        for (distance, isDrag) in [(2.0, false), (3.0, false), (4.0, true)] {
            var tracker = RemotePointerGestureTracker()
            tracker.beganPress(at: point(400, 300), button: .left, modifiers: [], in: square, now: start)
            _ = tracker.dragged(to: point(400 + distance, 300), now: start)
            let gesture = tracker.endedPress(at: point(400 + distance, 300), clickCount: 1,
                                            in: square, now: start)
            switch (isDrag, gesture) {
            case (true, .drag), (false, .click): break
            default: XCTFail("moved \(distance) pt: expected drag=\(isDrag), got \(String(describing: gesture))")
            }
        }
    }

    /// A drag whose release drifted over the black bar still has to let go. Dropping
    /// it would leave the remote app believing the button is still held — text
    /// selection stuck, window move stuck — with nothing on screen left to release.
    func testADragThatEndsInTheLetterboxStillReleasesAtTheEdge() {
        var tracker = RemotePointerGestureTracker()
        tracker.beganPress(at: point(480, 700), button: .left, modifiers: [], in: letterboxed, now: start)
        _ = tracker.dragged(to: point(480, 730), now: start)
        guard case .drag(let fromU, let fromV, let toU, let toV, let button, _) =
            tracker.endedPress(at: point(480, 60), clickCount: 1, in: letterboxed, now: start) else {
            return XCTFail("expected a drag, got a click or nothing")
        }
        XCTAssertEqual(fromU, 0.5, accuracy: 0.0001)
        XCTAssertEqual(toU, 0.5, accuracy: 0.0001)
        XCTAssertEqual(toV, 1, accuracy: 0.0001, "clamped onto the image rather than dropped")
        XCTAssertLessThan(fromV, toV, "the press was inside the image, above where the release landed")
        XCTAssertEqual(button, .left)
    }

    /// A press that started on the black bar belongs to the window's chrome, not to
    /// the remote desktop, and neither its release nor any travel it implies should
    /// reach the agent.
    func testAPressOutsideTheImageIsNotRemembered() {
        var tracker = RemotePointerGestureTracker()
        XCTAssertFalse(tracker.beganPress(at: point(480, 60), button: .left, modifiers: [],
                                          in: letterboxed, now: start))
        XCTAssertNil(tracker.endedPress(at: point(480, 700), clickCount: 1, in: letterboxed, now: start))
        XCTAssertFalse(tracker.isEngaged(at: start), "a click on the chrome is not a takeover")
    }

    /// A long drag takes more than the five seconds one lease lasts. Without a
    /// renewal the agent would resume in the middle of the person's gesture.
    func testAHeldButtonRenewsTheLeaseAndNotOncePerEvent() {
        var tracker = RemotePointerGestureTracker()
        tracker.beganPress(at: point(100, 100), button: .left, modifiers: [], in: square, now: start)
        XCTAssertFalse(tracker.dragged(to: point(200, 200), now: start.addingTimeInterval(0.5)),
                       "the press itself already claimed")
        XCTAssertTrue(tracker.dragged(to: point(201, 201), now: start.addingTimeInterval(2)))
        XCTAssertFalse(tracker.dragged(to: point(202, 202), now: start.addingTimeInterval(3)))
        XCTAssertTrue(tracker.dragged(to: point(203, 203), now: start.addingTimeInterval(4)))
        XCTAssertTrue(tracker.isEngaged(at: start.addingTimeInterval(6)),
                      "the renewal at four seconds carries the gesture past the original five")
    }

    /// Trackpad deltas are fractions. Rounding each event on its own turned a slow,
    /// careful two-finger slide into nothing at all.
    func testSlowScrollingAccumulatesIntoWholeLines() {
        var tracker = RemotePointerGestureTracker()
        for _ in 0..<2 {
            XCTAssertNil(tracker.scrolled(deltaX: 0, deltaY: 0.4, at: point(480, 270), in: square, now: start),
                         "less than a line is not yet a scroll")
        }
        XCTAssertEqual(tracker.scrolled(deltaX: 0, deltaY: 0.4, at: point(480, 270), in: square, now: start),
                       .scroll(u: 0.5, v: 0.5, linesX: 0, linesY: 1))
        XCTAssertEqual(tracker.scrolled(deltaX: 0, deltaY: 2.9, at: point(480, 270), in: square, now: start),
                       .scroll(u: 0.5, v: 0.5, linesX: 0, linesY: 3),
                       "the leftover tenth carries into the next event instead of being rounded away")
    }

    /// Scrolling is a deliberate action, so the travel after it is the same person
    /// looking for the next thing to move.
    func testScrollingMakesTravelMeaningful() {
        var tracker = RemotePointerGestureTracker()
        _ = tracker.scrolled(deltaX: 0, deltaY: 3, at: point(480, 270), in: square, now: start)
        XCTAssertNotNil(tracker.pointerMoved(to: point(400, 200), in: square, now: start.addingTimeInterval(1)))
    }

    /// A release with no press behind it — one that began in another window, or
    /// after the surface stopped being an input target — is nobody's gesture.
    func testAReleaseWithNoPressBehindItEmitsNothing() {
        var tracker = RemotePointerGestureTracker()
        XCTAssertNil(tracker.endedPress(at: point(100, 100), clickCount: 1, in: square, now: start))
        XCTAssertFalse(tracker.dragged(to: point(100, 100), now: start))
    }

    /// The button and the modifiers belong to the press, not to the release: a
    /// shift-click that lost its shift key over the last few milliseconds is still
    /// the shift-click the person started.
    func testThePressKeepsItsButtonAndModifiers() {
        var tracker = RemotePointerGestureTracker()
        tracker.beganPress(at: point(480, 270), button: .right, modifiers: [.shift, .cmd],
                           in: square, now: start)
        XCTAssertEqual(tracker.endedPress(at: point(480, 270), clickCount: 1, in: square, now: start),
                       .click(u: 0.5, v: 0.5, button: .right, count: 1, modifiers: [.shift, .cmd]))
    }

    /// The click count is AppKit's, not a guess: a second press in place has to
    /// arrive as a double click or opening a document from the desktop viewer means
    /// two single clicks on the same icon.
    func testASecondClickInPlaceIsReportedAsADoubleClick() {
        var tracker = RemotePointerGestureTracker()
        tracker.beganPress(at: point(480, 270), button: .left, modifiers: [], in: square, now: start)
        XCTAssertEqual(tracker.endedPress(at: point(480, 270), clickCount: 2, in: square, now: start),
                       .click(u: 0.5, v: 0.5, button: .left, count: 2, modifiers: []))
    }

    /// Revoking input has to forget both halves: the press in flight, and the
    /// engagement that was letting travel through. A desktop that just became the
    /// console must not finish the gesture it was in the middle of.
    func testResetDropsThePressAndTheEngagement() {
        var tracker = RemotePointerGestureTracker()
        tracker.beganPress(at: point(100, 100), button: .left, modifiers: [], in: square, now: start)
        _ = tracker.scrolled(deltaX: 0, deltaY: 5, at: point(100, 100), in: square, now: start)
        tracker.reset()
        XCTAssertNil(tracker.endedPress(at: point(400, 400), clickCount: 1, in: square, now: start))
        XCTAssertFalse(tracker.isEngaged(at: start))
        XCTAssertNil(tracker.pointerMoved(to: point(100, 100), in: square, now: start))
        XCTAssertFalse(tracker.dragged(to: point(100, 100), now: start), "no press is being tracked")
    }

    /// Typing into a proxy is a deliberate action too, so the pointer travel that
    /// follows it belongs to the same person.
    func testNoteEngagementMakesTravelMeaningfulForOneLease() {
        var tracker = RemotePointerGestureTracker()
        tracker.noteEngagement(now: start)
        XCTAssertNotNil(tracker.pointerMoved(to: point(100, 100), in: square, now: start.addingTimeInterval(4)))
        XCTAssertNil(tracker.pointerMoved(to: point(100, 100), in: square,
                                         now: start.addingTimeInterval(RemotePointerGestureTracker.humanLeaseSeconds)))
    }
}
