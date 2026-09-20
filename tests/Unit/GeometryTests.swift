import XCTest
import AgentSpaceCore

final class GeometryTests: XCTestCase {

    /// The bug this type exists to prevent, reproduced from a real measurement:
    /// on macOS 27.0 with a scaled Retina display, `CGDisplayPixelsWide()`
    /// returned 1920 (points) while the display mode's `pixelWidth` returned
    /// 3840. Deriving the scale from the former yields 1.
    func testScaleComesFromTheDisplayModeNotPixelsWide() {
        let geometry = DisplayGeometry(modeWidth: 1920, modePixelWidth: 3840,
                                       boundsWidth: 1920, boundsHeight: 1080)
        XCTAssertEqual(geometry.scale, 2)
        XCTAssertEqual(geometry.width, 1920)
        XCTAssertEqual(geometry.pixelWidth, 3840)
        XCTAssertEqual(geometry.pixelHeight, 2160)
    }

    func testNonRetinaDisplay() {
        let geometry = DisplayGeometry(modeWidth: 1920, modePixelWidth: 1920,
                                       boundsWidth: 1920, boundsHeight: 1080)
        XCTAssertEqual(geometry.scale, 1)
        XCTAssertEqual(geometry.pixelWidth, 1920)
    }

    func testDegenerateModeFallsBackToOne() {
        let geometry = DisplayGeometry(modeWidth: 0, modePixelWidth: 0,
                                       boundsWidth: 1440, boundsHeight: 900)
        XCTAssertEqual(geometry.scale, 1)
        XCTAssertEqual(geometry.pixelWidth, 1440)
    }

    func testPixelToPointConversion() {
        let geometry = DisplayGeometry(width: 1920, height: 1080,
                                       pixelWidth: 3840, pixelHeight: 2160, scale: 2)
        XCTAssertEqual(geometry.point(fromPixel: 3456), 1728)
        XCTAssertEqual(geometry.point(fromPixel: 100), 50)
        XCTAssertEqual(geometry.pixel(fromPoint: 500), 1000)
    }

    func testRoundTripIsStableAtScaleTwo() {
        let geometry = DisplayGeometry(width: 1920, height: 1080,
                                       pixelWidth: 3840, pixelHeight: 2160, scale: 2)
        for point in [0, 1, 17, 500, 1919] {
            XCTAssertEqual(geometry.point(fromPixel: geometry.pixel(fromPoint: point)), point)
        }
    }

    // MARK: Coordinate validation

    func testValidCoordinate() {
        let geometry = DisplayGeometry(width: 1920, height: 1080,
                                       pixelWidth: 3840, pixelHeight: 2160, scale: 2)
        XCTAssertNil(CoordinateRules.validate(x: 100, y: 100, geometry: geometry))
    }

    func testNonFiniteRejected() {
        XCTAssertEqual(CoordinateRules.validate(x: .nan, y: 1, geometry: nil)?.code, .invalidCoordinate)
        XCTAssertEqual(CoordinateRules.validate(x: 1, y: .infinity, geometry: nil)?.code, .invalidCoordinate)
    }

    func testNegativeRejected() {
        XCTAssertEqual(CoordinateRules.validate(x: -1, y: 1, geometry: nil)?.code, .invalidCoordinate)
    }

    func testAbsurdRejected() {
        XCTAssertEqual(
            CoordinateRules.validate(x: 10_000_000, y: 1, geometry: nil)?.code,
            .invalidCoordinate)
    }

    /// The most likely real mistake: an agent reads a pixel coordinate off a 2x
    /// screenshot and posts it as a point. That lands outside the display, and
    /// the error has to say so in those words.
    func testOffDisplayCoordinateExplainsThePixelPointMixup() {
        let geometry = DisplayGeometry(width: 1920, height: 1080,
                                       pixelWidth: 3840, pixelHeight: 2160, scale: 2)
        let error = CoordinateRules.validate(x: 3456, y: 1117, geometry: geometry)
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.code, .invalidCoordinate)
        XCTAssertTrue(error!.message.contains("scale=2"), error!.message)
    }

    func testPointAtDisplayEdge() {
        let geometry = DisplayGeometry(width: 1920, height: 1080,
                                       pixelWidth: 3840, pixelHeight: 2160, scale: 2)
        XCTAssertTrue(geometry.contains(point: (1919, 1079)))
        XCTAssertFalse(geometry.contains(point: (1920, 1079)))
        XCTAssertFalse(geometry.contains(point: (1919, 1080)))
    }
    // MARK: - Which display a window is on

    /// The Retina panel is 1440x900 points at 2x; the external panel is
    /// 1920x1080 points at 1x. A window that is mostly on the Retina panel must
    /// be encoded at 2x — the first version of this code asked `max(by:)` with a
    /// "bigger first" comparator and so took the *smallest* overlap, i.e. the 1x
    /// panel, and shipped a half-resolution capture of a Retina window.
    func testLargestOverlapDisplayWins() {
        let retina = DisplayScaleSelection.Candidate(
            bounds: CGRect(x: 0, y: 0, width: 1440, height: 900), pixelWidth: 2880, pointWidth: 1440)
        let external = DisplayScaleSelection.Candidate(
            bounds: CGRect(x: 0, y: 900, width: 1920, height: 1080), pixelWidth: 1920, pointWidth: 1920)
        // 400x300 with only its bottom 100 points spilling onto the external
        // panel: 80% Retina, 20% 1x.
        let window = CGRect(x: 100, y: 700, width: 400, height: 300)

        XCTAssertEqual(
            DisplayScaleSelection.pixelsPerPoint(windowFrame: window, in: [external, retina]), 2,
            "the panel holding most of the window decides the scale, whatever the array order")
        XCTAssertGreaterThan(
            DisplayScaleSelection.overlap(of: window, on: retina.bounds),
            DisplayScaleSelection.overlap(of: window, on: external.bounds))
    }

    func testWindowSpanningTheSeamFollowsTheBulkOfIt() {
        let left = DisplayScaleSelection.Candidate(
            bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000), pixelWidth: 1000, pointWidth: 1000)
        let right = DisplayScaleSelection.Candidate(
            bounds: CGRect(x: 1000, y: 0, width: 1000, height: 1000), pixelWidth: 2000, pointWidth: 1000)
        XCTAssertEqual(
            DisplayScaleSelection.pixelsPerPoint(windowFrame: CGRect(x: 950, y: 100, width: 400, height: 200),
                                                 in: [left, right]), 2)
        XCTAssertEqual(
            DisplayScaleSelection.pixelsPerPoint(windowFrame: CGRect(x: 600, y: 100, width: 400, height: 200),
                                                 in: [left, right]), 1)
    }

    /// A window that touches nothing — off-screen, or a display that went to
    /// sleep between the listing and the capture — must not crash or invent a
    /// zero scale.
    func testWindowOnNoDisplayFallsBack() {
        let panel = DisplayScaleSelection.Candidate(
            bounds: CGRect(x: 0, y: 0, width: 1440, height: 900), pixelWidth: 2880, pointWidth: 1440)
        XCTAssertEqual(
            DisplayScaleSelection.pixelsPerPoint(
                windowFrame: CGRect(x: 5000, y: 5000, width: 200, height: 100),
                in: [panel], fallback: 2), 2)
        XCTAssertEqual(
            DisplayScaleSelection.pixelsPerPoint(windowFrame: CGRect(x: 0, y: 0, width: 10, height: 10),
                                                 in: [], fallback: 3), 3)
        XCTAssertNil(DisplayScaleSelection.candidate(
            for: CGRect(x: 5000, y: 0, width: 10, height: 10), in: [panel]))
    }

    func testSingleDisplayAndDegenerateGeometry() {
        let only = DisplayScaleSelection.Candidate(
            bounds: CGRect(x: 0, y: 0, width: 512, height: 288), pixelWidth: 512, pointWidth: 256)
        XCTAssertEqual(only.pixelsPerPoint, 2)
        XCTAssertEqual(
            DisplayScaleSelection.pixelsPerPoint(windowFrame: CGRect(x: 10, y: 10, width: 50, height: 50),
                                                 in: [only]), 2)
        XCTAssertEqual(
            DisplayScaleSelection.Candidate(
                bounds: .zero, pixelWidth: 0, pointWidth: 0).pixelsPerPoint, 1,
            "a zero-sized mode is not a scale of zero")
        XCTAssertEqual(
            DisplayScaleSelection.overlap(of: CGRect(x: 0, y: 0, width: 10, height: 10),
                                          on: CGRect(x: 100, y: 100, width: 10, height: 10)), 0,
            "disjoint rects intersect in a null rect, not a negative area")
    }
}
