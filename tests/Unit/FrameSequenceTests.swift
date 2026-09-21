import XCTest
@testable import AgentSpaceCore

final class FrameSequenceTests: XCTestCase {
    func testValidDeltaAndMissingBase() {
        var validator = FrameSequenceValidator()
        XCTAssertEqual(validator.accept(generation: 1, sequence: 10, baseSequence: 0, kind: .fullBGRA), .accepted)
        XCTAssertEqual(validator.accept(generation: 1, sequence: 11, baseSequence: 10, kind: .deltaBGRA), .accepted)
        XCTAssertEqual(validator.accept(generation: 1, sequence: 13, baseSequence: 12, kind: .deltaBGRA), .requestFullFrame)
    }

    func testGenerationChangeRequiresFullFrame() {
        var validator = FrameSequenceValidator()
        _ = validator.accept(generation: 1, sequence: 1, baseSequence: 0, kind: .fullBGRA)
        XCTAssertEqual(validator.accept(generation: 2, sequence: 2, baseSequence: 1, kind: .deltaBGRA), .requestFullFrame)
        XCTAssertEqual(validator.accept(generation: 2, sequence: 3, baseSequence: 0, kind: .fullBGRA), .accepted)
    }
}
