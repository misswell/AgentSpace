import XCTest
@testable import AgentSpaceCore

/// Direct tests for the ps-output parsing behind §30's resource card — the
/// contract previously noted as an untested limitation (§127). Lines mirror
/// what `/bin/ps -axo uid=,pid=,rss=,pcpu=` actually emits: the pid column
/// arrived with the footprint pass (§407), which walks the same snapshot one
/// process per syscall.
final class ResourcesParsingTests: XCTestCase {

    func testAccumulatesOneUidAcrossManyProcesses() {
        let output = """
        501 100 102400 8.4
        501 200 204800 1.6
        501 300 512 0.0
        """
        let t = ResourcesParsing.accumulate(output, uid: 501)
        XCTAssertEqual(t.processCount, 3)
        XCTAssertEqual(t.memoryBytes, (102_400 + 204_800 + 512) * 1024)
        XCTAssertEqual(t.cpuPercent, 10.0, accuracy: 0.0001)
        XCTAssertEqual(t.pids, [100, 200, 300])
    }

    func testIgnoresOtherUids() {
        let output = """
        501 100 102400 8.4
        502 900 999999 99.0
        0 1 4096 0.2
        """
        let t = ResourcesParsing.accumulate(output, uid: 501)
        XCTAssertEqual(t.processCount, 1)
        XCTAssertEqual(t.memoryBytes, 102_400 * 1024)
        XCTAssertEqual(t.cpuPercent, 8.4, accuracy: 0.0001)
        // Only the matching uid's pid enters the footprint walk.
        XCTAssertEqual(t.pids, [100])
    }

    func testSkipsMalformedLinesWithoutDying() {
        let output = """
        not-a-uid 100 1024 1.0
        501 100 102400
        501 200 notanumber 2.0
        501 notapid 102400 8.4
        501 300 102400 8.4
        """
        let t = ResourcesParsing.accumulate(output, uid: 501)
        // Only the fully-parseable 501 line counts, and its pid is the one kept.
        XCTAssertEqual(t.processCount, 1)
        XCTAssertEqual(t.memoryBytes, 102_400 * 1024)
        XCTAssertEqual(t.cpuPercent, 8.4, accuracy: 0.0001)
        XCTAssertEqual(t.pids, [300])
    }

    func testEmptyAndHeaderOnlyOutputYieldZeroes() {
        XCTAssertEqual(ResourcesParsing.accumulate("", uid: 501), ResourcesParsing.Totals())
        XCTAssertEqual(
            ResourcesParsing.accumulate("UID   PID   RSS  %CPU", uid: 501),
            ResourcesParsing.Totals())
    }

    func testHundredPercentPerCoreIsSummedNotCapped() {
        // §170: CPU honestly exceeds 100% on multicore; the sum is not clamped.
        let output = """
        501 100 1024 160.0
        """
        XCTAssertEqual(ResourcesParsing.accumulate(output, uid: 501).cpuPercent, 160.0, accuracy: 0.0001)
    }

    func testPidCountStaysConsistentWithProcessCount() {
        // The footprint pass sums one syscall per pid, so a parse that let the
        // two counts drift would silently measure the wrong set.
        let output = """
        501 11 1024 1.0
        501 12 2048 2.0
        502 13 4096 4.0
        501 14 4096 8.0
        """
        let t = ResourcesParsing.accumulate(output, uid: 501)
        XCTAssertEqual(t.pids.count, t.processCount)
        XCTAssertEqual(t.pids, [11, 12, 14])
    }
}
