import Foundation

/// What the worker says about one frame stream when asked. Every field here is
/// measured on the worker's own timelines; the viewer reports what only it can
/// see (`FrameRenderStats`) rather than pretending a local present happened
/// somewhere else.
public struct FrameStats: Codable, Equatable, Sendable {
    // Raw counts, since the stream opened.
    public var framesCaptured: UInt64 = 0
    public var framesPublished: UInt64 = 0
    public var framesDropped: UInt64 = 0
    public var framesMerged: UInt64 = 0
    public var fullFrames: UInt64 = 0
    public var deltaFrames: UInt64 = 0
    /// Frames a peer failed to acknowledge inside its deadline, so the worker
    /// stopped waiting on it. A viewer that is merely slow and one that has
    /// stopped reading look the same until this number moves.
    public var unacknowledgedDrops: UInt64 = 0
    public var heartbeatsSent: UInt64 = 0
    /// Times a capture ended while a viewer was attached — closed window,
    /// vanished display, ScreenCaptureKit giving up. Without this the only sign
    /// of it is a picture that stops changing.
    public var captureTerminations: UInt64 = 0
    public var modeSwitchCount: UInt64 = 0
    public var socketReconnects: UInt64 = 0
    public var sharedBytes: UInt64 = 0
    public var videoBytes: UInt64 = 0

    // Derived over a recent window, not since the first frame.
    public var captureFPS: Double = 0
    public var publishFPS: Double = 0
    /// Damage as a fraction of the surface, averaged over the recent window.
    public var dirtyRatio: Double = 0
    public var fullFrameRatio: Double = 0
    public var pendingDamageArea: UInt64 = 0
    public var mappingBytes: Int = 0

    // Which path the stream is on right now, and what it costs to be there.
    public var frameMode: String = "delta"
    public var encoderActive: Bool = false
    public var videoEncoderActivations: UInt64 = 0
    public var videoEncoderInvalidations: UInt64 = 0
    /// Times the machine was asked for an H.264 encoder and could not produce
    /// one. A stream that has always been on deltas and one that has tried to
    /// leave them and failed look identical in every other field here.
    public var videoEncoderFailures: UInt64 = 0
    /// The most recent shared buffer the kernel refused, if any.
    ///
    /// A value rather than a message so a viewer can decide what to show without
    /// reading English. It survives the failure on purpose: the stream that
    /// cannot be opened is exactly the one being asked about, and a
    /// `frame.stats` reply that answers "nothing has gone wrong" about a desktop
    /// with no picture is worse than one that repeats the errno.
    public var allocationFailure: SharedFrameAllocationFailure?

    // Capture → publish, in milliseconds, because the worker owns both ends.
    public var captureToPublishP50: Double = 0
    public var captureToPublishP95: Double = 0

    public init() {}
}

/// What the viewer says about the same stream. Local arrival and local present
/// can only be measured where the pixels land, and the instant the worker put a
/// frame on the socket is deliberately *not* one of them: it never crosses the
/// wire, so a number for it would be an estimate wearing a unit.
public struct FrameRenderStats: Codable, Equatable, Sendable {
    public var framesReceived: UInt64 = 0
    /// Heartbeats among them. A still desktop is mostly these, which is the
    /// difference between "the stream is quiet" and "the stream is dead".
    public var heartbeatsReceived: UInt64 = 0
    public var framesRendered: UInt64 = 0
    /// Frames the local pipeline refused rather than queueing, so the newest
    /// picture stayed on screen instead of a backlog of older ones.
    public var framesDropped: UInt64 = 0
    /// Frames that could not be continued from — a gap, a lost slot, a new
    /// surface — and forced a baseline request.
    public var sequenceGaps: UInt64 = 0
    public var socketReconnects: UInt64 = 0
    public var renderFPS: Double = 0
    public var receiveToRenderP50: Double = 0
    public var receiveToRenderP95: Double = 0
    public var endToEndP50: Double = 0
    public var endToEndP95: Double = 0

    public init() {}
}
