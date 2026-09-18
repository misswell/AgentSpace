import Foundation
import Darwin
import CoreGraphics
import ApplicationServices
import AgentSpaceCore

// agentspace-worker — the per-Space daemon.
//
// Runs as the AgentSpace user inside that user's Aqua session (started by a
// LaunchAgent with `LimitLoadToSessionType: Aqua`) and lends the session out
// over a unix socket. See docs/protocol.md for the wire contract and
// docs/security.md for why each check below exists.

// SIGPIPE is ignored process-wide so a client that disappears surfaces as an
// EPIPE errno rather than killing the worker mid-write.
signal(SIGPIPE, SIG_IGN)

/// Signal sources must outlive the scope that creates them or the dispatch
/// source is cancelled the moment its reference drops.
var signalSources: [DispatchSourceSignal] = []

let workerVersion = Operations.workerVersion

// MARK: - Arguments

/// A usage error; see the CLI's twin for why this is not a bare `String`.
struct ArgumentError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

struct Arguments {
    var spaceID: UUID?
    var spaceName: String = "AgentSpace"
    var runtimeDir: String?
    var socketPath: String?
    var token: String?
    var tokenFile: String?
    var check = false
    var once = false
    var quiet = false
}

func usage() -> String {
    """
    agentspace-worker \(workerVersion) — AgentSpace session daemon

    USAGE:
      agentspace-worker --space-id <uuid> [options]

    OPTIONS:
      --space-id <uuid>     Space this worker serves (required unless --check)
      --name <name>         Human-readable Space name
      --runtime-dir <dir>   Override the runtime root (default \(RuntimePaths.defaultRuntimeRoot))
      --socket <path>       Override the socket path
      --token <hex>         Session token (64 hex chars). Prefer --token-file.
      --token-file <path>   Read the session token from a file
      --check               Print a machine-readable readiness report and exit
      --once                Serve exactly one request, then exit
      --quiet               Suppress the startup banner
      --version             Print the version
      --help                Print this message

    EXIT CODES:
      0    ok / clean shutdown
      64   bad arguments
      69   no window server in this session (NO_WINDOW_SERVER)
      70   socket could not be created or bound
      77   running as root (WORKER_IS_ROOT)
      78   runtime directory is not usable
    """
}

func parseArguments(_ argv: [String]) -> Result<Arguments, ArgumentError> {
    var arguments = Arguments()
    var index = 0
    func next(_ flag: String) -> Result<String, ArgumentError> {
        index += 1
        guard index < argv.count else { return .failure(ArgumentError("\(flag) requires a value")) }
        return .success(argv[index])
    }
    while index < argv.count {
        let flag = argv[index]
        switch flag {
        case "--space-id":
            switch next(flag) {
            case .success(let value):
                guard let uuid = UUID(uuidString: value) else {
                    return .failure(ArgumentError("--space-id must be a UUID, got '\(value)'"))
                }
                arguments.spaceID = uuid
            case .failure(let error): return .failure(error)
            }
        case "--name":
            switch next(flag) {
            case .success(let value): arguments.spaceName = value
            case .failure(let error): return .failure(error)
            }
        case "--runtime-dir":
            switch next(flag) {
            case .success(let value): arguments.runtimeDir = value
            case .failure(let error): return .failure(error)
            }
        case "--socket":
            switch next(flag) {
            case .success(let value): arguments.socketPath = value
            case .failure(let error): return .failure(error)
            }
        case "--token":
            switch next(flag) {
            case .success(let value): arguments.token = value
            case .failure(let error): return .failure(error)
            }
        case "--token-file":
            switch next(flag) {
            case .success(let value): arguments.tokenFile = value
            case .failure(let error): return .failure(error)
            }
        case "--check": arguments.check = true
        case "--once": arguments.once = true
        case "--quiet": arguments.quiet = true
        case "--version":
            print(workerVersion)
            exit(0)
        case "--help", "-h":
            print(usage())
            exit(0)
        default:
            return .failure(ArgumentError("unknown argument '\(flag)'"))
        }
        index += 1
    }
    return .success(arguments)
}

// MARK: - Readiness

/// The startup gate. Plan §2: if the background session is not usable, fail
/// immediately — never continue and hope.
///
/// Note what this does **not** do: it does not refuse to *start* when the
/// session is on the console. A worker whose Space is currently on the console
/// is still a perfectly good worker; it just refuses input (see
/// `Operations.input`). Refusing to start would take the diagnostic surface away
/// exactly when the user needs it to understand why input stopped.
enum Readiness {
    struct Report {
        var ok: Bool
        var uid: uid_t
        var user: String
        var graphicAccess: Bool?
        var verdict: String
        var screenRecording: Bool
        var accessibility: Bool
        var socketPath: String
        var socketPathFits: Bool
        var problems: [String]

        var json: JSONValue {
            .obj([
                "ok": .bool(ok),
                "uid": .int(Int(uid)),
                "user": .string(user),
                "graphicAccess": graphicAccess.map { JSONValue.bool($0) } ?? .null,
                "sessionVerdict": .string(verdict),
                "screenRecording": .bool(screenRecording),
                "accessibility": .bool(accessibility),
                "socketPath": .string(socketPath),
                "socketPathFits": .bool(socketPathFits),
                "problems": .array(problems.map { .string($0) }),
                "protocol": .int(agentSpaceProtocolVersion),
                "workerVersion": .string(workerVersion),
            ])
        }
    }

    static func evaluate(arguments: Arguments, paths: RuntimePaths, socketPath: String) -> Report {
        var problems: [String] = []

        let uid = getuid()
        var username = "unknown"
        if let pw = getpwuid(uid), let name = pw.pointee.pw_name {
            username = String(cString: name)
        }

        if uid == 0 {
            problems.append("running as root: agentspace-worker must run as the AgentSpace user, never root")
        }

        let source = SystemSessionInfo()
        let graphic = source.hasGraphicAccess()
        let verdict = SessionGuard.verdict(using: source)
        switch verdict {
        case .noWindowServer:
            problems.append("no window server in this session: the worker needs a real Aqua session (log the AgentSpace user in through the GUI, not ssh)")
        case .isConsole:
            problems.append("this session is currently the console; the worker will start but will refuse all input")
        case .indeterminate:
            problems.append("CGSessionCopyCurrentDictionary did not answer; the worker will refuse all input (fail closed)")
        case .usable:
            break
        }

        if !RuntimePaths.socketPathFits(socketPath) {
            problems.append("socket path is \(socketPath.utf8.count) bytes, over the \(RuntimePaths.maxSocketPathBytes)-byte sun_path limit")
        }
        if !FileManager.default.fileExists(atPath: paths.directory) {
            problems.append("runtime directory \(paths.directory) does not exist yet")
        }

        let blocking = problems.contains {
            $0.hasPrefix("running as root") || $0.hasPrefix("no window server")
                || $0.hasPrefix("socket path is")
        }

        return Report(
            ok: !blocking,
            uid: uid,
            user: username,
            graphicAccess: graphic,
            verdict: verdictName(verdict),
            screenRecording: CGPreflightScreenCaptureAccess(),
            accessibility: AXIsProcessTrusted(),
            socketPath: socketPath,
            socketPathFits: RuntimePaths.socketPathFits(socketPath),
            problems: problems)
    }

    static func verdictName(_ verdict: SessionVerdict) -> String {
        switch verdict {
        case .usable: return "usable"
        case .isConsole: return "isConsole"
        case .noWindowServer: return "noWindowServer"
        case .indeterminate: return "indeterminate"
        }
    }
}

// MARK: - Socket server

final class SocketServer {
    let socketPath: String
    let context: WorkerContext
    let operations: Operations
    let serveOnce: Bool

    private var listenFD: Int32 = -1
    private let queue = DispatchQueue(label: BundleIdentifiers.worker + ".connections", attributes: .concurrent)

    init(socketPath: String, context: WorkerContext, serveOnce: Bool) {
        self.socketPath = socketPath
        self.context = context
        self.operations = Operations(context: context)
        self.serveOnce = serveOnce
    }

    enum BindError: Error {
        case alreadyRunning
        case socketFailed(String)
        case pathTooLong(Int)
        case bindFailed(String)
        case listenFailed(String)
        case chmodFailed(String)
    }

    func bind() throws {
        guard RuntimePaths.socketPathFits(socketPath) else {
            throw BindError.pathTooLong(socketPath.utf8.count)
        }
        // Single-instance guard: an exclusive, non-blocking flock on a lock
        // file next to the socket. The kernel releases the lock when the
        // process dies, so a crashed worker leaves nothing to clean up.
        // Without this, a second worker would unlink the live socket below
        // and steal the endpoint out from under the first one.
        let lockPath = (socketPath as NSString).deletingLastPathComponent + "/worker.lock"
        let lockFD = open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0 else {
            throw BindError.socketFailed(String(cString: strerror(errno)))
        }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            close(lockFD)
            throw BindError.alreadyRunning
        }
        // lockFD is intentionally not closed: holding the descriptor is what
        // holds the lock for the lifetime of this worker.
        // A stale socket from a crashed worker would make `bind` fail with
        // EADDRINUSE forever, so it is removed first. Safe because the
        // directory is ACL'd to this Space, and the flock above guarantees
        // no other live worker owns this endpoint.
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw BindError.socketFailed(String(cString: strerror(errno)))
        }

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < 104 else {
            close(fd)
            throw BindError.pathTooLong(pathBytes.count)
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 104) { chars in
                for (i, byte) in pathBytes.enumerated() { chars[i] = CChar(bitPattern: byte) }
                chars[pathBytes.count] = 0
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw BindError.bindFailed(message)
        }
        guard listen(fd, 16) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw BindError.listenFailed(message)
        }
        // 0660 with group staff, inside a 0700 directory ACL'd to the main user
        // and the agent user. The directory is what actually restricts who can
        // reach this; the mode is belt and braces.
        if chmod(socketPath, 0o660) != 0 {
            let message = String(cString: strerror(errno))
            close(fd)
            throw BindError.chmodFailed(message)
        }
        listenFD = fd

        // If the helper gave us the main user's name, extend the ACL to the
        // socket too, so a 0660 that happens to exclude them cannot lock the GUI
        // out of its own Space.
        if let mainUser = context.mainUser {
            _ = ACLRunner.apply("user:\(mainUser) allow read,write", to: socketPath)
        }
    }

    /// Serve until killed, or exactly one request when `--once`.
    func serve() {
        while true {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                Log.ipc.error("accept failed: \(String(cString: strerror(errno)))")
                continue
            }
            if serveOnce {
                handle(fd: clientFD)
                return
            }
            queue.async { [weak self] in
                self?.handle(fd: clientFD)
            }
        }
    }

    private func handle(fd: Int32) {
        let connection = Connection(fd: fd)
        defer { connection.close() }

        let request: RPCRequest
        do {
            guard let line = try connection.readLine() else { return }
            switch RPCCodec.decodeRequest(line) {
            case .success(let decoded): request = decoded
            case .failure(let error):
                connection.send(RPCResponse(id: "", error: error))
                return
            }
        } catch let error as AgentSpaceError {
            connection.send(RPCResponse(id: "", error: error))
            return
        } catch {
            connection.send(RPCResponse(id: "", error: AgentSpaceError(
                code: .badRequest, message: "could not read request: \(error)")))
            return
        }

        // Protocol version gate: refusing loudly beats two builds
        // misunderstanding each other's fields.
        guard request.protocol == agentSpaceProtocolVersion else {
            connection.send(RPCResponse(id: request.requestId, error: AgentSpaceError(
                code: .protocolMismatch,
                message: "worker speaks protocol \(agentSpaceProtocolVersion), request declared \(request.protocol). Reinstall so the GUI, CLI and worker come from the same build.")))
            return
        }

        // Token gate. Everything except `hello` requires it.
        if !Method.tokenExempt.contains(request.method) {
            let presented = request.token ?? ""
            guard presented.isEmpty == false, context.token.matches(presented) else {
                Log.ipc.error("rejected \(request.method) from pid \(getpid())-peer: bad or missing session token")
                connection.send(RPCResponse(id: request.requestId, error: AgentSpaceError(
                    code: .unauthorized,
                    message: "missing or incorrect session token for this AgentSpace")))
                return
            }
        }

        let started = Date()
        switch operations.dispatch(method: request.method, params: request.params) {
        case .success(let result):
            connection.send(RPCResponse(id: request.requestId, result: result))
        case .failure(let error):
            connection.send(RPCResponse(id: request.requestId, error: error))
        }
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        Log.ipc.debug("\(request.method) \(elapsed)ms")
    }
}

// MARK: - Entry point

switch parseArguments(Array(CommandLine.arguments.dropFirst())) {
case .failure(let error):
    FileHandle.standardError.write(Data(("agentspace-worker: " + error.message + "\n\n" + usage() + "\n").utf8))
    exit(64)

case .success(let arguments):
    // Resolve paths, honouring the test/override flags.
    let spaceID = arguments.spaceID ?? UUID()
    let paths = RuntimePaths(
        spaceID: spaceID,
        root: arguments.runtimeDir ?? RuntimePaths.root,
        socketPath: arguments.socketPath)
    let socketPath = paths.socketPath

    if arguments.check {
        let report = Readiness.evaluate(arguments: arguments, paths: paths, socketPath: socketPath)
        if let data = try? RPCCodec.encoder().encode(report.json),
           let text = String(data: data, encoding: .utf8) {
            print(text)
        }
        exit(report.ok ? 0 : 1)
    }

    guard arguments.spaceID != nil else {
        FileHandle.standardError.write(Data("agentspace-worker: --space-id is required\n\n".utf8))
        FileHandle.standardError.write(Data((usage() + "\n").utf8))
        exit(64)
    }

    // Gate 1: never root. Plan §7 / §63.10.
    if let refusal = PrivilegeGuard.refuseReason(uid: getuid()) {
        Log.worker.error(refusal.message)
        FileHandle.standardError.write(Data(("agentspace-worker: " + refusal.message + "\n").utf8))
        exit(77)
    }

    // Gate 2: a real Aqua session with a window server, or nothing this worker
    // does can work. Plan §2: fail immediately rather than half-run.
    let readiness = Readiness.evaluate(arguments: arguments, paths: paths, socketPath: socketPath)
    if readiness.graphicAccess == false {
        let message = "no window server in this session (SessionGetInfo reports sessionHasGraphicAccess = false). agentspace-worker only runs inside an Aqua GUI session; log the AgentSpace user in through the GUI and retry."
        Log.session.error(message)
        FileHandle.standardError.write(Data(("agentspace-worker: " + message + "\n").utf8))
        exit(69)
    }

    // Resolve the session token.
    let token: SessionToken
    if let raw = arguments.token {
        let parsed = SessionToken(hex: raw)
        guard parsed.isValidShape else {
            FileHandle.standardError.write(Data("agentspace-worker: --token must be \(SessionToken.byteCount * 2) hex characters\n".utf8))
            exit(64)
        }
        token = parsed
    } else if let tokenFile = arguments.tokenFile, let loaded = TokenStore.read(from: tokenFile) {
        token = loaded
    } else if let loaded = TokenStore.read(from: paths.tokenPath) {
        token = loaded
    } else {
        // No token on disk: mint one. This is the `--once`/development path and
        // the first-run path; the helper normally writes it first via
        // `createUser`, so a mismatch here means someone started the worker by
        // hand, which is worth a line in the log.
        guard let generated = SessionToken.generate() else {
            FileHandle.standardError.write(Data("agentspace-worker: could not generate a session token (SecRandomCopyBytes failed)\n".utf8))
            exit(70)
        }
        if let error = TokenStore.write(generated, to: paths.tokenPath) {
            FileHandle.standardError.write(Data(("agentspace-worker: " + error.message + "\n").utf8))
            exit(78)
        }
        Log.worker.info("generated a new session token at \(paths.tokenPath)")
        token = generated
    }

    guard let context = WorkerContext(
        spaceID: spaceID,
        spaceName: arguments.spaceName,
        token: token,
        paths: paths)
    else {
        FileHandle.standardError.write(Data("agentspace-worker: could not resolve the current user\n".utf8))
        exit(77)
    }

    let server = SocketServer(socketPath: socketPath, context: context, serveOnce: arguments.once)

    // Create the runtime directory if this is a development/first run. In
    // production the helper has already made it with the right ACL.
    try? FileManager.default.createDirectory(
        atPath: paths.directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
    try? FileManager.default.createDirectory(
        atPath: context.screenshotsDirectory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])

    do {
        try server.bind()
    } catch SocketServer.BindError.alreadyRunning {
        let message = "another worker is already serving this Space"
        Log.worker.error(message)
        FileHandle.standardError.write(Data(("agentspace-worker: " + message + "\n").utf8))
        exit(78) // EX_CONFIG: the environment already has a worker here
    } catch {
        let message = "could not bind \(socketPath): \(error)"
        Log.worker.error(message)
        FileHandle.standardError.write(Data(("agentspace-worker: " + message + "\n").utf8))
        exit(70)
    }

    // pid file, so `agentspace status` can tell a live worker from a stale socket.
    try? Data("\(getpid())\n".utf8).write(to: URL(fileURLWithPath: paths.pidPath))
    try? Data("\(spaceID.uuidString)\n".utf8).write(to: URL(fileURLWithPath: paths.tokenPath + ".space"))
    try? Data("\(getpid())\n".utf8).write(to: URL(fileURLWithPath: paths.statusPath + ".pid"))

    if !arguments.quiet {
        let banner = "agentspace-worker \(workerVersion) uid=\(getuid()) space=\(arguments.spaceName) socket=\(socketPath) verdict=\(readiness.verdict)"
        Log.worker.info(banner)
        FileHandle.standardError.write(Data((banner + "\n").utf8))
    }

    // Clean shutdown: remove the socket so the next start does not trip over it
    // and so the GUI can tell the worker is gone.
    let cleanup = {
        unlink(socketPath)
        try? FileManager.default.removeItem(atPath: paths.pidPath)
    }
    // The signal sources run on their OWN queue, not `.main`.
    //
    // This is not a style choice. `server.serve()` blocks the main thread in
    // `accept()`, so a handler queued on the main queue would never run: the
    // process would ignore SIGTERM entirely and could only be stopped with
    // SIGKILL. That was observed live — `kill <pid>` left the worker running and
    // a shell `wait`ing on it hung forever. libdispatch services signal sources on
    // its own worker threads when given a non-main queue, so the handler fires
    // while the main thread is still parked in `accept()`.
    let signalQueue = DispatchQueue(label: BundleIdentifiers.worker + ".signals")
    for signalNumber in [SIGTERM, SIGINT] {
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: signalQueue)
        source.setEventHandler {
            Log.worker.info("received signal \(signalNumber), shutting down")
            cleanup()
            exit(0)
        }
        source.resume()
        // Keep the source alive for the process lifetime.
        signalSources.append(source)
    }

    server.serve()
    cleanup()
    exit(0)
}
