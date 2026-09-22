import XCTest
@testable import AgentSpaceCore

/// The Desktop Viewer's click arithmetic. Plan §17: the user clicks a picture of
/// the agent's desktop in the *main* app and that has to arrive as a real click
/// in the *other* session, so the mapping between the three coordinate spaces has
/// to be right to the point.
final class PreviewMappingTests: XCTestCase {

    /// A 3840x2160 capture of a 1920x1080 display (scale 2), shown in a view
    /// that happens to be exactly the image's aspect ratio.
    private func exactFit() -> PreviewMapping {
        PreviewMapping(imageWidth: 3840, imageHeight: 2160,
                       displayWidth: 1920, displayHeight: 1080,
                       viewWidth: 960, viewHeight: 540)
    }

    private func wideView() -> PreviewMapping {
        PreviewMapping(imageWidth: 3840, imageHeight: 2160,
                       displayWidth: 1920, displayHeight: 1080,
                       viewWidth: 960, viewHeight: 1080)
    }

    func testCentreOfThePreviewIsTheCentreOfTheDisplay() {
        let mapping = exactFit()
        let point = mapping.displayPoint(viewX: 480, viewY: 270)
        XCTAssertEqual(point?.x, 960)
        XCTAssertEqual(point?.y, 540)
    }

    func testCornersMapToTheDisplayCorners() {
        let mapping = exactFit()
        XCTAssertEqual(mapping.displayPoint(viewX: 0, viewY: 0)?.x, 0)
        XCTAssertEqual(mapping.displayPoint(viewX: 0, viewY: 0)?.y, 0)
        // The bottom-right pixel of the image is the last point on the display.
        XCTAssertEqual(mapping.displayPoint(viewX: 959.9, viewY: 539.9)?.x, 1919)
        XCTAssertEqual(mapping.displayPoint(viewX: 959.9, viewY: 539.9)?.y, 1079)
    }

    /// AppKit NSViews use a bottom-left local origin while the SwiftUI preview
    /// mapping uses a top-left origin.  The transparent click surface must use
    /// this bridge or a click near the visual top lands near the bottom of the
    /// agent's display.
    func testAppKitBottomLeftCoordinatesAreFlippedBeforeMapping() {
        let mapping = exactFit()

        let visualTop = mapping.displayPoint(appKitX: 480, appKitY: 539.9)
        XCTAssertEqual(visualTop?.x, 960)
        XCTAssertEqual(visualTop?.y, 0)

        let visualBottom = mapping.displayPoint(appKitX: 480, appKitY: 0)
        XCTAssertEqual(visualBottom?.x, 960)
        XCTAssertEqual(visualBottom?.y, 1079)
    }

    /// The bug this whole type exists to prevent: treating a view point in a
    /// half-size preview as a display point, or a pixel as a point. A click at
    /// the visual centre must be 960,540 — never 1920,1080 and never 480,270.
    func testScaleIsAppliedSoAPixelIsNeverUsedAsAPoint() {
        let mapping = exactFit()
        let point = mapping.displayPoint(viewX: 480, viewY: 270)
        XCTAssertNotEqual(point?.x, 1920, "a pixel coordinate was used as a point")
        XCTAssertNotEqual(point?.x, 480, "the preview was treated as being display-sized")
        XCTAssertEqual(point?.x, 960)
    }

    /// A wide view letterboxes the image vertically. Clicking in the black bar
    /// must do nothing rather than clamp onto the nearest edge of the screen.
    func testLetterboxClicksAreRefusedNotClamped() {
        // 960x1080 view for a 16:9 image: the image is 960x540, centred.
        let mapping = wideView()
        let rect = mapping.fittedRect
        XCTAssertEqual(rect?.x, 0)
        XCTAssertEqual(rect?.width, 960)
        XCTAssertEqual(rect?.height, 540)
        XCTAssertEqual(rect?.y, 270, "the image should be centred vertically")

        XCTAssertNil(mapping.displayPoint(viewX: 480, viewY: 10),
                     "a click in the top letterbox bar must be refused")
        XCTAssertNil(mapping.displayPoint(viewX: 480, viewY: 1070),
                     "a click in the bottom letterbox bar must be refused")
        XCTAssertNotNil(mapping.displayPoint(viewX: 480, viewY: 540),
                        "a click on the image itself must be accepted")
    }

    /// A tall view letterboxes horizontally.
    func testPillarboxClicksAreRefused() {
        let mapping = PreviewMapping(imageWidth: 3840, imageHeight: 2160,
                                     displayWidth: 1920, displayHeight: 1080,
                                     viewWidth: 1920, viewHeight: 540)
        let rect = mapping.fittedRect
        XCTAssertEqual(rect?.height, 540)
        XCTAssertEqual(rect?.width, 960)
        XCTAssertEqual(rect?.x, 480)
        XCTAssertNil(mapping.displayPoint(viewX: 10, viewY: 270), "left pillar bar")
        XCTAssertNil(mapping.displayPoint(viewX: 1910, viewY: 270), "right pillar bar")
        XCTAssertNotNil(mapping.displayPoint(viewX: 960, viewY: 270))
    }

    /// A downscaled preview (`--max-width`) keeps the scale but shrinks the
    /// image, so the mapping must use the *image's* size to find the fraction and
    /// the *display's* scale to convert. Using the image's own pixel dimensions
    /// as if they were display pixels would halve the result.
    func testDownscaledPreviewStillProducesFullDisplayCoordinates() {
        // A 1280x720 preview of the same 1920x1080-point display. The image is
        // smaller than the framebuffer, which is exactly what makes dividing by
        // the backing scale wrong: 640 image pixels is half the picture and half
        // the screen, 960 points — not 320.
        let mapping = PreviewMapping(imageWidth: 1280, imageHeight: 720,
                                     displayWidth: 1920, displayHeight: 1080,
                                     viewWidth: 1280, viewHeight: 720)
        let centre = mapping.displayPoint(viewX: 640, viewY: 360)
        XCTAssertEqual(centre?.x, 960)
        XCTAssertEqual(centre?.y, 540)

        let bottomRight = mapping.displayPoint(viewX: 1279.9, viewY: 719.9)
        XCTAssertEqual(bottomRight?.x, 1919)
        XCTAssertEqual(bottomRight?.y, 1079)
    }

    func testZeroSizedViewOrImageIsRefusedRatherThanDividingByZero() {
        let noView = PreviewMapping(imageWidth: 3840, imageHeight: 2160,
                                    displayWidth: 1920, displayHeight: 1080,
                                    viewWidth: 0, viewHeight: 0)
        XCTAssertNil(noView.fittedRect)
        XCTAssertNil(noView.displayPoint(viewX: 0, viewY: 0))

        // The one frame before the first capture arrives.
        let noImage = PreviewMapping(imageWidth: 0, imageHeight: 0,
                                     displayWidth: 1920, displayHeight: 1080,
                                     viewWidth: 800, viewHeight: 600)
        XCTAssertNil(noImage.fittedRect)
        XCTAssertNil(noImage.displayPoint(viewX: 400, viewY: 300))
    }

    /// Every point inside the image must round-trip: draw the pointer, then click
    /// where it was drawn. If these disagreed, the indicator would lie.
    func testRoundTripThroughViewPointLandsBackOnTheSameDisplayPoint() {
        let mapping = wideView()
        for x in stride(from: 0.0, through: 1920.0, by: 137.0) {
            for y in stride(from: 0.0, through: 1080.0, by: 91.0) {
                guard let view = mapping.viewPoint(displayX: x, displayY: y) else {
                    XCTFail("viewPoint returned nil for an on-display point (\(x), \(y))")
                    continue
                }
                guard let back = mapping.displayPoint(viewX: view.x, viewY: view.y) else {
                    XCTFail("displayPoint refused a point it had just produced (\(view.x), \(view.y))")
                    continue
                }
                XCTAssertEqual(back.x, x, accuracy: 1.0)
                XCTAssertEqual(back.y, y, accuracy: 1.0)
            }
        }
    }

    func testOffDisplayPointsHaveNoViewPosition() {
        let mapping = exactFit()
        XCTAssertNil(mapping.viewPoint(displayX: 5000, displayY: 100))
        XCTAssertNil(mapping.viewPoint(displayX: -1, displayY: 100))
        XCTAssertNotNil(mapping.viewPoint(displayX: 1919, displayY: 1079))
    }

    /// The factory takes the display's point size from `DisplayGeometry`, which
    /// is the same value the worker validated the coordinates against — so the
    /// preview and the input API cannot disagree about how big the display is.
    /// A downscaled preview must not change the mapping.
    func testFittingUsesTheReportedGeometrySoADownscaleChangesNothing() {
        let geometry = DisplayGeometry(width: 1920, height: 1080,
                                       pixelWidth: 3840, pixelHeight: 2160, scale: 2)
        let full = PreviewMapping.fitting(imageWidth: 3840, imageHeight: 2160,
                                          geometry: geometry, viewWidth: 960, viewHeight: 540)
        let downscaled = PreviewMapping.fitting(imageWidth: 640, imageHeight: 360,
                                                geometry: geometry, viewWidth: 960, viewHeight: 540)
        XCTAssertEqual(full.displayPoint(viewX: 480, viewY: 270)?.x,
                       downscaled.displayPoint(viewX: 480, viewY: 270)?.x)
        XCTAssertEqual(full.displayPoint(viewX: 480, viewY: 270)?.x, 960)
        XCTAssertEqual(downscaled.displayPoint(viewX: 480, viewY: 270)?.y, 540)
    }

    /// A click in the last pixel must be a click on the last point, not one past
    /// the edge — an off-by-one here comes back as INVALID_COORDINATE from the
    /// worker and looks like a bug in the agent.
    func testTheLastPixelMapsToTheLastPointNotPastTheEdge() {
        let mapping = exactFit()
        let corner = mapping.displayPoint(viewX: 959.999, viewY: 539.999)
        XCTAssertEqual(corner?.x, 1919)
        XCTAssertEqual(corner?.y, 1079)
        XCTAssertLessThan(corner!.x, 1920)
        XCTAssertLessThan(corner!.y, 1080)
    }

    /// A machine that reports no display must not crash the app with a
    /// divide-by-zero or a negative coordinate.
    func testZeroSizedDisplayIsHandledRatherThanDividingByZero() {
        let mapping = PreviewMapping(imageWidth: 100, imageHeight: 100,
                                     displayWidth: 0, displayHeight: 0,
                                     viewWidth: 100, viewHeight: 100)
        let point = mapping.displayPoint(viewX: 50, viewY: 50)
        XCTAssertEqual(point?.x, 0)
        XCTAssertEqual(point?.y, 0)
        XCTAssertNil(mapping.viewPoint(displayX: 0, displayY: 0))
    }

    // MARK: - Fractions of the captured image

    /// The unit a remote surface reports a gesture in. The centre of the picture
    /// is half across and half down it, and AppKit's bottom-left origin must be
    /// flipped on the way, or a hover near the menu bar moves the agent's pointer
    /// to the Dock.
    func testFractionIsAcrossTheImageWithTheTopEdgeAtZero() {
        let mapping = exactFit()
        let centre = mapping.fraction(appKitX: 480, appKitY: 270)
        XCTAssertEqual(centre?.u ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(centre?.v ?? -1, 0.5, accuracy: 0.0001)

        let topEdge = mapping.fraction(appKitX: 0, appKitY: 539.999)
        XCTAssertEqual(topEdge?.u ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(topEdge?.v ?? -1, 0, accuracy: 0.001, "the visual top edge is v 0")

        let bottomEdge = mapping.fraction(appKitX: 959.999, appKitY: 0)
        XCTAssertEqual(bottomEdge?.u ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(bottomEdge?.v ?? -1, 1, accuracy: 0.001, "the visual bottom edge is v 1")
    }

    /// Same refusal as a click: a gesture over the black bar is not a gesture over
    /// the desktop. This is what keeps a cursor crossing the letterbox from moving
    /// the agent's pointer to the nearest screen edge.
    func testFractionInALetterboxBarIsRefused() {
        let mapping = wideView()
        // Top-left y 10 of a 1080-tall view is AppKit y 1070.
        XCTAssertNil(mapping.fraction(appKitX: 480, appKitY: 1070), "top letterbox bar")
        XCTAssertNil(mapping.fraction(appKitX: 480, appKitY: 10), "bottom letterbox bar")
        let inside = mapping.fraction(appKitX: 480, appKitY: 540)
        XCTAssertEqual(inside?.u ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(inside?.v ?? -1, 0.5, accuracy: 0.0001)
    }

    /// The clamped form exists for a gesture that *started* inside the image and
    /// drifted out: a drag whose release landed on the black bar still has to
    /// let go, so it ends at the edge rather than nowhere.
    func testClampedFractionPullsADriftedReleaseBackOntoTheImage() {
        let mapping = wideView()
        let release = mapping.fractionClamped(appKitX: 480, appKitY: 1070)
        XCTAssertEqual(release?.u ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(release?.v ?? -1, 0, accuracy: 0.0001, "the top edge, not outside it")
        XCTAssertEqual(mapping.fractionClamped(appKitX: -50, appKitY: 540)?.u, 0)
    }

    /// A fraction and a view point are two routes to the same display point, so
    /// the surface's letterbox arithmetic and the input conversion cannot
    /// disagree about where the hand was.
    func testFractionAndViewPointResolveToTheSameDisplayPoint() {
        let mapping = wideView()
        for u in stride(from: 0.0, through: 1.0, by: 0.1) {
            for v in stride(from: 0.0, through: 1.0, by: 0.1) {
                let expected = mapping.displayPoint(u: u, v: v)
                let drawn = mapping.viewPoint(displayX: expected.x, displayY: expected.y)!
                let through = mapping.fraction(appKitX: drawn.x, appKitY: mapping.viewHeight - drawn.y)
                XCTAssertNotNil(through, "a point produced by the mapping left the image")
                XCTAssertEqual(through?.u ?? -1, u, accuracy: 0.001)
                XCTAssertEqual(through?.v ?? -1, v, accuracy: 0.001)
            }
        }
    }

    /// The last fraction of the display is its last point: `1.0` multiplied out is
    /// one past the edge, which the worker answers with INVALID_COORDINATE and a
    /// person experiences as "the bottom row of the desktop cannot be clicked".
    func testFractionOfOneMapsToTheLastPointAndNotPastIt() {
        let mapping = exactFit()
        let corner = mapping.displayPoint(u: 1, v: 1)
        XCTAssertEqual(corner.x, 1919)
        XCTAssertEqual(corner.y, 1079)
        let origin = mapping.displayPoint(u: 0, v: 0)
        XCTAssertEqual(origin.x, 0)
        XCTAssertEqual(origin.y, 0)
    }
}
