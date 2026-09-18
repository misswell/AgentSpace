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
}
