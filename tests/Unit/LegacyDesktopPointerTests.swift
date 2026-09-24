import XCTest
@testable import AgentSpaceCore

final class LegacyDesktopPointerTests: XCTestCase {
    private let display = DisplayGeometry(width: 1920, height: 1080,
                                          pixelWidth: 1920, pixelHeight: 1080, scale: 1)

    func testRawPressAndReleaseBecomesTheClickAnOldWorkerUnderstands() {
        var pointer = LegacyDesktopPointer()
        XCTAssertNil(pointer.action(for: .pointerDown(u: 0.5, v: 0.5, button: .left,
                                                      clickCount: 1, modifiers: []), display: display))
        XCTAssertTrue(pointer.hasPendingPress)
        XCTAssertEqual(pointer.action(for: .pointerUp(u: 0.5, v: 0.5, button: .left,
                                                     clickCount: 1, modifiers: []), display: display),
                       .click(x: 960, y: 540, button: .left, count: 1, modifiers: []))
        XCTAssertFalse(pointer.hasPendingPress)
    }

    func testRawDragUsesTheOriginalPressAndOneAtomicAction() {
        var pointer = LegacyDesktopPointer()
        _ = pointer.action(for: .pointerDown(u: 0.25, v: 0.25, button: .left,
                                             clickCount: 1, modifiers: []), display: display)
        XCTAssertNil(pointer.action(for: .pointerDrag(fromU: 0.25, fromV: 0.25,
                                                      toU: 0.5, toV: 0.5, button: .left,
                                                      modifiers: []), display: display))
        XCTAssertEqual(pointer.action(for: .pointerUp(u: 0.5, v: 0.5, button: .left,
                                                     clickCount: 1, modifiers: []), display: display),
                       .drag(fromX: 480, fromY: 270, toX: 960, toY: 540,
                             button: .left, modifiers: []))
    }

    func testDoubleClickAndScrollKeepTheirMeaning() {
        var pointer = LegacyDesktopPointer()
        XCTAssertEqual(pointer.action(for: .click(u: 0.5, v: 0.5, button: .left,
                                                 count: 2, modifiers: []), display: display),
                       .click(x: 960, y: 540, button: .left, count: 2, modifiers: []))
        XCTAssertEqual(pointer.action(for: .scroll(u: 0.5, v: 0.5, linesX: 1, linesY: -2),
                                      display: display),
                       .scroll(x: 960, y: 540, dx: 1, dy: -2))
    }
}
