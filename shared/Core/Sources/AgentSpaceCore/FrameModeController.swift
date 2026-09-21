import Foundation

public enum FrameDeliveryMode: String, Codable, Sendable { case delta, video }

public struct PerformancePolicy: Equatable, Sendable {
    public var videoThreshold: Double
    public var deltaThreshold: Double
    public var enterVideoSeconds: TimeInterval
    public var leaveVideoSeconds: TimeInterval
    public var ewmaAlpha: Double

    public init(videoThreshold: Double = 0.5, deltaThreshold: Double = 0.15, enterVideoSeconds: TimeInterval = 0.4, leaveVideoSeconds: TimeInterval = 1.5, ewmaAlpha: Double = 0.25) {
        self.videoThreshold = videoThreshold; self.deltaThreshold = deltaThreshold
        self.enterVideoSeconds = enterVideoSeconds; self.leaveVideoSeconds = leaveVideoSeconds; self.ewmaAlpha = ewmaAlpha
    }
}

public struct FrameModeController: Sendable {
    public private(set) var mode: FrameDeliveryMode = .delta
    private let policy: PerformancePolicy
    private var ewma: Double?
    private var qualifyingTime: TimeInterval = 0

    public init(policy: PerformancePolicy = .init()) { self.policy = policy }

    public mutating func observe(damageRatio: Double, elapsed: TimeInterval) -> FrameDeliveryMode {
        let bounded = min(1, max(0, damageRatio))
        ewma = ewma.map { policy.ewmaAlpha * bounded + (1 - policy.ewmaAlpha) * $0 } ?? bounded
        switch mode {
        case .delta:
            if ewma! > policy.videoThreshold { qualifyingTime += elapsed } else { qualifyingTime = 0 }
            if qualifyingTime >= policy.enterVideoSeconds { mode = .video; qualifyingTime = 0 }
        case .video:
            if ewma! < policy.deltaThreshold { qualifyingTime += elapsed } else { qualifyingTime = 0 }
            if qualifyingTime >= policy.leaveVideoSeconds { mode = .delta; qualifyingTime = 0 }
        }
        return mode
    }
}
