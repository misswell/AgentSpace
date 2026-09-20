import XCTest
@testable import AgentSpaceCore

/// Disk usage measurement (plan §30).
///
/// Checked against `du`, which is the number a user can reproduce. That matters
/// more than it sounds: the whole reason to report *allocated* rather than
/// *logical* size is that allocated is what Finder, `du` and the filesystem agree
/// on, and a measurement that disagreed with all three would be worse than none.
final class DiskUsageTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: "/tmp/du-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    /// `du -sk` in kilobytes, which is the unit `du` reports by default.
    private func duKilobytes(_ path: String) -> UInt64 {
        let result = WorkspacePreparer.run(["/usr/bin/du", "-sk", path])
        let first = result.output.split(separator: "\t").first ?? ""
        return UInt64(first.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    func testAnEmptyDirectoryMeasuresZero() throws {
        let measurement = DiskUsage.allocatedBytes(under: root.path)
        XCTAssertEqual(measurement.bytes, 0)
        XCTAssertFalse(measurement.truncated)
        XCTAssertEqual(measurement.files, 0)
    }

    func testANonExistentDirectoryMeasuresZeroRatherThanFailing() throws {
        // The worker samples a Space whose home may not exist yet. A throw here
        // would make the whole status call fail for a Space that is merely new.
        let measurement = DiskUsage.allocatedBytes(under: root.path + "/nope")
        XCTAssertEqual(measurement.bytes, 0)
        XCTAssertFalse(measurement.truncated)
    }

    func testMeasurementAgreesWithDU() throws {
        // One MiB of incompressible data, plus nested directories, so the walk has
        // to recurse rather than reading one level.
        var bytes = [UInt8]()
        bytes.reserveCapacity(1 << 20)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for _ in 0..<(1 << 20) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            bytes.append(UInt8(truncatingIfNeeded: seed >> 33))
        }
        try Data(bytes).write(to: root.appendingPathComponent("blob.bin"))

        let nested = root.appendingPathComponent("a/b/c")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "small".write(to: nested.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)

        let measured = DiskUsage.allocatedBytes(under: root.path)
        let expected = duKilobytes(root.path) * 1024

        // `du` counts the directories' own entries and we deliberately do not
        // (a directory's size is derived from its contents on some filesystems, so
        // adding it would double count). The two must therefore agree to within a
        // few blocks, not exactly.
        XCTAssertGreaterThan(measured.bytes, 1 << 20, "the megabyte was not counted")
        let difference = measured.bytes > expected ? measured.bytes - expected : expected - measured.bytes
        XCTAssertLessThan(difference, 64 * 1024, "measured \(measured.bytes) vs du \(expected)")
    }

    func testTheWalkStopsAtItsBudgetAndSaysSo() throws {
        // A Space's home can contain a `node_modules` with hundreds of thousands of
        // files. The walk must not become an unbounded stall, and a partial answer
        // must be labelled partial rather than presented as exact.
        for index in 0..<40 {
            try "x".write(to: root.appendingPathComponent("f\(index)"), atomically: true, encoding: .utf8)
        }

        let truncated = DiskUsage.allocatedBytes(under: root.path, budget: 10)
        XCTAssertTrue(truncated.truncated, "the budget was exceeded but the result claims to be complete")
        XCTAssertLessThan(truncated.files, 40)

        let complete = DiskUsage.allocatedBytes(under: root.path, budget: 1000)
        XCTAssertFalse(complete.truncated)
        XCTAssertEqual(complete.files, 40)
        XCTAssertGreaterThanOrEqual(complete.bytes, truncated.bytes,
                                    "a partial measurement exceeded the complete one")
    }

    func testSymlinksAreNotFollowedOutOfTheDirectory() throws {
        // If symlinks were followed, a link from one Space's home into another's —
        // or into a huge shared directory — would attribute that space's bytes to
        // the wrong Space. A loop would hang the walk outright.
        let outside = URL(fileURLWithPath: "/tmp/du-outside-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        var bytes = [UInt8](repeating: 7, count: 512 * 1024)
        try Data(bytes).write(to: outside.appendingPathComponent("big.bin"))
        bytes = []

        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link"), withDestinationURL: outside)
        // A self-referential loop, which is the shape that would hang a naive walk.
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("loop"), withDestinationURL: root)

        try "x".write(to: root.appendingPathComponent("own.txt"), atomically: true, encoding: .utf8)

        let measurement = DiskUsage.allocatedBytes(under: root.path)
        XCTAssertEqual(measurement.files, 1, "a symlink target was counted as part of this directory")
        XCTAssertLessThan(measurement.bytes, 64 * 1024, "the linked-in 512 KB was counted")
    }

    // MARK: - a metric must not spend a privacy decision

    /// Pseudo-random bytes, because APFS gives a block-less allocation to a file
    /// of zeros and the test would then be measuring compression, not the walk.
    private func writeRandomBytes(to url: URL, count: Int) throws {
        var bytes = [UInt8]()
        bytes.reserveCapacity(count)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for _ in 0..<count {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            bytes.append(UInt8(truncatingIfNeeded: seed >> 33))
        }
        try Data(bytes).write(to: url)
    }

    private func makeProtectedFixture() throws {
        let documents = root.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try writeRandomBytes(to: documents.appendingPathComponent("taxes.pdf"), count: 256 * 1024)
        try writeRandomBytes(to: root.appendingPathComponent("notes.txt"), count: 4 * 1024)
    }

    func testProtectedRootsAreLeftOutOfTheWalkAndTheNumberSaysSo() throws {
        try makeProtectedFixture()

        let skipped = DiskUsage.allocatedBytes(under: root.path, skip: ["Documents"])
        XCTAssertLessThan(skipped.bytes, 128 * 1024,
                          "Documents was entered even though it was in `skip`")
        XCTAssertEqual(skipped.files, 1)
        XCTAssertTrue(skipped.skippedProtected,
                      "a figure for part of the home was reported as the whole home")

        // The same call with the grant in place: the bytes were always there, so
        // `skip` is the only difference and the number has to move.
        let complete = DiskUsage.allocatedBytes(under: root.path, skip: [])
        XCTAssertGreaterThanOrEqual(complete.bytes, 256 * 1024)
        XCTAssertEqual(complete.files, 2)
        XCTAssertFalse(complete.skippedProtected)
    }

    func testSkippingIsRootRelativeNotByNameAnywhere() throws {
        // `~/a/Documents` is an ordinary directory the agent created; the gate is
        // on the home's own protected roots. Skipping by basename anywhere in the
        // tree would silently under-report an agent's work.
        let nested = root.appendingPathComponent("project/Documents")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try writeRandomBytes(to: nested.appendingPathComponent("draft.txt"), count: 64 * 1024)

        let measurement = DiskUsage.allocatedBytes(under: root.path, skip: ["Documents"])
        XCTAssertGreaterThanOrEqual(measurement.bytes, 64 * 1024)
        XCTAssertEqual(measurement.files, 1)
    }

    func testSkippingSomethingAbsentDoesNotFlagTheResult() throws {
        try makeProtectedFixture()
        let measurement = DiskUsage.allocatedBytes(under: root.path, skip: ["Library", "Music"])
        XCTAssertFalse(measurement.skippedProtected,
                       "an empty skip is not a reason to call the figure partial")
        XCTAssertEqual(measurement.files, 2)
    }

    func testTheBudgetStillStopsTheWalkWhenRootsAreSkipped() throws {
        try makeProtectedFixture()
        let measurement = DiskUsage.allocatedBytes(under: root.path, budget: 1, skip: ["Documents"])
        XCTAssertTrue(measurement.truncated)
    }
}
