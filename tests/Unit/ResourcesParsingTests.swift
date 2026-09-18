import XCTest
@testable import AgentSpaceCore

/// Direct tests for the ps-output parsing behind §30's resource card — the
/// contract previously noted as an untested limitation (§127). Lines mirror
/// what `/bin/ps -axo uid=,rss=,pcpu=` actually emits.
final class ResourcesParsingTests: XCTestCase {

    func testAccumulatesOneUidAcrossManyProcesses() {
        let output = """
        501 102400 8.4
        501 204800 1.6
        501 512 0.0
        """
        let t = ResourcesParsing.accumulate(output, uid: 501)
        XCTAssertEqual(t.processCount, 3)
        XCTAssertEqual(t.memoryBytes, (102_400 + 204_800 + 512) * 1024)
        XCTAssertEqual(t.cpuPercent, 10.0, accuracy: 0.0001)
    }

    func testIgnoresOtherUids() {
        let output = """
        501 102400 8.4
        502 999999 99.0
        0 4096 0.2
        """
        let t = ResourcesParsing.accumulate(output, uid: 501)
        XCTAssertEqual(t.processCount, 1)
        XCTAssertEqual(t.memoryBytes, 102_400 * 1024)
        XCTAssertEqual(t.cpuPercent, 8.4, accuracy: 0.0001)
    }

    func testSkipsMalformedLinesWithoutDying() {
        let output = """
        not-a-uid 1024 1.0
        501 102400
        501 notanumber 2.0
        501 102400 8.4
        """
        let t = ResourcesParsing.accumulate(output, uid: 501)
        // Only the fully-parseable 501 line counts.
        XCTAssertEqual(t.processCount, 1)
        XCTAssertEqual(t.memoryBytes, 102_400 * 1024)
        XCTAssertEqual(t.cpuPercent, 8.4, accuracy: 0.0001)
    }

    func testEmptyAndHeaderOnlyOutputYieldZeroes() {
        XCTAssertEqual(ResourcesParsing.accumulate("", uid: 501), ResourcesParsing.Totals())
        XCTAssertEqual(
            ResourcesParsing.accumulate("UID   RSS  %CPU", uid: 501),
            ResourcesParsing.Totals())
    }

    func testHundredPercentPerCoreIsSummedNotCapped() {
        // §170: CPU honestly exceeds 100% on multicore; the sum is not clamped.
        let output = """
        501 1024 160.0
        """
        XCTAssertEqual(ResourcesParsing.accumulate(output, uid: 501).cpuPercent, 160.0, accuracy: 0.0001)
    }
}
