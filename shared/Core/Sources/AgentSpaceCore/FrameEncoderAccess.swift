import Foundation

/// Whether the video path can take a frame right now, and what happens when it
/// cannot.
///
/// The rule this holds is one sentence: an encoder that cannot be created is a
/// reason to send pixels, not a reason to stop the stream. Before it, a failed
/// activation left the frame with neither path — no H.264 payload and nothing in
/// the shared buffer either — which is a frozen desktop behind a heartbeat that
/// still looked alive.
///
/// The cooldown is the other half. A machine without a usable VideoToolbox will
/// not grow one in the next few frames, and asking on every frame turns one
/// broken environment into sixty activations a second, each of which allocates
/// hardware in order to fail, on the thread that is also delivering the fallback
/// frames.
public struct FrameEncoderAccess: Sendable {
    public let interval: TimeInterval
    public private(set) var failures: UInt64 = 0
    public private(set) var nextAttempt: TimeInterval = 0

    public init(interval: TimeInterval = 5) {
        self.interval = max(0, interval)
    }

    /// Which path a frame takes. `open` creates the encoder and says whether it
    /// worked; it is not called at all while the cooldown is closed, which is
    /// what the counter below measures — attempts, not frames.
    ///
    /// A `.video` answer whose encoder is unavailable comes back as `.delta`, and
    /// the caller treats that as the instruction it is.
    public mutating func path(for requested: FrameDeliveryMode, opening open: () -> Bool, at now: TimeInterval) -> FrameDeliveryMode {
        guard requested == .video else { return requested }
        guard now >= nextAttempt else { return .delta }
        guard open() else {
            failures &+= 1
            nextAttempt = now + interval
            return .delta
        }
        nextAttempt = 0
        return .video
    }
}
