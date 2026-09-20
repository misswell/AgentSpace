import XCTest
@testable import AgentSpaceCore

final class RemoteWindowTests: XCTestCase {
    func testWindowRoundTripsWithoutLosingItsReusableIDProtection() throws {
        let window = RemoteWindow(
            id: 42,
            pid: 901,
            appName: "TextEdit",
            bundleIdentifier: "com.apple.TextEdit",
            title: "Notes",
            frame: CGRectValue(x: 40, y: 80, width: 900, height: 700),
            layer: 0,
            visible: true,
            minimized: false,
            generation: 7)

        let decoded = try JSONDecoder().decode(
            RemoteWindow.self,
            from: JSONEncoder().encode(window))

        XCTAssertEqual(decoded, window)
        XCTAssertEqual(decoded.identity, WindowIdentity(pid: 901, windowID: 42, generation: 7))
    }

    func testNormalizedPointUsesTheCurrentRemoteFrame() throws {
        let point = try WindowCoordinateMapper.point(
            xFraction: 0.5,
            yFraction: 0.25,
            in: CGRectValue(x: 100, y: 200, width: 800, height: 600))
        XCTAssertEqual(point.x, 500)
        XCTAssertEqual(point.y, 350)
    }

    func testNormalizedPointRefusesFractionsOutsideTheWindow() {
        XCTAssertThrowsError(try WindowCoordinateMapper.point(
            xFraction: 1.01,
            yFraction: 0.5,
            in: CGRectValue(x: 0, y: 0, width: 100, height: 100))) { error in
                XCTAssertEqual((error as? AgentSpaceError)?.code, .invalidCoordinate)
            }
    }
}
