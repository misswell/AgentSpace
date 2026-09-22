import Foundation
import XCTest
@testable import AgentSpaceCore

/// The back-pressure a Fusion proxy needs: travel is state, and state only has
/// to be delivered once. A click is an event and must never queue behind a
/// stack of superseded positions.
final class PointerTravelCoalescerTests: XCTestCase {
    private var sent: [Int] = []
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeCoalescer(minimumInterval: TimeInterval = 1.0 / 30.0) -> PointerTravelCoalescer<JSONValue> {
        PointerTravelCoalescer<JSONValue>(minimumInterval: minimumInterval) { [weak self] value in
            guard let index = value["index"]?.intValue else {
                XCTFail("travel payload lost its index"); return
            }
            self?.sent.append(index)
        }
    }

    private func position(_ index: Int) -> JSONValue { .object(["index": .int(index)]) }

    /// The regression: a hand waved across a proxy used to enqueue one blocking
    /// RPC per mouse-moved event, ahead of the click that ended the wave.
    func testAHundredPositionsBecomeOneRequestAndOneReplacement() {
        let coalescer = makeCoalescer()
        for index in 0..<100 { coalescer.offer(position(index), now: start) }
        XCTAssertEqual(sent, [0], "only the position offered while nothing was in flight goes out")
        XCTAssertTrue(coalescer.isInFlight)
        XCTAssertTrue(coalescer.hasPendingPosition)
        XCTAssertEqual(coalescer.outstandingCount, 2, "one in flight plus the newest, never a queue")

        coalescer.finished(now: start.addingTimeInterval(1))
        XCTAssertEqual(sent, [0, 99], "what follows the in-flight request is the latest position")
        XCTAssertFalse(coalescer.hasPendingPosition)
    }

    /// Without a completion the backlog still cannot grow: the queue is what
    /// made a slow worker expensive, not the mouse.
    func testAStalledRequestDoesNotAccumulatePositions() {
        let coalescer = makeCoalescer()
        for index in 0..<500 { coalescer.offer(position(index), now: start) }
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(coalescer.outstandingCount, 2)
    }

    /// 200 events a second across one second of waving, at the documented cap.
    func testTravelIsCappedAtTheConfiguredRate() {
        let coalescer = makeCoalescer()
        for index in 0..<200 {
            let now = start.addingTimeInterval(Double(index) * 0.005)
            coalescer.offer(position(index), now: now)
            coalescer.finished(now: now)
            coalescer.pump(now: now)
        }
        XCTAssertLessThanOrEqual(sent.count, 32, "30 Hz plus the position that started the second")
        XCTAssertGreaterThan(sent.count, 10, "rate limiting must not starve travel entirely")
        XCTAssertEqual(sent, sent.sorted(), "positions are delivered in the order they were taken")
        XCTAssertEqual(Set(sent).count, sent.count, "no position is sent twice")
    }

    /// A position that was too early to send is not lost — the next pump picks
    /// it up even though the mouse has not moved since.
    func testARateLimitedPositionStillReachesTheAgentOnTheNextPump() {
        let coalescer = makeCoalescer()
        coalescer.offer(position(0), now: start)
        coalescer.finished(now: start)
        coalescer.offer(position(1), now: start.addingTimeInterval(0.001))
        XCTAssertEqual(sent.count, 1, "too soon to send the second position")

        coalescer.pump(now: start.addingTimeInterval(0.002))
        XCTAssertEqual(sent.count, 1, "still inside the interval")

        coalescer.pump(now: start.addingTimeInterval(0.05))
        XCTAssertEqual(sent, [0, 1])
    }

    /// Travel that belongs to a window nobody is looking at any more must not be
    /// posted after that window is gone.
    func testResetDropsEverythingUnsent() {
        let coalescer = makeCoalescer()
        for index in 0..<10 { coalescer.offer(position(index), now: start) }
        coalescer.reset()
        XCTAssertFalse(coalescer.hasPendingPosition)
        XCTAssertFalse(coalescer.isInFlight)
        XCTAssertEqual(coalescer.outstandingCount, 0)

        coalescer.finished(now: start.addingTimeInterval(1))
        coalescer.pump(now: start.addingTimeInterval(2))
        XCTAssertEqual(sent, [0], "reset cancels the pending position, not the request in flight")

        // And it keeps working afterwards.
        coalescer.offer(position(42), now: start.addingTimeInterval(3))
        XCTAssertEqual(sent, [0, 42])
    }

    /// The completion of a request that was never started — e.g. a response that
    /// arrived after the proxy stopped — must not strand the coalescer.
    func testStrayCompletionDoesNotBlockLaterTravel() {
        let coalescer = makeCoalescer()
        coalescer.finished(now: start)
        coalescer.offer(position(7), now: start)
        XCTAssertEqual(sent, [7])
    }
}
