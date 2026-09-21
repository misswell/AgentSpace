import XCTest
@testable import AgentSpaceCore

final class FrameModeControllerTests: XCTestCase {
    func testHysteresisPreventsOscillation() {
        var controller = FrameModeController(policy: .init(videoThreshold: 0.5, deltaThreshold: 0.15, enterVideoSeconds: 0.4, leaveVideoSeconds: 1.5, ewmaAlpha: 1))
        XCTAssertEqual(controller.observe(damageRatio: 0.8, elapsed: 0.2), .delta)
        XCTAssertEqual(controller.observe(damageRatio: 0.8, elapsed: 0.2), .video)
        XCTAssertEqual(controller.observe(damageRatio: 0.1, elapsed: 1.0), .video)
        XCTAssertEqual(controller.observe(damageRatio: 0.1, elapsed: 0.5), .delta)
        XCTAssertEqual(controller.observe(damageRatio: 0.3, elapsed: 10), .delta)
    }
}
