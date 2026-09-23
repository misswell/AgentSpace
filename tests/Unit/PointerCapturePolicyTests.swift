import XCTest
import CoreGraphics
@testable import AgentSpaceCore

/// Pointer capture: when the local cursor hides, when travel forwards, and every
/// way out of both.
///
/// This is the state machine that decides whether a person can see their own
/// pointer anywhere on their Mac, so the tests are about the exits as much as the
/// entries: every path out of capture has to restore the cursor, and the one way
/// to get that wrong is to leave a rectangle claimed.
final class PointerCapturePolicyTests: XCTestCase {

    // MARK: - Desktop Mode: entering is taking control

    func testDesktopModeCapturesOnEntryAndReleasesOnExit() {
        var controller = PointerCaptureController()
        controller.apply(.desktop)
        XCTAssertEqual(controller.state, .outside)

        XCTAssertEqual(controller.pointer(inside: true), .controlling)
        XCTAssertTrue(controller.state.hidesLocalCursor)
        XCTAssertTrue(controller.state.forwardsTravel)

        XCTAssertEqual(controller.pointer(inside: false), .outside)
        XCTAssertFalse(controller.state.hidesLocalCursor)
        XCTAssertFalse(controller.state.forwardsTravel)
    }

    /// A drag that leaves the picture must keep the button down. The gesture is
    /// the reason capture was taken; ending it because the hand crossed the
    /// letterbox would drop a slider mid-stroke.
    func testAGestureSurvivesLeavingTheImage() {
        var controller = PointerCaptureController()
        controller.apply(.desktop)
        _ = controller.pointer(inside: true)
        controller.pressStarted()
        XCTAssertEqual(controller.pointer(inside: false), .controlling,
                       "a held button keeps capture even when the pointer leaves")
        XCTAssertTrue(controller.isPressHeld)

        XCTAssertEqual(controller.pressEnded(pointerInside: false), .outside,
                       "the release is what ends it, and the pointer is outside")
    }

    func testAReleaseInsideKeepsControllingInDesktopMode() {
        var controller = PointerCaptureController()
        controller.apply(.desktop)
        _ = controller.pointer(inside: true)
        controller.pressStarted()
        XCTAssertEqual(controller.pressEnded(pointerInside: true), .controlling)
    }

    // MARK: - Fusion: press takes control

    func testAProxyCapturesOnPressNotOnEntry() {
        var controller = PointerCaptureController()
        controller.apply(.fusionProxy)
        XCTAssertEqual(controller.pointer(inside: true), .hovering)
        XCTAssertFalse(controller.state.hidesLocalCursor)
        XCTAssertFalse(controller.state.forwardsTravel)

        controller.pressStarted()
        XCTAssertEqual(controller.state, .controlling)
        XCTAssertTrue(controller.state.hidesLocalCursor)

        // Releasing inside a proxy returns to hovering rather than to controlling:
        // the person may still be reading that window, but they are not holding it.
        XCTAssertEqual(controller.pressEnded(pointerInside: true), .hovering)
    }

    // MARK: - Off

    func testOffNeverCaptures() {
        var controller = PointerCaptureController()
        controller.apply(.watchOnly)
        XCTAssertEqual(controller.pointer(inside: true), .outside)
        controller.pressStarted()
        XCTAssertEqual(controller.state, .outside)
        XCTAssertFalse(controller.state.hidesLocalCursor)
    }

    /// Changing to `off` while capture is held must return the pointer. This is
    /// the preference switch, and a person who turns capture off has to get their
    /// cursor back in the same instant.
    func testSwitchingToOffReleasesCapture() {
        var controller = PointerCaptureController()
        controller.apply(.desktop)
        _ = controller.pointer(inside: true)
        XCTAssertTrue(controller.state.hidesLocalCursor)
        controller.apply(.watchOnly)
        XCTAssertEqual(controller.state, .outside)
        XCTAssertFalse(controller.state.hidesLocalCursor)
    }

    /// Reloading the same profile must not end a capture: the surface re-applies
    /// its policy on every SwiftUI update, and a policy that reset on each one
    /// would make the cursor flicker at the frame rate.
    func testReapplyingTheSamePolicyDoesNotEndCapture() {
        var controller = PointerCaptureController()
        controller.apply(.desktop)
        _ = controller.pointer(inside: true)
        controller.apply(.desktop)
        XCTAssertTrue(controller.state.hidesLocalCursor)
    }

    // MARK: - Exits

    /// Every way out of capture goes through `releaseAll`, so the local cursor
    /// cannot be left hidden by a path that forgot to restore it. This is the
    /// property that makes cursor rects safe: the failure mode of a missed reset
    /// is a visible cursor, never an invisible one.
    func testReleaseAllRestoresTheCursorFromEveryState() {
        for policy in [PointerCapturePolicy.desktop, .fusionProxy] {
            var controller = PointerCaptureController()
            controller.apply(policy)
            _ = controller.pointer(inside: true)
            controller.pressStarted()
            controller.releaseAll()
            XCTAssertEqual(controller.state, .outside)
            XCTAssertFalse(controller.state.hidesLocalCursor)
            XCTAssertFalse(controller.isPressHeld)
        }
    }

    func testEscapeReleasesCaptureWithoutLeavingTheImage() {
        var controller = PointerCaptureController()
        controller.apply(.desktop)
        _ = controller.pointer(inside: true)
        controller.escapeToHovering()
        XCTAssertEqual(controller.state, .hovering)
        XCTAssertFalse(controller.state.hidesLocalCursor)
        XCTAssertFalse(controller.state.forwardsTravel)
        // And re-entering the picture takes it again: escape is a hand-back, not
        // a mode change.
        XCTAssertEqual(controller.pointer(inside: true), .controlling)
    }

    // MARK: - Cursor rects

    private var square: PreviewMapping {
        PreviewMapping(imageWidth: 1000, imageHeight: 1000, displayWidth: 500, displayHeight: 500,
                       viewWidth: 800, viewHeight: 600)
    }

    /// The rect covers the *image*, never the letterbox: a transparent cursor on
    /// a black bar would hide the pointer over a region that is not the agent's
    /// desktop at all.
    func testTheCursorRectIsTheImageAndNotTheLetterbox() throws {
        let rect = try XCTUnwrap(CursorRectPolicy.imageRect(state: .controlling, mapping: square))
        // A 1:1 image in an 800x600 view fits to height 600, width 600, centred.
        XCTAssertEqual(rect.width, 600, accuracy: 0.5)
        XCTAssertEqual(rect.height, 600, accuracy: 0.5)
        XCTAssertEqual(rect.origin.x, 100, accuracy: 0.5)
        XCTAssertEqual(rect.origin.y, 0, accuracy: 0.5)
        XCTAssertLessThan(rect.maxX, 800, "the bars either side stay visible")
    }

    func testNoRectWhileNotControlling() {
        XCTAssertNil(CursorRectPolicy.imageRect(state: .outside, mapping: square))
        XCTAssertNil(CursorRectPolicy.imageRect(state: .hovering, mapping: square))
    }

    /// A picture that is not on screen yet has no rect, and the honest answer is
    /// nil rather than a zero-sized rect — which AppKit would treat as a claim
    /// over one point.
    func testNoRectBeforeTheFirstFrame() {
        let empty = PreviewMapping(imageWidth: 0, imageHeight: 0, displayWidth: 500, displayHeight: 500,
                                   viewWidth: 800, viewHeight: 600)
        XCTAssertNil(CursorRectPolicy.imageRect(state: .controlling, mapping: empty))
    }

    // MARK: - Mouse capture mode

    func testMouseCaptureModeAutoTakesThePointerInDesktopAndOnPressInFusion() {
        XCTAssertEqual(MouseCaptureMode.auto.policy(for: .desktop).entry, .captureOnEntry)
        XCTAssertEqual(MouseCaptureMode.auto.policy(for: .fusion).entry, .captureOnPress)
    }

    func testMouseCaptureModeClickToCaptureNeverTakesItOnEntry() {
        XCTAssertEqual(MouseCaptureMode.clickToCapture.policy(for: .desktop).entry, .captureOnPress)
        XCTAssertEqual(MouseCaptureMode.clickToCapture.policy(for: .fusion).entry, .captureOnPress)
    }

    func testMouseCaptureModeOffDisablesEverything() {
        XCTAssertEqual(MouseCaptureMode.off.policy(for: .desktop).entry, .disabled)
        XCTAssertEqual(MouseCaptureMode.off.policy(for: .fusion).entry, .disabled)
    }

    func testMouseCaptureModeDefaultsToAutoAndParsesItsStoredValue() {
        XCTAssertEqual(MouseCaptureMode.default, .auto)
        XCTAssertEqual(MouseCaptureMode.parse("clickToCapture"), .clickToCapture)
        XCTAssertEqual(MouseCaptureMode.parse("off"), .off)
        XCTAssertNil(MouseCaptureMode.parse("something else"))
        XCTAssertNil(MouseCaptureMode.parse(nil))
    }
}
