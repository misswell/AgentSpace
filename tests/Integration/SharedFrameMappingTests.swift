import Darwin
import XCTest
@testable import AgentSpaceCore

/// The viewer's half of the frame protocol, run against this machine's kernel.
///
/// Everything here goes through a real `shm_open`/`ftruncate`/`mmap` region and a
/// real `SCM_RIGHTS` hand-off, because the two facts that decide whether a desktop
/// appears are properties of the kernel rather than of the code: a shared memory
/// object is rounded *up*, and the descriptor that arrives through a socket is the
/// only evidence the viewer ever gets about which buffer it is reading. A test that
/// mocked either one would pass on the bug.
final class SharedFrameMappingTests: XCTestCase {
    /// Writes one full-frame baseline into `slot` of `region`, the way the worker
    /// does: header, then descriptors, then pixels at the offsets the *logical*
    /// geometry says — which is the thing being checked from the other side.
    private func writeBaseline(into region: SharedFrameRegion, slot: Int, sequence: UInt64,
                               width: Int, height: Int, fill: UInt32) -> (SharedFrameNotice, FrameHeader) {
        let geometry = region.geometry
        let payloadOffset = geometry.slotOffset(slot) + SharedFrameLayout.slotMetadataSize
        let length = geometry.payloadCapacity
        let pixels = region.slotPointer(slot).advanced(by: SharedFrameLayout.slotMetadataSize)
        for index in 0..<(width * height) { pixels.advanced(by: index * 4).storeBytes(of: fill &+ UInt32(index), as: UInt32.self) }
        let header = SharedFrameSlotHeader(surfaceGeneration: region.surfaceGeneration, sequence: sequence, baseSequence: 0,
                                           timestampNanoseconds: 1_000, width: UInt32(width), height: UInt32(height),
                                           frameKind: .fullBGRA, patchCount: 1, payloadSize: UInt32(length))
        header.encoded().copyBytes(to: region.slotPointer(slot).assumingMemoryBound(to: UInt8.self), count: SharedFrameSlotHeader.byteCount)
        let descriptor = SharedPatchDescriptor(x: 0, y: 0, width: UInt32(width), height: UInt32(height), bytesPerRow: UInt32(width * 4),
                                              payloadOffset: UInt32(payloadOffset), payloadLength: UInt32(length))
        descriptor.encoded().copyBytes(to: region.slotPointer(slot).advanced(by: SharedFrameSlotHeader.byteCount).assumingMemoryBound(to: UInt8.self),
                                       count: SharedPatchDescriptor.byteCount)
        let notice = SharedFrameNotice(surfaceGeneration: region.surfaceGeneration, slotIndex: UInt16(slot), frameKind: .fullBGRA,
                                       patchCount: 1, baseSequence: 0, mappingSize: UInt32(geometry.regionSize))
        let transport = FrameHeader(streamID: UUID(), sequence: sequence, timestampNanoseconds: 1_000, codec: .sharedBGRA,
                                    width: UInt32(width), height: UInt32(height), payloadSize: UInt32(SharedFrameNotice.byteCount))
        return (notice, transport)
    }

    /// The descriptor a viewer is handed by `SCM_RIGHTS`, mapped the way the app
    /// maps it. The fd is deliberately not closed here: `SharedFrameMapping` owns it
    /// from the moment the constructor takes it, which is the production rule.
    private func mappedRegion(_ region: SharedFrameRegion) throws -> (SharedFrameMapping, Int) {
        var pair: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair), 0, "socketpair failed: errno \(errno)")
        let writer = FrameSocket(fd: pair[0])
        let reader = FrameSocket(fd: pair[1])
        defer { writer.close(); reader.close() }
        try writer.sendFileDescriptor(region.fd)
        let passed = try reader.receiveFileDescriptor()
        var info = stat()
        XCTAssertEqual(fstat(passed, &info), 0)
        return (try SharedFrameMapping(fd: passed), Int(info.st_size))
    }

    /// Root cause one, on a real object: `fstat` says more than the protocol does,
    /// and a stream still has to work.
    ///
    /// This is the pairing that killed every Desktop frame once `shm_open` was fixed
    /// — the viewer required the two numbers to be equal, and the kernel had no
    /// intention of making them so.
    func testAPageRoundedRegionStillDecodesByItsLogicalLayout() throws {
        let region = try SharedFrameRegion(width: 1, height: 1, surfaceGeneration: 7)
        let (mapping, objectSize) = try mappedRegion(region)
        let geometry = region.geometry
        XCTAssertGreaterThanOrEqual(objectSize, geometry.regionSize, "the kernel never gives less than was asked for")
        XCTAssertEqual(mapping.mappedCapacity, objectSize, "what the mapping may read is what the object actually is")
        guard objectSize > geometry.regionSize else {
            return XCTFail("a \(geometry.regionSize)-byte region was not rounded up on this kernel, so this test can no longer show the two sizes disagree")
        }

        let (notice, transport) = writeBaseline(into: region, slot: 0, sequence: 1, width: 1, height: 1, fill: 0xDEAD_0000)
        let (slot, patches) = try mapping.frame(notice: notice, header: transport)
        XCTAssertEqual(slot.sequence, 1)
        XCTAssertEqual(patches.count, 1)
        let pixel = mapping.pointer.advanced(by: Int(patches[0].payloadOffset)).load(as: UInt32.self)
        XCTAssertEqual(pixel, 0xDEAD_0000, "the patch has to name the bytes that were written")
    }

    /// Slot 0 sits at offset zero in every layout, wrong or right, so a stream that
    /// only ever used it could carry this bug forever. Slot 1 is one `slotSize` past
    /// the start of the *logical* region; a viewer that computed the layout from the
    /// rounded object would look 8 KiB away, where the writer never wrote.
    func testTheSecondSlotIsFoundAtItsLogicalOffsetAndNotOneKernelRoundingAway() throws {
        let region = try SharedFrameRegion(width: 8, height: 4, surfaceGeneration: 3)
        let (mapping, objectSize) = try mappedRegion(region)
        let geometry = region.geometry
        let offsetFromRoundedSize = SharedFrameLayout.slotOffset(1, payloadCapacity: objectSize / SharedFrameLayout.slotCount - SharedFrameLayout.slotMetadataSize)
        XCTAssertGreaterThan(offsetFromRoundedSize, geometry.slotOffset(1), "the two layouts have to disagree here for this test to mean anything")

        let (notice, transport) = writeBaseline(into: region, slot: 1, sequence: 12, width: 8, height: 4, fill: 0xFEED_0000)
        XCTAssertEqual(notice.slotIndex, 1)
        // Reading slot 1 at the rounded offset would decode zeroed bytes, so a wrong
        // layout cannot slip through here as a picture: the header's magic is the
        // first thing the reader checks, and the pixel comparison is the second.
        let (slot, patches) = try mapping.frame(notice: notice, header: transport)
        XCTAssertEqual(slot.surfaceGeneration, 3)
        XCTAssertEqual(slot.frameKind, .fullBGRA)
        XCTAssertEqual(Int(patches[0].payloadOffset), geometry.slotOffset(1) + SharedFrameLayout.slotMetadataSize)
        XCTAssertEqual(mapping.pointer.advanced(by: Int(patches[0].payloadOffset)).load(as: UInt32.self), 0xFEED_0000,
                       "slot 1 has to be read where the writer put it")
    }

    /// The guard is still a guard: a notice whose logical size does not match the
    /// frame's own dimensions is two ends laying the buffer out differently, and
    /// reading on would be a picture assembled from the wrong offsets. `mappingSize`
    /// is never the kernel's number, so the rounded size is refused too — that is the
    /// false answer this guard exists to keep from ever being tried.
    func testRejectsANoticeSizedFromTheKernelRoundingOrByOneByte() throws {
        let region = try SharedFrameRegion(width: 8, height: 4, surfaceGeneration: 5)
        let (mapping, objectSize) = try mappedRegion(region)
        let (notice, transport) = writeBaseline(into: region, slot: 0, sequence: 1, width: 8, height: 4, fill: 1)
        XCTAssertNoThrow(try mapping.frame(notice: notice, header: transport))

        var rounded = notice
        rounded.mappingSize = UInt32(objectSize)
        XCTAssertThrowsError(try mapping.frame(notice: rounded, header: transport)) { error in
            XCTAssertEqual((error as? SharedFrameMappingFault)?.kind, .logicalSizeMismatch)
        }
        var skewed = notice
        skewed.mappingSize = notice.mappingSize + 1
        XCTAssertThrowsError(try mapping.frame(notice: skewed, header: transport)) { error in
            XCTAssertEqual((error as? SharedFrameMappingFault)?.kind, .logicalSizeMismatch)
        }
    }

    /// A descriptor smaller than the layout it is being asked to hold — a stale or
    /// wrong fd — must be refused before anything reads past the mapping.
    func testRejectsAMappingSmallerThanTheLayoutItIsAskedToRead() throws {
        let region = try SharedFrameRegion(width: 8, height: 4, surfaceGeneration: 1)
        let (mapping, objectSize) = try mappedRegion(region)
        let larger = try SharedFrameGeometry.make(width: 2000, height: 2000)
        XCTAssertGreaterThan(larger.regionSize, objectSize, "the premise: this frame does not fit this mapping")
        let notice = SharedFrameNotice(surfaceGeneration: 1, slotIndex: 0, frameKind: .fullBGRA, patchCount: 1,
                                       baseSequence: 0, mappingSize: UInt32(larger.regionSize))
        let transport = FrameHeader(streamID: UUID(), sequence: 4, timestampNanoseconds: 1, codec: .sharedBGRA,
                                    width: 2000, height: 2000, payloadSize: UInt32(SharedFrameNotice.byteCount))
        XCTAssertThrowsError(try mapping.frame(notice: notice, header: transport)) { error in
            let fault = error as? SharedFrameMappingFault
            XCTAssertEqual(fault?.kind, .capacityTooSmall)
            XCTAssertEqual(fault?.mappedCapacity, objectSize)
            XCTAssertEqual(fault?.logicalRegionSize, larger.regionSize)
        }
    }

    /// A slot whose header names a different frame than the transport pointed at is
    /// the "metadata changed while reading" case, and the dimensions belong to it:
    /// the geometry every offset below is derived from is the header's opinion about
    /// the frame size, so the buffer has to agree with it.
    func testRejectsASlotWrittenForAnotherSurfaceSize() throws {
        let region = try SharedFrameRegion(width: 8, height: 4, surfaceGeneration: 1)
        let (mapping, _) = try mappedRegion(region)
        let (notice, _) = writeBaseline(into: region, slot: 0, sequence: 1, width: 8, height: 4, fill: 1)
        let otherSize = FrameHeader(streamID: UUID(), sequence: 1, timestampNanoseconds: 1, codec: .sharedBGRA,
                                    width: 16, height: 8, payloadSize: UInt32(SharedFrameNotice.byteCount))
        var forOtherSize = notice
        forOtherSize.mappingSize = UInt32(try SharedFrameGeometry.make(width: 16, height: 8).regionSize)
        XCTAssertThrowsError(try mapping.frame(notice: forOtherSize, header: otherSize)) { error in
            XCTAssertEqual((error as? SharedFrameMappingFault)?.kind, .metadataMismatch)
        }
    }

    /// Root cause two, from the side the viewer can prove: a notice describing a
    /// *second* region must never decode through the first connection's mapping.
    ///
    /// The worker now refuses to swap a region under a live connection, so this
    /// should only ever be reachable from a broken or hostile peer — which is
    /// exactly why it is checked here instead of trusted. The generation is new, the
    /// size is new, and the fd is the old one: the answer is a fault, not pixels.
    func testANoticeFromANewerRegionNeverReadsThroughTheOlderMapping() throws {
        let oldRegion = try SharedFrameRegion(width: 8, height: 4, surfaceGeneration: 1)
        let (mapping, _) = try mappedRegion(oldRegion)
        let (oldNotice, oldTransport) = writeBaseline(into: oldRegion, slot: 0, sequence: 1, width: 8, height: 4, fill: 1)
        XCTAssertEqual(try mapping.frame(notice: oldNotice, header: oldTransport).0.surfaceGeneration, 1)

        let replacement = try SharedFrameRegion(width: 16, height: 8, surfaceGeneration: 2)
        let notice = SharedFrameNotice(surfaceGeneration: replacement.surfaceGeneration, slotIndex: 0, frameKind: .fullBGRA,
                                       patchCount: 1, baseSequence: 0, mappingSize: UInt32(replacement.size))
        let transport = FrameHeader(streamID: UUID(), sequence: 1, timestampNanoseconds: 1, codec: .sharedBGRA,
                                    width: UInt32(16), height: UInt32(8), payloadSize: UInt32(SharedFrameNotice.byteCount))
        XCTAssertThrowsError(try mapping.frame(notice: notice, header: transport)) { error in
            XCTAssertEqual((error as? SharedFrameMappingFault)?.kind, .metadataMismatch,
                           "the old buffer still holds generation 1's header, so this is caught as stale metadata rather than drawn as a picture")
        }
    }

    /// The line a stream that will not come up leaves in the log. Sizes and ids the
    /// operator can compare; never the shared memory name, which is a random token
    /// that identifies nothing while its length names the bug.
    func testTheFaultLineCarriesTheNumbersAndNotTheName() throws {
        let geometry = try SharedFrameGeometry.make(width: 1280, height: 800)
        let fault = SharedFrameMappingFault(kind: .capacityTooSmall, width: 1280, height: 800,
                                            logicalRegionSize: geometry.regionSize, noticeMappingSize: geometry.regionSize,
                                            mappedCapacity: 8_208_384, slot: 1, generation: 2, sequence: 128)
        let line = fault.logLine
        for fragment in ["capacityTooSmall", "width=1280", "height=800", "logical=\(geometry.regionSize)",
                         "capacity=8208384", "slot=1", "generation=2", "sequence=128"] {
            XCTAssertTrue(line.contains(fragment), "\(line) is missing \(fragment)")
        }
        XCTAssertFalse(line.contains("as_"), "a shared memory name reached the log")
    }
}
