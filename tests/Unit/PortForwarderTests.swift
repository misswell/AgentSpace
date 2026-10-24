import XCTest
import Network
@testable import AgentSpaceCore

/// The mapped-port forwarder, over real sockets: a listener on the generated
/// external port, the account's "service" on its internal port, and bytes that
/// must cross both ways — including the ownership gate refusing a port the
/// account no longer owns.
final class PortForwarderTests: XCTestCase {

    /// A stand-in for the agent account's local API: a chunk-streaming echo
    /// server on 127.0.0.1 — every received chunk comes back reversed, in
    /// order, until the client closes. It never assumes a request fits one
    /// receive, which is what makes the large-body test meaningful.
    private final class EchoService {
        let listener: NWListener
        let queue = DispatchQueue(label: "portmap-tests.echo")
        private(set) var port: UInt16 = 0
        private let ready = DispatchSemaphore(value: 0)

        init() throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
            var failed: String?
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.port = self?.listener.port?.rawValue ?? 0
                    self?.ready.signal()
                case .failed(let error):
                    failed = "\(error)"
                    self?.ready.signal()
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
            XCTAssertEqual(ready.wait(timeout: .now() + 5), .success)
            XCTAssertNil(failed)
            XCTAssertGreaterThan(port, 0)
        }

        private func accept(_ connection: NWConnection) {
            connection.start(queue: queue)
            receive(connection)
        }

        private func receive(_ connection: NWConnection) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, _ in
                guard let data, !data.isEmpty else {
                    connection.cancel()
                    return
                }
                connection.send(content: Data(data.reversed()), completion: .contentProcessed { _ in
                    self.receive(connection)
                })
            }
        }
    }

    /// The port the runtime would hand out: the allocator's first candidate
    /// that nothing on this Mac is listening on — the real selection path,
    /// not a constant, so the test also covers a busy candidate now and then.
    private func freeExternalPort(account: UUID, internal internalPort: UInt16) throws -> UInt16 {
        let external = try XCTUnwrap(AgentPortAllocator.choose(
            account: account, port: internalPort,
            isFree: { !TCPProbe.answers(host: "127.0.0.1", port: $0, timeout: 0.6) }))
        return external
    }

    /// One request/response through a freshly made connection, the way a
    /// client of a local API actually calls it. Echo semantics: the reply is
    /// whole when as many bytes have come back as went in — anything less is
    /// a closed or refused connection, not a slow one.
    private func roundTrip(host: String, port: UInt16, payload: Data,
                           timeout: TimeInterval = 8) throws -> Data {
        let queue = DispatchQueue(label: "portmap-tests.client")
        let connection = NWConnection(
            host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let semaphore = DispatchSemaphore(value: 0)
        var reply = Data()
        var failure: String?

        func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, complete, error in
                if let data { reply.append(data) }
                if reply.count >= payload.count {
                    semaphore.signal()
                } else if complete || error != nil {
                    failure = "short reply: \(reply.count) of \(payload.count) bytes" +
                        (error.map { " (\($0))" } ?? "")
                    semaphore.signal()
                } else {
                    readMore()
                }
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: payload, completion: .contentProcessed { error in
                    if let error {
                        failure = "send: \(error)"
                        semaphore.signal()
                        return
                    }
                    readMore()
                })
            case .failed(let error):
                failure = "connect: \(error)"
                semaphore.signal()
            default:
                break
            }
        }
        connection.start(queue: queue)
        defer { connection.cancel() }
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            throw NSError(domain: "portmap-tests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "the round trip timed out"])
        }
        if let failure {
            throw NSError(domain: "portmap-tests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: failure])
        }
        return reply
    }

    func testBytesCrossBothWaysThroughTheGeneratedPort() throws {
        let service = try EchoService()
        let account = UUID()
        let external = try freeExternalPort(account: account, internal: service.port)
        let forwarder = PortForwarder(accountID: account, externalPort: external, internalPort: service.port)
        try forwarder.start(gate: { true })

        let payload = Data("agentspace round trip".utf8)
        let reply = try roundTrip(host: "127.0.0.1", port: external, payload: payload)
        XCTAssertEqual(reply, Data(payload.reversed()))

        // A second connection on the same forwarder: mappings serve many
        // callers, not one.
        let again = try roundTrip(host: "127.0.0.1", port: external, payload: payload)
        XCTAssertEqual(again, Data(payload.reversed()))

        forwarder.stop()
        XCTAssertFalse(forwarder.isRunning)
    }

    func testALargeBodySurvivesTheBackpressureLoop() throws {
        let service = try EchoService()
        let account = UUID()
        let external = try freeExternalPort(account: account, internal: service.port)
        let forwarder = PortForwarder(accountID: account, externalPort: external, internalPort: service.port)
        try forwarder.start(gate: { true })
        defer { forwarder.stop() }

        // Comfortably more than the 64 KiB receive window, so the pipe has to
        // chain send completions rather than landing in one receive. The
        // service reverses per received chunk, so the assertion is on the
        // whole payload surviving — same length, same bytes — not on one
        // contiguous reverse (the small test proves the ordering).
        let payload = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0) })
        let reply = try roundTrip(host: "127.0.0.1", port: external, payload: payload, timeout: 15)
        XCTAssertEqual(reply.count, payload.count)
        XCTAssertEqual([UInt8](reply).sorted(), [UInt8](payload).sorted(),
                       "the bytes that came back are not the bytes that went in")
    }

    func testTheGateRefusesAPortTheAccountDoesNotOwn() throws {
        let service = try EchoService()
        let account = UUID()
        let external = try freeExternalPort(account: account, internal: service.port)
        let forwarder = PortForwarder(accountID: account, externalPort: external, internalPort: service.port)
        try forwarder.start(gate: { false })
        defer { forwarder.stop() }

        // The gate refuses at accept: the client's connection closes without a
        // reply, and the service never sees a request.
        XCTAssertThrowsError(try roundTrip(host: "127.0.0.1", port: external, payload: Data("x".utf8)))
    }

    func testASecondForwarderOnTheSameExternalPortIsRefused() throws {
        let service = try EchoService()
        let account = UUID()
        let external = try freeExternalPort(account: account, internal: service.port)
        let first = PortForwarder(accountID: account, externalPort: external, internalPort: service.port)
        try first.start(gate: { true })
        defer { first.stop() }

        let second = PortForwarder(accountID: account, externalPort: external, internalPort: service.port)
        XCTAssertThrowsError(try second.start(gate: { true })) { error in
            XCTAssertEqual(
                error as? PortForwarder.StartError,
                .addressBusy("127.0.0.1:\(external)"))
        }
    }

    func testTheProbeReportsWhoAnswers() {
        XCTAssertFalse(TCPProbe.answers(host: "127.0.0.1", port: 1, timeout: 0.5))
    }
}
