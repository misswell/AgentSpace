import Foundation

/// One HTTP request, already parsed. The transport builds this; everything below
/// is pure and testable without a socket.
public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    /// Header lookup is case-insensitive, as HTTP requires. A caller that sends
    /// `authorization` instead of `Authorization` must not be told it sent none.
    public func header(_ name: String) -> String? {
        let lower = name.lowercased()
        return headers.first { $0.key.lowercased() == lower }?.value
    }

    /// Path with the query string split off, and percent-decoded path segments.
    public var pathSegments: [String] {
        let withoutQuery = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        return withoutQuery
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
    }

    public var queryItems: [String: String] {
        let parts = path.split(separator: "?", maxSplits: 1)
        guard parts.count == 2 else { return [:] }
        var result: [String: String] = [:]
        for pair in parts[1].split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard let key = String(kv[0]).removingPercentEncoding else { continue }
            let value = kv.count > 1 ? (String(kv[1]).removingPercentEncoding ?? "") : ""
            result[key] = value
        }
        return result
    }

    public var jsonBody: JSONValue? {
        guard !body.isEmpty else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: body)
    }
}

public struct HTTPResponse: Equatable, Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public static func json(_ value: JSONValue, status: Int = 200) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: data)
    }

    public static func png(_ data: Data) -> HTTPResponse {
        HTTPResponse(status: 200, headers: ["Content-Type": "image/png"], body: data)
    }

    /// The single error shape every failure uses. A client that has to branch on
    /// HTML-vs-JSON error pages is a client that will get it wrong.
    public static func error(
        code: AgentSpaceErrorCode,
        message: String,
        status: Int,
        requestId: String,
        recoverable: Bool? = nil
    ) -> HTTPResponse {
        .json(.obj([
            "ok": .bool(false),
            "error": .obj([
                "code": .string(code.rawValue),
                "message": .string(message),
                "recoverable": .bool(recoverable ?? APIStatusMapper.recoverable(code)),
                "requestId": .string(requestId),
            ]),
        ]), status: status)
    }
}

// MARK: - Status mapping

public enum APIStatusMapper {
    /// HTTP status for an AgentSpace error code.
    ///
    /// The mapping is the product statement "this failure is not a success":
    /// a worker that is offline is 503, never a 200 with an empty body, and a
    /// console session is 409 because the request was well formed and refused.
    public static func status(for code: AgentSpaceErrorCode) -> Int {
        switch code {
        case .unauthorized, .protocolMismatch:
            return 401
        case .badRequest, .invalidAction, .invalidCoordinate, .invalidTarget,
             .methodNotFound, .workspaceInvalid, .networkConfigRejected:
            return 400
        case .workspaceDenied, .execDenied:
            return 403
        case .appNotFound:
            return 404
        case .sessionNotReady, .sessionIsConsole, .noWindowServer, .noInputTarget,
             .inputBusyByHuman, .appNotRunning, .previewNotRunning:
            return 409
        case .workerOffline, .helperUnavailable, .helperRejected,
             .accessibilityDenied, .screenRecordingDenied:
            return 503
        case .commandTimeout, .appLaunchTimeout:
            return 504
        case .captureStreamFailed, .internalError, .workerIsRoot:
            return 500
        }
    }

    /// Whether a client may sensibly retry. This is the plan's
    /// "`recoverable`" field, and it is deliberately conservative: only
    /// conditions that can clear on their own are marked recoverable.
    public static func recoverable(_ code: AgentSpaceErrorCode) -> Bool {
        switch code {
        case .workerOffline, .sessionNotReady, .inputBusyByHuman,
             .appLaunchTimeout, .commandTimeout, .captureStreamFailed,
             .helperUnavailable, .previewNotRunning:
            return true
        default:
            return false
        }
    }
}

// MARK: - Routes

/// The endpoint list, as a closed enum. There is deliberately no way to express
/// "call method X with parameters Y": the HTTP surface names intents, and the
/// adapter below is the only thing that knows which worker method each maps to.
public enum APIRoute: Equatable, Sendable {
    case health
    case networkStatus
    case agents
    case agentStatus(id: String)
    case agentApps(id: String)
    case agentScreenshot(id: String)
    case agentInput(id: String)
    case agentLaunch(id: String)
    case agentQuit(id: String)
    case agentWindows(id: String)

    public var requiredScope: APIScope {
        switch self {
        case .health, .networkStatus, .agents, .agentStatus, .agentApps:
            return .read
        case .agentScreenshot, .agentWindows:
            return .observe
        case .agentInput, .agentLaunch, .agentQuit:
            return .control
        }
    }

    /// Match a request. `nil` means "no such endpoint" (404), which is different
    /// from "that endpoint exists but this method is wrong" (405).
    public static func match(_ request: HTTPRequest) -> Result<APIRoute, RouteError> {
        let segments = request.pathSegments
        let method = request.method.uppercased()

        func requireMethod(_ expected: String) -> RouteError? {
            method == expected ? nil : .methodNotAllowed(expected)
        }

        if segments == ["healthz"] {
            if let error = requireMethod("GET") { return .failure(error) }
            return .success(.health)
        }
        if segments == ["v1", "network", "status"] {
            if let error = requireMethod("GET") { return .failure(error) }
            return .success(.networkStatus)
        }
        if segments == ["v1", "agents"] {
            if let error = requireMethod("GET") { return .failure(error) }
            return .success(.agents)
        }
        guard segments.count == 4, segments[0] == "v1", segments[1] == "agents" else {
            return .failure(.notFound)
        }
        let id = segments[2]
        // An id is an Agent UUID. Anything else is refused here rather than
        // resolved later: the plan forbids a client naming a socket path or a
        // session token, and the cheapest way to enforce that is to accept only
        // UUIDs.
        guard UUID(uuidString: id) != nil else { return .failure(.invalidAgentID) }

        switch segments[3] {
        case "status":
            if let error = requireMethod("GET") { return .failure(error) }
            return .success(.agentStatus(id: id))
        case "apps":
            if let error = requireMethod("GET") { return .failure(error) }
            return .success(.agentApps(id: id))
        case "screenshot":
            if let error = requireMethod("POST") { return .failure(error) }
            return .success(.agentScreenshot(id: id))
        case "input":
            if let error = requireMethod("POST") { return .failure(error) }
            return .success(.agentInput(id: id))
        case "launch":
            if let error = requireMethod("POST") { return .failure(error) }
            return .success(.agentLaunch(id: id))
        case "quit":
            if let error = requireMethod("POST") { return .failure(error) }
            return .success(.agentQuit(id: id))
        case "windows":
            if let error = requireMethod("GET") { return .failure(error) }
            return .success(.agentWindows(id: id))
        default:
            return .failure(.notFound)
        }
    }

    public enum RouteError: Error, Equatable, Sendable {
        case notFound
        case methodNotAllowed(String)
        case invalidAgentID

        public var status: Int {
            switch self {
            case .notFound: return 404
            case .methodNotAllowed: return 405
            case .invalidAgentID: return 400
            }
        }

        public var message: String {
            switch self {
            case .notFound:
                return "no such endpoint"
            case .methodNotAllowed(let expected):
                return "this endpoint only accepts \(expected)"
            case .invalidAgentID:
                return "the agent id must be a UUID; worker socket paths and session tokens are not accepted"
            }
        }

        public var code: AgentSpaceErrorCode {
            switch self {
            case .methodNotAllowed: return .badRequest
            case .notFound, .invalidAgentID: return .badRequest
            }
        }
    }
}

// MARK: - Rate limiting

/// Two independent limits: per token, and per Agent. The per-Agent limit is the
/// one that protects a desktop from a runaway client; the per-token limit stops
/// one credential from spending the whole machine.
public struct RateLimitPolicy: Equatable, Sendable {
    public var perTokenPerMinute: Int
    public var perAgentPerMinute: Int
    public var maxConcurrentPerAgent: Int

    public init(perTokenPerMinute: Int = 240, perAgentPerMinute: Int = 120, maxConcurrentPerAgent: Int = 4) {
        self.perTokenPerMinute = perTokenPerMinute
        self.perAgentPerMinute = perAgentPerMinute
        self.maxConcurrentPerAgent = maxConcurrentPerAgent
    }
}

public struct TokenBucket: Equatable, Sendable {
    public private(set) var tokens: Double
    public let capacity: Double
    public let refillPerSecond: Double
    public private(set) var lastRefill: Date

    public init(capacity: Int, refillPerSecond: Double, now: Date = Date()) {
        self.tokens = Double(capacity)
        self.capacity = Double(capacity)
        self.refillPerSecond = refillPerSecond
        self.lastRefill = now
    }

    public mutating func take(_ count: Double = 1, now: Date = Date()) -> Bool {
        let elapsed = max(0, now.timeIntervalSince(lastRefill))
        tokens = min(capacity, tokens + elapsed * refillPerSecond)
        lastRefill = now
        guard tokens >= count else { return false }
        tokens -= count
        return true
    }
}

public struct RateLimiter: Sendable {
    public let policy: RateLimitPolicy
    private var tokenBuckets: [String: TokenBucket]
    private var agentBuckets: [String: TokenBucket]
    private var inFlight: [String: Int]

    public init(policy: RateLimitPolicy = RateLimitPolicy()) {
        self.policy = policy
        self.tokenBuckets = [:]
        self.agentBuckets = [:]
        self.inFlight = [:]
    }

    public enum Decision: Equatable, Sendable {
        case allow
        case rateLimited(retryAfterSeconds: Int)
        case tooManyConcurrent
    }

    public mutating func check(tokenID: String, agentID: String?, now: Date = Date()) -> Decision {
        if var bucket = tokenBuckets[tokenID] {
            guard bucket.take(now: now) else {
                let wait = Int(ceil(1.0 / max(bucket.refillPerSecond, 0.001)))
                tokenBuckets[tokenID] = bucket
                return .rateLimited(retryAfterSeconds: max(1, wait))
            }
            tokenBuckets[tokenID] = bucket
        } else {
            var bucket = TokenBucket(
                capacity: policy.perTokenPerMinute,
                refillPerSecond: Double(policy.perTokenPerMinute) / 60.0,
                now: now)
            // The request that creates the bucket spends from it too. The first
            // version returned before taking, which made every fresh token one
            // request over budget — a limit that is off by one on first use is
            // a limit that cannot be tested honestly.
            guard bucket.take(now: now) else {
                tokenBuckets[tokenID] = bucket
                return .rateLimited(retryAfterSeconds: 1)
            }
            tokenBuckets[tokenID] = bucket
        }

        guard let agentID else { return .allow }

        if var bucket = agentBuckets[agentID] {
            guard bucket.take(now: now) else {
                let wait = Int(ceil(1.0 / max(bucket.refillPerSecond, 0.001)))
                agentBuckets[agentID] = bucket
                return .rateLimited(retryAfterSeconds: max(1, wait))
            }
            agentBuckets[agentID] = bucket
        } else {
            var bucket = TokenBucket(
                capacity: policy.perAgentPerMinute,
                refillPerSecond: Double(policy.perAgentPerMinute) / 60.0,
                now: now)
            guard bucket.take(now: now) else {
                agentBuckets[agentID] = bucket
                return .rateLimited(retryAfterSeconds: 1)
            }
            agentBuckets[agentID] = bucket
        }

        let current = inFlight[agentID] ?? 0
        guard current < policy.maxConcurrentPerAgent else { return .tooManyConcurrent }
        return .allow
    }

    public mutating func begin(agentID: String) {
        inFlight[agentID, default: 0] += 1
    }

    public mutating func end(agentID: String) {
        inFlight[agentID] = max(0, (inFlight[agentID] ?? 0) - 1)
    }

    public func concurrentCount(agentID: String) -> Int { inFlight[agentID] ?? 0 }
}
