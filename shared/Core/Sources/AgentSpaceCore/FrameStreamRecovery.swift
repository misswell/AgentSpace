import Foundation

/// What the viewer says to the person watching while a frame stream will not lay
/// out — and when it stops calling each attempt a hiccup.
///
/// The judgment lives here rather than in the overlay because the overlay is not
/// testable, and because the two states differ in exactly one thing: whether
/// another attempt is worth presenting as news. The first mapping fault is a
/// reconnect; a third in a row is a machine whose app and worker disagree about
/// the buffer, and a window that keeps saying "reconnecting" turns a permanent
/// failure into the appearance of patience.
public enum FrameStreamNotice: Equatable, Sendable {
    /// Nothing to say: streaming, or waiting for a first frame.
    case none
    /// The shared picture could not be read. The connection was dropped and
    /// another attempt is underway, which is the honest message while it is.
    case resynchronising
    /// Enough attempts in a row have failed the same way that reconnecting is no
    /// longer the useful next step to offer.
    case unrecoverable
}

public struct FrameStreamRecovery: Sendable {
    /// Three consecutive faults is where this stops being transient. Judged
    /// against the client's own back-off (0.5 s, 1 s, 2 s, 5 s), three attempts is
    /// about three and a half seconds of trying: long enough to be sure, short
    /// enough that the person in front of a black window is not still being told
    /// to wait.
    public static let giveUpAfterAttempts = 3

    public private(set) var consecutiveMappingFaults = 0
    public init() {}

    public var notice: FrameStreamNotice {
        if consecutiveMappingFaults == 0 { return .none }
        return consecutiveMappingFaults >= Self.giveUpAfterAttempts ? .unrecoverable : .resynchronising
    }

    /// Records one more connection that died with an untrustworthy mapping, and
    /// returns what the window should now say.
    public mutating func noteMappingFault() -> FrameStreamNotice {
        consecutiveMappingFaults &+= 1
        return notice
    }

    /// Pixels landed, so the count describes the past rather than the current
    /// stream. Without this a stream that recovered once reports "unrecoverable"
    /// forever after three bad seconds.
    public mutating func noteStreaming() { consecutiveMappingFaults = 0 }
}
