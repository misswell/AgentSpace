import XCTest
@testable import AgentSpaceCore

final class CaptureTargetTests: XCTestCase {
    func testRetinaDesktopIsAnAdditiveFrameTarget() throws {
        let target = CaptureTarget.retinaDesktop
        XCTAssertEqual(try CaptureTarget(jsonValue: target.jsonValue), target)
        XCTAssertEqual(target.jsonValue["kind"]?.stringValue, "retinaDesktop")
        XCTAssertEqual(try CaptureTarget(jsonValue: .obj(["kind": .string("display")])),
                       .display(displayID: nil))
        XCTAssertEqual(try CaptureTarget(jsonValue: .obj([
            "kind": .string("display"), "displayId": .int(42)
        ])), .display(displayID: 42))
    }
}
