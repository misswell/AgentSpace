import Darwin
import XCTest
@testable import AgentSpaceCore

/// The allocator against a real kernel.
///
/// These are not string comparisons with a `shm_open` call drawn next to them for
/// atmosphere. Each one runs the syscall, and the assertions are about what the
/// syscall left behind: a descriptor that still answers `fstat`, a name that no
/// longer resolves, an `errno` that arrived before anything could overwrite it. A
/// test that only checked `name.utf8.count <= 31` would have passed on the build
/// that broke every desktop viewer, which is why the ones below are written against
/// `shm_open` itself.
final class SharedFrameRegionAllocationTests: XCTestCase {
    /// The name shape that shipped before this fix, and the refusal it produced:
    /// `shm_open failed: File name too long`.
    ///
    /// Do not include space or stream UUIDs here. Darwin POSIX shared-memory names
    /// have a much smaller limit than UNIX-domain socket paths.
    func testOverlongNameRefusesWithENAMETOOLONGAndItsLength() {
        let legacy = "/agentspace-\(UUID().uuidString)"
        XCTAssertEqual(legacy.utf8.count, 48)
        XCTAssertThrowsError(try SharedFrameRegion.allocate(regionSize: 4096, makeName: { legacy })) { error in
            guard let failure = error as? SharedFrameAllocationError else { return XCTFail("not an allocation failure: \(error)") }
            XCTAssertEqual(failure.operation, .create)
            XCTAssertEqual(failure.systemErrorCode, ENAMETOOLONG)
            XCTAssertEqual(failure.attemptedNameBytes, 48)
            // The sentence is what a log line and an older viewer's error carry, so
            // it has to name the limit as well as the errno.
            XCTAssertTrue(failure.message.contains("ENAMETOOLONG"), failure.message)
            XCTAssertTrue(failure.message.contains("48-byte name against a 31-byte limit"), failure.message)
            XCTAssertFalse(failure.message.contains(String(legacy.dropFirst("/agentspace-".count))),
                           "the random token identifies nothing and belongs in no log")
        }
    }

    /// `O_CREAT | O_EXCL` is kept precisely so two streams can never be handed the
    /// same buffer, which makes a collision a case to retry rather than to trust.
    func testCollidingNameIsRetriedWithAFreshOne() throws {
        let taken = SharedMemoryName.make()
        let held = try hold(taken)
        defer { close(held); shm_unlink(taken) }

        var attempts = 0
        let allocation = try SharedFrameRegion.allocate(regionSize: 4096, makeName: {
            attempts += 1
            return attempts == 1 ? taken : SharedMemoryName.make()
        })
        defer { close(allocation.fd); shm_unlink(allocation.name) }
        XCTAssertEqual(attempts, 2, "the collision should cost exactly one retry")
        XCTAssertTrue(sharedMemoryDescriptorIsOpen(allocation.fd), "the retry should hand back a usable descriptor")
        XCTAssertNotEqual(allocation.name, taken)
    }

    /// Every attempt colliding is not the same event as one collision, and is not
    /// reported as if it were.
    func testExhaustedCollisionsReportEEXISTAfterTheAttemptBudget() throws {
        let taken = SharedMemoryName.make()
        let held = try hold(taken)
        defer { close(held); shm_unlink(taken) }

        var attempts = 0
        XCTAssertThrowsError(try SharedFrameRegion.allocate(regionSize: 4096, makeName: {
            attempts += 1
            return taken
        }, attempts: 3)) { error in
            guard let failure = error as? SharedFrameAllocationError else { return XCTFail("not an allocation failure: \(error)") }
            XCTAssertEqual(failure.operation, .create)
            XCTAssertEqual(failure.systemErrorCode, EEXIST)
            XCTAssertEqual(failure.attemptedNameBytes, taken.utf8.count)
        }
        XCTAssertEqual(attempts, 3, "the budget is the number of names tried")
    }

    /// The rule this file exists around — a failure must not leave a named object
    /// behind — at the stage a too-large frame now fails at.
    ///
    /// Its premise moved with the layout. This used to reach `mmap` with a region
    /// sized by the caller and let the kernel refuse it (measured here: `ftruncate`
    /// accepts a 1 PiB object, `mmap` answers `ENOMEM`). Now the size comes from
    /// `SharedFrameGeometry`, which refuses anything the notice could not name
    /// before the first syscall — so the object is never created, and the namespace
    /// assertion is the same one as before while the stage that earns it is earlier.
    func testAMappingTheWireCannotNameNeverReachesTheNamespace() {
        let probe = "/as-test-mapfailure"
        shm_unlink(probe)
        let pixels = 1 << 24
        XCTAssertThrowsError(try SharedFrameRegion(width: pixels, height: pixels, surfaceGeneration: 1, makeName: { probe })) { error in
            guard let refusal = error as? AgentSpaceError else { return XCTFail("not a geometry refusal: \(error)") }
            XCTAssertEqual(refusal.code, .badRequest)
            XCTAssertEqual(refusal.message, "shared frame mapping is too large")
        }
        let reopened = shmOpen(probe, O_RDWR)
        XCTAssertLessThan(reopened.descriptor, 0, "a refused stream left an object nobody owns")
        XCTAssertEqual(reopened.code, ENOENT)
    }

    /// The success path and the two handles a region is meant to hold: a descriptor
    /// and a mapping, with the name deliberately gone.
    func testRegionWritesThroughItsMappingAfterItsNameIsGone() throws {
        let probe = "/as-test-success"
        shm_unlink(probe)
        let region = try SharedFrameRegion(width: 8, height: 4, surfaceGeneration: 7, makeName: { probe })
        let reopened = shmOpen(probe, O_RDWR)
        XCTAssertLessThan(reopened.descriptor, 0, "the name should be gone once the mapping exists")
        XCTAssertEqual(reopened.code, ENOENT)
        XCTAssertEqual(region.surfaceGeneration, 7)
        XCTAssertEqual(region.size, SharedFrameLayout.regionSize(payloadCapacity: 8 * 4 * 4))
        XCTAssertTrue(sharedMemoryDescriptorIsOpen(region.fd), "the descriptor is the only handle left, so it has to work")

        // Written through the mapping and read back through it: the buffer a viewer
        // is handed has to survive the name disappearing from under it.
        memset(region.slotPointer(0), 0x41, 4)
        memset(region.slotPointer(1), 0x53, 4)
        XCTAssertEqual(region.slotPointer(0).load(as: UInt32.self), 0x4141_4141)
        XCTAssertEqual(region.slotPointer(1).load(as: UInt32.self), 0x5353_5353)
    }

    /// Each new mapping is a new object with its own generation, and one stream's
    /// pixels never land in another's buffer.
    func testRegionsNeverShareABuffer() throws {
        let first = try SharedFrameRegion(width: 4, height: 4, surfaceGeneration: 1)
        let second = try SharedFrameRegion(width: 4, height: 4, surfaceGeneration: 2)
        XCTAssertNotEqual(first.fd, second.fd)
        XCTAssertNotEqual(first.pointer, second.pointer)
        XCTAssertEqual(second.surfaceGeneration, 2)
        memset(first.slotPointer(1), 0xFF, 4)
        XCTAssertNotEqual(second.slotPointer(1).load(as: UInt32.self), 0xFFFF_FFFF,
                          "two streams sharing one buffer is the bug this whole type exists to prevent")
    }

    /// `deinit` gives both back. Without this, every window opened and closed on a
    /// long-running worker walks the descriptor table up until the process runs out,
    /// which is a failure that arrives looking like an unrelated one.
    func testRegionClosesItsDescriptorWhenReleased() throws {
        let probe = "/as-test-release"
        shm_unlink(probe)
        var descriptor: Int32 = -1
        do {
            let region = try SharedFrameRegion(width: 4, height: 4, surfaceGeneration: 1, makeName: { probe })
            descriptor = region.fd
            XCTAssertTrue(sharedMemoryDescriptorIsOpen(descriptor))
        }
        XCTAssertFalse(sharedMemoryDescriptorIsOpen(descriptor), "the descriptor outlived the region")
    }

    /// The seam takes a name, so the tests above pass one. Production does not, and
    /// what production produces has to fit the allocator as well as the limit.
    func testProductionNamesAreAcceptedByTheAllocator() throws {
        for _ in 0..<200 {
            let allocation = try SharedFrameRegion.allocate(regionSize: SharedFrameLayout.regionSize(payloadCapacity: 64), makeName: SharedMemoryName.make)
            XCTAssertTrue(sharedMemoryDescriptorIsOpen(allocation.fd))
            XCTAssertEqual(shm_unlink(allocation.name), 0, "each name should still be there to remove")
            close(allocation.fd)
        }
    }

    /// What the viewer lays a region out by, measured on a region the real
    /// allocator made.
    ///
    /// `st_size` on the descriptor is the requested size *rounded up* (measured
    /// here: a 4 KiB request reports 16 KiB), so a reader that derived the slot
    /// layout from it would compute a second slot the writer never wrote — a
    /// corrupted picture rather than an error. This is the pairing the Desktop
    /// viewer died on once the name itself was short enough to open.
    func testARealRegionIsLaidOutByItsGeometryNotByWhatTheKernelReported() throws {
        let region = try SharedFrameRegion(width: 1, height: 1, surfaceGeneration: 1)
        var info = stat()
        XCTAssertEqual(fstat(region.fd, &info), 0)
        let objectSize = Int(info.st_size)
        XCTAssertGreaterThanOrEqual(objectSize, region.size, "the kernel never gives less than was asked for")
        XCTAssertEqual(region.geometry, try SharedFrameGeometry.make(width: 1, height: 1),
                       "the writer's layout has to be exactly what the reader derives from the same dimensions")
        guard objectSize != region.size else {
            return XCTFail("this region's size happened not to be rounded up, so it cannot show what rounding does — pick a width and height whose region is not 16 KiB aligned")
        }
        let offsetFromRoundedSize = SharedFrameLayout.slotOffset(1, payloadCapacity: objectSize / SharedFrameLayout.slotCount - SharedFrameLayout.slotMetadataSize)
        XCTAssertGreaterThan(offsetFromRoundedSize, region.geometry.slotOffset(1),
                             "a layout derived from st_size points at bytes the writer never wrote, which is the bug rather than a second opinion")
    }

    /// Create a name and keep it busy, so a later `O_EXCL` on it answers EEXIST.
    private func hold(_ name: String) throws -> Int32 {
        let attempt = shmOpen(name, O_CREAT | O_EXCL | O_RDWR)
        if attempt.descriptor < 0 { throw XCTSkip("the kernel refused \(name): errno \(attempt.code)") }
        return attempt.descriptor
    }
}
