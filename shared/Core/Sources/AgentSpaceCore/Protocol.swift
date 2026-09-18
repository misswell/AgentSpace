import Foundation

/// Version of the on-the-wire contract between AgentSpace.app / CLI / MCP and
/// the per-Space worker. Bump on any incompatible change; both ends refuse to
/// talk across a mismatch rather than guessing (plan §21).
public let agentSpaceProtocolVersion = 1

/// Wire method names. A single source of truth so GUI, CLI and MCP cannot
/// drift into three slightly different spellings (plan §49).
public enum Method {
    public static let hello = "hello"
    public static let status = "status"
    public static let screenshot = "screenshot"
    public static let input = "input"
    public static let apps = "apps"
    public static let launch = "launch"
    public static let quit = "quit"
    public static let forceQuit = "forceQuit"
    public static let activate = "activate"
    public static let exec = "exec"
    public static let axSnapshot = "ax.snapshot"
    public static let axFrontmost = "ax.frontmost"
    public static let axWindows = "ax.windows"
    public static let axPerform = "ax.perform"
    public static let shutdown = "shutdown"

    /// Live Desktop Preview (plan §52). Pull model: `start` opens the capture
    /// stream, `frame` returns the newest frame, `stop` closes it. The GUI only
    /// runs this loop while its viewer is open, and the worker auto-stops a
    /// stream nobody pulls (see `PreviewController`).
    public static let previewStart = "preview.start"
    public static let previewFrame = "preview.frame"
    public static let previewStop = "preview.stop"

    /// Methods that must never be answered unless the caller proved it holds
    /// the Space's session secret. Everything is on this list except `hello`,
    /// which answers only non-sensitive liveness facts and is what a client
    /// uses to discover the token requirement.
    public static let tokenExempt: Set<String> = [hello]
}

// MARK: - JSON value

/// A minimal, Codable, order-preserving JSON value.
///
/// Used for `params` and `result` so the transport never has to know what any
/// particular method means. Keeps `AgentSpaceCore` free of `Any`, which in turn
/// keeps the protocol testable without a worker.
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    // MARK: Accessors

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(d)
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        default: return nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    public static func obj(_ pairs: [String: JSONValue]) -> JSONValue { .object(pairs) }
}

/// Convenience: build a JSONValue tree from literals where the ergonomics help.
extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

// MARK: - Request

/// One RPC call. `token` is the Space's 256-bit session secret (plan §20); it
/// is compared in constant time before any method other than `hello` runs.
public struct RPCRequest: Codable, Equatable, Sendable {
    public var `protocol`: Int
    public var requestId: String
    public var token: String?
    public var method: String
    public var params: JSONValue

    public init(
        protocol version: Int = agentSpaceProtocolVersion,
        requestId: String = UUID().uuidString,
        token: String? = nil,
        method: String,
        params: JSONValue = .object([:])
    ) {
        self.protocol = version
        self.requestId = requestId
        self.token = token
        self.method = method
        self.params = params
    }
}

// MARK: - Response

/// The reply envelope. Exactly one of `result` / `error` is populated.
public struct RPCResponse: Codable, Equatable, Sendable {
    public var id: String
    public var ok: Bool
    public var result: JSONValue?
    public var error: AgentSpaceError?

    public init(id: String, result: JSONValue) {
        self.id = id
        self.ok = true
        self.result = result
        self.error = nil
    }

    public init(id: String, error: AgentSpaceError) {
        self.id = id
        self.ok = false
        self.result = nil
        self.error = error
    }
}

// MARK: - Liveness envelope

/// The answer every *client* entry point gives when it cannot reach a Space.
///
/// This is the shape the plan requires in §2. It exists so the "no background
/// session" case is a first-class, typed outcome rather than an exception that
/// some caller might be tempted to catch and paper over by running on the
/// console instead. There is deliberately no variant of this value that means
/// "carry on in the user's session".
public struct UnavailableStatus: Codable, Equatable, Sendable {
    public enum Reason: String, Codable, Sendable, CaseIterable {
        case agentSessionNotReady = "AGENT_SESSION_NOT_READY"
        case workerOffline = "WORKER_OFFLINE"
        case sessionIsConsole = "SESSION_IS_CONSOLE"
        case accessibilityDenied = "ACCESSIBILITY_DENIED"
        case screenRecordingDenied = "SCREEN_RECORDING_DENIED"
        case noWindowServer = "NO_WINDOW_SERVER"
        case notFound = "SPACE_NOT_FOUND"

        /// Maps the precise worker-side code onto the envelope reason.
        public init(_ code: AgentSpaceErrorCode) {
            switch code {
            case .sessionNotReady: self = .agentSessionNotReady
            case .workerOffline: self = .workerOffline
            case .sessionIsConsole: self = .sessionIsConsole
            case .accessibilityDenied: self = .accessibilityDenied
            case .screenRecordingDenied: self = .screenRecordingDenied
            case .noWindowServer: self = .noWindowServer
            default: self = .agentSessionNotReady
            }
        }
    }

    public var status: String = "unavailable"
    public var reason: Reason
    /// Optional human context. Never contains a secret (plan §37).
    public var detail: String?

    public init(reason: Reason, detail: String? = nil) {
        self.reason = reason
        self.detail = detail
    }

    public init(error: AgentSpaceError) {
        self.reason = Reason(error.code)
        self.detail = error.message
    }
}

// MARK: - Framing

/// Wire framing constants. One JSON object per line, UTF-8, `\n` terminated.
public enum Framing {
    /// Requests larger than this are rejected `BAD_REQUEST` without buffering.
    public static let maxRequestBytes = 1 << 20
    /// Responses (screenshots are base64 here) get a larger ceiling.
    public static let maxResponseBytes = 64 << 20
    public static let newline: UInt8 = 0x0A
}

// MARK: - Codec

public enum RPCCodec {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        // Sorted keys make captured transcripts diffable, which matters when
        // the whole point of `docs/validation.md` is comparing runs.
        e.outputFormatting = [.sortedKeys]
        return e
    }

    public static func decoder() -> JSONDecoder { JSONDecoder() }

    public static func encodeLine(_ value: some Encodable) throws -> Data {
        var data = try encoder().encode(value)
        data.append(Framing.newline)
        return data
    }

    /// Parse one request line. Any failure is a `BAD_REQUEST`, never a crash:
    /// this runs on bytes that arrived over a socket a different user can see.
    public static func decodeRequest(_ data: Data) -> Result<RPCRequest, AgentSpaceError> {
        guard data.count <= Framing.maxRequestBytes else {
            return .failure(AgentSpaceError(
                code: .badRequest,
                message: "request larger than \(Framing.maxRequestBytes) bytes"))
        }
        do {
            return .success(try decoder().decode(RPCRequest.self, from: data))
        } catch {
            return .failure(AgentSpaceError(
                code: .badRequest,
                message: "malformed request: \(error.localizedDescription)"))
        }
    }

    public static func decodeResponse(_ data: Data) -> Result<RPCResponse, AgentSpaceError> {
        do {
            return .success(try decoder().decode(RPCResponse.self, from: data))
        } catch {
            return .failure(AgentSpaceError(
                code: .badRequest,
                message: "malformed response: \(error.localizedDescription)"))
        }
    }
}
