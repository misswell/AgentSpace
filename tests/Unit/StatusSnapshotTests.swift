import Foundation
import XCTest
@testable import AgentSpaceCore

/// Pins the on-disk contract of status.json — the §20 runtime trio's
/// third file — before any process writes it.
final class StatusSnapshotTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_760_000_000)

    func testRunningPayloadHasAllFieldsWithStableTypes() throws {
        let data = StatusSnapshot.json(
            phase: .running, pid: 4242, uid: 501,
            spaceId: UUID(uuidString: "AABBCCDD-0011-2233-4455-66778899AABB")!,
            spaceName: "dev", verdict: "background",
            at: fixedDate)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["phase"] as? String, "running")
        XCTAssertEqual(object["pid"] as? Int, 4242)
        XCTAssertEqual(object["uid"] as? Int, 501)
        XCTAssertEqual(object["spaceId"] as? String, "AABBCCDD-0011-2233-4455-66778899AABB")
        XCTAssertEqual(object["spaceName"] as? String, "dev")
        XCTAssertEqual(object["verdict"] as? String, "background")
        XCTAssertNotNil(object["writtenAt"])
    }

    func testStoppedPhaseRecordsStopped() throws {
        let data = StatusSnapshot.json(
            phase: .stopped, pid: 4242, uid: 501,
            spaceId: UUID(), spaceName: "dev", verdict: "background",
            at: fixedDate)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["phase"] as? String, "stopped")
    }

    func testTimestampIsISO8601UTC() throws {
        let data = StatusSnapshot.json(
            phase: .running, pid: 1, uid: 0,
            spaceId: UUID(), spaceName: "dev", verdict: "background",
            at: fixedDate)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let stamp = try XCTUnwrap(object["writtenAt"] as? String)
        // 1_760_000_000 is 2025-10-09T08:53:20Z — the Z suffix proves UTC.
        XCTAssertEqual(stamp, "2025-10-09T08:53:20Z")
    }

    func testKeysAreSortedSoOutputIsByteStable() {
        let space = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let first = StatusSnapshot.json(
            phase: .running, pid: 9, uid: 501, spaceId: space,
            spaceName: "dev", verdict: "background", at: fixedDate)
        let second = StatusSnapshot.json(
            phase: .running, pid: 9, uid: 501, spaceId: space,
            spaceName: "dev", verdict: "background", at: fixedDate)
        XCTAssertEqual(first, second)
        // Sorted keys: phase < pid < spaceId < spaceName < uid < verdict < writtenAt.
        let text = String(data: first, encoding: .utf8)!
        let keyOrder = ["phase", "pid", "spaceId", "spaceName", "uid", "verdict", "writtenAt"]
            .compactMap { key in text.range(of: "\"\(key)\"")?.lowerBound }
        XCTAssertEqual(keyOrder, keyOrder.sorted())
    }

    func testDifferentSpacesProduceDifferentFiles() throws {
        let a = StatusSnapshot.json(
            phase: .running, pid: 1, uid: 501,
            spaceId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            spaceName: "a", verdict: "background", at: fixedDate)
        let b = StatusSnapshot.json(
            phase: .running, pid: 1, uid: 502,
            spaceId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            spaceName: "b", verdict: "background", at: fixedDate)
        XCTAssertNotEqual(a, b)
        let objectB = try XCTUnwrap(JSONSerialization.jsonObject(with: b) as? [String: Any])
        XCTAssertEqual(objectB["spaceId"] as? String, "22222222-2222-2222-2222-222222222222")
    }
}
