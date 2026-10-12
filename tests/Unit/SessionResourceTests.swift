import XCTest
import AgentSpaceCore

final class SessionResourceTests: XCTestCase {
    func testAbsolutePathsStayLiteral() throws {
        let path = "/tmp/notes $(touch nope) 中文.txt"
        let url = try SessionResource.url(for: path)
        XCTAssertTrue(url.isFileURL)
        XCTAssertEqual(url.path, path)
    }

    func testWebAndSettingsResources() throws {
        XCTAssertEqual(try SessionResource.url(for: "https://example.com/a?q=hello%20world").host, "example.com")
        XCTAssertEqual(try SessionResource.url(for: "x-apple.systempreferences:com.apple.preference.sound").scheme,
                       "x-apple.systempreferences")
        XCTAssertEqual(try SessionResource.url(for: "file:///tmp/test.txt").path, "/tmp/test.txt")
    }

    func testMalformedOrExecutableResourcesAreRefused() {
        for reference in ["", "relative.txt", "javascript:alert(1)", "data:text/html,x",
                          "https:///", "https://user:password@example.com", "file://remote/path",
                          "https://example.com\n", "/tmp/a\0b"] {
            XCTAssertThrowsError(try SessionResource.url(for: reference), reference) { error in
                XCTAssertEqual((error as? AgentSpaceError)?.code, .badRequest)
            }
        }
    }

    func testTextLimitCountsUTF8BytesAndAcceptsEmptyText() throws {
        try SessionResource.validateText("")
        try SessionResource.validateText(String(repeating: "a", count: SessionResource.maxTextBytes))
        XCTAssertThrowsError(try SessionResource.validateText(String(repeating: "a", count: SessionResource.maxTextBytes + 1)))
        XCTAssertThrowsError(try SessionResource.validateText(String(repeating: "中", count: SessionResource.maxTextBytes / 3 + 1)))
    }
}
