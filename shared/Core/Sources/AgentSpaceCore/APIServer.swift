import Foundation
import CFNetwork
import Network

#if canImport(Darwin)
import Darwin
#endif

/// The HTTP listener.
///
/// Built on `Network.framework` (connection handling, TLS) and `CFHTTPMessage`
/// (request parsing and response serialisation), both of which ship with macOS.
/// The product's own code never parses HTTP: a hand-written parser is where
/// request smuggling and header-injection bugs live, and neither belongs in a
/// component that can drive a desktop.
///
/// Binding rules, enforced here rather than by the caller:
/// - the listen address is a single explicit IPv4 address, never `0.0.0.0`;
/// - a remote API only listens on the virtual address, and refuses to start
///   when that address is not assigned to an interface;
/// - a loopback listener is always `127.0.0.1`, never a wildcard.
public struct APIListenPolicy: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Reachable only from this Mac. Always 127.0.0.1.
        case loopback(port: Int)
        /// Reachable from the virtual network only.
        case virtualNetwork(address: IPv4Address, port: Int)
    }

    public let kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }

    public static func loopback(port: Int = VirtualNetworkValidator.defaultPort) -> APIListenPolicy {
        APIListenPolicy(kind: .loopback(port: port))
    }

    public static func virtualNetwork(_ address: IPv4Address, port: Int) -> APIListenPolicy {
        APIListenPolicy(kind: .virtualNetwork(address: address, port: port))
    }

    public var port: Int {
        switch kind {
        case .loopback(let port): return port
        case .virtualNetwork(_, let port): return port
        }
    }

    public var host: String {
        switch kind {
        case .loopback: return "127.0.0.1"
        case .virtualNetwork(let address, _): return address.description
        }
    }

    /// A wildcard bind is refused by construction: there is no case for it. This
    /// function exists so a caller reading a stored value cannot smuggle one in.
    public static func isValidBindAddress(_ text: String) -> Bool {
        guard let address = IPv4Address(text) else { return false }
        return address.isLoopback || address.isPrivate || address.isSharedAddressSpace
    }
}

/// One HTTP server. `start()` binds and begins accepting; `stop()` closes.
public final class APIServer: @unchecked Sendable {
    public struct Configuration: Sendable {
        public var policy: APIListenPolicy
        public var service: APIAgentService
        public var rateLimit: RateLimitPolicy
        public var tokenPaths: VirtualNetworkPaths
        public var maxRequestBytes: Int
        public var maxResponseBytes: Int
        public var networkStatus: @Sendable () -> JSONValue
        /// Refuse to bind until this answers true. Used for the virtual-address
        /// case: the API must not come up on a physical interface by accident
        /// while the tunnel is down.
        public var isBindAddressAvailable: @Sendable (String) -> Bool

        public init(
            policy: APIListenPolicy,
            service: APIAgentService,
            rateLimit: RateLimitPolicy = RateLimitPolicy(),
            tokenPaths: VirtualNetworkPaths = VirtualNetworkPaths(),
            maxRequestBytes: Int = 1 << 20,
            maxResponseBytes: Int = 16 << 20,
            networkStatus: @escaping @Sendable () -> JSONValue = { .obj(["connected": .bool(false)]) },
            isBindAddressAvailable: @escaping @Sendable (String) -> Bool = { _ in true }
        ) {
            self.policy = policy
            self.service = service
            self.rateLimit = rateLimit
            self.tokenPaths = tokenPaths
            self.maxRequestBytes = maxRequestBytes
            self.maxResponseBytes = maxResponseBytes
            self.networkStatus = networkStatus
            self.isBindAddressAvailable = isBindAddressAvailable
        }
    }

    private let configuration: Configuration
    private let queue = DispatchQueue(label: "com.agentspace.api.server")
    private var listener: NWListener?
    private var limiter: RateLimiter
    private let limiterQueue = DispatchQueue(label: "com.agentspace.api.limiter")
    private var started = false

    public init(configuration: Configuration) {
        self.configuration = configuration
        self.limiter = RateLimiter(policy: configuration.rateLimit)
    }

    public enum StartError: Error, CustomStringConvertible {
        case bindAddressUnavailable(String)
        case invalidPort(Int)
        case listenerFailed(String)

        public var description: String {
            switch self {
            case .bindAddressUnavailable(let host):
                return "\(host) is not assigned to any interface on this Mac, so the API cannot listen on it. The virtual network is probably down."
            case .invalidPort(let port):
                return "port \(port) is outside 1–65535"
            case .listenerFailed(let reason):
                return "the HTTP listener could not start: \(reason)"
            }
        }
    }

    /// The port the listener actually bound. Meaningful after `start()`; a
    /// policy of 0 asks the kernel for an ephemeral port, which is what tests
    /// and a second instance should use rather than probing for a free one and
    /// racing everything else on the machine for it.
    public private(set) var boundPort: Int = 0

    public func start() throws {
        // 0 means "any free port" and is allowed only for loopback: a virtual
        // address must keep the port a person configured, because that port is
        // what a client was told to call.
        let port = configuration.policy.port
        if case .virtualNetwork = configuration.policy.kind {
            guard (1...65_535).contains(port) else { throw StartError.invalidPort(port) }
        } else {
            guard (0...65_535).contains(port) else { throw StartError.invalidPort(port) }
        }
        let host = configuration.policy.host
        guard APIListenPolicy.isValidBindAddress(host) else {
            throw StartError.bindAddressUnavailable(host)
        }
        if case .virtualNetwork = configuration.policy.kind {
            guard configuration.isBindAddressAvailable(host) else {
                throw StartError.bindAddressUnavailable(host)
            }
        }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(port))!)
        // No reuse-any: a second API must fail loudly rather than share a port
        // with an instance that is already serving.
        parameters.allowLocalEndpointReuse = false
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw StartError.listenerFailed("\(error)")
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
        started = true
        // `NWListener.port` is only populated once the listener is running, so
        // wait one turn of the queue. A failure leaves `boundPort` at 0, which
        // callers treat as "not bound".
        let semaphore = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { semaphore.signal() }
            if case .failed = state { semaphore.signal() }
        }
        _ = semaphore.wait(timeout: .now() + 5)
        boundPort = Int(listener.port?.rawValue ?? 0)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        started = false
    }

    public var isRunning: Bool { started }

    // MARK: Connections

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            if let error {
                _ = error
                connection.cancel()
                return
            }
            var accumulated = buffer
            if let chunk { accumulated.append(chunk) }

            guard accumulated.count <= self.configuration.maxRequestBytes else {
                self.respond(connection, self.tooLarge())
                return
            }

            switch HTTPRequestParser.parse(accumulated, maxBodyBytes: self.configuration.maxRequestBytes) {
            case .needMoreData:
                if isComplete {
                    connection.cancel()
                } else {
                    self.receive(connection, buffer: accumulated)
                }
            case .invalid(let reason):
                self.respond(connection, .error(
                    code: .badRequest, message: reason, status: 400,
                    requestId: UUID().uuidString, recoverable: false))
            case .complete(let request):
                self.respond(connection, self.handle(request))
            }
        }
    }

    private func tooLarge() -> HTTPResponse {
        .error(code: .badRequest,
               message: "request larger than \(configuration.maxRequestBytes) bytes",
               status: 413, requestId: UUID().uuidString, recoverable: false)
    }

    private func respond(_ connection: NWConnection, _ response: HTTPResponse) {
        let data = HTTPResponseSerializer.serialize(response)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: Dispatch

    /// The whole request pipeline, in the order that matters: authenticate
    /// before anything else, then rate-limit, then route, then act.
    public func handle(_ request: HTTPRequest) -> HTTPResponse {
        let requestId = UUID().uuidString

        let route: APIRoute
        switch APIRoute.match(request) {
        case .success(let matched):
            route = matched
        case .failure(let error):
            return .error(code: error.code, message: error.message, status: error.status,
                          requestId: requestId, recoverable: false)
        }

        // `/healthz` is the one unauthenticated endpoint: a load balancer or a
        // person checking whether the service is up should not need a secret to
        // learn that it is. It reveals nothing about any agent.
        if route == .health {
            return configuration.service.execute(
                route: route, request: request, requestId: requestId,
                networkStatus: configuration.networkStatus)
        }

        guard let authorization = request.header("Authorization"),
              let secret = bearerToken(from: authorization) else {
            return .error(code: .unauthorized,
                          message: "missing bearer token",
                          status: 401, requestId: requestId, recoverable: false)
        }
        guard let record = APITokenStore.authenticate(secret: secret, paths: configuration.tokenPaths) else {
            return .error(code: .unauthorized,
                          message: "invalid or revoked API token",
                          status: 401, requestId: requestId, recoverable: false)
        }
        guard record.allows(route.requiredScope) else {
            return .error(code: .unauthorized,
                          message: "this token does not grant \(route.requiredScope.displayName)",
                          status: 403, requestId: requestId, recoverable: false)
        }

        let agentID: String?
        if case .agentStatus(let id) = route { agentID = id }
        else if case .agentApps(let id) = route { agentID = id }
        else if case .agentScreenshot(let id) = route { agentID = id }
        else if case .agentInput(let id) = route { agentID = id }
        else if case .agentLaunch(let id) = route { agentID = id }
        else if case .agentQuit(let id) = route { agentID = id }
        else if case .agentWindows(let id) = route { agentID = id }
        else { agentID = nil }

        var decision: RateLimiter.Decision = .allow
        limiterQueue.sync {
            decision = limiter.check(tokenID: record.id, agentID: agentID)
            if case .allow = decision, let agentID { limiter.begin(agentID: agentID) }
        }
        defer {
            if let agentID {
                limiterQueue.sync { limiter.end(agentID: agentID) }
            }
        }

        switch decision {
        case .allow:
            break
        case .rateLimited(let retryAfter):
            var response = HTTPResponse.error(
                code: .badRequest, message: "rate limited", status: 429,
                requestId: requestId, recoverable: true)
            response.headers["Retry-After"] = String(retryAfter)
            return response
        case .tooManyConcurrent:
            return .error(code: .badRequest,
                          message: "too many concurrent requests for this agent",
                          status: 429, requestId: requestId, recoverable: true)
        }

        let response = configuration.service.execute(
            route: route, request: request, requestId: requestId,
            networkStatus: configuration.networkStatus)
        guard response.body.count <= configuration.maxResponseBytes else {
            return .error(code: .internalError,
                          message: "response larger than the configured limit",
                          status: 500, requestId: requestId, recoverable: false)
        }
        return response
    }

    func bearerToken(from header: String) -> String? {
        let parts = header.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].caseInsensitiveCompare("Bearer") == .orderedSame else {
            return nil
        }
        let token = parts[1].trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }
}

// MARK: - Parsing and serialising

public enum HTTPRequestParser {
    public enum Result: Equatable {
        case needMoreData
        case complete(HTTPRequest)
        case invalid(String)
    }

    /// Parse a possibly-incremental request.
    ///
    /// `CFHTTPMessage` owns the header grammar; this only decides completeness
    /// from `Content-Length`, refuses a chunked body (the API does not accept
    /// one, and pretending to parse it would be a smuggling surface), and
    /// refuses a body that disagrees with its own length.
    public static func parse(_ data: Data, maxBodyBytes: Int) -> Result {
        let message = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, true).takeRetainedValue()
        let appended = data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            return CFHTTPMessageAppendBytes(message, base, raw.count)
        }
        guard appended else { return .invalid("malformed HTTP request") }
        guard CFHTTPMessageIsHeaderComplete(message) else { return .needMoreData }

        guard let url = CFHTTPMessageCopyRequestURL(message)?.takeRetainedValue() as URL?,
              let method = CFHTTPMessageCopyRequestMethod(message)?.takeRetainedValue() as String? else {
            return .invalid("malformed request line")
        }
        let headers = CFHTTPMessageCopyAllHeaderFields(message)?.takeRetainedValue() as? [String: String] ?? [:]

        if headers.keys.contains(where: { $0.lowercased() == "transfer-encoding" }) {
            return .invalid("chunked request bodies are not accepted")
        }

        let declaredLength = headers.first { $0.key.lowercased() == "content-length" }
            .flatMap { Int($0.value) }
        let body = CFHTTPMessageCopyBody(message)?.takeRetainedValue() as Data? ?? Data()
        let expected = declaredLength ?? 0
        guard expected >= 0 else { return .invalid("negative Content-Length") }
        guard expected <= maxBodyBytes else { return .invalid("body larger than the configured limit") }
        guard body.count >= expected else { return .needMoreData }
        guard body.count == expected else {
            return .invalid("request body does not match Content-Length")
        }

        let path = url.path.isEmpty ? "/" : url.path + (url.query.map { "?" + $0 } ?? "")
        return .complete(HTTPRequest(method: method, path: path, headers: headers, body: body))
    }
}

public enum HTTPResponseSerializer {
    public static func serialize(_ response: HTTPResponse) -> Data {
        let message = CFHTTPMessageCreateResponse(
            kCFAllocatorDefault, response.status,
            reason(for: response.status) as CFString, kCFHTTPVersion1_1).takeRetainedValue()
        var headers = response.headers
        headers["Content-Length"] = String(response.body.count)
        headers["Connection"] = "close"
        for (name, value) in headers {
            CFHTTPMessageSetHeaderFieldValue(message, name as CFString, value as CFString)
        }
        if !response.body.isEmpty {
            CFHTTPMessageSetBody(message, response.body as CFData)
        }
        return CFHTTPMessageCopySerializedMessage(message)?.takeRetainedValue() as Data? ?? Data()
    }

    public static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        case 413: return "Payload Too Large"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        default: return "Unknown"
        }
    }
}
