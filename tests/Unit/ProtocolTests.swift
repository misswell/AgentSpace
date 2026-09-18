import XCTest
import AgentSpaceCore

final class ProtocolTests: XCTestCase {

    // MARK: Round trips

    func testRequestRoundTrip() throws {
        let request = RPCRequest(
            requestId: "abc",
            token: "deadbeef",
            method: Method.screenshot,
            params: .obj(["maxWidth": .int(1280)]))
        let data = try RPCCodec.encoder().encode(request)
        let decoded = try RPCCodec.decoder().decode(RPCRequest.self, from: data)
        XCTAssertEqual(decoded, request)
        XCTAssertEqual(decoded.protocol, agentSpaceProtocolVersion)
    }

    func testSuccessResponseShape() throws {
        let response = RPCResponse(id: "abc", result: .obj(["performed": .int(3)]))
        let data = try RPCCodec.encodeLine(response)
        XCTAssertEqual(data.last, Framing.newline, "responses must be newline terminated")

        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""ok":true"#), text)
        XCTAssertFalse(text.contains(#""error""#), text)
    }

    func testErrorResponseShape() throws {
        let response = RPCResponse(id: "abc", error: AgentSpaceError(
            code: .sessionIsConsole, message: "refused"))
        let data = try RPCCodec.encodeLine(response)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""ok":false"#), text)
        XCTAssertTrue(text.contains(#""code":"SESSION_IS_CONSOLE""#), text)
        XCTAssertTrue(text.contains(#""recoverable":true"#), text)
    }

    func testErrorResponseHasNoResultField() throws {
        let response = RPCResponse(id: "x", error: AgentSpaceError(code: .badRequest, message: "m"))
        let text = String(decoding: try RPCCodec.encodeLine(response), as: UTF8.self)
        XCTAssertNil(response.result)
        XCTAssertFalse(text.contains(#""result""#), text)
    }

    // MARK: Decoding failures

    func testMalformedRequestIsBadRequestNotACrash() {
        let result = RPCCodec.decodeRequest(Data("this is not json".utf8))
        guard case .failure(let error) = result else { return XCTFail("should fail") }
        XCTAssertEqual(error.code, .badRequest)
    }

    func testOversizedRequestRejectedBeforeBuffering() {
        var data = Data(repeating: UInt8(ascii: "a"), count: Framing.maxRequestBytes + 1)
        data.append(contentsOf: Array(#"{"method":"hello"}"#.utf8))
        guard case .failure(let error) = RPCCodec.decodeRequest(data) else {
            return XCTFail("should fail")
        }
        XCTAssertEqual(error.code, .badRequest)
        XCTAssertTrue(error.message.contains("larger than"), error.message)
    }

    func testEmptyObjectIsNotAValidRequest() {
        guard case .failure = RPCCodec.decodeRequest(Data("{}".utf8)) else {
            return XCTFail("a request must name a method")
        }
    }

    // MARK: JSONValue

    func testJSONValuePreservesIntegers() throws {
        let data = Data(#"{"x":500,"y":-12,"big":9007199254740993}"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(value["x"]?.intValue, 500)
        XCTAssertEqual(value["y"]?.intValue, -12)
        // Ints must not be coerced through Double, or large ids lose precision.
        XCTAssertEqual(value["big"]?.intValue, 9007199254740993)
    }

    func testJSONValueNestedAccess() throws {
        let data = Data(#"{"session":{"onConsole":true,"verdict":"usable"},"list":[1,2,3]}"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(value["session"]?["onConsole"]?.boolValue, true)
        XCTAssertEqual(value["session"]?["verdict"]?.stringValue, "usable")
        XCTAssertEqual(value["list"]?.arrayValue?.count, 3)
        XCTAssertNil(value["missing"])
    }

    func testJSONValueRoundTrip() throws {
        let original = JSONValue.obj([
            "int": .int(1), "double": .double(1.5), "string": .string("s"),
            "bool": .bool(true), "null": .null,
            "array": .array([.int(1), .string("two")]),
            "nested": .obj(["a": .bool(false)]),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDictionaryLiteralErgonomics() {
        let value: JSONValue = ["a": 1, "b": "two", "c": true]
        XCTAssertEqual(value["a"]?.intValue, 1)
        XCTAssertEqual(value["b"]?.stringValue, "two")
        XCTAssertEqual(value["c"]?.boolValue, true)
    }

    // MARK: Unavailable envelope

    /// Plan §2's exact required shape.
    func testUnavailableEnvelopeShape() throws {
        let envelope = UnavailableStatus(reason: .agentSessionNotReady)
        let text = String(decoding: try RPCCodec.encoder().encode(envelope), as: UTF8.self)
        XCTAssertTrue(text.contains(#""status":"unavailable""#), text)
        XCTAssertTrue(text.contains(#""reason":"AGENT_SESSION_NOT_READY""#), text)
    }

    func testUnavailableEnvelopeMapsEveryRelevantCode() {
        let table: [AgentSpaceErrorCode: UnavailableStatus.Reason] = [
            .sessionNotReady: .agentSessionNotReady,
            .workerOffline: .workerOffline,
            .sessionIsConsole: .sessionIsConsole,
            .accessibilityDenied: .accessibilityDenied,
            .screenRecordingDenied: .screenRecordingDenied,
            .noWindowServer: .noWindowServer,
        ]
        for (code, expected) in table {
            XCTAssertEqual(UnavailableStatus(error: AgentSpaceError(code: code, message: "m")).reason, expected)
        }
    }

    /// There must be no envelope value that reads as "carry on locally".
    ///
    /// The switch is exhaustive on purpose: adding a case to the enum without
    /// deciding whether it is a refusal stops this file compiling.
    func testUnavailableEnvelopeHasNoProceedVariant() {
        XCTAssertFalse(UnavailableStatus.Reason.allCases.isEmpty)
        for reason in UnavailableStatus.Reason.allCases {
            switch reason {
            case .agentSessionNotReady, .workerOffline, .sessionIsConsole,
                 .accessibilityDenied, .screenRecordingDenied, .noWindowServer, .notFound:
                // Every case is a refusal. None of them means "proceed".
                XCTAssertNotEqual(UnavailableStatus(reason: reason).status, "available")
            }
        }
    }

    // MARK: Method table

    func testTokenExemptionIsOnlyHello() {
        XCTAssertEqual(Method.tokenExempt, [Method.hello])
    }

    /// Every method the CLI and the MCP server name must exist in the worker's
    /// dispatch table. Kept as a list here so adding a method to one side and
    /// forgetting the other is a test failure.
    func testMethodNamespaceIsStable() {
        let expected: Set<String> = [
            "hello", "status", "screenshot", "input", "apps", "launch", "quit",
            "forceQuit", "activate", "exec", "ax.snapshot", "ax.frontmost",
            "ax.windows", "ax.elementAt", "ax.perform", "shutdown",
        ]
        let actual: Set<String> = [
            Method.hello, Method.status, Method.screenshot, Method.input,
            Method.apps, Method.launch, Method.quit, Method.forceQuit,
            Method.activate, Method.exec, Method.axSnapshot, Method.axFrontmost,
            Method.axWindows, Method.axElementAt, Method.axPerform, Method.shutdown,
        ]
        XCTAssertEqual(actual, expected)
    }
}
