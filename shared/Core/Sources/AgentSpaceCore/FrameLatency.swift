import Foundation

/// Percentiles over a sliding window of recent samples, in milliseconds.
///
/// A mean would hide the thing that matters here: a stream that averages 8 ms
/// while one frame in fifty takes 120 ms is a stream that stutters. And the
/// window is bounded because a diagnostic that remembers its first hour reports
/// the machine's mood averaged over an hour.
public struct LatencyWindow: Equatable, Sendable {
    public static let defaultCapacity = 120

    public let capacity: Int
    private var samples: [Double] = []
    private var next = 0
    private(set) var count = 0

    public init(capacity: Int = LatencyWindow.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    public mutating func record(_ milliseconds: Double) {
        guard milliseconds.isFinite, milliseconds >= 0 else { return }
        if samples.isEmpty { samples = Array(repeating: 0, count: capacity) }
        samples[next] = milliseconds
        next = (next + 1) % capacity
        count += 1
    }

    public var isEmpty: Bool { count == 0 }
    public var sampleCount: Int { min(count, capacity) }

    public subscript(percentile: Double) -> Double? {
        guard sampleCount > 0 else { return nil }
        let sorted = samples.prefix(sampleCount).sorted()
        let bounded = min(100, max(0, percentile))
        let index = min(sorted.count - 1, Int((bounded / 100) * Double(sorted.count)))
        return sorted[index]
    }

    public var median: Double? { self[50] }
    public var p95: Double? { self[95] }
}

/// Latency between the moments a frame is observed, split so that each side
/// reports only what it can actually see.
///
/// The worker owns capture and publish. The viewer owns local arrival and
/// present, and can tie them back to capture because the frame carries its
/// capture stamp — but it cannot time the worker's publish, because that instant
/// is not on the wire, and inventing it would produce a number that looks
/// measured. So the viewer reports arrival→present and the whole
/// capture→present chain; the gap between the two is the worker's own cost plus
/// the socket. End-to-end is the number a person sees.
///
/// Both stamps are uptime on the *same* Mac: AgentSpace has no network
/// transport, so an agent desktop and its viewer share one clock and no
/// negotiation is needed. A sample that arrives out of order, or so far out of
/// order that it must be two different clocks, is discarded rather than
/// recorded: a flattering number is worse than a missing one.
public struct FrameLatency: Equatable, Sendable {
    /// Nothing in this pipeline may legitimately take longer than this and still
    /// be called latency.
    public static let maximumPlausibleNanoseconds: Int64 = 5_000_000_000

    public private(set) var captureToPublish = LatencyWindow()
    public private(set) var receiveToRender = LatencyWindow()
    public private(set) var captureToRender = LatencyWindow()

    public init() {}

    public mutating func record(captureToPublished nanoseconds: Int64) {
        guard let value = milliseconds(nanoseconds) else { return }
        captureToPublish.record(value)
    }

    public mutating func record(receiveToRendered nanoseconds: Int64) {
        guard let value = milliseconds(nanoseconds) else { return }
        receiveToRender.record(value)
    }

    public mutating func record(captureToRendered nanoseconds: Int64) {
        guard let value = milliseconds(nanoseconds) else { return }
        captureToRender.record(value)
    }

    /// Rejects both negatives and absurd magnitudes.
    ///
    /// The upper bound is not paranoia about a slow machine: the capture stamp
    /// comes from ScreenCaptureKit, and if that ever hands back a timestamp on a
    /// different epoch than host uptime, the "latency" is the distance between
    /// two clocks rather than a measurement. A missing sample is honest; a
    /// five-hour p95 is a bug report that reads like a perf problem.
    private func milliseconds(_ nanoseconds: Int64) -> Double? {
        guard nanoseconds >= 0, nanoseconds <= FrameLatency.maximumPlausibleNanoseconds else { return nil }
        return Double(nanoseconds) / 1_000_000
    }
}

/// Frames per second over a window, from the first and last event inside it.
///
/// Counting events and dividing by *elapsed since start* would decay toward
/// zero the longer a stream runs. This measures the recent rate, which is the
/// only rate a viewer can see.
public struct RateMeter: Equatable, Sendable {
    public let window: TimeInterval
    private var timestamps: [TimeInterval] = []

    public init(window: TimeInterval = 2) { self.window = max(0.1, window) }

    public mutating func record(_ at: TimeInterval) {
        timestamps.append(at)
        let horizon = at - window
        while let first = timestamps.first, first < horizon { timestamps.removeFirst() }
    }

    public mutating func current(at now: TimeInterval) -> Double {
        recordHorizon(now)
        guard timestamps.count > 1 else { return timestamps.isEmpty ? 0 : 1 / window }
        let span = timestamps.last! - timestamps.first!
        guard span > 0 else { return 0 }
        return Double(timestamps.count - 1) / span
    }

    private mutating func recordHorizon(_ now: TimeInterval) {
        let horizon = now - window
        while let first = timestamps.first, first < horizon { timestamps.removeFirst() }
    }

    public var eventsInWindow: Int { timestamps.count }
}
