import Darwin
import XCTest
@testable import AgentSpaceCore

/// The frame engine's decisions, tested where they are made.
///
/// None of this needs a window server, a GPU or a second process: what is under
/// test is when a slot may be acknowledged, when silence means death, how many
/// frames may be in flight, and what a number on the wire is allowed to mean.
/// The parts that need real pixels are gated on a real machine instead
/// (`docs/validation.md`).
final class FrameEngineTests: XCTestCase {

    // MARK: Heartbeat on the wire

    func testHeartbeatTravelsInTheHeaderWithoutChangingItsSize() throws {
        let beat = FrameHeader.heartbeat(streamID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, timestampNanoseconds: 42)
        XCTAssertEqual(beat.encoded().count, FrameHeader.byteCount, "the frame size is a wire constant; a heartbeat must not grow it")
        let decoded = try FrameHeader(decoding: beat.encoded())
        XCTAssertTrue(decoded.isHeartbeat)
        XCTAssertEqual(decoded.timestampNanoseconds, 42)
        XCTAssertEqual(decoded.payloadSize, 0)
    }

    func testAFrameIsNotAHeartbeat() throws {
        let frame = FrameHeader(streamID: UUID(), sequence: 7, timestampNanoseconds: 1, codec: .sharedBGRA, width: 4, height: 4, payloadSize: 64)
        XCTAssertFalse(frame.isHeartbeat)
        XCTAssertFalse(try FrameHeader(decoding: frame.encoded()).isHeartbeat)
    }

    // MARK: Silence versus a still desktop

    func testStaleWindowNeverShorterThanTwoHeartbeats() {
        // A policy that could expire before the second heartbeat arrived would
        // reconnect a healthy stream on a schedule it cannot keep.
        XCTAssertEqual(FrameIdlePolicy(heartbeatInterval: 4, staleAfter: 1).staleAfter, 8)
        XCTAssertEqual(FrameIdlePolicy(heartbeatInterval: 2, staleAfter: 8).staleAfter, 8)
    }

    func testHeartbeatCadenceAndStaleness() {
        var live = FrameStreamLiveness(policy: .init(heartbeatInterval: 2, staleAfter: 8), at: 1000)
        XCTAssertFalse(live.heartbeatDue(at: 1001.5))
        XCTAssertTrue(live.heartbeatDue(at: 1002))
        live.noteHeartbeatSent(at: 1002)
        XCTAssertFalse(live.isStale(at: 1006))
        XCTAssertTrue(live.isStale(at: 1010))
    }

    func testAnyActivitySuspendsTheDeadline() {
        // The "a static desktop must not be misjudged" case, in the direction
        // that matters: frames are their own heartbeat.
        var live = FrameStreamLiveness(policy: .init(heartbeatInterval: 2, staleAfter: 8), at: 1000)
        live.noteActivity(at: 1001)
        XCTAssertFalse(live.heartbeatDue(at: 1002.5))
        XCTAssertFalse(live.isStale(at: 1005))
    }

    // MARK: The GPU backlog bound

    func testBudgetAllowsOneInFlightPermitPerFrameBeingDrawn() {
        var budget = GPUFrameBudget(capacity: 2)
        XCTAssertTrue(budget.begin())
        XCTAssertTrue(budget.begin())
        XCTAssertFalse(budget.begin(), "a third frame would be a backlog, not a pipeline")
        budget.end()
        XCTAssertTrue(budget.begin())
        XCTAssertEqual(budget.inFlight, 2)
    }

    func testBudgetNeverGoesNegativeAndResetClearsIt() {
        var budget = GPUFrameBudget(capacity: 2)
        budget.end()
        XCTAssertEqual(budget.inFlight, 0)
        _ = budget.begin()
        budget.reset()
        XCTAssertEqual(budget.inFlight, 0)
    }

    func testLockedBudgetSurvivesConcurrentCompletionCallbacks() {
        // Metal calls the completion handler on a queue of its own choosing, so
        // releasing permits is genuinely multi-threaded. A lost release here is a
        // renderer that silently stops presenting while still acknowledging.
        let budget = InFlightBudget(capacity: 4)
        let rounds = 200
        DispatchQueue.concurrentPerform(iterations: rounds) { _ in
            _ = budget.begin()
        }
        XCTAssertEqual(budget.inFlight, 4)
        DispatchQueue.concurrentPerform(iterations: rounds) { _ in budget.end() }
        XCTAssertEqual(budget.inFlight, 0)
        XCTAssertTrue(budget.begin())
    }

    // MARK: The ACK rule

    func testEveryFrameGivesItsSlotBack() {
        // The rule this asserts is the one that parks a stream: acknowledge
        // first, ask for a baseline second, never the other way round and never
        // neither.
        for acceptance in [FrameAcceptance.applied(.uploaded), .applied(.uploadedWithoutPresent),
                           .applied(.refused), .duplicate, .needsBaseline] {
            let commands = FrameSlotFeedback.commands(slot: 1, sequence: 9, acceptance: acceptance)
            XCTAssertEqual(commands.first?.kind, .acknowledge, "\(acceptance)")
            XCTAssertEqual(commands.filter { $0.kind == .acknowledge }.count, 1, "\(acceptance)")
            XCTAssertEqual(commands.first?.slotIndex, 1)
            XCTAssertEqual(commands.first?.sequence, 9)
        }
    }

    func testOnlyAFrameThatDidNotLandAsksForABaseline() {
        func asksFull(_ acceptance: FrameAcceptance) -> Bool {
            FrameSlotFeedback.commands(slot: 0, sequence: 1, acceptance: acceptance).contains { $0.kind == .requestFull }
        }
        XCTAssertFalse(asksFull(.applied(.uploaded)))
        XCTAssertFalse(asksFull(.applied(.uploadedWithoutPresent)),
                       "a dropped present still holds the newest pixels; a baseline would be a wasted round trip")
        XCTAssertFalse(asksFull(.duplicate))
        XCTAssertTrue(asksFull(.applied(.refused)))
        XCTAssertTrue(asksFull(.needsBaseline))
    }

    // MARK: Latency numbers that mean what they say

    func testPercentilesComeFromTheRecentWindowOnly() {
        var window = LatencyWindow(capacity: 3)
        window.record(10)
        window.record(20)
        window.record(30)
        XCTAssertEqual(window[50] ?? 0, 20, accuracy: 0.001)
        XCTAssertEqual(window[95] ?? 0, 30, accuracy: 0.001)
        window.record(40)
        XCTAssertEqual(window.sampleCount, 3)
        XCTAssertEqual(window[50] ?? 0, 30, accuracy: 0.001, "the oldest sample must fall out, or an hour-old spike is today's p50")
    }

    func testEachLatencySegmentDropsItsOwnBadSamples() {
        var latency = FrameLatency()
        // Nothing about this can be latency: a stamp that far ahead has to come
        // from a different clock, and averaging it in would read as a perf bug.
        latency.record(receiveToRendered: 5_000_000_000_000)
        latency.record(captureToRendered: 5_000_000_000_000)
        // Negative means the stamps arrived out of order, which is a lost sample,
        // not a frame that travelled backwards.
        latency.record(captureToPublished: -1)
        latency.record(receiveToRendered: -1)
        latency.record(captureToRendered: -1)
        XCTAssertEqual(latency.captureToPublish.sampleCount, 0)
        XCTAssertEqual(latency.receiveToRender.sampleCount, 0)
        XCTAssertEqual(latency.captureToRender.sampleCount, 0)
        latency.record(receiveToRendered: 8_000_000)
        latency.record(captureToRendered: 10_000_000)
        XCTAssertEqual(latency.receiveToRender[50] ?? 0, 8, accuracy: 0.001)
        XCTAssertEqual(latency.captureToRender[50] ?? 0, 10, accuracy: 0.001)
    }

    func testRateMeterMeasuresTheRecentRateNotTheLifetimeAverage() {
        var meter = RateMeter(window: 2)
        var second = 0.0
        while second <= 3.0 { meter.record(second); second += 0.1 }
        let rate = meter.current(at: 3.05)
        XCTAssertEqual(rate, 10, accuracy: 1, "ten a second inside the window, not the average since the stream opened")
        XCTAssertEqual(meter.current(at: 30), 0)
    }

    // MARK: Damage that has not been published yet

    func testPendingAreaReportsWithoutConsuming() {
        let accumulator = DirtyRegionAccumulator()
        accumulator.merge([DirtyRect(x: 0, y: 0, width: 10, height: 10)], frameWidth: 100, frameHeight: 100)
        XCTAssertEqual(accumulator.pendingArea(), 100)
        XCTAssertEqual(accumulator.pendingArea(), 100, "reading the diagnostic must not empty the damage it reports")
        _ = accumulator.take()
        XCTAssertEqual(accumulator.pendingArea(), 0)
    }

    // MARK: The socket's deadlines

    func testSendTimeoutSaysThePeerStoppedReading() throws {
        let pair = try SocketPair()
        // The peer never reads, so once its buffer is full the write cannot
        // finish. 8 MB is more than any unix socket buffer, and the deadline is
        // what turns that stall into an answer.
        let payload = Data(repeating: 0x41, count: 8 * 1024 * 1024)
        let started = FrameClock.uptime()
        XCTAssertThrowsError(try pair.sender.writeAll(payload)) { error in
            XCTAssertEqual(error as? FrameSocketFailure, .sendTimeout)
        }
        let elapsed = FrameClock.uptime() - started
        XCTAssertGreaterThan(elapsed, 0.5, "a timeout that returns instantly is a full buffer, not a deadline")
        XCTAssertLessThan(elapsed, 10)
        XCTAssertTrue(pair.sender.sendIncomplete)
        XCTAssertThrowsError(try pair.sender.writeAll(Data([1])), "a half-written frame cannot be resumed")
    }

    func testSilenceBecomesStaleAndWakesTheReader() throws {
        // The peer's end stays open, so silence is the only thing this reader can
        // observe — which is exactly what a blocking read cannot see.
        let pair = try SocketPair(readerPolicy: FrameIdlePolicy(heartbeatInterval: 0.2, staleAfter: 0.4))
        XCTAssertThrowsError(try pair.reader.readExactly(16)) { error in
            XCTAssertEqual(error as? FrameSocketFailure, .stale)
        }
    }

    func testAbortWakesAParkedReaderWithoutReleasingTheDescriptor() throws {
        // A policy that will never expire, so the only way this read can end is
        // the abort — which is the point: the publisher queue stops a connection
        // whose owner is blocked inside a syscall.
        let pair = try SocketPair()
        let finished = DispatchSemaphore(value: 0)
        var outcome: FrameSocketFailure?
        DispatchQueue.global().async {
            do { _ = try pair.reader.readExactly(16) }
            catch let failure as FrameSocketFailure { outcome = failure }
            catch { outcome = .protocolError("\(error)") }
            finished.signal()
        }
        usleep(200_000)
        pair.reader.abort()
        XCTAssertEqual(finished.wait(timeout: .now() + 3), .success, "abort did not release the blocked read")
        XCTAssertEqual(outcome, .disconnected)
        XCTAssertTrue(pair.reader.isDead)
    }

    func testClosingReleasesTheDescriptorExactlyOnce() throws {
        let pair = try SocketPair()
        // The invariant behind `abort`: the descriptor belongs to its owner, an
        // abort does not release it, and the owner's `close` does so once. A
        // descriptor number handed back to the next `open` is a far worse bug
        // than a leaked one.
        pair.reader.abort()
        XCTAssertEqual(fcntl(pair.receiverFD, F_GETFD), 0)
        pair.reader.close()
        XCTAssertEqual(fcntl(pair.receiverFD, F_GETFD), -1)
        pair.reader.close()
        XCTAssertEqual(fcntl(pair.receiverFD, F_GETFD), -1)
    }

    func testFrameRoundTripsThroughTheSharedTransport() throws {
        let pair = try SocketPair()
        let header = FrameHeader(streamID: UUID(), sequence: 3, timestampNanoseconds: 77, codec: .h264, width: 320, height: 200, payloadSize: 3)
        try pair.sender.sendFrame(header: header, payload: Data([1, 2, 3]))
        let received = try pair.reader.readFrame()
        XCTAssertEqual(received.header.sequence, 3)
        XCTAssertEqual(received.header.codec, .h264)
        XCTAssertEqual(received.payload, Data([1, 2, 3]))
        try pair.sender.sendLine(FrameClientCommand(kind: .requestFull))
        XCTAssertEqual(try JSONDecoder().decode(FrameClientCommand.self, from: pair.reader.readLine()).kind, .requestFull)
    }

    func testDescriptorPassingSurvivesTheMoveToSharedTransport() throws {
        let pair = try SocketPair()
        let path = "/tmp/agentspace-frame-fd-\(UUID().uuidString)"
        let file = open(path, O_RDWR | O_CREAT | O_EXCL, 0o600)
        defer { close(file); unlink(path) }
        XCTAssertGreaterThan(file, 0)
        try pair.sender.sendFileDescriptor(file)
        let passed = try pair.reader.receiveFileDescriptor()
        defer { close(passed) }
        XCTAssertGreaterThan(passed, 0)
        XCTAssertNotEqual(passed, file, "the receiver gets its own descriptor, not a copy of the number")
        var receivedAttributes = stat()
        var originalAttributes = stat()
        XCTAssertEqual(fstat(passed, &receivedAttributes), 0)
        XCTAssertEqual(fstat(file, &originalAttributes), 0)
        XCTAssertEqual(receivedAttributes.st_ino, originalAttributes.st_ino, "both descriptors name the same object")
    }
}

/// A connected pair, each side wrapped the way production wraps it: a send
/// deadline that turns a stalled peer into an answer, and a receive timeout short
/// enough that no test can hang.
private final class SocketPair {
    let sender: FrameSocket
    let reader: FrameSocket
    /// The raw descriptor behind `reader`, for assertions about who released it.
    let receiverFD: Int32

    init(readerPolicy: FrameIdlePolicy = FrameIdlePolicy(heartbeatInterval: 60, staleAfter: 600)) throws {
        var fds: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else { throw POSIXError(.EIO) }
        sender = FrameSocket(fd: fds[0], policy: readerPolicy, sendTimeout: 1, receiveTimeout: 0.2)
        reader = FrameSocket(fd: fds[1], policy: readerPolicy, sendTimeout: 1, receiveTimeout: 0.2)
        receiverFD = fds[1]
    }
}
