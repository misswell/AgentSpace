import XCTest
@testable import AgentSpaceCore

/// Decoding rules for `ResourceUsage`'s footprint field (§407): a payload from
/// a worker that predates the field must decode with `nil` — "did not look" —
/// rather than zero, and the GUI's fallback for an old worker depends on it.
final class ResourceUsageTests: XCTestCase {

    private func encode(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    func testPayloadWithoutFootprintDecodesNil() throws {
        let json = try encode([
            "cpuPercent": 1.5, "memoryBytes": 1_048_576, "processCount": 3,
            "diskBytes": 0, "diskMeasured": false,
            "diskTruncated": false, "diskExcludesProtected": false,
        ])
        let usage = try JSONDecoder().decode(ResourceUsage.self, from: json)
        XCTAssertNil(usage.memoryFootprintBytes)
        XCTAssertNil(usage.memoryFootprintDisplay)
        XCTAssertEqual(usage.memoryBytes, 1_048_576)
    }

    func testPayloadWithFootprintDecodes() throws {
        let json = try encode([
            "cpuPercent": 1.5, "memoryBytes": 1_048_576, "processCount": 3,
            "memoryFootprintBytes": 524_288,
            "diskBytes": 0, "diskMeasured": false,
            "diskTruncated": false, "diskExcludesProtected": false,
        ])
        let usage = try JSONDecoder().decode(ResourceUsage.self, from: json)
        XCTAssertEqual(usage.memoryFootprintBytes, 524_288)
        XCTAssertNotNil(usage.memoryFootprintDisplay)
    }

    func testRoundTripKeepsFootprint() throws {
        let usage = ResourceUsage(
            cpuPercent: 2, memoryBytes: 10, processCount: 2,
            memoryFootprintBytes: 4_096)
        let data = try JSONEncoder().encode(usage)
        let decoded = try JSONDecoder().decode(ResourceUsage.self, from: data)
        XCTAssertEqual(decoded.memoryFootprintBytes, 4_096)
    }
}
