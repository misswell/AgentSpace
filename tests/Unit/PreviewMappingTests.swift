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
}
