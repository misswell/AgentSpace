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
}
