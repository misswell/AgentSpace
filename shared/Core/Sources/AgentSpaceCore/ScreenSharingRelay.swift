import Foundation
import Network

/// Apple's client rejects a direct connection to this Mac's ordinary VNC port.
/// A temporary loopback relay is the same transport as a local port forward;
/// Apple's client still owns authentication and the choice of login session.
/// No parsing, recording, credentials, input synthesis, or external listener.
public final class ScreenSharingRelay: @unchecked Sendable {
    public enum Failure: Error {
        case unavailable, cancelled
    }

    private let queue = DispatchQueue(label: "AgentSpace.account-login.relay")
    private let destinationPort: NWEndpoint.Port
    private var listener: NWListener?
    private var connections: [UUID: (NWConnection, NWConnection)] = [:]
    private var started = false
    private var stopped = false
    private var pending: CheckedContinuation<UInt16, Error>?
    private var deadline: DispatchWorkItem?

    public init() { destinationPort = 5900 }
    // Test server only; production cannot choose another host or destination.
    init(destinationPort: UInt16) {
        self.destinationPort = NWEndpoint.Port(rawValue: destinationPort)!
    }

    public func start() async throws -> UInt16 {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    guard !started, !stopped else {
                        continuation.resume(throwing: Failure.cancelled)
                        return
                    }
                    started = true
                    pending = continuation
                    do {
                        let parameters = NWParameters.tcp
                        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                        let listener = try NWListener(using: parameters)
                        self.listener = listener
                        listener.stateUpdateHandler = { [weak self] state in
                            guard let self else { return }
                            switch state {
                            case .ready:
                                guard let port = listener.port?.rawValue else {
                                    self.finish(.failure(Failure.unavailable)); return
                                }
                                self.finish(.success(port))
                            case .failed:
                                self.finish(.failure(Failure.unavailable))
                                self.close()
                            default: break
                            }
                        }
                        listener.newConnectionHandler = { [weak self] in self?.accept($0) }
                        let timeout = DispatchWorkItem { [weak self] in
                            self?.finish(.failure(Failure.unavailable))
                            self?.close()
                        }
                        deadline = timeout
                        queue.asyncAfter(deadline: .now() + 5, execute: timeout)
                        listener.start(queue: queue)
                    } catch {
                        finish(.failure(Failure.unavailable))
                        close()
                    }
                }
            }
        } onCancel: { self.stop() }
    }

    public func stop() { queue.async { [self] in close() } }

    private func finish(_ result: Result<UInt16, Error>) {
        deadline?.cancel()
        deadline = nil
        pending?.resume(with: result)
        pending = nil
    }

    private func close() {
        stopped = true
        finish(.failure(Failure.cancelled))
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        for (client, server) in connections.values { client.cancel(); server.cancel() }
        connections.removeAll()
    }

    private func accept(_ client: NWConnection) {
        guard !stopped, connections.isEmpty else { client.cancel(); return }
        let id = UUID()
        let server = NWConnection(host: "127.0.0.1", port: destinationPort, using: .tcp)
        connections[id] = (client, server)
        server.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.pipe(client, to: server, id: id)
                self.pipe(server, to: client, id: id)
            case .failed, .cancelled: self.disconnect(id)
            default: break
            }
        }
        client.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.disconnect(id)
            default: break
            }
        }
        client.start(queue: queue)
        server.start(queue: queue)
    }

    private func pipe(_ source: NWConnection, to destination: NWConnection, id: UUID) {
        guard connections[id] != nil else { return }
        source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self, self.connections[id] != nil else { return }
            guard let data, !data.isEmpty, error == nil else { self.disconnect(id); return }
            destination.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if error != nil || complete { self.disconnect(id) }
                else { self.pipe(source, to: destination, id: id) }
            })
        }
    }

    private func disconnect(_ id: UUID) {
        guard let pair = connections.removeValue(forKey: id) else { return }
        pair.0.stateUpdateHandler = nil
        pair.1.stateUpdateHandler = nil
        pair.0.cancel(); pair.1.cancel()
    }

    /// Probe only the banner. No authentication attempt, password, or UI.
    public static func isAvailable(timeout: TimeInterval = 3) async -> Bool {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "AgentSpace.account-login.probe")
            let connection = NWConnection(host: "127.0.0.1", port: 5900, using: .tcp)
            var answered = false
            var deadline: DispatchWorkItem?
            func finish(_ available: Bool) {
                guard !answered else { return }
                answered = true
                deadline?.cancel()
                connection.stateUpdateHandler = nil
                connection.cancel()
                continuation.resume(returning: available)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.receive(minimumIncompleteLength: 12, maximumLength: 12) { data, _, _, _ in
                        finish(data == Data("RFB 003.889\n".utf8))
                    }
                case .failed, .cancelled: finish(false)
                default: break
                }
            }
            let work = DispatchWorkItem { finish(false) }
            deadline = work
            queue.asyncAfter(deadline: .now() + timeout, execute: work)
            connection.start(queue: queue)
        }
    }
}
