import Foundation
import XCTest
@testable import AgentSpaceCore

/// §37: an exported diagnostics bundle must be safe to hand out. The redactor
/// is the last line of defense, so it is tested property-style — feed it
/// anything secret-shaped and assert nothing recognizable survives.
final class DiagnosticsTests: XCTestCase {

    // MARK: - The redactor

    func testSessionTokensAreRedacted() {
        let token = (0..<32).map { _ in String(format: "%02x", Int.random(in: 0...255)) }.joined()
        let result = Diagnostics.redact("token file says \(token) somewhere")
        XCTAssertFalse(result.text.contains(token), "a 64-hex token must not survive: \(result.text)")
        XCTAssertTrue(result.text.contains("<redacted-token>"))
        XCTAssertEqual(result.redactions, 1)
    }

    /// The boundary case is the point: a 40-hex git commit SHA (or a short
    /// one) is *not* a token and must survive — an export that mangles every
    /// hex string is an export nobody can debug from.
    func testCommitShapesAreNotMistakenForTokens() {
        let sha = "b2bef61c0ffee0123456789abcdef0123456789a" // 40 hex
        let short = "99e4025"
        let result = Diagnostics.redact("commit \(sha) parent \(short)")
        XCTAssertTrue(result.text.contains(sha))
        XCTAssertTrue(result.text.contains(short))
        XCTAssertEqual(result.redactions, 0)
    }

    func testKeyedSecretValuesAreRedactedWhateverTheKeySpelling() {
        let input = """
        password: hunter2!
        TOKEN=eyJhbGciOi
        secret = value123
        passphrase:"with-dashes"
        """
        let result = Diagnostics.redact(input)
        for value in ["hunter2", "eyJhbGciOi", "value123", "with-dashes"] {
            XCTAssertFalse(result.text.contains(value), "value leaked: \(result.text)")
        }
        // The keys survive so the reader can still see *what* was redacted.
        XCTAssertTrue(result.text.contains("password"))
        XCTAssertTrue(result.text.contains("TOKEN"))
    }

    /// The word "token" or "password" in ordinary prose must not be mangled —
    /// only key:value shapes are touched.
    func testProseMentionsOfSecretWordsSurvive() {
        let result = Diagnostics.redact("the token file was absent; password entry points are documented")
        XCTAssertTrue(result.text.contains("the token file was absent"))
        XCTAssertEqual(result.redactions, 0)
    }

    func testInlineImagesAndBlobsAreRedacted() {
        let pixel = String(repeating: "QUFB", count: 1500) // 6000 base64 chars
        let result = Diagnostics.redact("frame: data:image/jpeg;base64,\(pixel) end")
        XCTAssertFalse(result.text.contains("QUFBQUFB"))
        XCTAssertTrue(result.text.contains("<redacted-image>"))
        XCTAssertEqual(result.redactions, 1)
    }

    /// Idempotence: running the redactor on its own output must be a no-op,
    /// or a bundle that passes through two layers would grow bogus markers.
    func testRedactionIsIdempotent() {
        let once = Diagnostics.redact("password: hunter2 \(String(repeating: "ab", count: 32))")
        let twice = Diagnostics.redact(once.text)
        XCTAssertEqual(once.text, twice.text)
        XCTAssertEqual(twice.redactions, 0)
    }

    // MARK: - The collector

    private var root: String!

    override func setUp() {
        super.setUp()
        root = "/tmp/as-diag-\(UUID().uuidString.prefix(8))"
        try? FileManager.default.createDirectory(atPath: root + "/Spaces", withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: root)
        super.tearDown()
    }

    /// The bundle must name every Space with its metadata, but contain no
    /// token *contents* — only the fact that a token file exists.
    func testCollectListsSpacesButNeverTokenContents() throws {
        let sid = UUID()
        let space: [String: Any] = [
            "id": sid.uuidString, "name": "Diag Test", "username": "_agentspace_diag01",
            "uid": 502, "state": "needsLogin", "createdAt": "2026-09-18T10:00:00Z",
            "workspace": ["kind": "none"], "sharedFolders": [Any](),
            "permissions": ["screenRecording": false, "accessibility": false],
            "autoStartWorker": true,
        ]
        try JSONSerialization.data(withJSONObject: ["spaces": [space]])
            .write(to: URL(fileURLWithPath: root + "/Spaces/index.json"))
        let runtime = RuntimePaths(spaceID: sid, root: root, socketPath: root + "/Runtime/\(sid)/worker.sock")
        try FileManager.default.createDirectory(
            atPath: (runtime.tokenPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let token = "a" .repeating(count: 64)
        try token.write(toFile: runtime.tokenPath, atomically: true, encoding: .utf8)

        let bundle = Diagnostics.collect(root: root)

        XCTAssertTrue(bundle.contains("Diag Test"))
        XCTAssertTrue(bundle.contains("_agentspace_diag01"))
        XCTAssertTrue(bundle.contains("tokenFile=present"), "existence is the signal: \(bundle)")
        XCTAssertFalse(bundle.contains(token), "the token's contents must never be collected")
        XCTAssertTrue(bundle.contains("doctor:"), "doctor output rides along")
    }
}

private extension String {
    func repeating(count: Int) -> String { String(repeating: self, count: count) }
}
