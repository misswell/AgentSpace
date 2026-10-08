import XCTest
import Darwin
@testable import AgentSpaceCore

final class InputDisconnectSignalTests: XCTestCase {
    func testClosedPeerReturnsDisconnectedInsteadOfSIGPIPE() throws {
        let marker = "AGENTSPACE_DISCONNECT_SIGNAL_CHILD"
        if ProcessInfo.processInfo.environment[marker] == "1" {
            // A fresh subprocess has the actual default signal disposition;
            // the test host must not ignore SIGPIPE and hide the product crash.
            signal(SIGPIPE, SIG_DFL)
            var pair: [Int32] = [-1, -1]
            XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair), 0)
            let transport = try InputSocketTransport(fd: pair[0])
            defer { transport.close() }
            Darwin.close(pair[1])
            for _ in 0..<2 {
                XCTAssertThrowsError(try transport.send(kind: .helloAck, payload: Data(), sequence: 0)) {
                    XCTAssertEqual($0 as? FrameSocketFailure, .disconnected)
                }
            }
            return
        }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        child.arguments = ["xctest", "-XCTest",
            "AgentSpaceUnitTests.InputDisconnectSignalTests/testClosedPeerReturnsDisconnectedInsteadOfSIGPIPE",
            Bundle(for: Self.self).bundleURL.path]
        var environment = ProcessInfo.processInfo.environment
        environment[marker] = "1"
        child.environment = environment
        let output = Pipe()
        child.standardOutput = output
        child.standardError = output
        try child.run()
        child.waitUntilExit()
        let transcript = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(child.terminationReason, .exit, transcript)
        XCTAssertEqual(child.terminationStatus, 0, transcript)
        XCTAssertTrue(transcript.contains("Executed 1 test"), "The child must actually run the regression: \(transcript)")
    }
}
