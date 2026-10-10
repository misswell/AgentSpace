import XCTest
@testable import AgentSpaceCore

final class DesktopViewportSizingTests: XCTestCase {
    func testTallViewerConformsToDesktopWithoutCroppingOrBars() throws {
        // The reported case: a tall viewer around a 1920×1080 desktop.
        let fitted = try XCTUnwrap(DesktopViewportSizing.contentSize(
            proposedWidth: 1532, controlsHeight: 180, titlebarHeight: 30,
            maximumFrameHeight: 1800, displayWidth: 1920, displayHeight: 1080))
        XCTAssertEqual(fitted.width, 1532)
        XCTAssertEqual(fitted.height - 180, 1532 * 1080 / 1920, accuracy: 0.001)
    }

    func testVisibleScreenHeightLimitsTheWidthAndKeepsTheSameAspect() throws {
        let fitted = try XCTUnwrap(DesktopViewportSizing.contentSize(
            proposedWidth: 2000, controlsHeight: 180, titlebarHeight: 30,
            maximumFrameHeight: 980, displayWidth: 1920, displayHeight: 1080))
        XCTAssertEqual(fitted.height + 30, 980, accuracy: 0.001)
        XCTAssertEqual(fitted.width / (fitted.height - 180), 1920.0 / 1080.0, accuracy: 0.001)
    }

    // MARK: - minimumViewportHeight (§381)

    /// The window that crashed 0.1.79: 749 pt wide around a 16:9 desktop. The
    /// aspect alone would want a 421 pt viewport, but the viewer's own minimum
    /// is 520 — so the width has to give, not the height.
    func testANarrowViewerIsWidenedInsteadOfShrunkUnderItsMinimum() throws {
        let fitted = try XCTUnwrap(DesktopViewportSizing.contentSize(
            proposedWidth: 749, controlsHeight: 32, titlebarHeight: 32,
            maximumFrameHeight: 1050, displayWidth: 1920, displayHeight: 1080,
            minimumViewportWidth: 720, minimumViewportHeight: 520))
        XCTAssertEqual(fitted.width, 520 * 1920.0 / 1080.0, accuracy: 0.001)   // 924.4
        XCTAssertEqual(fitted.height - 32, 520, accuracy: 0.001)
    }

    func testAViewerAlreadyWideEnoughIsLeftOnItsWidth() throws {
        let fitted = try XCTUnwrap(DesktopViewportSizing.contentSize(
            proposedWidth: 1120, controlsHeight: 32, titlebarHeight: 32,
            maximumFrameHeight: 1050, displayWidth: 1920, displayHeight: 1080,
            minimumViewportWidth: 720, minimumViewportHeight: 520))
        XCTAssertEqual(fitted.width, 1120, accuracy: 0.001)
        XCTAssertEqual(fitted.height - 32, 630, accuracy: 0.001)
    }

    /// The mirror of the case above: a portrait display at the viewer's *width*
    /// minimum is taller than this screen allows, so the aspect has no answer
    /// here and saying so is the point — the caller then leaves the window
    /// alone instead of trading frames with SwiftUI.
    func testAnAspectThatCannotHoldAtTheMinimumIsReported() {
        let fitted = DesktopViewportSizing.contentSize(
            proposedWidth: 700, controlsHeight: 32, titlebarHeight: 32,
            maximumFrameHeight: 1050, displayWidth: 1080, displayHeight: 1920,
            minimumViewportWidth: 720, minimumViewportHeight: 520)
        XCTAssertNil(fitted)
    }

    func testTheScreenWidthCapsTheWidthBeforeTheAspectFloorDecides() {
        let fitted = DesktopViewportSizing.contentSize(
            proposedWidth: 1800, controlsHeight: 32, titlebarHeight: 32,
            maximumFrameHeight: 1050, displayWidth: 5120, displayHeight: 1440,
            minimumViewportWidth: 720, minimumViewportHeight: 520, maximumWidth: 1366)
        XCTAssertNil(fitted)
    }

    // MARK: - onScreenFrame

    /// The frame that opened this round: 610 −520 749 552, saved by a build that
    /// let the window be walked off the bottom of the screen (§381).
    func testAFrameBelowTheScreenComesBackWithItsSizeIntact() {
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1050)
        let reached = DesktopViewportSizing.onScreenFrame(
            CGRect(x: 610, y: -520, width: 749, height: 552), visibleArea: visible)
        XCTAssertEqual(reached, CGRect(x: 610, y: 0, width: 749, height: 552))
    }

    func testAFrameAlreadyOnScreenIsLeftAlone() {
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1050)
        let saved = CGRect(x: 400, y: 113, width: 1120, height: 662)
        XCTAssertEqual(DesktopViewportSizing.onScreenFrame(saved, visibleArea: visible), saved)
    }

    func testAFramePartlyOffEachEdgeIsPulledFullyInside() {
        let visible = CGRect(x: 0, y: 25, width: 1920, height: 1050)
        let reached = DesktopViewportSizing.onScreenFrame(
            CGRect(x: -300, y: 1000, width: 500, height: 400), visibleArea: visible)
        XCTAssertEqual(reached, CGRect(x: 0, y: 675, width: 500, height: 400))
    }

    /// A second display's visible area is not at the origin, and the window has
    /// to land inside *that* rectangle, not inside a main-screen-shaped one.
    func testTheVisibleAreaIsUsedAsGivenNotAsTheMainScreen() {
        let secondDisplay = CGRect(x: 1920, y: 0, width: 1440, height: 860)
        let reached = DesktopViewportSizing.onScreenFrame(
            CGRect(x: 500, y: 200, width: 800, height: 600), visibleArea: secondDisplay)
        XCTAssertEqual(reached, CGRect(x: 1920, y: 200, width: 800, height: 600))
    }

    func testASavedSizeLargerThanTheScreenShrinksToFit() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 860)
        let reached = DesktopViewportSizing.onScreenFrame(
            CGRect(x: 100, y: 50, width: 2000, height: 1200), visibleArea: visible)
        XCTAssertEqual(reached, CGRect(x: 0, y: 0, width: 1440, height: 860))
    }
}
