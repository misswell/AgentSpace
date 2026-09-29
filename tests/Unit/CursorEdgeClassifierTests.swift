import XCTest
@testable import AgentSpaceCore

final class CursorEdgeClassifierTests: XCTestCase {
    private let window = CursorEdgeClassifier.WindowFrame(x: 100, y: 100, width: 800, height: 600)

    func testTheMiddleOfAWindowIsNotAResizeBorder() {
        XCTAssertEqual(CursorEdgeClassifier.shape(pointX: 500, pointY: 400, windowFrames: [window]), .none)
        // Inside but a hair past the edge margin is still body, not border.
        XCTAssertEqual(CursorEdgeClassifier.shape(pointX: 106, pointY: 400, windowFrames: [window]), .none)
        XCTAssertEqual(CursorEdgeClassifier.shape(pointX: 500, pointY: 106, windowFrames: [window]), .none)
    }

    func testTheEdgesNameTheAxisArrows() {
        XCTAssertEqual(CursorEdgeClassifier.shape(pointX: 103, pointY: 400, windowFrames: [window]), .leftRight)
        XCTAssertEqual(CursorEdgeClassifier.shape(pointX: 897, pointY: 400, windowFrames: [window]), .leftRight)
        XCTAssertEqual(CursorEdgeClassifier.shape(pointX: 500, pointY: 103, windowFrames: [window]), .upDown)
        XCTAssertEqual(CursorEdgeClassifier.shape(pointX: 500, pointY: 697, windowFrames: [window]), .upDown)
    }

    func testTheCornersNameTheDiagonals() {
        XCTAssertEqual(CursorEdgeClassifier.shape(pointX: 105, pointY: 105, windowFrames: [window]), .northWestSouthEast)
        XCTAssertEqual(CursorEdgeClassifier.shape(pointX: 895, pointY: 695, windowFrames: [window]), .northWestSouthEast)
        XCTAssertEqual(CursorEdgeClassifier.shape(pointX: 895, pointY: 105, windowFrames: [window]), .northEastSouthWest)
        XCTAssertEqual(CursorEdgeClassifier.shape(pointX: 105, pointY: 695, windowFrames: [window]), .northEastSouthWest)
    }

    func testAWindowCornerWinsOverEitherSingleBorder() {
        // 8 px from the left edge alone is body, but 8 px from two edges at
        // once is the corner the wider margin exists for.
        XCTAssertEqual(CursorEdgeClassifier.shape(pointX: 108, pointY: 108, windowFrames: [window]), .northWestSouthEast)
    }

    func testAPointOnNoWindowIsNotAResizeBorder() {
        // Outside every window: the desktop background and the gaps between
        // windows are not resize handles.
        XCTAssertEqual(CursorEdgeClassifier.shape(pointX: 50, pointY: 400, windowFrames: [window]), .none)
        XCTAssertEqual(CursorEdgeClassifier.shape(pointX: 500, pointY: 50, windowFrames: [window]), .none)
        XCTAssertEqual(CursorEdgeClassifier.shape(pointX: 500, pointY: 400, windowFrames: []), .none)
    }

    func testTheFrontmostWindowContainingThePointDecides() {
        let background = CursorEdgeClassifier.WindowFrame(x: 0, y: 0, width: 1920, height: 1080)
        let front = window
        // Inside the front window's body but 3 px from the window behind it
        // does not make the point a resize border of the window behind.
        XCTAssertEqual(CursorEdgeClassifier.shape(pointX: 103, pointY: 400, windowFrames: [front, background]), .leftRight)
        // A point over the front window's body, far from its own borders, is
        // body even though it sits on the back window's border zone.
        let deep = CursorEdgeClassifier.WindowFrame(x: 105, y: 105, width: 700, height: 500)
        XCTAssertEqual(CursorEdgeClassifier.shape(pointX: 103, pointY: 400, windowFrames: [deep, background]), .none)
    }

    func testDegenerateWindowsAreSkipped() {
        let line = CursorEdgeClassifier.WindowFrame(x: 100, y: 100, width: 800, height: 0)
        XCTAssertEqual(CursorEdgeClassifier.shape(pointX: 103, pointY: 100, windowFrames: [line]), .none)
    }
}
