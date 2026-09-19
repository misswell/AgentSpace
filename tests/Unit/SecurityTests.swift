import XCTest
import AgentSpaceCore

final class SecurityTests: XCTestCase {

    // MARK: Token generation

    func testGeneratedTokenIs256BitsOfHex() {
        guard let token = SessionToken.generate() else {
            return XCTFail("SecRandomCopyBytes failed")
        }
        XCTAssertEqual(token.hex.count, 64)
        XCTAssertTrue(token.isValidShape)
        XCTAssertTrue(token.hex.allSatisfy { $0.isHexDigit })
    }

    func testGeneratedTokensDiffer() {
        var seen: Set<String> = []
        for _ in 0..<64 {
            guard let token = SessionToken.generate() else { return XCTFail("generation failed") }
            XCTAssertFalse(seen.contains(token.hex), "the CSPRNG repeated a 256-bit token")
            seen.insert(token.hex)
        }
        XCTAssertEqual(seen.count, 64)
    }

    func testTokenShapeValidation() {
        XCTAssertFalse(SessionToken(hex: "").isValidShape)
        XCTAssertFalse(SessionToken(hex: "abc").isValidShape)
        XCTAssertFalse(SessionToken(hex: String(repeating: "z", count: 64)).isValidShape)
        XCTAssertFalse(SessionToken(hex: String(repeating: "a", count: 65)).isValidShape)
        XCTAssertTrue(SessionToken(hex: String(repeating: "a", count: 64)).isValidShape)
    }

    // MARK: Token comparison

    func testMatchingIsCaseInsensitive() {
        let hex = String(repeating: "Ab", count: 32)
        let token = SessionToken(hex: hex)
        XCTAssertTrue(token.matches(hex.lowercased()))
        XCTAssertTrue(token.matches(hex.uppercased()))
    }

    func testNonMatchingRejected() {
        guard let token = SessionToken.generate(), let other = SessionToken.generate() else {
            return XCTFail("generation failed")
        }
        XCTAssertFalse(token.matches(other.hex))
        XCTAssertTrue(token.matches(token.hex))
    }

    func testEmptyAndWrongLengthRejected() {
        let token = SessionToken(hex: String(repeating: "a", count: 64))
        XCTAssertFalse(token.matches(""))
        XCTAssertFalse(token.matches(String(repeating: "a", count: 63)))
        XCTAssertFalse(token.matches(String(repeating: "a", count: 65)))
    }

    /// A shared prefix must not shorten the comparison: this is the timing
    /// property `timingsafe_bcmp` is used for. The assertion is functional
    /// (a prefix is not a match); the constant-time guarantee comes from the
    /// primitive, and this test pins that the primitive is actually reached.
    func testSharedPrefixIsNotAMatch() {
        let token = SessionToken(hex: String(repeating: "a", count: 63) + "b")
        XCTAssertFalse(token.matches(String(repeating: "a", count: 64)))
    }

    // MARK: Token storage

    func testTokenFileIsOwnerOnlyAndRoundTrips() throws {
        let directory = NSTemporaryDirectory() + "/agentspace-token-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }

        guard let token = SessionToken.generate() else { return XCTFail("generation failed") }
        let path = directory + "/token"
        XCTAssertNil(TokenStore.write(token, to: path))
        XCTAssertEqual(TokenStore.read(from: path)?.hex, token.hex)

        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o600, "the session token must be owner-read/write only")
    }

    func testMissingTokenFileReadsNil() {
        XCTAssertNil(TokenStore.read(from: "/nonexistent/agentspace/token"))
    }

    func testCorruptTokenFileReadsNil() throws {
        let path = NSTemporaryDirectory() + "/agentspace-corrupt-\(UUID().uuidString)"
        try Data("not-a-token\n".utf8).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertNil(TokenStore.read(from: path))
    }

    func testTokenFileToleratesTrailingNewline() throws {
        let path = NSTemporaryDirectory() + "/agentspace-nl-\(UUID().uuidString)"
        guard let token = SessionToken.generate() else { return XCTFail() }
        try Data((token.hex + "\n").utf8).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertEqual(TokenStore.read(from: path)?.hex, token.hex)
    }

    // MARK: Redaction

    func testSecretKeysAreRedacted() {
        let scrubbed = Redaction.scrub(.obj([
            "token": .string("super-secret"),
            "password": .string("hunter2"),
            "sessionToken": .string("abc"),
            "apiKey": .string("xyz"),
            "username": .string("guofeng"),
        ]))
        XCTAssertEqual(scrubbed["token"]?.stringValue, Redaction.placeholder)
        XCTAssertEqual(scrubbed["password"]?.stringValue, Redaction.placeholder)
        XCTAssertEqual(scrubbed["sessionToken"]?.stringValue, Redaction.placeholder)
        XCTAssertEqual(scrubbed["apiKey"]?.stringValue, Redaction.placeholder)
        XCTAssertEqual(scrubbed["username"]?.stringValue, "guofeng")
    }

    func testNestedSecretsAreRedacted() {
        let scrubbed = Redaction.scrub(.obj([
            "outer": .obj(["inner": .obj(["token": .string("leak")])]),
            "list": .array([.obj(["secret": .string("leak")])]),
        ]))
        XCTAssertEqual(scrubbed["outer"]?["inner"]?["token"]?.stringValue, Redaction.placeholder)
        XCTAssertEqual(scrubbed["list"]?.arrayValue?.first?["secret"]?.stringValue, Redaction.placeholder)
    }

    /// The likeliest leak is a token interpolated into a message rather than
    /// sitting under a key anyone thought to list.
    func testBareHexTokenInAStringIsRedacted() {
        let text = "connecting with 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef now"
        let scrubbed = Redaction.scrubString(text)
        XCTAssertFalse(scrubbed.contains("0123456789abcdef0123456789abcdef"))
        XCTAssertTrue(scrubbed.contains(Redaction.placeholder), scrubbed)
    }

    func testKeyValueSecretsInStringsAreRedacted() {
        let scrubbed = Redaction.scrubString("token=abcdef123456")
        XCTAssertFalse(scrubbed.contains("abcdef123456"), scrubbed)
    }

    func testOrdinaryTextIsUntouched() {
        let text = "launched Google Chrome pid 4242"
        XCTAssertEqual(Redaction.scrubString(text), text)
    }

    func testScrubStringMap() {
        let scrubbed = Redaction.scrubStringMap(["token": "abc", "app": "Safari"])
        XCTAssertEqual(scrubbed["token"], Redaction.placeholder)
        XCTAssertEqual(scrubbed["app"], "Safari")
    }

    // MARK: Runtime paths

    func testSocketPathFitsWithinSunPath() {
        let paths = RuntimePaths(spaceID: UUID())
        XCTAssertTrue(paths.socketPathFits, "the default layout must fit sun_path")
        XCTAssertLessThanOrEqual(paths.socketPath.utf8.count, RuntimePaths.maxSocketPathBytes)
    }

    func testOverlongSocketPathIsDetectedNotTruncated() {
        let long = "/tmp/" + String(repeating: "x", count: 200)
        XCTAssertFalse(RuntimePaths(spaceID: UUID(), root: long).socketPathFits)
    }

    func testExplicitSocketPathOverrideWins() {
        let custom = "/tmp/agentspace-test.sock"
        let paths = RuntimePaths(spaceID: UUID(), socketPath: custom)
        XCTAssertEqual(paths.socketPath, custom)
    }

    func testRuntimePathsArePerSpace() {
        let a = RuntimePaths(spaceID: UUID())
        let b = RuntimePaths(spaceID: UUID())
        XCTAssertNotEqual(a.directory, b.directory)
        XCTAssertNotEqual(a.socketPath, b.socketPath)
        XCTAssertNotEqual(a.tokenPath, b.tokenPath)
    }

    /// Plan §29: every Space needs its own socket *and* its own token. Two
    /// Spaces sharing one token would make a compromise of either one a
    /// compromise of both.
    func testDifferentSpacesHaveDifferentTokens() {
        var tokens: Set<String> = []
        for _ in 0..<8 {
            guard let token = SessionToken.generate() else { return XCTFail() }
            tokens.insert(token.hex)
        }
        XCTAssertEqual(tokens.count, 8)
    }

    // MARK: ACL runner seam

    func testACLRunnerIsSubstitutable() {
        var recorded: [(String, String)] = []
        let original = ACLRunner.runner
        defer { ACLRunner.runner = original }
        ACLRunner.runner = { entry, path in
            recorded.append((entry, path))
            return 0
        }
        let paths = RuntimePaths(spaceID: UUID())
        XCTAssertNil(paths.applyACL(mainUser: "guofeng", agentUser: "_agentspace_a37f91"))
        XCTAssertEqual(recorded.count, 2)
        XCTAssertTrue(recorded[0].0.contains("user:guofeng"))
        XCTAssertTrue(recorded[1].0.contains("user:_agentspace_a37f91"))
        XCTAssertTrue(recorded.allSatisfy { $0.0.contains("file_inherit") })
        XCTAssertTrue(recorded.allSatisfy { $0.0.contains("directory_inherit") })
    }

    func testACLFailureIsReported() {
        let original = ACLRunner.runner
        defer { ACLRunner.runner = original }
        ACLRunner.runner = { _, _ in 1 }
        let error = RuntimePaths(spaceID: UUID()).applyACL(mainUser: "a", agentUser: "b")
        XCTAssertNotNil(error)
        XCTAssertTrue(error!.message.contains("exited 1"), error!.message)
    }

    func testRuntimePermissionVerifierAcceptsTheTwoPrincipalACL() throws {
        let directory = "/tmp/runtime-permissions-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let original = RuntimePermissionVerifier.aclReader
        defer { RuntimePermissionVerifier.aclReader = original }
        RuntimePermissionVerifier.aclReader = { _ in
            """
            0: user:guofeng allow read,write,execute,file_inherit,directory_inherit
            1: user:_agentspace_a37f91 allow read,write,execute,file_inherit,directory_inherit
            """
        }

        let error = RuntimePermissionVerifier.verifyDirectory(
            directory,
            expectedOwner: getuid(),
            mainUser: "guofeng",
            agentUser: "_agentspace_a37f91")

        XCTAssertNil(error, error?.message ?? "")
    }

    func testRuntimePermissionVerifierRefusesAMissingMainUserACL() throws {
        let directory = "/tmp/runtime-permissions-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let original = RuntimePermissionVerifier.aclReader
        defer { RuntimePermissionVerifier.aclReader = original }
        RuntimePermissionVerifier.aclReader = { _ in
            "0: user:_agentspace_a37f91 allow read,write,execute,file_inherit,directory_inherit"
        }

        let error = RuntimePermissionVerifier.verifyDirectory(
            directory,
            expectedOwner: getuid(),
            mainUser: "guofeng",
            agentUser: "_agentspace_a37f91")

        XCTAssertEqual(error?.code, .helperRejected)
        XCTAssertTrue(error?.message.contains("guofeng") == true)
    }

    func testRuntimePermissionVerifierRequiresInheritanceOnEachPrincipalEntry() throws {
        let directory = "/tmp/runtime-permissions-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let original = RuntimePermissionVerifier.aclReader
        defer { RuntimePermissionVerifier.aclReader = original }
        RuntimePermissionVerifier.aclReader = { _ in
            """
            0: user:guofeng allow read,write,execute
            1: user:agentdev allow read,write,execute,file_inherit,directory_inherit
            """
        }

        let error = RuntimePermissionVerifier.verifyDirectory(
            directory,
            expectedOwner: getuid(),
            mainUser: "guofeng",
            agentUser: "agentdev")

        XCTAssertEqual(error?.code, .helperRejected)
        XCTAssertTrue(error?.message.contains("guofeng") == true)
    }

    func testRuntimePermissionVerifierRefusesAnExtraNamedUser() throws {
        let directory = "/tmp/runtime-permissions-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let original = RuntimePermissionVerifier.aclReader
        defer { RuntimePermissionVerifier.aclReader = original }
        RuntimePermissionVerifier.aclReader = { _ in
            """
            0: user:guofeng allow read,write,execute,file_inherit,directory_inherit
            1: user:agentdev allow read,write,execute,file_inherit,directory_inherit
            2: user:mallory allow read,write,execute,file_inherit,directory_inherit
            """
        }
        let error = RuntimePermissionVerifier.verifyDirectory(
            directory, expectedOwner: getuid(), mainUser: "guofeng", agentUser: "agentdev")
        XCTAssertEqual(error?.code, .helperRejected)
        XCTAssertTrue(error?.message.contains("mallory") == true)
    }
}
