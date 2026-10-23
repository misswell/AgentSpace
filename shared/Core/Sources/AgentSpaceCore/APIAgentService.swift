import Foundation

/// Turns an `APIRoute` plus its body into exactly one Worker RPC, and turns the
/// Worker's answer back into HTTP.
///
/// This is the only place the HTTP surface knows a worker method name. A client
/// cannot name one, and cannot name a socket path or a session token: the agent
/// id resolves through the registry, and the token is read from that agent's
/// runtime directory by the same code the CLI uses.
public struct APIAgentService: Sendable {
    public let root: String

    public init(root: String? = nil) {
        self.root = root ?? AgentSpaceEnvironment.rootOverride ?? RuntimePaths.root
    }

    public struct AgentSummary: Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var username: String
        public var state: String
        public var acceptsInput: Bool
    }

    // MARK: Registry

    public func accounts() -> [AgentAccount] {
        SpaceRegistry.load(root: root).spaces
    }

    public func account(id: String) -> AgentAccount? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return SpaceRegistry.load(root: root).spaces.first { $0.id == uuid }
    }

    /// One call to a resolved agent's worker.
    ///
    /// The token is read from the agent's own runtime directory, never from the
    /// HTTP request: an API client authenticates to AgentSpace, not to the
    /// worker, and the plan is explicit that the two credentials are different.
    public func call(
        agent: AgentAccount,
        method: String,
        params: JSONValue = .object([:]),
        timeout: Double = AgentSpaceEnvironment.socketTimeoutSeconds
    ) throws -> JSONValue {
        let paths = AgentSpaceEnvironment.paths(for: agent)
        guard let token = TokenStore.read(from: paths.tokenPath) else {
            throw AgentSpaceError(
                code: .workerOffline,
                message: "no session token for this agent; the worker has never started")
        }
        let client = WorkerClient(socketPath: paths.socketPath)
        let response: RPCResponse
        do {
            response = try client.call(method: method, params: params, token: token.hex, timeout: timeout)
        } catch {
            throw AgentSpaceError(
                code: .workerOffline,
                message: "the agent's worker did not answer: \(error)")
        }
        if let error = response.error { throw error }
        return response.result ?? .null
    }

    /// Health of the whole API: the registry, plus whether each agent's worker
    /// answers at all. Never reports a worker as healthy because the process
    /// exists — it asks.
    public func health() -> JSONValue {
        let spaces = accounts()
        var agents: [JSONValue] = []
        var usable = 0
        for account in spaces {
            let paths = AgentSpaceEnvironment.paths(for: account)
            let socketPresent = FileManager.default.fileExists(atPath: paths.socketPath)
            let tokenPresent = FileManager.default.fileExists(atPath: paths.tokenPath)
            let healthy = socketPresent && tokenPresent
            if healthy { usable += 1 }
            agents.append(.obj([
                "id": .string(account.id.uuidString),
                "name": .string(account.name),
                "workerSocket": .bool(socketPresent),
                "sessionToken": .bool(tokenPresent),
            ]))
        }
        return .obj([
            "ok": .bool(true),
            "agents": .int(spaces.count),
            "usable": .int(usable),
            "detail": .array(agents),
        ])
    }

    // MARK: Route execution

    /// Execute a route. Returns a response; every failure is mapped here so no
    /// caller can accidentally turn a refusal into a 200.
    public func execute(
        route: APIRoute,
        request: HTTPRequest,
        requestId: String,
        networkStatus: () -> JSONValue
    ) -> HTTPResponse {
        switch route {
        case .health:
            return .json(health())
        case .networkStatus:
            return .json(networkStatus())

        case .agents:
            let spaces = accounts()
            let list: [JSONValue] = spaces.map { account in
                .obj([
                    "id": .string(account.id.uuidString),
                    "name": .string(account.name),
                    "username": .string(account.username),
                ])
            }
            return .json(.obj(["ok": .bool(true), "agents": .array(list)]))

        case .agentStatus(let id):
            guard let account = account(id: id) else { return notFound(id, requestId) }
            return callAndMap(account: account, method: Method.status, requestId: requestId)

        case .agentApps(let id):
            guard let account = account(id: id) else { return notFound(id, requestId) }
            return callAndMap(account: account, method: Method.apps, requestId: requestId)

        case .agentWindows(let id):
            guard let account = account(id: id) else { return notFound(id, requestId) }
            return callAndMap(account: account, method: Method.windowList, requestId: requestId)

        case .agentScreenshot(let id):
            guard let account = account(id: id) else { return notFound(id, requestId) }
            return screenshot(account: account, request: request, requestId: requestId)

        case .agentInput(let id):
            guard let account = account(id: id) else { return notFound(id, requestId) }
            return input(account: account, request: request, requestId: requestId)

        case .agentLaunch(let id):
            guard let account = account(id: id) else { return notFound(id, requestId) }
            return appAction(account: account, method: Method.launch, request: request, requestId: requestId)

        case .agentQuit(let id):
            guard let account = account(id: id) else { return notFound(id, requestId) }
            return appAction(account: account, method: Method.quit, request: request, requestId: requestId)
        }
    }

    // MARK: Route bodies

    private func notFound(_ id: String, _ requestId: String) -> HTTPResponse {
        .error(code: .badRequest,
               message: "no agent with id \(id)",
               status: 404, requestId: requestId, recoverable: false)
    }

    private func callAndMap(account: AgentAccount, method: String, requestId: String) -> HTTPResponse {
        do {
            let result = try call(agent: account, method: method)
            return .json(.obj(["ok": .bool(true), "result": result]))
        } catch let error as AgentSpaceError {
            return map(error, requestId: requestId)
        } catch {
            return .error(code: .internalError, message: "\(error)", status: 500,
                          requestId: requestId, recoverable: false)
        }
    }

    private func screenshot(account: AgentAccount, request: HTTPRequest, requestId: String) -> HTTPResponse {
        var params: [String: JSONValue] = ["inline": .bool(true)]
        if let body = request.jsonBody?.objectValue {
            if let maxWidth = body["maxWidth"]?.intValue { params["maxWidth"] = .int(maxWidth) }
            if let display = body["display"]?.intValue { params["display"] = .int(display) }
        }
        do {
            let result = try call(agent: account, method: Method.screenshot, params: .object(params))
            guard let base64 = result["pngBase64"]?.stringValue,
                  let data = Data(base64Encoded: base64) else {
                return .error(code: .internalError,
                              message: "the worker captured a screenshot but returned no PNG bytes",
                              status: 500, requestId: requestId, recoverable: false)
            }
            return .png(data)
        } catch let error as AgentSpaceError {
            return map(error, requestId: requestId)
        } catch {
            return .error(code: .internalError, message: "\(error)", status: 500,
                          requestId: requestId, recoverable: false)
        }
    }

    private func input(account: AgentAccount, request: HTTPRequest, requestId: String) -> HTTPResponse {
        guard let body = request.jsonBody?.objectValue,
              let actions = body["actions"] else {
            return .error(code: .invalidAction,
                          message: #"input requires a JSON body with an "actions" array"#,
                          status: 400, requestId: requestId, recoverable: false)
        }
        // Validated with the same parser the CLI and the worker use, before the
        // call is made, so a malformed batch costs one round trip rather than a
        // partial batch landing on the desktop.
        if case .failure(let error) = InputAction.parseBatch(actions) {
            return .error(code: error.code, message: error.message,
                          status: 400, requestId: requestId, recoverable: false)
        }
        return callAndMapParams(
            account: account, method: Method.input,
            params: .obj(["actions": actions]), requestId: requestId)
    }

    private func appAction(
        account: AgentAccount,
        method: String,
        request: HTTPRequest,
        requestId: String
    ) -> HTTPResponse {
        guard let body = request.jsonBody?.objectValue,
              let app = body["app"]?.stringValue, !app.isEmpty else {
            return .error(code: .badRequest,
                          message: #"this endpoint requires a JSON body with an "app" string"#,
                          status: 400, requestId: requestId, recoverable: false)
        }
        var params: [String: JSONValue] = ["app": .string(app)]
        if let timeout = body["timeoutSeconds"]?.intValue {
            params["timeoutSeconds"] = .int(timeout)
        }
        return callAndMapParams(
            account: account, method: method, params: .object(params), requestId: requestId)
    }

    private func callAndMapParams(
        account: AgentAccount,
        method: String,
        params: JSONValue,
        requestId: String
    ) -> HTTPResponse {
        do {
            let result = try call(agent: account, method: method, params: params)
            return .json(.obj(["ok": .bool(true), "result": result]))
        } catch let error as AgentSpaceError {
            return map(error, requestId: requestId)
        } catch {
            return .error(code: .internalError, message: "\(error)", status: 500,
                          requestId: requestId, recoverable: false)
        }
    }

    private func map(_ error: AgentSpaceError, requestId: String) -> HTTPResponse {
        .error(
            code: error.code,
            message: error.message,
            status: APIStatusMapper.status(for: error.code),
            requestId: requestId,
            recoverable: APIStatusMapper.recoverable(error.code))
    }
}
