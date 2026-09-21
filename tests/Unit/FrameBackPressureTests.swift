import XCTest
@testable import AgentSpaceCore

final class FrameBackPressureTests: XCTestCase {
    func testSlowConsumerGetsNewestFrameInsteadOfAQueueOfOldFrames() {
        let buffer = LatestFrameBuffer<Int>()
        buffer.store(1)
        buffer.store(2)
        buffer.store(3)
        XCTAssertEqual(buffer.take(), 3)
        XCTAssertNil(buffer.take())
    }

    func testThirtyCapturedTenConsumedNeverBuildsAHistoryQueue() {
        let buffer = LatestFrameBuffer<Int>()
        var consumed: [Int] = []
        for frame in 1...30 {
            buffer.store(frame)
            if frame.isMultiple(of: 3), let latest = buffer.take() { consumed.append(latest) }
        }
        XCTAssertEqual(consumed, Array(stride(from: 3, through: 30, by: 3)))
        XCTAssertNil(buffer.take())
    }
}
