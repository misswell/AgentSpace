import Foundation

/// What the encoder said about being handed a frame.
///
/// A bare `Void` return was the bug this describes: "submitted", "still working
/// on the previous frame" and "VideoToolbox refused" all looked the same to the
/// caller, so a frame dropped on the floor was indistinguishable from one on its
/// way to a viewer — and the counter that was supposed to show it stayed at zero.
public enum FrameEncodeSubmission: Equatable, Sendable {
    case submitted
    /// The encoder is still working on the frame before this one, so this frame
    /// never entered the codec.
    case busy
    /// `VTCompressionSessionEncodeFrame` said no, carrying its `OSStatus`.
    case failed(Int32)
}

/// Whether the viewer has been given a key frame yet.
///
/// The rule the type exists to keep: *asking* for an IDR is not the same as a
/// viewer *having* one. `VTCompressionSessionEncodeFrame` submits a frame, and
/// between that submission and the payload there is room for the frame to be
/// dropped, for the encode to fail, and for the socket to be gone by the time
/// bytes come back. Any of those leaves a decoder with neither SPS/PPS nor an
/// IDR, so the next frame must still be forced — clearing on submission is what
/// made a stream that lost its first key frame undecodable until the encoder's
/// own key frame interval happened to come round again.
public struct FrameKeyFrameState: Equatable, Sendable {
    public private(set) var needsKeyFrame = true

    public init() {}

    /// What to ask the encoder for on the frame being submitted now.
    public var forceKeyFrame: Bool { needsKeyFrame }

    /// A payload came out of the encoder and reached the socket.
    ///
    /// Only a key frame the socket accepted clears the request. A send that
    /// failed means the viewer is gone, and the one that reconnects needs an IDR
    /// as much as the first one did — so that case sets it rather than leaving it
    /// whatever it was.
    public mutating func noteOutput(isKeyFrame: Bool, delivered: Bool) {
        if isKeyFrame && delivered { needsKeyFrame = false }
        else if !delivered { needsKeyFrame = true }
    }

    /// The viewer cannot be continued from: it has never had a key frame, or it
    /// has been showing shared pixels since the last one, or the connection that
    /// carried it is gone.
    public mutating func require() { needsKeyFrame = true }
}
