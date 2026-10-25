import XCTest
@testable import AgentSpaceCore

/// Live tests for the footprint half of the resources sample (§407). The
/// syscall contract was pinned by measurement on 2026-10-25: flavor 4 returns
/// 0 on success, `ri_phys_footprint` is word 9, and same-uid reads need no
/// privilege — these tests keep the live behaviour honest rather than the
/// arithmetic only.
final class ProcessFootprintTests: XCTestCase {

    func testOwnProcessHasAPositiveFootprint() {
        // Any running process — including this test runner — owns private
        // pages, so a real answer is strictly positive. A zero or nil here
        // means the offset or the flavor is wrong, exactly the failure mode
        /// the §407 measurement guarded against.
        guard let bytes = ProcessFootprint.bytes(pid: getpid()) else {
            return XCTFail("proc_pid_rusage refused the test's own pid")
        }
        XCTAssertGreaterThan(bytes, 0)
    }

    func testEmptySetIsAMeasuredZero() {
        XCTAssertEqual(ProcessFootprint.sum(pids: []), 0)
    }

    func testSumIncludesTheSamePidsIndividually() {
        let own = getpid()
        guard let individual = ProcessFootprint.bytes(pid: own),
              let summed = ProcessFootprint.sum(pids: [own]) else {
            return XCTFail("proc_pid_rusage refused the test's own pid")
        }
        XCTAssertEqual(summed, individual)
    }

    func testSumSurvivesSomePidsRefusing() {
        // A pid that no longer exists is normal table churn; the ones that do
        // answer must still be summed rather than failing the whole pass.
        let own = getpid()
        guard let ownBytes = ProcessFootprint.bytes(pid: own) else {
            return XCTFail("proc_pid_rusage refused the test's own pid")
        }
        // pid 2 is a kernel-ish pid the test uid cannot read; if some system
        // does allow it, the sum is still ≥ the own contribution, so the
        // assertion holds either way.
        let summed = ProcessFootprint.sum(pids: [2, own])
        XCTAssertNotNil(summed)
        XCTAssertGreaterThanOrEqual(summed!, ownBytes)
    }
}
