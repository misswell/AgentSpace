import XCTest
@testable import AgentSpaceCore

final class SharedFrameLayoutTests: XCTestCase {
    func testHeaderAndPatchesRoundTrip() throws {
        let descriptor = SharedPatchDescriptor(x: 2, y: 3, width: 10, height: 11, bytesPerRow: 40, payloadOffset: 4096, payloadLength: 440)
        let header = SharedFrameSlotHeader(surfaceGeneration: 7, sequence: 9, baseSequence: 8, timestampNanoseconds: 10, width: 100, height: 80, frameKind: .deltaBGRA, patchCount: 1, payloadSize: 440)
        XCTAssertEqual(try SharedFrameSlotHeader(decoding: header.encoded()), header)
        XCTAssertEqual(try SharedPatchDescriptor(decoding: descriptor.encoded()), descriptor)
        XCTAssertNoThrow(try SharedFrameLayout.validate(header: header, patches: [descriptor], regionSize: 8192))
    }

    func testRejectsOutOfBoundsAndOverflow() {
        let header = SharedFrameSlotHeader(surfaceGeneration: 1, sequence: 1, baseSequence: 0, timestampNanoseconds: 0, width: 100, height: 100, frameKind: .deltaBGRA, patchCount: 1, payloadSize: 400)
        XCTAssertThrowsError(try SharedFrameLayout.validate(header: header, patches: [
            .init(x: 95, y: 0, width: 10, height: 1, bytesPerRow: 40, payloadOffset: 0, payloadLength: 40),
        ], regionSize: 1024))
        XCTAssertThrowsError(try SharedFrameLayout.validate(header: header, patches: [
            .init(x: 0, y: 0, width: 10, height: 10, bytesPerRow: 40, payloadOffset: UInt32.max - 10, payloadLength: 40),
        ], regionSize: 1024))
    }

    func testRejectsMalformedDescriptorBytes() {
        XCTAssertThrowsError(try SharedPatchDescriptor(decoding: Data(repeating: 0, count: 3)))
    }
}
