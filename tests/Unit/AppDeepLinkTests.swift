import XCTest
@testable import AgentSpaceCore

final class AppDeepLinkTests: XCTestCase {

    func testURLRoundTripsThroughSpaceID() {
        let id = UUID()
        let url = AppDeepLink.url(forSpaceID: id)
        XCTAssertEqual(url.scheme, "agentspace")
        // plan(v2) §16: generated links use the `agent` host now.
        XCTAssertEqual(url.host, "agent")
        XCTAssertEqual(AppDeepLink.spaceID(in: url), id)
    }

    func testAccountURLSpellingRoundTrips() {
        let id = UUID()
        let url = AppDeepLink.url(forAccountID: id)
        XCTAssertEqual(url.absoluteString, "agentspace://agent/\(id.uuidString)")
        XCTAssertEqual(AppDeepLink.spaceID(in: url), id)
    }

    /// Links made before plan(v2) §16 keep working: the `space` host resolves
    /// to the same account.
    func testLegacySpaceHostStillResolves() {
        let id = UUID()
        let legacy = URL(string: "agentspace://space/\(id.uuidString)")!
        XCTAssertEqual(AppDeepLink.spaceID(in: legacy), id)
    }

    func testWrongSchemeIsRefused() {
        let url = AppDeepLink.url(forSpaceID: UUID())
        let other = URL(string: url.absoluteString.replacingOccurrences(of: "agentspace:", with: "otherscheme:"))!
        XCTAssertNil(AppDeepLink.spaceID(in: other))
    }

    func testWrongHostIsRefused() {
        let url = URL(string: "agentspace://notspace/\(UUID().uuidString)")!
        XCTAssertNil(AppDeepLink.spaceID(in: url))
    }

    func testMalformedPathIsRefused() {
        XCTAssertNil(AppDeepLink.spaceID(in: URL(string: "agentspace://agent/not-a-uuid")!))
        XCTAssertNil(AppDeepLink.spaceID(in: URL(string: "agentspace://agent/")!))
        XCTAssertNil(AppDeepLink.spaceID(in: URL(string: "agentspace://space/not-a-uuid")!))
        XCTAssertNil(AppDeepLink.spaceID(in: URL(string: "agentspace://space/")!))
    }

    func testURLOfOneSpaceDoesNotResolveToAnother() {
        let first = AppDeepLink.url(forSpaceID: UUID())
        let second = UUID()
        XCTAssertNotEqual(AppDeepLink.spaceID(in: first), second)
    }
}
