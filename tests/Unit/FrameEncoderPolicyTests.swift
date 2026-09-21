import XCTest
@testable import AgentSpaceCore

/// What the video path does when the machine cannot give it an encoder, and what
/// it remembers about having tried.
///
/// Two rules, both of them things this code used to get wrong. The first: an
/// encoder that cannot be created is a reason to send pixels, not a reason to stop
/// the stream — so a refusal has to come back as `.delta` with the surface still
/// on its way, and it has to be counted. The second: asking again on every frame
/// turns one broken environment into sixty allocations a second on the thread that
/// is also delivering the fallback, so the cooldown has to hold the question back
/// rather than answer it faster.
final class FrameEncoderAccessTests: XCTestCase {
    func testVideoRequestWithWorkingEncoderIsVideo() {
        var access = FrameEncoderAccess(interval: 5)
        var opened = 0
        let path = access.path(for: .video, opening: { opened += 1; return true }, at: 100)
        XCTAssertEqual(path, .video)
        XCTAssertEqual(opened, 1)
        XCTAssertEqual(access.failures, 0)
    }

    /// The regression: a failed activation used to leave the frame on no path at
    /// all, which is a frozen desktop behind a heartbeat that still looked alive.
    func testFailedActivationFallsBackToDeltaAndCountsIt() {
        var access = FrameEncoderAccess(interval: 5)
        let path = access.path(for: .video, opening: { false }, at: 100)
        XCTAssertEqual(path, .delta, "a video frame with no encoder is a delta frame")
        XCTAssertEqual(access.failures, 1)
    }

    /// The cooldown is the difference between "this machine cannot encode" being
    /// reported once and being reported six hundred times a second.
    func testCooldownHoldsTheQuestionBackRatherThanAnsweringItFaster() {
        var access = FrameEncoderAccess(interval: 5)
        var opened = 0
        let first = access.path(for: .video, opening: { opened += 1; return false }, at: 100)
        XCTAssertEqual(first, .delta)

        for second in stride(from: 100.5, through: 104.5, by: 0.5) {
            XCTAssertEqual(access.path(for: .video, opening: { opened += 1; return false }, at: second), .delta)
        }
        XCTAssertEqual(opened, 1, "the whole window should cost one activation attempt")
        XCTAssertEqual(access.failures, 1)

        // The window closes; the machine gets asked again, and a machine that has
        // grown an encoder in the meantime is believed.
        XCTAssertEqual(access.path(for: .video, opening: { opened += 1; return true }, at: 105), .video)
        XCTAssertEqual(opened, 2)
    }

    func testAWorkingPathResetsTheCooldown() {
        var access = FrameEncoderAccess(interval: 5)
        _ = access.path(for: .video, opening: { true }, at: 0)
        var opened = 0
        XCTAssertEqual(access.path(for: .video, opening: { opened += 1; return true }, at: 1_000), .video)
        XCTAssertEqual(opened, 1, "an encoder that already exists is not a cooldown case")
    }

    /// Failures count attempts, not frames. Sixty frames over a minute on a
    /// machine that cannot encode are twelve questions and twelve failures —
    /// sixty would blame the stream for the codec's own retry interval, and one
    /// would hide every later attempt.
    func testFailuresCountAttemptsAndNotFrames() {
        var access = FrameEncoderAccess(interval: 5)
        for second in stride(from: 0, to: 60, by: 1) {
            XCTAssertEqual(access.path(for: .video, opening: { false }, at: Double(second)), .delta)
        }
        XCTAssertEqual(access.failures, 12, "sixty frames, twelve questions, twelve failures")
    }

    func testDeltaRequestsNeverTouchTheEncoder() {
        var access = FrameEncoderAccess(interval: 5)
        var opened = 0
        XCTAssertEqual(access.path(for: .delta, opening: { opened += 1; return true }, at: 100), .delta)
        XCTAssertEqual(opened, 0)
        XCTAssertEqual(access.failures, 0)
    }
}

/// Whether the viewer has a key frame, decided by what reached it rather than by
/// what was asked for.
///
/// `VTCompressionSessionEncodeFrame` submits a frame. Between that and the payload
/// there is room for the frame to be dropped, for the encode to fail, and for the
/// socket to be gone by the time bytes come back — and any of those leaves a
/// decoder with neither SPS/PPS nor an IDR. Clearing the request on submission is
/// what made a stream that lost its first key frame undecodable until the encoder's
/// own interval happened to come round again.
final class FrameKeyFrameStateTests: XCTestCase {
    func testAFreshViewerHasNeverSeenAKeyFrame() {
        XCTAssertTrue(FrameKeyFrameState().forceKeyFrame)
    }

    func testOnlyAKeyFrameThatReachedTheSocketClearsTheRequest() {
        var state = FrameKeyFrameState()
        state.noteOutput(isKeyFrame: false, delivered: true)
        XCTAssertTrue(state.forceKeyFrame, "an ordinary frame is undecodable on its own")

        state.noteOutput(isKeyFrame: true, delivered: false)
        XCTAssertTrue(state.forceKeyFrame, "a key frame the socket refused is one the viewer does not have")

        state.noteOutput(isKeyFrame: true, delivered: true)
        XCTAssertFalse(state.forceKeyFrame, "the sequence can continue now")

        state.noteOutput(isKeyFrame: false, delivered: true)
        XCTAssertFalse(state.forceKeyFrame, "a delivered delta does not restart anything")
    }

    /// A connection that came back is a viewer that has been showing shared pixels
    /// — or no pixels at all — since the last IDR.
    func testAConnectionOrPathChangeRequiresAnother() {
        var state = FrameKeyFrameState()
        state.noteOutput(isKeyFrame: true, delivered: true)
        XCTAssertFalse(state.forceKeyFrame)
        state.require()
        XCTAssertTrue(state.forceKeyFrame)
    }

    /// The sequence the type exists for: a first key frame that never arrives
    /// leaves the stream exactly as undecodable as it was, and the frame after it
    /// has to be forced as well.
    func testAKeyFrameThatNeverArrivesLeavesTheStreamAsUndecodableAsItStarted() {
        var state = FrameKeyFrameState()
        // Submitted with a forced IDR and dropped by the codec: with no output
        // there is nothing to report, so the request cannot clear itself by being
        // asked.
        XCTAssertTrue(state.forceKeyFrame)
        state.noteOutput(isKeyFrame: true, delivered: false)
        XCTAssertTrue(state.forceKeyFrame)
        state.noteOutput(isKeyFrame: true, delivered: true)
        XCTAssertFalse(state.forceKeyFrame, "and the first one that lands ends it")
    }

    /// A refusal worth logging carries the `OSStatus` that produced it, which is
    /// the difference between "encoding is broken here" and "-12903, the session
    /// was closed under it".
    func testFailedSubmissionCarriesTheStatusThatRefusedIt() {
        guard case let .failed(status) = FrameEncodeSubmission.failed(-12903) else {
            return XCTFail("the refusing status should survive the submission")
        }
        XCTAssertEqual(status, -12903)
        XCTAssertNotEqual(FrameEncodeSubmission.busy, .submitted)
    }
}
