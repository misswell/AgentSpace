import XCTest
import CoreGraphics
@testable import AgentSpaceCore

/// The unit half of the frame-cost round (§382).
///
/// The live test (`tests/App/FrameStreamCostTests.swift`) measures the ratio a
/// person can feel — main-thread updates per frame — but it needs a real stream,
/// a real worker and a real desktop. This file pins the same rule where it can be
/// re-run in a second and can fail for exactly one reason: a frame that changed
/// nothing must be worth nothing to the interface.
final class FrameSurfaceStatusTests: XCTestCase {
    /// The measured symptom, in miniature: a still 4K desktop delivers frames
    /// (heartbeats and duplicate-forced repaints included) at a steady rate while
    /// changing nothing a viewer draws. Before this type, every one of them wrote
    /// the published size; now the tenth frame costs the same as the second.
    func testTenFramesOfOneSizePublishOnce() {
        var status = FrameSurfaceStatus()
        var publishes = 0
        for _ in 0..<10 {
            if status.accept(CGSize(width: 3840, height: 2160)).isWorthPublishing { publishes += 1 }
        }
        XCTAssertEqual(publishes, 1, "one size, ten frames: only the first is worth a UI update")
        XCTAssertEqual(status.size, CGSize(width: 3840, height: 2160))
    }

    /// A re-negotiated stream (quality switch, display change) must still reach the
    /// interface, and the frames after it must go quiet again.
    func testASizeChangePublishesOnceAndThenGoesQuiet() {
        var status = FrameSurfaceStatus()
        _ = status.accept(CGSize(width: 2880, height: 1800))
        var changes: [CGSize?] = []
        for size in [CGSize(width: 2880, height: 1800), CGSize(width: 1920, height: 1200),
                     CGSize(width: 1920, height: 1200), CGSize(width: 1920, height: 1200)] {
            changes.append(status.accept(size).newSize)
        }
        XCTAssertEqual(changes, [nil, CGSize(width: 1920, height: 1200), nil, nil])
    }

    /// The obligation the retraction exists for: an error or a notice on screen is
    /// a claim about the stream, and the first frame after it disproves the claim.
    /// Dropping that frame's retraction would leave a recovered stream apologising.
    func testAMessageIsRetractedByTheNextFrameAndOnlyOnce() {
        var status = FrameSurfaceStatus()
        _ = status.accept(CGSize(width: 1920, height: 1200))
        status.noteStatusShown()
        var publishes = 0
        let first = status.accept(CGSize(width: 1920, height: 1200))
        if first.isWorthPublishing { publishes += 1 }
        XCTAssertTrue(first.retractStatus, "the frame that lands after a message must take it back")
        XCTAssertNil(first.newSize, "no size moved, so nothing but the retraction is published")
        for _ in 0..<5 {
            if status.accept(CGSize(width: 1920, height: 1200)).isWorthPublishing { publishes += 1 }
        }
        XCTAssertEqual(publishes, 1, "the retraction is owed once, not once per frame thereafter")
    }

    /// Two things can be true of one frame, and then one hop does both jobs — the
    /// size the stream renegotiated to and the message it just disproved.
    func testOneFrameCanBothResizeAndRetract() {
        var status = FrameSurfaceStatus()
        _ = status.accept(CGSize(width: 2880, height: 1800))
        status.noteStatusShown()
        let change = status.accept(CGSize(width: 1920, height: 1200))
        XCTAssertEqual(change.newSize, CGSize(width: 1920, height: 1200))
        XCTAssertTrue(change.retractStatus)
        XCTAssertTrue(change.isWorthPublishing)
    }

    /// A stream that has delivered nothing yet has published nothing: the initial
    /// size is a not-yet, not a size, and a frame claiming zero pixels must not
    /// make the interface announce a zero-pixel surface.
    func testNothingIsPublishedBeforeRealPixelsArrive() {
        var status = FrameSurfaceStatus()
        XCTAssertFalse(status.accept(.zero).isWorthPublishing)
        XCTAssertFalse(status.accept(.zero).isWorthPublishing)
        XCTAssertTrue(status.accept(CGSize(width: 1280, height: 800)).isWorthPublishing)
    }

    /// A retraction is not lost when the status arrives before any frame does: the
    /// obligation is a stored field rather than an argument to `accept`. Two
    /// messages still owe one retraction, because the hop that clears them clears
    /// every property they were written to, and none is owed afterwards.
    func testARetractionOutlivesTheFramesBeforeItsOwn() {
        var status = FrameSurfaceStatus()
        status.noteStatusShown()
        status.noteStatusShown()
        XCTAssertTrue(status.accept(CGSize(width: 800, height: 600)).retractStatus)
        XCTAssertFalse(status.accept(CGSize(width: 800, height: 600)).retractStatus)
    }
}
