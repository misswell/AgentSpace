import XCTest
@testable import AgentSpaceCore

/// The frame and pointer rates, and what raises them.
///
/// The numbers here are the product's answer to "why does a dragged window feel
/// remote", so the tests state the relationships rather than the constants: a
/// gesture outranks a stored preference, a preference is never exceeded while
/// nothing is happening, and pointer travel is independent of the frame rate.
final class InputRatePolicyTests: XCTestCase {

    func testAnIdleDesktopRunsBelowTheCeilingButNeverAtZero() {
        let policy = InputRatePolicy(ceiling: 30)
        let idle = policy.frames(for: .idle)
        XCTAssertGreaterThan(idle, 0, "a still stream still has to notice the next change")
        XCTAssertLessThan(idle, 30)
    }

    func testAnActiveDesktopRunsAtExactlyTheConfiguredRate() {
        for ceiling in [10, 30, 60] {
            XCTAssertEqual(InputRatePolicy(ceiling: ceiling).frames(for: .active), ceiling)
        }
    }

    /// A drag is the one case that deliberately exceeds the stored preference,
    /// and only up to 60: a window being dragged at 15 FPS does not look dragged,
    /// and asking the capture for more than 60 is beyond what the frame budget
    /// offers anyway.
    func testAGestureRaisesTheRateAndIsCappedAtSixty() {
        XCTAssertEqual(InputRatePolicy(ceiling: 5).frames(for: .interactive), 60)
        XCTAssertEqual(InputRatePolicy(ceiling: 15).frames(for: .interactive), 60)
        XCTAssertEqual(InputRatePolicy(ceiling: 30).frames(for: .interactive), 60)
        XCTAssertEqual(InputRatePolicy(ceiling: 60).frames(for: .interactive), 60)
    }

    /// A person who asked for 60 does not get 100: the ceiling is theirs.
    func testTheCeilingIsNeverExceeded() {
        let policy = InputRatePolicy(ceiling: 30)
        for activity in [FrameActivity.idle, .active, .interactive, .video] {
            XCTAssertLessThanOrEqual(policy.frames(for: activity), 60)
        }
        XCTAssertEqual(InputRatePolicy(ceiling: 1).frames(for: .active), 1)
    }

    /// Video is sustained high-damage content, not a gesture: it gets the
    /// ceiling rather than the gesture's boost.
    func testVideoFollowsTheCeiling() {
        XCTAssertEqual(InputRatePolicy(ceiling: 30).frames(for: .video), 60,
                       "video is the one content that benefits from the top rate")
        XCTAssertEqual(InputRatePolicy(ceiling: 60).frames(for: .video), 60)
    }

    /// Pointer travel does not follow the frame rate down. The cursor is drawn
    /// locally from a position the worker publishes; tying it to capture frames
    /// is the defect this whole round exists to remove.
    func testPointerTravelIsIndependentOfTheFrameCeiling() {
        let slowFrames = InputRatePolicy(ceiling: 5, pointerRate: 120)
        XCTAssertEqual(slowFrames.pointerInterval(for: .active), 1.0 / 120.0, accuracy: 1e-9)
        XCTAssertEqual(slowFrames.frames(for: .active), 5)
    }

    func testPointerRateIsClampedToTheRangeAHandCanTellApart() {
        XCTAssertEqual(InputRatePolicy(ceiling: 30, pointerRate: 5).pointerRate, 30)
        XCTAssertEqual(InputRatePolicy(ceiling: 30, pointerRate: 500).pointerRate, 120)
    }

    // MARK: - Activity

    func testActivityFallsToIdleAfterTheIdleWindow() {
        let start = Date()
        var tracker = FrameActivityTracker(now: start)
        XCTAssertEqual(tracker.activity(at: start), .active)
        XCTAssertEqual(tracker.activity(at: start.addingTimeInterval(FrameActivityTracker.idleAfter - 0.1)), .active)
        XCTAssertEqual(tracker.activity(at: start.addingTimeInterval(FrameActivityTracker.idleAfter + 0.1)), .idle)
    }

    func testAHeldButtonOutranksEverythingElse() {
        let start = Date()
        var tracker = FrameActivityTracker(now: start)
        tracker.notePress(true, at: start)
        XCTAssertEqual(tracker.activity(at: start.addingTimeInterval(FrameActivityTracker.idleAfter * 10)), .interactive,
                       "a still but held pointer is a gesture, not an idle desktop")
        tracker.notePress(false, at: start.addingTimeInterval(1))
    }

    func testSustainedDamageReadsAsVideo() {
        let start = Date()
        var tracker = FrameActivityTracker(now: start)
        tracker.noteSustainedDamage(true)
        XCTAssertEqual(tracker.activity(at: start.addingTimeInterval(FrameActivityTracker.idleAfter * 10)), .video)
    }

    // MARK: - Display refresh

    /// The pointer rate comes from the display rather than from a constant, and
    /// is clamped at both ends: below 30 Hz nothing is gained, and above 120 the
    /// packets cost more than the hand can use.
    func testThePointerRateFollowsTheDisplayWithinItsClamp() {
        XCTAssertEqual(DisplayRefresh.pointerRate(for: nil), DisplayRefresh.defaultPointerRate)
        XCTAssertGreaterThanOrEqual(DisplayRefresh.pointerRate(for: nil), 30)
        XCTAssertLessThanOrEqual(DisplayRefresh.pointerRate(for: nil), 120)
    }

    /// The coalescer's default is the display's interval, not the old 1/30. The
    /// 30 Hz default was chosen when the picture behind the pointer refreshed at
    /// 5-15 FPS; both ends of that sentence have changed.
    func testTheCoalescerDefaultIsTheDisplayRateNotThirty() {
        XCTAssertEqual(DisplayRefresh.defaultPointerInterval, 1.0 / DisplayRefresh.defaultPointerRate, accuracy: 1e-9)
        XCTAssertLessThan(DisplayRefresh.defaultPointerInterval, 1.0 / 30.0,
                          "the default is faster than the rate it replaced")
    }
}

/// The tracker's raw pointer model: a press goes out as a press.
final class RawPointerPhaseTests: XCTestCase {
    /// A 1:1 image in a 1:1 view, and the AppKit y flip is done for us by the
    /// mapping: `appKitY` is measured from the *bottom* of the view, so the
    /// helper below names points in image terms and converts.
    private let square = PreviewMapping(imageWidth: 1000, imageHeight: 1000,
                                        displayWidth: 500, displayHeight: 500,
                                        viewWidth: 1000, viewHeight: 1000)

    /// The AppKit point for a top-left position, so the tests read in the
    /// coordinate system the rest of the product uses.
    private func point(topLeftX: Double, topLeftY: Double) -> CGPoint {
        CGPoint(x: topLeftX, y: 1000 - topLeftY)
    }

    func testRawModeSendsThePressImmediatelyWithItsClickCount() {
        var tracker = RemotePointerGestureTracker()
        tracker.beginControl(rawPhases: true)
        let gesture = tracker.beganPressPhases(at: point(topLeftX: 250, topLeftY: 250), button: .left,
                                               clickCount: 2, modifiers: [.cmd],
                                               in: square, now: Date())
        XCTAssertEqual(gesture, .pointerDown(u: 0.25, v: 0.25, button: .left,
                                             clickCount: 2, modifiers: [.cmd]),
                       "the remote window server decides click vs drag, and it needs the press first")
    }

    /// The threshold model is what a proxy keeps, and it must not start
    /// streaming before the hand has actually travelled.
    func testThresholdModeStillWaitsForTravel() {
        var tracker = RemotePointerGestureTracker()
        tracker.beginControl(rawPhases: false)
        XCTAssertNil(tracker.beganPressPhases(at: point(topLeftX: 250, topLeftY: 250), button: .left,
                                              clickCount: 1, modifiers: [],
                                              in: square, now: Date()))
        let smallMove = tracker.dragged(to: point(topLeftX: 252, topLeftY: 250), in: square, now: Date())
        XCTAssertTrue(smallMove.gestures.isEmpty, "two points is still a click")
        let bigMove = tracker.dragged(to: point(topLeftX: 300, topLeftY: 250), in: square, now: Date())
        XCTAssertEqual(bigMove.gestures.first, .pointerDown(u: 0.25, v: 0.25, button: .left,
                                                            clickCount: 1, modifiers: []))
    }

    /// In raw mode even the first points travel: the window starts moving as soon
    /// as the hand does, instead of three points late.
    func testRawModeForwardsTravelBelowTheThreshold() {
        var tracker = RemotePointerGestureTracker()
        tracker.beginControl(rawPhases: true)
        _ = tracker.beganPressPhases(at: point(topLeftX: 250, topLeftY: 250), button: .left,
                                     clickCount: 1, modifiers: [], in: square, now: Date())
        let update = tracker.draggedPhases(to: point(topLeftX: 252, topLeftY: 250), in: square, now: Date())
        XCTAssertEqual(update.gestures, [
            .pointerDrag(fromU: 0.25, fromV: 0.25, toU: 0.252, toV: 0.25, button: .left, modifiers: []),
        ])
    }

    func testRawReleaseReportsItsOwnClickCount() {
        var tracker = RemotePointerGestureTracker()
        tracker.beginControl(rawPhases: true)
        _ = tracker.beganPressPhases(at: point(topLeftX: 250, topLeftY: 250), button: .left,
                                     clickCount: 2, modifiers: [], in: square, now: Date())
        XCTAssertEqual(tracker.endedPress(at: point(topLeftX: 250, topLeftY: 250), clickCount: 2,
                                          in: square, now: Date()),
                       .pointerUp(u: 0.25, v: 0.25, button: .left, clickCount: 2, modifiers: []))
    }

    func testRawPressDoesNotBecomeASecondClickWhenControlEndsBeforeRelease() {
        var tracker = RemotePointerGestureTracker()
        tracker.beginControl(rawPhases: true)
        let point = point(topLeftX: 250, topLeftY: 250)
        XCTAssertEqual(tracker.beganPressPhases(at: point, button: .left, clickCount: 1,
                                                modifiers: [], in: square, now: Date()),
                       .pointerDown(u: 0.25, v: 0.25, button: .left, clickCount: 1, modifiers: []))
        tracker.endControl()
        XCTAssertTrue(tracker.releaseTravelPhases(to: point, in: square, now: Date()).gestures.isEmpty)
        XCTAssertEqual(tracker.endedPress(at: point, clickCount: 1, in: square, now: Date()),
                       .pointerUp(u: 0.25, v: 0.25, button: .left, clickCount: 1, modifiers: []),
                       "a raw down must be matched by one up, even if capture changes during the press")
    }

    /// A surface that goes away mid-press must not leave the remote button held.
    func testCancellingARawPressEmitsARelease() {
        var tracker = RemotePointerGestureTracker()
        tracker.beginControl(rawPhases: true)
        _ = tracker.beganPressPhases(at: point(topLeftX: 500, topLeftY: 500), button: .left,
                                     clickCount: 1, modifiers: [], in: square, now: Date())
        XCTAssertEqual(tracker.cancelPress(),
                       .pointerUp(u: 0.5, v: 0.5, button: .left, clickCount: 1, modifiers: []))
    }

    /// Control takes over from the lease: entering a captured surface forwards
    /// travel with no lease at all, which is the behaviour that makes Desktop
    /// Mode hover work without a click first.
    func testControlForwardsTravelWithoutALease() {
        var tracker = RemotePointerGestureTracker()
        XCTAssertNil(tracker.pointerMoved(to: point(topLeftX: 500, topLeftY: 500), in: square, now: Date()),
                     "crossing a picture is not taking control")
        tracker.beginControl(rawPhases: true)
        XCTAssertEqual(tracker.pointerMoved(to: point(topLeftX: 500, topLeftY: 500), in: square, now: Date()),
                       .hover(u: 0.5, v: 0.5))
        tracker.endControl()
        XCTAssertNil(tracker.pointerMoved(to: point(topLeftX: 500, topLeftY: 500), in: square, now: Date()))
    }

    /// End control is not a lease: nothing may be left behind holding automation
    /// paused after the pointer has left.
    func testEndingControlLeavesNoEngagementBehind() {
        var tracker = RemotePointerGestureTracker()
        tracker.beginControl(rawPhases: true)
        XCTAssertTrue(tracker.isEngaged(at: Date()))
        tracker.endControl()
        XCTAssertFalse(tracker.isEngaged(at: Date()))
        XCTAssertFalse(tracker.isControlling)
        XCTAssertFalse(tracker.isRaw)
    }
}
