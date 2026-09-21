import XCTest
@testable import AgentSpaceCore

final class FrameHandshakeTests: XCTestCase {
    func testValidationRefusesEachWrongIdentity() {
        let space = UUID(), stream = UUID(), worker = UUID()
        let token = String(repeating: "ab", count: 32)
        let expected = FrameHandshakeExpectation(spaceID: space, streamID: stream, token: token, protocolVersion: agentSpaceProtocolVersion, peerUID: 501, workerInstanceID: worker, sessionGeneration: 2)
        let good = FrameHello(protocolVersion: agentSpaceProtocolVersion, spaceID: space, streamID: stream, token: token, clientPID: 99, capabilities: [.sharedBGRA, .h264])
        XCTAssertNoThrow(try expected.validate(good, actualPeerUID: 501))
        XCTAssertThrowsError(try expected.validate(.init(protocolVersion: 99, spaceID: space, streamID: stream, token: token, clientPID: 1, capabilities: []), actualPeerUID: 501))
        XCTAssertThrowsError(try expected.validate(.init(protocolVersion: agentSpaceProtocolVersion, spaceID: UUID(), streamID: stream, token: token, clientPID: 1, capabilities: []), actualPeerUID: 501))
        XCTAssertThrowsError(try expected.validate(.init(protocolVersion: agentSpaceProtocolVersion, spaceID: space, streamID: stream, token: "bad", clientPID: 1, capabilities: []), actualPeerUID: 501))
        XCTAssertThrowsError(try expected.validate(good, actualPeerUID: 502))
    }
}
