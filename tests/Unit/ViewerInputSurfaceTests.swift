import XCTest
import AgentSpaceCore

final class ViewerInputSurfaceTests: XCTestCase {
    func testWindowUsesFractionPacketsAndLocalCursorPoints() {
        let identity = WindowIdentity(pid: 99, windowID: 42, generation: 7)
        let surface = ViewerInputSurface.window(identity, CGRectValue(x: 100, y: 200, width: 800, height: 600))
        XCTAssertEqual(surface.target, .window(identity))
        let point = surface.point(u: 0.5, v: 0.25)
        XCTAssertEqual(point.x, 0.5); XCTAssertEqual(point.y, 0.25)
        let cursor = surface.cursorPoint(x: 500, y: 350)
        XCTAssertEqual(cursor.x, 400); XCTAssertEqual(cursor.y, 150)
    }

    func testDesktopUsesLogicalPointsOnRetina() {
        let surface = ViewerInputSurface.desktop(DisplayGeometry(width: 1000, height: 800,
            pixelWidth: 2000, pixelHeight: 1600, scale: 2))
        XCTAssertEqual(surface.target, .desktop)
        let point = surface.point(u: 0.5, v: 0.25)
        XCTAssertEqual(point.x, 500); XCTAssertEqual(point.y, 200)
        let cursor = surface.cursorPoint(x: 500, y: 200)
        XCTAssertEqual(cursor.x, 500); XCTAssertEqual(cursor.y, 200)
    }

    func testFrameRateUsesDesktopPreferenceAndIgnoresLegacyFusionCap() {
        let name = "viewer-rate-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(5, forKey: "fusionFPSPolicy")
        XCTAssertEqual(ViewerFrameRate.ceiling(in: defaults), 30)
        defaults.set(60, forKey: ViewerFrameRate.storageKey)
        XCTAssertEqual(ViewerFrameRate.ceiling(in: defaults), 60)
        defaults.set(0, forKey: ViewerFrameRate.storageKey)
        XCTAssertEqual(ViewerFrameRate.ceiling(in: defaults), 30)
    }
}
