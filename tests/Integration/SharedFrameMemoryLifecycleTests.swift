import Darwin
import XCTest
@testable import AgentSpaceCore

/// One frame buffer's whole life, on this machine's kernel.
///
/// The unit tests ask the allocator about refusals. This one asks about the path
/// that has to work: `shm_open`, `ftruncate`, `mmap`, a write, a read, the name
/// removed, the mapping still live, and finally the descriptor handed across a real
/// socket — which is the only way a viewer is ever given pixels, and the step a
/// name-based design would not survive.
final class SharedFrameMemoryLifecycleTests: XCTestCase {
    func testAllocateMapReadWriteUnlinkAndRelease() throws {
        let name = SharedMemoryName.make()
        let allocation = try SharedFrameRegion.allocate(regionSize: 4096, makeName: { name })
        defer { close(allocation.fd); shm_unlink(name) }

        var info = stat()
        XCTAssertEqual(fstat(allocation.fd, &info), 0, "the descriptor has to be the handle the caller keeps")
        // Measured here: `ftruncate(4096)` leaves an `st_size` of 16384. Darwin
        // rounds a shm object up, so the size asked for is a lower bound and
        // never an equality — and it is the requested size, not `st_size`, that
        // the frame protocol maps by.
        XCTAssertGreaterThanOrEqual(Int(info.st_size), 4096, "ftruncate has to have sized it at least to")

        let mapped = mmap(nil, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, allocation.fd, 0)
        XCTAssertNotEqual(mapped, MAP_FAILED, "mmap of a sized shm object failed: errno \(errno)")
        defer { munmap(mapped!, 4096) }
        mapped!.storeBytes(of: UInt64(0x4153_4153_4153_4153), toByteOffset: 0, as: UInt64.self)
        XCTAssertEqual(mapped!.load(fromByteOffset: 0, as: UInt64.self), 0x4153_4153_4153_4153)

        // The name goes; the pixels do not. Everything the frame protocol does after
        // this point runs off a descriptor.
        XCTAssertEqual(shm_unlink(name), 0)
        XCTAssertEqual(mapped!.load(fromByteOffset: 0, as: UInt64.self), 0x4153_4153_4153_4153,
                       "the mapping must survive the name being removed")
        XCTAssertEqual(open(name, O_RDWR).code, ENOENT, "nothing may be able to reach it by name again")
    }

    /// A region the worker still holds, read through a descriptor a second party got
    /// from `SCM_RIGHTS`. Neither end names the object; the writer's name is already
    /// gone and the reader never had one.
    func testRegionReadsThroughADescriptorPassedOverASocket() throws {
        let region = try SharedFrameRegion(width: 8, height: 4, surfaceGeneration: 5)
        var pair: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair), 0, "socketpair failed: errno \(errno)")
        let writer = FrameSocket(fd: pair[0])
        let reader = FrameSocket(fd: pair[1])
        defer { writer.close(); reader.close() }

        let header = SharedFrameSlotHeader(surfaceGeneration: 5, sequence: 1, baseSequence: 0, timestampNanoseconds: 1_000,
                                           width: 8, height: 4, frameKind: .fullBGRA, patchCount: 1, payloadSize: 32)
        let slot = region.slotPointer(0)
        header.encoded().copyBytes(to: slot.assumingMemoryBound(to: UInt8.self), count: SharedFrameSlotHeader.byteCount)
        for offset in stride(from: 0, to: 32, by: 4) {
            slot.advanced(by: SharedFrameSlotHeader.byteCount + offset).storeBytes(of: UInt32(0xDEAD_0000 &+ UInt32(offset)), as: UInt32.self)
        }
        let notice = SharedFrameNotice(surfaceGeneration: 5, slotIndex: 0, frameKind: .fullBGRA, patchCount: 1, baseSequence: 0, mappingSize: UInt32(region.size))

        try writer.sendFileDescriptor(region.fd)
        try writer.sendFrame(header: FrameHeader(streamID: UUID(), sequence: 1, timestampNanoseconds: 1_000, codec: .sharedBGRA,
                                                 width: 8, height: 4, payloadSize: UInt32(SharedFrameNotice.byteCount)),
                             payload: notice.encoded())

        let passed = try reader.receiveFileDescriptor()
        defer { close(passed) }
        var info = stat()
        XCTAssertEqual(fstat(passed, &info), 0)
        XCTAssertGreaterThanOrEqual(Int(info.st_size), region.size, "the passed descriptor is the same object, at least as large")

        let frame = try reader.readFrame()
        XCTAssertEqual(try SharedFrameNotice(decoding: frame.payload), notice)

        let mapped = mmap(nil, region.size, PROT_READ, MAP_SHARED, passed, 0)
        XCTAssertNotEqual(mapped, MAP_FAILED, "mmap of the passed descriptor failed: errno \(errno)")
        defer { munmap(mapped!, region.size) }
        XCTAssertEqual(try SharedFrameSlotHeader(decoding: Data(bytes: mapped!.assumingMemoryBound(to: UInt8.self), count: SharedFrameSlotHeader.byteCount)), header)
        XCTAssertEqual(mapped!.advanced(by: SharedFrameSlotHeader.byteCount).load(as: UInt32.self), 0xDEAD_0000,
                       "the payload written past the header has to be readable at the same offset")
    }

    /// The frame wire is a fixed header and a notice that names a slot and a
    /// generation. A shared-memory name appears in neither, because the descriptor
    /// is what crosses — a name arriving from a peer would be a second,
    /// caller-controlled way to choose a buffer.
    func testTheFrameWireHasNoRoomForAName() throws {
        let header = FrameHeader(streamID: UUID(), sequence: 7, timestampNanoseconds: 9, codec: .sharedBGRA, width: 16, height: 9, payloadSize: UInt32(SharedFrameNotice.byteCount))
        let headerBytes = header.encoded()
        XCTAssertEqual(headerBytes.count, FrameHeader.byteCount, "the fixed header may not grow a name field")
        XCTAssertEqual(try FrameHeader(decoding: headerBytes), header)

        let notice = SharedFrameNotice(surfaceGeneration: 3, slotIndex: 1, frameKind: .deltaBGRA, patchCount: 4, baseSequence: 12, mappingSize: 8192)
        let noticeBytes = notice.encoded()
        XCTAssertEqual(noticeBytes.count, SharedFrameNotice.byteCount, "the notice may not grow a name field either")
        XCTAssertEqual(try SharedFrameNotice(decoding: noticeBytes), notice)

        let name = SharedMemoryName.make()
        XCTAssertNil((headerBytes + noticeBytes).firstRange(of: Data(name.utf8)), "a name reached the wire")
    }

    /// `shm_open` is marked unavailable to Swift on macOS even though the symbol is
    /// in libSystem, which is why `SharedFrameRegion` reaches for it by name. The
    /// probe has to do the same to check what the object looks like from outside.
    private func open(_ name: String, _ flags: Int32) -> (descriptor: Int32, code: Int32) {
        var code: Int32 = 0
        let descriptor = name.withCString { address -> Int32 in
            let opened = probeShmOpen(address, flags, S_IRUSR | S_IWUSR)
            code = errno
            return opened
        }
        return (descriptor, code)
    }
}

@_silgen_name("shm_open")
private func probeShmOpen(_ name: UnsafePointer<CChar>, _ flags: Int32, _ mode: mode_t) -> Int32
