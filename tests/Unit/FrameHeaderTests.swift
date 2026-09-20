import XCTest
@testable import AgentSpaceCore

final class FrameHeaderTests: XCTestCase {
    func testFixedHeaderRoundTripsInNetworkByteOrder() throws {
        let streamID = UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF")!
        let header = FrameHeader(
            streamID: streamID, sequence: 99, timestampNanoseconds: 123_456_789,
            codec: .jpeg, width: 1280, height: 720, payloadSize: 456_789)
        let encoded = header.encoded()
        XCTAssertEqual(encoded.count, FrameHeader.byteCount)
        XCTAssertEqual(Array(encoded.prefix(4)), [0x41, 0x53, 0x46, 0x52])
        XCTAssertEqual(try FrameHeader(decoding: encoded), header)
    }

    func testHeaderRejectsWrongMagicAndTruncation() {
        XCTAssertThrowsError(try FrameHeader(decoding: Data(repeating: 0, count: FrameHeader.byteCount)))
        XCTAssertThrowsError(try FrameHeader(decoding: Data([0x41, 0x53])))
    }
}
