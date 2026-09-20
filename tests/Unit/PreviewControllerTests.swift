import Foundation
import XCTest
@testable import AgentSpaceCore

/// The §52 preview lifecycle, with the platform frame source replaced by a
/// counting fake. What is under test is the state machine — start/stop
/// idempotence, newest-frame-wins, and the idle auto-stop — because those are
/// the properties a GUI crash or a runaway stream would violate.
///
/// The idle auto-stop is tested through the watchdog, not through a later pull:
/// the client that leaks a stream is precisely the one that never calls again,
/// so a test that has to call `frame()` to prove the stop would be testing the
/// mechanism that does not exist in the failure case.
final class PreviewControllerTests: XCTestCase {

    /// Counts its starts and stops; frames advance from nil to a fixed blob.
    final class FakeSource: PreviewFrameSource {
        private let lock = NSLock()
        private var _started = 0
        private var _stopped = 0
        var started: Int { lock.lock(); defer { lock.unlock() }; return _started }
        var stopped: Int { lock.lock(); defer { lock.unlock() }; return _stopped }

        /// A non-nil default: "no frame yet" is a legitimate state the
        /// controller reports as nil, so tests that assert frame flow must opt
        /// out explicitly rather than trip over it accidentally.
        /// The captures this source has produced. A test appends one to emulate
        /// the next frame arriving; pulling twice with nothing appended is the
        /// newest-frame-wins case, which is not a new capture.
        var frames: [Data] = [Data("frame".utf8)]
        let startError: Error?

        func capture(_ data: Data) { lock.lock(); frames.append(data); lock.unlock() }

        init(startError: Error? = nil) { self.startError = startError }

        func start(maxFPS: Int) throws {
            if let startError { throw startError }
            lock.lock(); _started += 1; lock.unlock()
        }

        func stop() { lock.lock(); _stopped += 1; lock.unlock() }

        var latestFrame: Data? {
            lock.lock(); defer { lock.unlock() }
            return frames.last
        }

        /// Counts captures the way the real source does: a repeat of the newest
        /// frame on a second pull is not a new capture.
        var frameSequence: Int { lock.lock(); defer { lock.unlock() }; return frames.count }
    }

    /// A clock the test moves by hand, so "10 seconds went by" costs nothing.
    final class FakeClock {
        private let lock = NSLock()
        private var current = Date(timeIntervalSince1970: 1_800_000_000)
        var now: Date { lock.lock(); defer { lock.unlock() }; return current }
        func advance(_ seconds: TimeInterval) {
            lock.lock(); current = current.addingTimeInterval(seconds); lock.unlock()
        }
    }

    /// Holds the tick the controller armed and fires it when the test asks.
    /// Every tick ever armed is kept, so a test can fire the one belonging to a
    /// stream that has since been replaced.
    final class FakeWatchdog: PreviewIdleWatchdog {
        private let lock = NSLock()
        private var live: (() -> Void)?
        private var armed: [() -> Void] = []
        private(set) var intervals: [TimeInterval] = []
        private(set) var cancels = 0

        func arm(interval: TimeInterval, onTick: @escaping () -> Void) {
            lock.lock(); live = onTick; armed.append(onTick); intervals.append(interval); lock.unlock()
        }

        func cancel() { lock.lock(); live = nil; cancels += 1; lock.unlock() }

        var isArmed: Bool { lock.lock(); defer { lock.unlock() }; return live != nil }
        var armCount: Int { lock.lock(); defer { lock.unlock() }; return intervals.count }

        /// The tick a live watchdog would run right now.
        func fire() { lock.lock(); let tick = live; lock.unlock(); tick?() }

        /// The n-th tick ever armed, live or not — the stale-timer case.
        func fire(armedBeforeRestart index: Int) {
            lock.lock(); let tick = armed.indices.contains(index) ? armed[index] : nil; lock.unlock()
            tick?()
        }
    }

    private let clock = FakeClock()
    private let watchdog = FakeWatchdog()
    private var factorySource: FakeSource!
    private var controller: PreviewController!

    override func setUp() {
        super.setUp()
        factorySource = FakeSource()
        controller = makeController(source: factorySource)
    }

    private func makeController(
        source: FakeSource, idleTimeout: TimeInterval = 10
    ) -> PreviewController {
        let clock = self.clock, watchdog = self.watchdog
        return PreviewController(idleTimeout: idleTimeout, clock: { clock.now }, watchdog: watchdog) { _ in
            source
        }
    }

    func testStartFrameStopRoundTrip() throws {
        factorySource.frames = [Data("frame1".utf8)]
        let fps = try controller.start(maxFPS: 5)
        XCTAssertEqual(fps, 5)
        XCTAssertTrue(controller.isRunning)

        XCTAssertEqual(controller.frame(), Data("frame1".utf8))
        factorySource.capture(Data("frame2".utf8))
        XCTAssertEqual(controller.frame(), Data("frame2".utf8))
        XCTAssertEqual(
            controller.frame(), Data("frame2".utf8),
            "two pulls of one capture both see the newest frame")

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
        clock.advance(5)
        try controller.start(maxFPS: 15)
        XCTAssertEqual(factorySource.started, 1, "the running source must not be rebuilt")
        XCTAssertTrue(controller.isRunning)
        // Idle clock re-armed: no timeout stop just because the first viewer
        // opened a while ago.
        clock.advance(6)
        watchdog.fire()
        XCTAssertTrue(controller.isRunning)
        XCTAssertNotNil(controller.frame())
    }

    /// The property the whole watchdog exists for: start, then silence. No
    /// second `frame()` call is available to notice the leak, because the
    /// client that leaks is a client that is gone.
    func testStreamStopsWithoutAnotherFramePullAfterTheIdleTimeout() throws {
        try controller.start(maxFPS: 5)
        XCTAssertTrue(watchdog.isArmed, "a running stream must be watched")
        XCTAssertEqual(watchdog.intervals.last ?? 0, 1, accuracy: 0.0001,
                       "a 10 s timeout should be re-checked about every second")

        clock.advance(9)
        watchdog.fire()
        XCTAssertTrue(controller.isRunning, "9 s of silence is still inside the timeout")

        clock.advance(2)
        watchdog.fire()
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(factorySource.stopped, 1)
        XCTAssertFalse(watchdog.isArmed, "a stream that stopped itself stops being watched")
        XCTAssertNil(controller.frame())

        // And after the auto-stop, a fresh start works — the failure mode
        // "auto-stopped once, dead forever" would be worse than the bug.
        try controller.start(maxFPS: 5)
        XCTAssertTrue(controller.isRunning)
    }

    /// The same timeout decided by a late pull, which is still the path a live
    /// but slow viewer takes.
    func testAnUnpulledStreamStopsItselfAfterTheIdleTimeout() throws {
        try controller.start(maxFPS: 5)
        _ = controller.frame(now: clock.now)
        XCTAssertNil(controller.frame(now: clock.now.addingTimeInterval(11)))
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(factorySource.stopped, 1)
    }

    func testAPullBeforeTheTimeoutKeepsTheStreamAlive() throws {
        try controller.start(maxFPS: 5)
        // A live viewer pulls steadily; 10 s of pulls, and 20 watchdog ticks,
        // never trip the 10 s idle.
        for _ in 0..<20 {
            clock.advance(0.5)
            XCTAssertNotNil(controller.frame())
            watchdog.fire()
            XCTAssertTrue(controller.isRunning)
        }
        XCTAssertEqual(factorySource.stopped, 0)
    }

    /// A failed start must not leave a half-built source behind, or the next
    /// start would believe a stream exists and never really begin — and it must
    /// not arm a watchdog for a stream that never came up.
    func testFailedStartCleansUpAndArmsNothing() {
        let failingSource = FakeSource(startError: AgentSpaceError(code: .noWindowServer, message: "no display"))
        let failing = makeController(source: failingSource)
        XCTAssertThrowsError(try failing.start(maxFPS: 5))
        XCTAssertFalse(failing.isRunning)
        XCTAssertEqual(failingSource.stopped, 1, "the half-started source must be stopped")
        XCTAssertFalse(watchdog.isArmed, "a failed start has nothing to watch")
        watchdog.fire()
        XCTAssertNil(failing.frame())

        XCTAssertNoThrow(try controller.start(maxFPS: 5))
        XCTAssertTrue(controller.isRunning)
    }

    /// Stopping cancels the watch, so a tick already in flight on another queue
    /// cannot stop the stream twice — `PreviewFrameSource.stop` is documented
    /// idempotent, but the counting fake makes "exactly once" checkable.
    func testWatchdogAndExplicitStopRaceToExactlyOneStop() throws {
        try controller.start(maxFPS: 5)
        clock.advance(11)
        let threads = 8
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.concurrentPerform(iterations: threads) { index in
            if index % 2 == 0 { controller.stop() } else { watchdog.fire() }
            done.signal()
        }
        for _ in 0..<threads { done.wait() }
        XCTAssertEqual(factorySource.stopped, 1, "detach-then-stop must hand the source to one caller only")
        XCTAssertFalse(controller.isRunning)
    }

    /// The stale-timer case: a tick armed for an earlier stream must not tear
    /// down the one that replaced it.
    func testARestartedStreamSurvivesTheTickArmedForThePreviousOne() throws {
        try controller.start(maxFPS: 5)
        let firstTick = watchdog.armCount
        clock.advance(11)
        controller.stop()
        try controller.start(maxFPS: 5)
        XCTAssertEqual(watchdog.armCount, firstTick + 1)

        watchdog.fire(armedBeforeRestart: 0)
        XCTAssertTrue(controller.isRunning, "the new stream is not idle yet")
        XCTAssertEqual(factorySource.stopped, 1, "only the explicit stop stopped a stream")
    }

    func testWatchdogTicksAndPullsFromDifferentThreadsNeverStall() throws {
        try controller.start(maxFPS: 5)
        let pulls = 200
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            for _ in 0..<pulls {
                _ = self.controller.frame()
                self.controller.stop()
                _ = self.controller.frame()
                _ = try? self.controller.start(maxFPS: 5)
            }
            done.signal()
        }
        for _ in 0..<pulls {
            clock.advance(0.1)
            watchdog.fire()
        }
        XCTAssertEqual(done.wait(timeout: .now() + 10), .success,
                       "the watchdog must never wait on a lock held across a source stop")
    }

    /// A window nobody is touching still gets pulled, because the pull is what
    /// proves a viewer is watching — but it must stop paying for a payload.
    func testPullAnswersUnchangedWhenTheClientAlreadyHasTheNewestFrame() throws {
        _ = try controller.start(maxFPS: 5)
        let first = controller.pull()
        XCTAssertEqual(first.data, Data("frame".utf8))
        XCTAssertEqual(first.sequence, 1)
        XCTAssertFalse(first.unchanged)

        let second = controller.pull(newerThanSequence: first.sequence)
        XCTAssertNil(second.data, "the same JPEG twice is not a new frame")
        XCTAssertTrue(second.unchanged)
        XCTAssertEqual(second.sequence, 1, "the answer still names the frame on screen")
    }

    /// A source that cannot count frames must not be silenced by a client
    /// reporting that it has seen frame zero.
    func testAZeroSequenceIsNeverTreatedAsAlreadySeen() throws {
        _ = try controller.start(maxFPS: 5)
        let result = controller.pull(newerThanSequence: 0)
        XCTAssertFalse(result.unchanged)
        XCTAssertEqual(result.data, Data("frame".utf8))
    }

    /// The "unchanged" answer is still a pull: it renews the idle clock, or an
    /// idle window would look like an abandoned viewer to the watchdog.
    func testAnUnchangedAnswerKeepsTheStreamAlive() throws {
        factorySource.frames = [Data("only".utf8)]
        _ = try controller.start(maxFPS: 5)
        XCTAssertEqual(controller.pull().sequence, 1)
        for _ in 0..<30 {
            clock.advance(0.5)
            XCTAssertTrue(controller.pull(newerThanSequence: 1).unchanged)
        }
        XCTAssertTrue(controller.isRunning)
        watchdog.fire()
        XCTAssertTrue(controller.isRunning, "five seconds of steady pulls cannot be idle")
    }

    func testFPSIsClampedToAUsableRange() throws {
        XCTAssertEqual(try controller.start(maxFPS: 0), 1, "zero would divide by zero downstream")
        controller.stop()
        XCTAssertEqual(try controller.start(maxFPS: 1000), 30, "an unbounded client must not set the capture rate")
    }

    func testFramePullStopsAndClearsTheStreamWhenSessionStopsBeingUsable() throws {
        for verdict in [SessionVerdict.isConsole, .indeterminate, .noWindowServer] {
            let source = FakeSource()
            let controller = makeController(source: source)
            try controller.start(maxFPS: 5)

            XCTAssertThrowsError(try controller.frame(sessionVerdict: verdict)) { error in
                XCTAssertEqual((error as? AgentSpaceError)?.code, verdict.errorCode)
            }
            XCTAssertFalse(controller.isRunning)
            XCTAssertEqual(source.stopped, 1)
            XCTAssertNil(controller.frame(), "a refused pull must not expose the last captured frame")
            XCTAssertFalse(watchdog.isArmed, "a session refusal must leave no watchdog behind")
        }
    }
}
