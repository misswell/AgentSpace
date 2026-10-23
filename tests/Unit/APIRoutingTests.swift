import XCTest
@testable import AgentSpaceCore

/// The HTTP surface, tested without a socket.
///
/// The security properties of this API are decided in pure code — which routes
/// exist, which scope they need, how a failure maps to a status — so they are
/// asserted here rather than discovered by a client in the field.
final class APIRoutingTests: XCTestCase {

    private func request(_ method: String, _ path: String, headers: [String: String] = [:]) -> HTTPRequest {
        HTTPRequest(method: method, path: path, headers: headers)
    }

    // MARK: - Routes

    func testEveryDocumentedEndpointResolves() {
        let id = UUID().uuidString
        let cases: [(String, String, APIRoute)] = [
            ("GET", "/healthz", .health),
            ("GET", "/v1/network/status", .networkStatus),
            ("GET", "/v1/agents", .agents),
            ("GET", "/v1/agents/\(id)/status", .agentStatus(id: id)),
            ("GET", "/v1/agents/\(id)/apps", .agentApps(id: id)),
            ("POST", "/v1/agents/\(id)/screenshot", .agentScreenshot(id: id)),
            ("POST", "/v1/agents/\(id)/input", .agentInput(id: id)),
            ("POST", "/v1/agents/\(id)/launch", .agentLaunch(id: id)),
            ("POST", "/v1/agents/\(id)/quit", .agentQuit(id: id)),
            ("GET", "/v1/agents/\(id)/windows", .agentWindows(id: id)),
        ]
        for (method, path, expected) in cases {
            XCTAssertEqual(try APIRoute.match(request(method, path)).get(), expected,
                           "\(method) \(path)")
        }
    }

    func testWrongMethodIsNotTheSameAsNoSuchEndpoint() {
        let id = UUID().uuidString
        XCTAssertEqual(APIRoute.match(request("POST", "/v1/agents")),
                       .failure(.methodNotAllowed("GET")))
        XCTAssertEqual(APIRoute.match(request("GET", "/v1/agents/\(id)/screenshot")),
                       .failure(.methodNotAllowed("POST")))
        XCTAssertEqual(APIRoute.match(request("GET", "/v1/nothing")), .failure(.notFound))
    }

    func testAgentIdMustBeAUUID() {
        // The plan forbids a client naming a socket path, a session token or a
        // worker method. Refusing anything that is not a UUID at the route layer
        // is what makes that true before any lookup happens.
        for bad in ["AgentUse", "6EA2FB6B-2B91", "socket", "token", "exec", ".."] {
            XCTAssertEqual(APIRoute.match(request("GET", "/v1/agents/\(bad)/status")),
                           .failure(.invalidAgentID), bad)
        }
        // A traversal attempt does not even reach the id check: it is not the
        // documented shape, so it is simply not an endpoint. Either refusal is
        // safe; what must never happen is a success.
        if case .success = APIRoute.match(request("GET", "/v1/agents/../../etc/passwd/status")) {
            XCTFail("a traversal path must not resolve to a route")
        }
    }

    func testQueryStringIsNotPartOfTheRoute() {
        let id = UUID().uuidString
        XCTAssertEqual(try APIRoute.match(request("GET", "/v1/agents/\(id)/status?x=1")).get(),
                       .agentStatus(id: id))
    }

    func testScopesAreOrderedFromReadOnlyToDangerous() {
        XCTAssertEqual(APIRoute.health.requiredScope, .read)
        XCTAssertEqual(APIRoute.agentApps(id: "x").requiredScope, .read)
        XCTAssertEqual(APIRoute.agentScreenshot(id: "x").requiredScope, .observe)
        XCTAssertEqual(APIRoute.agentWindows(id: "x").requiredScope, .observe)
        XCTAssertEqual(APIRoute.agentInput(id: "x").requiredScope, .control)
        XCTAssertEqual(APIRoute.agentLaunch(id: "x").requiredScope, .control)
        XCTAssertEqual(APIRoute.agentQuit(id: "x").requiredScope, .control)
    }

    // MARK: - Error mapping

    func testFailuresKeepTheirMeaningInTheStatusCode() {
        XCTAssertEqual(APIStatusMapper.status(for: .unauthorized), 401)
        XCTAssertEqual(APIStatusMapper.status(for: .badRequest), 400)
        XCTAssertEqual(APIStatusMapper.status(for: .invalidAction), 400)
        XCTAssertEqual(APIStatusMapper.status(for: .appNotFound), 404)
        XCTAssertEqual(APIStatusMapper.status(for: .sessionIsConsole), 409)
        XCTAssertEqual(APIStatusMapper.status(for: .workerOffline), 503)
        XCTAssertEqual(APIStatusMapper.status(for: .commandTimeout), 504)
        XCTAssertEqual(APIStatusMapper.status(for: .internalError), 500)
        // A denied permission is not a client mistake; it is a service that
        // cannot act right now.
        XCTAssertEqual(APIStatusMapper.status(for: .accessibilityDenied), 503)
        XCTAssertEqual(APIStatusMapper.status(for: .screenRecordingDenied), 503)
    }

    func testEveryErrorCodeHasAnHTTPStatus() {
        // Exhaustiveness is enforced by the compiler, but this also asserts the
        // mapping never produces an out-of-range code.
        for code in AgentSpaceErrorCode.allCases {
            let status = APIStatusMapper.status(for: code)
            XCTAssertTrue((400...599).contains(status), "\(code) mapped to \(status)")
        }
    }

    func testRecoverabilityIsConservative() {
        XCTAssertTrue(APIStatusMapper.recoverable(.workerOffline))
        XCTAssertTrue(APIStatusMapper.recoverable(.sessionNotReady))
        XCTAssertTrue(APIStatusMapper.recoverable(.commandTimeout))
        XCTAssertFalse(APIStatusMapper.recoverable(.sessionIsConsole))
        XCTAssertFalse(APIStatusMapper.recoverable(.invalidAction))
        XCTAssertFalse(APIStatusMapper.recoverable(.unauthorized))
    }

    func testErrorBodyHasTheDocumentedShape() throws {
        let response = HTTPResponse.error(
            code: .sessionIsConsole, message: "refused", status: 409, requestId: "req-1")
        let json = try JSONDecoder().decode(JSONValue.self, from: response.body)
        XCTAssertEqual(json["ok"]?.boolValue, false)
        XCTAssertEqual(json["error"]?["code"]?.stringValue, "SESSION_IS_CONSOLE")
        XCTAssertEqual(json["error"]?["message"]?.stringValue, "refused")
        XCTAssertEqual(json["error"]?["recoverable"]?.boolValue, false)
        XCTAssertEqual(json["error"]?["requestId"]?.stringValue, "req-1")
    }

    // MARK: - Tokens

    func testTokenDigestIsNotTheSecretAndIsStable() {
        let secret = "abcdef0123456789"
        let digest = APITokenStore.digest(of: secret)
        XCTAssertEqual(digest.count, 64)
        XCTAssertNotEqual(digest, secret)
        XCTAssertEqual(digest, APITokenStore.digest(of: secret))
        // Known SHA-256 of the empty string, so a broken hash is caught rather
        // than silently producing 64 hex characters of nonsense.
        XCTAssertEqual(APITokenStore.digest(of: ""),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(APITokenStore.digest(of: "abc"),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testScopesExpandDownwardsOnly() {
        XCTAssertEqual(APIScope.expand([.control]), [.read, .observe, .control])
        XCTAssertEqual(APIScope.expand([.exec]), [.read, .observe, .control, .exec])
        XCTAssertEqual(APIScope.expand([.read]), [.read])
        XCTAssertEqual(APIScope.expand([.observe]), [.read, .observe])
    }

    func testTokenLifecycleCreateAuthenticateRotateRevoke() throws {
        let root = NSTemporaryDirectory() + "/agentspace-api-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        let paths = VirtualNetworkPaths(root: root)

        let (record, secret) = try APITokenStore.create(
            name: "ci", scopes: [.observe], paths: paths)
        XCTAssertEqual(secret.count > 40, true)
        XCTAssertEqual(record.digest, APITokenStore.digest(of: secret))
        XCTAssertFalse(FileManager.default.contents(atPath: paths.tokenPath)
            .flatMap { String(data: $0, encoding: .utf8) }?
            .contains(secret) ?? false,
            "the secret must never be written to disk")

        let attributes = try FileManager.default.attributesOfItem(atPath: paths.tokenPath)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        XCTAssertEqual(APITokenStore.authenticate(secret: secret, paths: paths)?.id, record.id)
        XCTAssertNil(APITokenStore.authenticate(secret: "wrong", paths: paths))

        let rotated = try XCTUnwrap(try APITokenStore.rotate(id: record.id, paths: paths))
        XCTAssertNotEqual(rotated.secret, secret)
        XCTAssertNil(APITokenStore.authenticate(secret: secret, paths: paths),
                     "the old secret must stop working after a rotation")
        XCTAssertNotNil(APITokenStore.authenticate(secret: rotated.secret, paths: paths))
        XCTAssertEqual(Set(rotated.record.scopes), [.observe])

        _ = try APITokenStore.revoke(id: rotated.record.id, paths: paths)
        XCTAssertNil(APITokenStore.authenticate(secret: rotated.secret, paths: paths))
    }

    func testTokenScopesGateRoutes() throws {
        let root = NSTemporaryDirectory() + "/agentspace-api-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        let paths = VirtualNetworkPaths(root: root)
        let (record, _) = try APITokenStore.create(name: "reader", scopes: [.read], paths: paths)
        XCTAssertTrue(record.allows(.read))
        XCTAssertFalse(record.allows(.observe))
        XCTAssertFalse(record.allows(.control))
        XCTAssertFalse(record.allows(.exec))
    }

    func testTokenNamesAndScopesAreRequired() {
        let root = NSTemporaryDirectory() + "/agentspace-api-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        let paths = VirtualNetworkPaths(root: root)
        XCTAssertThrowsError(try APITokenStore.create(name: "  ", scopes: [.read], paths: paths))
        XCTAssertThrowsError(try APITokenStore.create(name: "x", scopes: [], paths: paths))
    }

    // MARK: - Bearer header

    func testBearerParsingIsCaseInsensitiveAndStrict() {
        let server = APIServer(configuration: .init(
            policy: .loopback(port: 8787), service: APIAgentService()))
        XCTAssertEqual(server.bearerToken(from: "Bearer abc"), "abc")
        XCTAssertEqual(server.bearerToken(from: "bearer abc"), "abc")
        XCTAssertEqual(server.bearerToken(from: "BEARER abc"), "abc")
        XCTAssertNil(server.bearerToken(from: "Basic abc"))
        XCTAssertNil(server.bearerToken(from: "Bearer"))
        XCTAssertNil(server.bearerToken(from: "Bearer   "))
    }

    func testHeaderLookupIgnoresCase() {
        let request = HTTPRequest(method: "GET", path: "/healthz",
                                  headers: ["authorization": "Bearer x"])
        XCTAssertEqual(request.header("Authorization"), "Bearer x")
        XCTAssertEqual(request.header("AUTHORIZATION"), "Bearer x")
    }

    // MARK: - Rate limiting

    func testTokenRateLimitRefills() {
        var limiter = RateLimiter(policy: RateLimitPolicy(
            perTokenPerMinute: 2, perAgentPerMinute: 100, maxConcurrentPerAgent: 4))
        let start = Date()
        XCTAssertEqual(limiter.check(tokenID: "t", agentID: nil, now: start), .allow)
        XCTAssertEqual(limiter.check(tokenID: "t", agentID: nil, now: start), .allow)
        if case .rateLimited = limiter.check(tokenID: "t", agentID: nil, now: start) {} else {
            XCTFail("a third request within the budget must be limited")
        }
        // Two per minute is one every 30 seconds; a minute later the budget is back.
        XCTAssertEqual(limiter.check(tokenID: "t", agentID: nil,
                                     now: start.addingTimeInterval(61)), .allow)
    }

    func testPerAgentLimitIsSeparateFromTheTokenLimit() {
        var limiter = RateLimiter(policy: RateLimitPolicy(
            perTokenPerMinute: 1000, perAgentPerMinute: 1, maxConcurrentPerAgent: 4))
        let start = Date()
        XCTAssertEqual(limiter.check(tokenID: "t", agentID: "a", now: start), .allow)
        if case .rateLimited = limiter.check(tokenID: "t", agentID: "a", now: start) {} else {
            XCTFail("the per-agent budget must bind even when the token has room")
        }
        XCTAssertEqual(limiter.check(tokenID: "t", agentID: "b", now: start), .allow,
                       "one busy agent must not starve another")
    }

    func testConcurrencyIsTrackedPerAgent() {
        var limiter = RateLimiter(policy: RateLimitPolicy(
            perTokenPerMinute: 1000, perAgentPerMinute: 1000, maxConcurrentPerAgent: 2))
        limiter.begin(agentID: "a")
        limiter.begin(agentID: "a")
        XCTAssertEqual(limiter.check(tokenID: "t", agentID: "a"), .tooManyConcurrent)
        limiter.end(agentID: "a")
        XCTAssertEqual(limiter.check(tokenID: "t", agentID: "a"), .allow)
        XCTAssertEqual(limiter.concurrentCount(agentID: "a"), 1)
    }

    // MARK: - Bind policy

    func testBindAddressesAreNeverWildcards() {
        XCTAssertEqual(APIListenPolicy.loopback(port: 8787).host, "127.0.0.1")
        XCTAssertEqual(APIListenPolicy.virtualNetwork(IPv4Address("100.64.0.10")!, port: 8787).host,
                       "100.64.0.10")
        XCTAssertFalse(APIListenPolicy.isValidBindAddress("0.0.0.0"))
        XCTAssertFalse(APIListenPolicy.isValidBindAddress("8.8.8.8"))
        XCTAssertTrue(APIListenPolicy.isValidBindAddress("127.0.0.1"))
        XCTAssertTrue(APIListenPolicy.isValidBindAddress("100.64.0.10"))
        XCTAssertTrue(APIListenPolicy.isValidBindAddress("192.168.1.10"))
    }

    func testVirtualAddressListenerRefusesWhenTheAddressIsMissing() {
        let server = APIServer(configuration: .init(
            policy: .virtualNetwork(IPv4Address("100.64.0.10")!, port: 8787),
            service: APIAgentService(),
            isBindAddressAvailable: { _ in false }))
        XCTAssertThrowsError(try server.start()) { error in
            XCTAssertTrue("\(error)".contains("100.64.0.10"))
        }
    }
}

/// Parsing and serialising, against the exact bytes a client sends.
final class HTTPMessageTests: XCTestCase {

    func testParsesACompleteRequest() throws {
        let raw = """
        POST /v1/agents/6EA2FB6B-2B91-4BEE-B7D0-7E76CA28C9A1/input HTTP/1.1\r
        Host: 100.64.0.10:8787\r
        Authorization: Bearer secret\r
        Content-Type: application/json\r
        Content-Length: 12\r
        \r
        {"a": "b"}  
        """
        // The body is exactly 12 bytes, which the parser must insist on.
        let data = Data(raw.utf8)
        guard case .complete(let request) = HTTPRequestParser.parse(data, maxBodyBytes: 1024) else {
            return XCTFail("did not parse")
        }
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/agents/6EA2FB6B-2B91-4BEE-B7D0-7E76CA28C9A1/input")
        XCTAssertEqual(request.header("authorization"), "Bearer secret")
        XCTAssertEqual(String(data: request.body, encoding: .utf8), #"{"a": "b"}  "#)
        XCTAssertEqual(request.body.count, 12)
    }

    func testIncompleteRequestAsksForMoreData() {
        let raw = "POST /v1/agents HTTP/1.1\r\nHost: x\r\nContent-Length: 50\r\n\r\n{\"a\":1}"
        XCTAssertEqual(HTTPRequestParser.parse(Data(raw.utf8), maxBodyBytes: 1024), .needMoreData)
        XCTAssertEqual(HTTPRequestParser.parse(Data("GET /healthz HTTP/1.1\r\n".utf8),
                                              maxBodyBytes: 1024), .needMoreData)
    }

    func testChunkedBodiesAreRefused() {
        let raw = "POST /v1/agents HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n"
        guard case .invalid(let reason) = HTTPRequestParser.parse(Data(raw.utf8), maxBodyBytes: 1024) else {
            return XCTFail("chunked must be refused rather than guessed at")
        }
        XCTAssertTrue(reason.contains("chunked"))
    }

    func testBodyLargerThanTheLimitIsRefusedBeforeItIsBuffered() {
        let raw = "POST /v1/agents HTTP/1.1\r\nHost: x\r\nContent-Length: 999999\r\n\r\n"
        guard case .invalid = HTTPRequestParser.parse(Data(raw.utf8), maxBodyBytes: 1024) else {
            return XCTFail("an oversized body must be refused")
        }
    }

    func testBodyDisagreeingWithContentLengthIsRefused() {
        let raw = "POST /v1/agents HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\n\r\n{\"a\":1}"
        guard case .invalid(let reason) = HTTPRequestParser.parse(Data(raw.utf8), maxBodyBytes: 1024) else {
            return XCTFail("a body longer than its declared length must be refused")
        }
        XCTAssertTrue(reason.contains("Content-Length"))
    }

    func testResponseCarriesLengthAndConnectionClose() throws {
        let body = #"{"ok":true}"#
        let response = HTTPResponse(status: 200, body: Data(body.utf8))
        let text = String(data: HTTPResponseSerializer.serialize(response), encoding: .utf8) ?? ""
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(text.lowercased().contains("content-length: \(body.utf8.count)"),
                      "Content-Length must describe the bytes actually written")
        XCTAssertTrue(text.lowercased().contains("connection: close"))
        XCTAssertTrue(text.hasSuffix(body), "the body follows the blank line unchanged")
    }

    func testErrorStatusReasonsAreSpelledOut() {
        XCTAssertEqual(HTTPResponseSerializer.reason(for: 429), "Too Many Requests")
        XCTAssertEqual(HTTPResponseSerializer.reason(for: 503), "Service Unavailable")
        XCTAssertEqual(HTTPResponseSerializer.reason(for: 409), "Conflict")
    }
}
