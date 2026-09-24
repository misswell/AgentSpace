import XCTest
@testable import AgentSpaceCore

final class InputChannelWorkQueuesTests: XCTestCase {
    func testAQuietReaderDoesNotStopAClickFromBeingWritten() {
        let queues = InputChannelWorkQueues(label: "input-channel-test")
        let reading = expectation(description: "reader is waiting for a reply")
        let sent = expectation(description: "click reaches the writer")
        let releaseReader = DispatchSemaphore(value: 0)
        defer { releaseReader.signal() }

        queues.read {
            reading.fulfill()
            _ = releaseReader.wait(timeout: .now() + 2)
        }
        wait(for: [reading], timeout: 1)
        queues.write { sent.fulfill() }
        wait(for: [sent], timeout: 0.5)
    }
}
