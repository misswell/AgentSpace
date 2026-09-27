import Foundation

/// Decides when a delayed cursor report may replace a locally drawn position.
/// The worker remains authoritative, but a report received during continuous
/// movement can describe an earlier hand position. Applying it immediately
/// would make the cursor jump backwards on every sample.
public enum CursorCorrection: Equatable, Sendable {
    case keepPrediction
    case smooth
    case snap
}

public enum CursorCorrectionPolicy {
    public static let settleDelay: TimeInterval = 0.08

    public static func decision(predictedX: Double, predictedY: Double,
                                confirmedX: Double, confirmedY: Double,
                                predictionAge: TimeInterval) -> CursorCorrection {
        if predictionAge < settleDelay { return .keepPrediction }
        let distance = hypot(predictedX - confirmedX, predictedY - confirmedY)
        if distance < 2 { return .keepPrediction }
        return distance <= 10 ? .smooth : .snap
    }
}
