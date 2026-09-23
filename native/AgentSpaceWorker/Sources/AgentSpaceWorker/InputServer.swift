import Darwin
import Foundation
import AgentSpaceCore

/// The persistent binary input channel's server side.
///
/// `worker.sock` stays what it is: one request per connection, JSON, for the
/// CLI, the MCP server and every low-frequency control call. This is the other
/// endpoint, and the reason it exists is a measurement — a `move` over the RPC
/// path cost p95 3.98 ms end to end (§327 row 894), every one of those opening
/// its own socket, and a hand at 125 Hz does not have 4 ms to spend per event on
/// bookkeeping. Here one connection lives as long as the desktop window does,
/// every packet is a fixed binary record, and travel is answered only
/// occasionally.
///
/// What does *not* change is the safety model. Every connection proves itself
/// the same way a frame connection does — peer uid, session token, worker
/// instance, session generation — and every event re-asks the session verdict
/// before it is posted. A fast channel to a session that has become the console
/// is still a refusal.
final class InputServer {
    /// A packet that arrives while the previous one is being applied is queued,
    /// not dropped, but only up to a bound: a client that sent a thousand moves
    /// while the worker was blocked should not make the worker spend the next
    /// second walking them all. Travel is coalesced by the client anyway; this
    /// is the backstop for a client that is not.
    static let maxQueuedPackets = 256

    private let context: WorkerContext
    private let operations: Operations
    private let lease: InputLeaseManager
    private var listenFD: Int32 = -1
    /// The queue input connections run on, at `.userInteractive` and shared with
    /// nothing else in the worker: a capture busy encoding a 3024-wide frame must
    /// not be the reason a click arrives late, and this is the boundary that makes
    /// that true by construction rather than by hope.
    ///
    /// **Concurrent, deliberately.** A connection parks in `read` for as long as
    /// its client keeps it open — which for a desktop viewer is the whole time the
    /// window is on screen. On a serial queue that first connection would be the
    /// only one ever served: a Fusion proxy opening its own would sit in the
    /// accept backlog, connected but mute. Each connection is independently
    /// ordered (one client's packets are applied in the order they were read), and
    /// nothing is shared between them except the lease and the gesture-frame
    /// store, both of which are locked.
    private let queue = DispatchQueue(label: BundleIdentifiers.worker + ".input-server",
                                      qos: .userInteractive, attributes: .concurrent)
    private let acceptQueue = DispatchQueue(label: BundleIdentifiers.worker + ".input-accept", qos: .userInteractive)
    private var connections: [ObjectIdentifier: InputConnection] = [:]
    private let connectionsLock = NSLock()

    init(context: WorkerContext, operations: Operations) {
        self.context = context
        self.operations = operations
        self.lease = operations.inputLease
    }

    var socketPath: String { context.paths.inputSocketPath }

    func bind() throws {
        let path = socketPath
        guard RuntimePaths.socketPathFits(path) else {
            throw AgentSpaceError(code: .internalError, message: "input socket path exceeds sockaddr_un")
        }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentSpaceError(code: .internalError, message: "could not create input socket") }
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 104) { chars in
                for (index, byte) in bytes.enumerated() { chars[index] = CChar(bitPattern: byte) }
                chars[bytes.count] = 0
            }
        }
        let result = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard result == 0, listen(fd, 16) == 0 else {
            let message = String(cString: strerror(errno)); Darwin.close(fd)
            throw AgentSpaceError(code: .internalError, message: "could not bind input socket: \(message)")
        }
        // The same shape the frame socket and the RPC socket use: 0660 inside a
        // 0700 directory ACL'd to exactly two users, plus an explicit ACL entry
        // so a mode that happens to exclude the controller cannot lock the GUI
        // out of its own account.
        guard chmod(path, 0o660) == 0 else {
            Darwin.close(fd); unlink(path)
            throw AgentSpaceError(code: .internalError, message: "could not restrict input socket")
        }
        if let mainUser = context.mainUser, ACLRunner.apply("user:\(mainUser) allow read,write", to: path) != 0 {
            Darwin.close(fd); unlink(path)
            throw AgentSpaceError(code: .internalError, message: "could not grant controller access to input socket")
        }
        listenFD = fd
    }

    func start() { acceptQueue.async { [weak self] in self?.acceptLoop() } }

    func stop() {
        if listenFD >= 0 { shutdown(listenFD, SHUT_RDWR); Darwin.close(listenFD); listenFD = -1 }
        unlink(socketPath)
        connectionsLock.lock()
        let live = Array(connections.values)
        connections.removeAll()
        connectionsLock.unlock()
        for connection in live { connection.stop() }
    }

    private func acceptLoop() {
        while listenFD >= 0 {
            let client = accept(listenFD, nil, nil)
            if client < 0 { if errno == EINTR { continue }; break }
            queue.async { [weak self] in self?.serve(client) }
        }
    }

    private func serve(_ fd: Int32) {
        // One connection per accepted socket, each blocking on its own thread.
        // Anything else would make one window's connection the cost of another
        // window's — see the note on `queue`.
        let connection = InputConnection(fd: fd, context: context, operations: operations, lease: lease)
        connectionsLock.lock(); connections[ObjectIdentifier(connection)] = connection; connectionsLock.unlock()
        defer {
            connectionsLock.lock(); connections[ObjectIdentifier(connection)] = nil; connectionsLock.unlock()
            connection.stop()
        }
        connection.pump()
    }
}
