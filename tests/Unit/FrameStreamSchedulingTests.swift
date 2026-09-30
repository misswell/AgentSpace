import XCTest
import AgentSpaceCore

final class FrameStreamSchedulingTests: XCTestCase {
    func testHiddenModeNeverEmbedsCursorEvenWithoutShapeChannel() {
        for active in [false, true] {
            XCTAssertFalse(MouseCaptureMode.takeoverHidden.embedsCursor(cursorChannelActive: active))
            XCTAssertFalse(MouseCaptureMode.takeoverHidden.hidesLocalCursor)
        }
        for mode in [MouseCaptureMode.takeover, .clickToCapture] {
            XCTAssertTrue(mode.embedsCursor(cursorChannelActive: false))
            XCTAssertFalse(mode.embedsCursor(cursorChannelActive: true))
        }
    }
    func testCursorAndFPSCommandsExecuteWhileReaderIsBlocked() {
        let scheduling = FrameStreamScheduling(label: "test.frame-stream")
        let reading = DispatchSemaphore(value: 0)
        let disconnect = DispatchSemaphore(value: 0)
        let cursor = DispatchSemaphore(value: 0)
        let fps = DispatchSemaphore(value: 0)
        scheduling.reader.async {
            reading.signal()
            disconnect.wait()
        }
        defer { disconnect.signal() }
        XCTAssertEqual(reading.wait(timeout: .now() + 1), .success)
        scheduling.control.async { cursor.signal() }
        scheduling.control.async { fps.signal() }
        XCTAssertEqual(cursor.wait(timeout: .now() + 1), .success,
                       "The cursor switch must reach the worker while frames are streaming")
        XCTAssertEqual(fps.wait(timeout: .now() + 1), .success,
                       "Live FPS updates must not wait for the stream to disconnect")
    }
}
