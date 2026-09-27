import XCTest
@testable import AgentSpaceCore

final class CursorCorrectionTests: XCTestCase {
    func testAnOlderWorkerPositionCannotPullBackAStillMovingCursor() {
        XCTAssertEqual(CursorCorrectionPolicy.decision(
            predictedX: 100, predictedY: 100, confirmedX: 70, confirmedY: 100,
            predictionAge: 0.02), .keepPrediction)
    }

    func testSettledCursorIgnoresRoundingAndSmoothsSmallDisagreement() {
        XCTAssertEqual(CursorCorrectionPolicy.decision(
            predictedX: 100, predictedY: 100, confirmedX: 101, confirmedY: 100,
            predictionAge: 0.1), .keepPrediction)
        XCTAssertEqual(CursorCorrectionPolicy.decision(
            predictedX: 100, predictedY: 100, confirmedX: 106, confirmedY: 100,
            predictionAge: 0.1), .smooth)
    }

    func testSettledCursorImmediatelyCorrectsLargeDisagreement() {
        XCTAssertEqual(CursorCorrectionPolicy.decision(
            predictedX: 100, predictedY: 100, confirmedX: 120, confirmedY: 100,
            predictionAge: 0.1), .snap)
    }
}
