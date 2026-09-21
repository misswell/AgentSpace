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

    /// The reader's half of a fact this engine learned from a real desktop: the
    /// size of the object it was handed is the writer's size *rounded up* by the
    /// kernel, so the layout can only be recovered from the number the writer
    /// put in the notice.
    func testPayloadCapacityIsTheExactInverseOfRegionSize() {
        for capacity in [0, 1, 4096, 1_112_960, 3024 * 1964 * 4] {
            XCTAssertEqual(SharedFrameLayout.payloadCapacity(forRegionSize: SharedFrameLayout.regionSize(payloadCapacity: capacity)), capacity)
        }
    }

    func testRejectsASizeThatIsNotTwoIdenticalSlots() {
        XCTAssertNil(SharedFrameLayout.payloadCapacity(forRegionSize: SharedFrameLayout.regionSize(payloadCapacity: 0) + 1), "an odd region cannot split into two equal slots")
        XCTAssertNil(SharedFrameLayout.payloadCapacity(forRegionSize: 0))
        XCTAssertNil(SharedFrameLayout.payloadCapacity(forRegionSize: 4), "two slots' worth of metadata does not fit, so this is not a region")
    }
}
