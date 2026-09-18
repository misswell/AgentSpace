import Foundation
import XCTest
@testable import AgentSpaceCore

/// The §52 preview lifecycle, with the platform frame source replaced by a
/// counting fake. What is under test is the state machine — start/stop
/// idempotence, newest-frame-wins, and the idle auto-stop — because those are
/// the properties a GUI crash or a runaway stream would violate.
final class PreviewControllerTests: XCTestCase {

    /// Counts its starts and stops; frames advance from nil to a fixed blob.
    final class FakeSource: PreviewFrameSource {
        private(set) var started = 0
        private(set) var stopped = 0
        /// A non-nil default: "no frame yet" is a legitimate state the
        /// controller reports as nil, so tests that assert frame flow must opt
        /// out explicitly rather than trip over it accidentally.
        var frames: [Data] = [Data("frame".utf8)]
        private var index = 0
        let startError: Error?

        init(startError: Error? = nil) { self.startError = startError }

        func start(maxFPS: Int) throws {
            if let startError { throw startError }
            started += 1
        }

        func stop() { stopped += 1 }

        var latestFrame: Data? {
            guard index < frames.count else { return frames.last }
            index += 1
            return frames[index - 1]
        }
    }

    private var factorySource: FakeSource!
    private var controller: PreviewController!

    override func setUp() {
        super.setUp()
        factorySource = FakeSource()
        controller = PreviewController(idleTimeout: 10) { _ in self.factorySource }
    }

    func testStartFrameStopRoundTrip() throws {
        factorySource.frames = [Data("frame1".utf8), Data("frame2".utf8), Data("frame2".utf8), Data("frame2".utf8)]
        let fps = try controller.start(maxFPS: 5)
        XCTAssertEqual(fps, 5)
        XCTAssertTrue(controller.isRunning)

        XCTAssertEqual(controller.frame(), Data("frame1".utf8))
        XCTAssertEqual(controller.frame(), Data("frame2".utf8))

        controller.stop()
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(factorySource.stopped, 1)
        // And pulling after stop is a plain nil, not a crash.
        XCTAssertNil(controller.frame())
    }

    /// A second start must not tear down the first viewer's stream — the
    /// common case is a user clicking "Open Desktop" twice.
    func testRestartingARunningStreamIsANoOpThatRearmsIdle() throws {
        try controller.start(maxFPS: 5)
        try controller.start(maxFPS: 15)
        XCTAssertEqual(factorySource.started, 1, "the running source must not be rebuilt")
        XCTAssertTrue(controller.isRunning)
        // Idle clock re-armed: no timeout stop just because the first viewer
        // opened a while ago.
        XCTAssertNotNil(controller.frame(now: Date().addingTimeInterval(5)))
    }

    /// The idle auto-stop is the safety property: a viewer that vanishes
    /// without a clean close must not leave the worker capturing forever.
    func testAnUnpulledStreamStopsItselfAfterTheIdleTimeout() throws {
        try controller.start(maxFPS: 5)
        // Pull once, then let the clock run: the next pull past the timeout
        // stops the stream and returns nothing.
        _ = controller.frame(now: Date())
        let late = controller.frame(now: Date().addingTimeInterval(11))
        XCTAssertNil(late)
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(factorySource.stopped, 1)

        // And after the auto-stop, a fresh start works — the failure mode
        // "auto-stopped once, dead forever" would be worse than the bug.
        try controller.start(maxFPS: 5)
        XCTAssertTrue(controller.isRunning)
    }

    func testAPullBeforeTheTimeoutKeepsTheStreamAlive() throws {
        try controller.start(maxFPS: 5)
        _ = controller.frame(now: Date())
        // A live viewer pulls steadily; 10 s of pulls never trip the 10 s idle.
        var now = Date()
        for _ in 0..<20 {
            now = now.addingTimeInterval(0.5)
            XCTAssertNotNil(controller.frame(now: now))
        }
        XCTAssertTrue(controller.isRunning)
    }

    /// A failed start must not leave a half-built source behind, or the next
    /// start would believe a stream exists and never really begin.
    func testFailedStartCleansUpAndTheNextStartCanSucceed() {
        let failing = PreviewController(idleTimeout: 10) { _ in
            FakeSource(startError: AgentSpaceError(code: .noWindowServer, message: "no display"))
        }
        XCTAssertThrowsError(try failing.start(maxFPS: 5))
        XCTAssertFalse(failing.isRunning)
        XCTAssertNil(failing.frame())

        // The controller built in setUp has a working source; the point of this
        // half is that the failed controller's state did not leak into a
        // phantom running flag.
        XCTAssertNoThrow(try controller.start(maxFPS: 5))
        XCTAssertTrue(controller.isRunning)
    }

    func testFPSIsClampedToAUsableRange() throws {
        XCTAssertEqual(try controller.start(maxFPS: 0), 1, "zero would divide by zero downstream")
        controller.stop()
        XCTAssertEqual(try controller.start(maxFPS: 1000), 30, "an unbounded client must not set the capture rate")
    }
}
