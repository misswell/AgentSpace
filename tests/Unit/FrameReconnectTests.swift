import XCTest
@testable import AgentSpaceCore

final class FrameReconnectTests: XCTestCase {
    func testNewWorkerRejectsOldMappingAndRequiresBaseline() {
        let old = UUID(), new = UUID()
        var state = FrameReconnectState()
        XCTAssertTrue(state.acceptHandshake(workerInstanceID: old, sessionGeneration: 1))
        state.didMapSurface(generation: 4)
        XCTAssertFalse(state.acceptHandshake(workerInstanceID: old, sessionGeneration: 1))
        XCTAssertTrue(state.acceptHandshake(workerInstanceID: new, sessionGeneration: 1))
        XCTAssertNil(state.surfaceGeneration)
        XCTAssertTrue(state.requiresFullFrame)
    }
}
