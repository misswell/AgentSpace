import XCTest
@testable import AgentSpaceCore

final class DesktopViewportSizingTests: XCTestCase {
    func testTallViewerConformsToDesktopWithoutCroppingOrBars() {
        // The reported case: a tall viewer around a 1920×1080 desktop.
        let fitted = DesktopViewportSizing.contentSize(
            proposedWidth: 1532, controlsHeight: 180, titlebarHeight: 30,
            maximumFrameHeight: 1800, displayWidth: 1920, displayHeight: 1080)
        XCTAssertEqual(fitted.width, 1532)
        XCTAssertEqual(fitted.height - 180, 1532 * 1080 / 1920, accuracy: 0.001)
    }

    func testVisibleScreenHeightLimitsTheWidthAndKeepsTheSameAspect() {
        let fitted = DesktopViewportSizing.contentSize(
            proposedWidth: 2000, controlsHeight: 180, titlebarHeight: 30,
            maximumFrameHeight: 980, displayWidth: 1920, displayHeight: 1080)
        XCTAssertEqual(fitted.height + 30, 980, accuracy: 0.001)
        XCTAssertEqual(fitted.width / (fitted.height - 180), 1920.0 / 1080.0, accuracy: 0.001)
    }
}
