import Darwin
import XCTest
@testable import AgentSpaceCore

/// The shape of a shared-memory name, and the limit it has to fit inside.
///
/// Every assertion here that could be made against a constant is also made
/// against the kernel, because the constant is the thing under test: a
/// `darwinMaximumBytes` of 31 that Darwin disagrees with is exactly the bug that
/// took the desktop viewer down, and only a syscall can catch it.
final class SharedMemoryNameTests: XCTestCase {
    func testNameFitsTheDarwinLimit() {
        for _ in 0..<100 {
            let name = SharedMemoryName.make()
            XCTAssertLessThanOrEqual(name.utf8.count, SharedMemoryName.darwinMaximumBytes,
                                     "\(name) is \(name.utf8.count) bytes")
        }
    }

    func testNameIsASingleComponentOfHex() {
        let name = SharedMemoryName.make()
        XCTAssertTrue(name.hasPrefix("/as-"), name)
        XCTAssertEqual(name.filter { $0 == "/" }.count, 1, "a second slash makes a path, not a name: \(name)")
        let token = name.dropFirst("/as-".count)
        XCTAssertEqual(token.count, 24, name)
        XCTAssertTrue(token.allSatisfy(\.isHexDigit), "\(token) is not hex")
        XCTAssertFalse(token.contains("-"), "a UUID's own dashes are wasted bytes: \(name)")
    }

    func testNamesDoNotRepeat() {
        // 1 000 in a loop is the cheap one; 10 000 in a set is the one that would
        // notice a token built from a low-entropy source. A million would only slow
        // the build down — a 96-bit token's collision odds are not what this test is
        // measuring.
        for _ in 0..<1_000 { XCTAssertNotEqual(SharedMemoryName.make(), SharedMemoryName.make()) }
        var seen = Set<String>()
        for _ in 0..<10_000 { XCTAssertTrue(seen.insert(SharedMemoryName.make()).inserted, "a name repeated") }
        XCTAssertEqual(seen.count, 10_000)
    }

    /// The bug, kept alive on purpose.
    ///
    /// Do not include space or stream UUIDs here. Darwin POSIX shared-memory names
    /// have a much smaller limit than UNIX-domain socket paths, and the old name —
    /// `/agentspace-<UUID>` — fitted one and not the other, which is why `frame.open`
    /// answered `shm_open failed: File name too long` on every account.
    ///
    /// The assertion is the kernel's, not a string comparison: if Darwin ever allows
    /// 48 bytes, this test has to fail loudly enough that the limit gets revisited
    /// rather than quietly pass on a shorter name.
    func testOldUUIDShapedNameIsStillRefusedByTheKernel() {
        let legacy = "/agentspace-\(UUID().uuidString)"
        XCTAssertEqual(legacy.utf8.count, 48)
        XCTAssertGreaterThan(legacy.utf8.count, SharedMemoryName.darwinMaximumBytes)
        let attempt = shmOpen(legacy, O_CREAT | O_EXCL | O_RDWR)
        XCTAssertEqual(attempt.code, ENAMETOOLONG, "the kernel accepted a \(legacy.utf8.count)-byte name: \(legacy)")
        if attempt.descriptor >= 0 { close(attempt.descriptor); shm_unlink(legacy) }
    }

    /// The measured edge: 31 bytes opens, 32 does not. A limit copied from a header
    /// rather than probed is a limit that can be wrong in either direction.
    func testDarwinLimitIsWhatItSaysItIs() {
        XCTAssertEqual(SharedMemoryName.darwinMaximumBytes, 31)
        let atLimit = "/as-" + String(repeating: "a", count: SharedMemoryName.darwinMaximumBytes - 4)
        XCTAssertEqual(atLimit.utf8.count, SharedMemoryName.darwinMaximumBytes)
        let accepted = shmOpen(atLimit, O_CREAT | O_EXCL | O_RDWR)
        XCTAssertEqual(accepted.code, 0, "a \(atLimit.utf8.count)-byte name should open")
        if accepted.descriptor >= 0 { close(accepted.descriptor) }
        XCTAssertEqual(shm_unlink(atLimit), 0)

        let overLimit = atLimit + "b"
        let refused = shmOpen(overLimit, O_CREAT | O_EXCL | O_RDWR)
        XCTAssertEqual(refused.code, ENAMETOOLONG, "a \(overLimit.utf8.count)-byte name should not open")
        if refused.descriptor >= 0 { close(refused.descriptor); shm_unlink(overLimit) }
    }
}
