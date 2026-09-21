import XCTest
@testable import AgentSpaceCore

final class DirtyRegionAccumulatorTests: XCTestCase {
    func testMergesOverlappingAndNearbyRects() {
        let accumulator = DirtyRegionAccumulator(policy: .init(maximumRects: 64, fullFrameThreshold: 0.5, mergeDistance: 2))
        accumulator.merge([.init(x: 10, y: 10, width: 20, height: 20)], frameWidth: 200, frameHeight: 100)
        accumulator.merge([.init(x: 29, y: 10, width: 20, height: 20)], frameWidth: 200, frameHeight: 100)
        XCTAssertEqual(accumulator.take(), .regions([.init(x: 10, y: 10, width: 39, height: 20)]))
    }

    func testPromotesLargeDamageToFullFrame() {
        let accumulator = DirtyRegionAccumulator(policy: .init(maximumRects: 64, fullFrameThreshold: 0.5, mergeDistance: 0))
        accumulator.merge([.init(x: 0, y: 0, width: 80, height: 80)], frameWidth: 100, frameHeight: 100)
        XCTAssertEqual(accumulator.take(), .fullFrame(width: 100, height: 100))
    }

    func testEmptyDamagePublishesNothing() {
        let accumulator = DirtyRegionAccumulator()
        accumulator.merge([], frameWidth: 100, frameHeight: 100)
        XCTAssertEqual(accumulator.take(), .none)
    }

    func testTooManyRectsPromoteToFullFrame() {
        let accumulator = DirtyRegionAccumulator(policy: .init(maximumRects: 2, fullFrameThreshold: 1, mergeDistance: 0))
        accumulator.merge([
            .init(x: 0, y: 0, width: 1, height: 1),
            .init(x: 10, y: 0, width: 1, height: 1),
            .init(x: 20, y: 0, width: 1, height: 1),
        ], frameWidth: 100, frameHeight: 100)
        XCTAssertEqual(accumulator.take(), .fullFrame(width: 100, height: 100))
    }
}
