import XCTest
@testable import AgentSpaceCore

/// The one arithmetic both ends of a frame stream are allowed to use.
///
/// The shapes below are the ones this machine's desktops actually produce, because
/// the bug these tests are written against was invisible at one size and fatal at
/// another: the writer's logical region and the kernel's rounded mapping are
/// different numbers, and every offset has to come from the first of them.
final class SharedFrameGeometryTests: XCTestCase {
    func testSizesThisProjectActuallyStreams() throws {
        for (width, height) in [(1, 1), (512, 288), (1280, 720), (1280, 800), (1920, 1080), (3024, 1964)] {
            let geometry = try SharedFrameGeometry.make(width: width, height: height)
            XCTAssertEqual(geometry.width, width)
            XCTAssertEqual(geometry.height, height)
            XCTAssertEqual(geometry.payloadCapacity, width * height * 4, "BGRA is four bytes a pixel")
            XCTAssertEqual(geometry.slotSize, SharedFrameLayout.slotMetadataSize + geometry.payloadCapacity)
            XCTAssertEqual(geometry.regionSize, geometry.slotSize * SharedFrameLayout.slotCount)
            XCTAssertLessThanOrEqual(geometry.regionSize, Int(UInt32.max), "the notice has to be able to name it")
        }
    }

    /// Slot 0 is always at zero, so it can never show a layout being wrong. Slot 1
    /// is the one that caught the bug, and it is exactly one slot past the start.
    func testSlotOffsetsAreOneSlotApart() throws {
        let geometry = try SharedFrameGeometry.make(width: 1280, height: 800)
        XCTAssertEqual(geometry.slotOffset(0), 0)
        XCTAssertEqual(geometry.slotOffset(1), geometry.slotSize)
        XCTAssertEqual(geometry.slotOffset(1) + geometry.slotSize, geometry.regionSize, "two slots fill the region and nothing else fits")
    }

    /// A region larger than the notice can name is refused here rather than
    /// wrapping on the wire, where it would arrive as a small size and be read as
    /// a mapping far too short for the frames written into it.
    func testRefusesDimensionsTheWireCannotName() {
        XCTAssertThrowsError(try SharedFrameGeometry.make(width: 65_536, height: 65_536))
        XCTAssertThrowsError(try SharedFrameGeometry.make(width: Int.max, height: 4))
        XCTAssertThrowsError(try SharedFrameGeometry.make(width: 0, height: 800), "a zero-sized surface has no pixels to lay out")
        XCTAssertThrowsError(try SharedFrameGeometry.make(width: 1280, height: -1))
    }

    /// The writer's own object reports the geometry, so the two ends cannot drift
    /// apart by each keeping a copy of the formula.
    func testTheRegionCarriesTheSameGeometryTheReaderDerives() throws {
        let region = try SharedFrameRegion(width: 1280, height: 800, surfaceGeneration: 1)
        XCTAssertEqual(region.geometry, try SharedFrameGeometry.make(width: 1280, height: 800))
        XCTAssertEqual(region.size, region.geometry.regionSize)
        XCTAssertEqual(region.payloadCapacity, region.geometry.payloadCapacity)
    }

    /// The frames this engine streams are the ones a real desktop produces, and
    /// they all have to fit the 256 MB shared-memory budget `FrameManager` enforces
    /// — a geometry that overflowed would sail past that check.
    func testAWholeRetinaDesktopFitsWithinTheWireAndTheBudget() throws {
        let geometry = try SharedFrameGeometry.make(width: 3024, height: 1964)
        XCTAssertLessThan(geometry.regionSize, 256 * 1024 * 1024 / 2)
    }
}

/// Which sentence the window is allowed to show while a stream will not come up.
///
/// The count lives in Core because the alternative is deciding it inside a SwiftUI
/// view, where no test reaches — and the difference between the two notices is a
/// promise: one says "this is being retried", the other says "retrying has not
/// worked yet, so do something else".
final class FrameStreamRecoveryTests: XCTestCase {
    func testFirstFaultsPromiseARetryAndTheThirdStopsPromisingIt() {
        var recovery = FrameStreamRecovery()
        XCTAssertEqual(recovery.notice, .none, "a stream that has not failed has nothing to say")
        XCTAssertEqual(recovery.noteMappingFault(), .resynchronising)
        XCTAssertEqual(recovery.noteMappingFault(), .resynchronising)
        XCTAssertEqual(recovery.noteMappingFault(), .unrecoverable)
        XCTAssertEqual(recovery.notice, .unrecoverable)
    }

    /// A stream that recovered must not go on reporting the trouble that fixed
    /// itself, or every later reconnect inherits an accusation.
    func testPixelsLandAndTheHistoryIsDropped() {
        var recovery = FrameStreamRecovery()
        _ = recovery.noteMappingFault()
        _ = recovery.noteMappingFault()
        recovery.noteStreaming()
        XCTAssertEqual(recovery.consecutiveMappingFaults, 0)
        XCTAssertEqual(recovery.notice, .none)
        XCTAssertEqual(recovery.noteMappingFault(), .resynchronising, "the count restarts, so a second bad stretch is news again")
    }

    /// The budget has to outlast the client's own back-off, or the window gives up
    /// before the loop has made the attempts it was going to make anyway.
    func testTheGivingUpPointIsAfterTheFirstThreeReconnectDelays() {
        let delays: [TimeInterval] = [0.5, 1, 2, 5]
        let spent = delays.prefix(FrameStreamRecovery.giveUpAfterAttempts).reduce(0, +)
        XCTAssertGreaterThanOrEqual(spent, 3, "three attempts is \(spent)s of retrying — \(FrameStreamRecovery.giveUpAfterAttempts) is not a giving-up point yet")
    }
}
