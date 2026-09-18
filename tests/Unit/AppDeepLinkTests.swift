import XCTest
@testable import AgentSpaceCore

final class AppDeepLinkTests: XCTestCase {

    func testURLRoundTripsThroughSpaceID() {
        let id = UUID()
        let url = AppDeepLink.url(forSpaceID: id)
        XCTAssertEqual(url.scheme, "agentspace")
        XCTAssertEqual(url.host, "space")
        XCTAssertEqual(AppDeepLink.spaceID(in: url), id)
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
        XCTAssertNil(AppDeepLink.spaceID(in: URL(string: "agentspace://space/not-a-uuid")!))
        XCTAssertNil(AppDeepLink.spaceID(in: URL(string: "agentspace://space/")!))
    }

    func testURLOfOneSpaceDoesNotResolveToAnother() {
        let first = AppDeepLink.url(forSpaceID: UUID())
        let second = UUID()
        XCTAssertNotEqual(AppDeepLink.spaceID(in: first), second)
    }
}
