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

    /// macOS files the remembered Screen Sharing password under
    /// `127.0.0.1:<port>` — measured on 2026-10-21, the login keychain held one
    /// `ptcl = "vnc "` item per past attempt, each with a different random
    /// port. The port therefore has to come from the account, and the pinned
    /// value is the promise that a released build keeps honouring an already
    /// remembered password.
    func testTheSignInPortIsStableAndChosenPerAccount() {
        let id = UUID(uuidString: "6EA2FB6B-2B91-4BEE-B7D0-7E76CA28C9A1")!
        XCTAssertEqual(ScreenSharingRelay.stablePort(for: id), 47_949)
        XCTAssertEqual(ScreenSharingRelay.stablePort(for: id),
                       ScreenSharingRelay.stablePort(for: UUID(uuidString: "6EA2FB6B-2B91-4BEE-B7D0-7E76CA28C9A1")!))
        let ids = (1...6).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))! }
        let ports = ids.map(ScreenSharingRelay.stablePort(for:))
        XCTAssertEqual(Set(ports).count, ids.count, "accounts collided on \(ports)")
        XCTAssertTrue(ports.allSatisfy { (47_000...47_999).contains($0) },
                      "the reserved range stays out of the kernel's ephemeral ports")
    }

    func testTheRelayBindsTheAccountsPortWhenItIsFree() async throws {
        let port = try await freePort()
        let relay = ScreenSharingRelay()
        defer { relay.stop() }
        let bound = try await relay.start(preferredPort: port)
        XCTAssertEqual(bound, port, "an unused saved port must be the one the person's keychain knows")
    }

    /// A local process holding the port must not cost the sign-in; the sheet
    /// falls back to a fresh port and the controller logs that the remembered
    /// password cannot match this time.
    func testATakenPortFallsBackInsteadOfFailingTheSignIn() async throws {
        let queue = DispatchQueue(label: "AgentSpace.relay-test.occupant")
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let occupant = try NWListener(using: parameters)
        let ready = expectation(description: "occupant listening")
        occupant.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        occupant.newConnectionHandler = { $0.cancel() }
        occupant.start(queue: queue)
        defer { occupant.cancel() }
        await fulfillment(of: [ready], timeout: 5)
        let taken = try XCTUnwrap(occupant.port?.rawValue)
        let relay = ScreenSharingRelay()
        defer { relay.stop() }
        let bound = try await relay.start(preferredPort: taken)
        XCTAssertNotEqual(bound, taken)
    }

    private func freePort() async throws -> UInt16 {
        let queue = DispatchQueue(label: "AgentSpace.relay-test.free-port")
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let ready = expectation(description: "probe listener ready")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.newConnectionHandler = { $0.cancel() }
        listener.start(queue: queue)
        await fulfillment(of: [ready], timeout: 5)
        let port = try XCTUnwrap(listener.port?.rawValue)
        listener.cancel()
        return port
    }
}
