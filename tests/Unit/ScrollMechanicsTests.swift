import XCTest
@testable import AgentSpaceCore

/// Turning wheel lines into a scroll bar position. This is the arithmetic
/// behind scrolling in a session that is not on the console, where a posted
/// wheel event reaches the session stream but no app (`docs/validation.md`
/// §315), so the scroll bar's fraction is the only thing that moves.
///
/// The numbers are TextEdit's own, read off a live scroll area: a 656x390
/// viewport over 656x5200 of content.
final class ScrollMechanicsTests: XCTestCase {
    private let viewportHeight = 390.0
    private let contentHeight = 5200.0

    func testOneLineIsOneTwentiethOfTheViewportOverTheScrollableRange() {
        let perLine = ScrollMechanics.fractionPerLine(viewport: viewportHeight,
                                                      content: contentHeight)
        // 390/20 = 19.5 points of content, over 5200-390 = 4810 points of range.
        XCTAssertEqual(perLine ?? -1, 19.5 / 4810, accuracy: 1e-9)
    }

    func testScrollingDownIncreasesTheValueAndScrollingUpDecreasesIt() {
        let down = ScrollMechanics.value(current: 0.4, lines: -3,
                                         viewport: viewportHeight, content: contentHeight)
        let up = ScrollMechanics.value(current: 0.4, lines: 3,
                                       viewport: viewportHeight, content: contentHeight)
        XCTAssertGreaterThan(down ?? -1, 0.4)
        XCTAssertLessThan(up ?? -1, 0.4)
        XCTAssertEqual((down ?? 0) - 0.4, 0.4 - (up ?? 0), accuracy: 1e-12)
    }

    func testAViewportThatAlreadyShowsEverythingCannotScroll() {
        // A short document in a tall window has no scrollable range, and a
        // step measured against it would be a division by zero.
        XCTAssertNil(ScrollMechanics.fractionPerLine(viewport: 400, content: 400))
        XCTAssertNil(ScrollMechanics.fractionPerLine(viewport: 900, content: 400))
        XCTAssertNil(ScrollMechanics.value(current: 0, lines: -5, viewport: 400, content: 400))
        XCTAssertNil(ScrollMechanics.fractionPerLine(viewport: 0, content: 5200))
    }

    func testTheValueNeverLeavesItsRange() {
        XCTAssertEqual(ScrollMechanics.value(current: 0.99, lines: -200,
                                             viewport: viewportHeight, content: contentHeight),
                       1.0)
        XCTAssertEqual(ScrollMechanics.value(current: 0.01, lines: 200,
                                             viewport: viewportHeight, content: contentHeight),
                       0.0)
    }

    func testALargeDeltaStillMovesByWholeLinesRatherThanJumpingToTheEnd() {
        // 20 lines at 19.5pt each is 390pt — exactly one page — out of 4810.
        let onePage = ScrollMechanics.value(current: 0, lines: -20,
                                            viewport: viewportHeight, content: contentHeight)
        XCTAssertEqual(onePage ?? -1, 390.0 / 4810.0, accuracy: 1e-9)
        XCTAssertLessThan(onePage ?? 1, 1.0)
    }

    func testZeroLinesIsANoOpSoTheCallerCanSkipTheWrite() {
        XCTAssertEqual(ScrollMechanics.value(current: 0.37, lines: 0,
                                             viewport: viewportHeight, content: contentHeight),
                       0.37)
    }
}
