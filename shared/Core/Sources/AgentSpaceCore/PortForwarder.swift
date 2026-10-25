import Foundation
import Network

/// One mapped port for one agent account: listens on `127.0.0.1:<external>`
/// — the generated port the main system calls — and forwards every accepted
/// connection to `127.0.0.1:<internal>`, which, because all accounts on this
/// Mac share one kernel network stack, is the service this account runs in
/// its own session. No tunnel, no interface configuration, no privilege, and
/// no network beyond loopback.
///
/// Because the stack is shared, the forwarder must prove the internal port
/// still belongs to *this* account before it forwards anything: `gate` is
/// asked on every accepted connection, and a port this account no longer
/// listens on is refused rather than silently pointed at whichever other
/// account claimed `127.0.0.1:<internal>` next. Fail closed: no verdict, no
/// bytes.
///
/// The byte path mirrors `ScreenSharingRelay` (64 KiB receives chained
/// through send completions, so a fast side cannot run ahead of a slow one),
/// generalized to many concurrent connections instead of the relay's single
/// pair.
public final class PortForwarder: @unchecked Sendable {

    public enum StartError: Error, CustomStringConvertible, Equatable {
        /// The external port is already taken on this machine — another local
        /// process holds it, or a second forwarder is serving it.
        case addressBusy(String)
        case listenerFailed(String)

        public var description: String {
            switch self {
            case .addressBusy(let endpoint):
                return "\(endpoint) is already in use on this Mac, so the mapped listener cannot bind it"
            case .listenerFailed(let reason):
                return "the mapped listener could not start: \(reason)"
            }
        }
    }

    public let accountID: UUID
    /// The port inside the agent account's session that connections go to.
    public let internalPort: UInt16
    /// The generated port this forwarder serves on `listenHost`.
    public let externalPort: UInt16
    /// The address this forwarder listens on: `127.0.0.1` for a generated or
    /// chosen port, or the account's fixed alias (`127.100.x.y`) when the
    /// fixed-address feature is on — where the port number stays the internal
    /// one, which is the point of having an address per account.
    public let listenHost: String

    /// Enough for a browser opening a page and its subresources at once; small
    /// enough that a stuck client cannot pin unbounded memory.
    public static let connectionLimit = 64

    private let queue = DispatchQueue(label: "com.agentspace.portmap.forwarder")
    private var listener: NWListener?

    /// One live connection. `clientClosed`/`upstreamClosed` are the half-close
    /// ledger: a FIN from one side ends *that side's* reading only — the other
    /// direction keeps flowing until its own end, because an API client that
    /// shuts its write side after the request still deserves the whole
    /// response. Both sides ended, or any error, tears the pair down.
    private struct Pair {
        let client: NWConnection
        let upstream: NWConnection
        var clientClosed = false
        var upstreamClosed = false
    }

    private var pairs: [UUID: Pair] = [:]
    private var gate: (@Sendable () -> Bool)?
    private var running = false

    public init(accountID: UUID, externalPort: UInt16, internalPort: UInt16,
                listenHost: String = "127.0.0.1") {
        self.accountID = accountID
        self.externalPort = externalPort
        self.internalPort = internalPort
        self.listenHost = listenHost
    }

    public var endpoint: String { "\(listenHost):\(externalPort)" }

    public var isRunning: Bool {
        queue.sync { running }
    }

    /// Live connections being forwarded right now.
    public var connectionCount: Int {
        queue.sync { pairs.count }
    }

    public func start(gate: @escaping @Sendable () -> Bool) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host(listenHost),
            port: NWEndpoint.Port(rawValue: externalPort)!)
        // No reuse: two forwarders on one endpoint is a bug the caller wants
        // to hear about, not a port silently shared.
        parameters.allowLocalEndpointReuse = false

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw StartError.listenerFailed("\(error)")
        }

        // The state handler is installed BEFORE `start`, or `.ready` can be
        // delivered before anything waits for it — the measured lesson behind
        // `APIServer.start`'s own handshake (validation §398 row 1354).
        // `.waiting` does NOT settle the handshake: on loopback it is often a
        // transient state on the way to `.ready`, and treating it as failure
        // is what made the review's flapping worse. Only `.ready`/`.failed`
        // settle it; the timeout does, and a wait that never ended is the
        // caller's address-busy to classify.
        let semaphore = DispatchSemaphore(value: 0)
        var ready = false
        var failed: String?
        var failedBecauseBusy = false
        var sawWaiting = false
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready = true
                semaphore.signal()
            case .failed(let error):
                failed = "\(error)"
                // Typed, not string-matched: EADDRINUSE is the caller's
                // address-busy to classify; anything else is a listener fault.
                if case let NWError.posix(code) = error, code == .EADDRINUSE {
                    failedBecauseBusy = true
                }
                semaphore.signal()
            case .waiting:
                sawWaiting = true
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 5)
        listener.stateUpdateHandler = nil

        guard ready, failed == nil else {
            listener.newConnectionHandler = nil
            listener.cancel()
            if failedBecauseBusy || sawWaiting || failed == nil {
                throw StartError.addressBusy("\(listenHost):\(externalPort)")
            }
            throw StartError.listenerFailed(failed ?? "did not become ready")
        }

        queue.sync {
            self.listener = listener
            self.gate = gate
            self.running = true
        }
    }

    public func stop() {
        queue.async { [self] in
            running = false
            gate = nil
            listener?.stateUpdateHandler = nil
            listener?.newConnectionHandler = nil
            listener?.cancel()
            listener = nil
            for (_, pair) in pairs {
                pair.client.stateUpdateHandler = nil
                pair.upstream.stateUpdateHandler = nil
                pair.client.cancel()
                pair.upstream.cancel()
            }
            pairs.removeAll()
        }
    }

    // MARK: Connections

    private func accept(_ client: NWConnection) {
        guard running, let gate, gate() else {
            client.cancel()
            return
        }
        guard pairs.count < Self.connectionLimit else {
            client.cancel()
            return
        }
        let id = UUID()
        let upstream = NWConnection(
            host: "127.0.0.1", port: NWEndpoint.Port(rawValue: internalPort)!, using: .tcp)
        pairs[id] = Pair(client: client, upstream: upstream)
        upstream.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.pipe(client, to: upstream, id: id, closing: \Pair.upstreamClosed)
                self.pipe(upstream, to: client, id: id, closing: \Pair.clientClosed)
            case .failed, .cancelled:
                self.disconnect(id)
            default:
                break
            }
        }
        client.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.disconnect(id)
            default:
                break
            }
        }
        client.start(queue: queue)
        upstream.start(queue: queue)
    }

    private func pipe(
        _ source: NWConnection,
        to destination: NWConnection,
        id: UUID,
        closing side: WritableKeyPath<Pair, Bool>
    ) {
        guard pairs[id] != nil else { return }
        source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self, self.pairs[id] != nil else { return }
            if let error {
                self.disconnect(id)
                return
            }
            guard let data, !data.isEmpty else {
                // EOF with nothing pending: half-close this side only.
                self.closeSide(side, id: id)
                return
            }
            destination.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self, self.pairs[id] != nil else { return }
                if let error {
                    self.disconnect(id)
                } else if complete {
                    // Everything the peer sent was forwarded, and it said no
                    // more is coming: half-close this side, keep the other.
                    self.closeSide(side, id: id)
                } else {
                    self.pipe(source, to: destination, id: id, closing: side)
                }
            })
        }
    }

    private func closeSide(_ side: WritableKeyPath<Pair, Bool>, id: UUID) {
        guard var pair = pairs[id] else { return }
        pair[keyPath: side] = true
        if pair.clientClosed && pair.upstreamClosed {
            pairs[id] = pair
            disconnect(id)
        } else {
            pairs[id] = pair
        }
    }

    private func disconnect(_ id: UUID) {
        guard let pair = pairs.removeValue(forKey: id) else { return }
        pair.client.stateUpdateHandler = nil
        pair.upstream.stateUpdateHandler = nil
        pair.client.cancel()
        pair.upstream.cancel()
    }
}

/// Whether something answers a TCP connect — used to probe whether a mapping's
/// generated port is free before committing it, and to report a mapping's live
/// state. Never on a hot path; blocking with a timeout is the point.
public enum TCPProbe {

    public static func answers(host: String, port: UInt16, timeout: TimeInterval = 1.5) -> Bool {
        let queue = DispatchQueue(label: "com.agentspace.portmap.probe")
        let semaphore = DispatchSemaphore(value: 0)
        let connection = NWConnection(
            host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        var answered = false
        var settled = false
        func finish(_ value: Bool) {
            guard !settled else { return }
            settled = true
            answered = value
            semaphore.signal()
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.cancel()
                finish(true)
            case .failed:
                finish(false)
            case .cancelled:
                // Reached without `.ready`: our own post-timeout cancel, or a
                // cancellation we did not ask for. Either way, no answer.
                finish(false)
            default:
                break
            }
        }
        connection.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + timeout)
        connection.stateUpdateHandler = nil
        connection.cancel()
        return answered
    }
}
