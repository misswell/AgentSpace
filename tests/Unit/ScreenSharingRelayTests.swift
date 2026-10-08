import XCTest
import Network
@testable import AgentSpaceCore

final class ScreenSharingRelayTests: XCTestCase {
    func testRelayPreservesFragmentedDuplexBytesAndClosesItsListener() async throws {
        let queue = DispatchQueue(label: "AgentSpace.relay-test")
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let server = try NWListener(using: parameters)
        let listening = expectation(description: "test service listening")
        let closed = expectation(description: "forwarded connection closed")
        server.stateUpdateHandler = { if case .ready = $0 { listening.fulfill() } }
        server.newConnectionHandler = { connection in
            func echo() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, complete, error in
                    guard let data, !data.isEmpty, error == nil else {
                        connection.cancel(); closed.fulfill(); return
                    }
                    connection.send(content: data, completion: .contentProcessed { _ in
                        if complete { connection.cancel(); closed.fulfill() }
                        else { echo() }
                    })
                }
            }
            connection.start(queue: queue)
            echo()
        }
        server.start(queue: queue)
        defer { server.cancel() }
        await fulfillment(of: [listening], timeout: 5)
        let targetPort = try XCTUnwrap(server.port?.rawValue)
        let relay = ScreenSharingRelay(destinationPort: targetPort)
        defer { relay.stop() }
        let relayPort = try await relay.start()
        let client = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: relayPort)!, using: .tcp)
        defer { client.cancel() }
        // Larger than either pipe's read size, with all byte values. A short
        // recv, accidental UTF-8 conversion or early EOF would lose evidence.
        let payload = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0) })
        let received = expectation(description: "byte-identical echo")
        var echoed = Data()
        func read() {
            client.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, complete, error in
                if let data { echoed.append(data) }
                if echoed.count >= payload.count || complete || error != nil { received.fulfill() }
                else { read() }
            }
        }
        client.stateUpdateHandler = { state in
            if case .ready = state {
                client.send(content: payload, completion: .contentProcessed { _ in })
                read()
            }
        }
        client.start(queue: queue)
        await fulfillment(of: [received], timeout: 10)
        XCTAssertEqual(echoed, payload)
        relay.stop()
        await fulfillment(of: [closed], timeout: 5)

        let refused = expectation(description: "listener gone")
        let next = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: relayPort)!, using: .tcp)
        defer { next.cancel() }
        var reported = false
        next.stateUpdateHandler = { state in
            guard !reported else { return }
            switch state {
            case .failed, .waiting(.posix(.ECONNREFUSED)):
                reported = true; refused.fulfill()
            case .ready:
                reported = true; XCTFail("stopped relay still accepts connections"); refused.fulfill()
            default: break
            }
        }
        next.start(queue: queue)
        await fulfillment(of: [refused], timeout: 5)
    }

    func testCancelledRelayCannotReopen() async {
        let relay = ScreenSharingRelay()
        relay.stop()
        do { _ = try await relay.start(); XCTFail("cancelled relay reopened") }
        catch { XCTAssertTrue(error is ScreenSharingRelay.Failure) }
    }
}
