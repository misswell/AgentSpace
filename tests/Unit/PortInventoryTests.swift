import XCTest
import Network
@testable import AgentSpaceCore

/// `PortInventory`: what lsof's rows mean, and what the live collector can
/// honestly report about this account's own listeners.
final class PortInventoryTests: XCTestCase {

    func testParsesTheShapesLsofActuallyPrints() {
        let text = """
        COMMAND   PID USER   FD   TYPE   DEVICE SIZE/OFF NODE NAME
        node    12345  agent   20u  IPv4 0xabc123      0t0  TCP 127.0.0.1:3000 (LISTEN)
        python  12346  agent   21u  IPv6 0xabc124      0t0  TCP [::1]:5000 (LISTEN)
        uvicorn 12347  agent   22u  IPv6 0xabc125      0t0  TCP *:8000 (LISTEN)
        launchd 12348  agent   23u  IPv4 0xabc126      0t0  TCP 0.0.0.0:7000 (LISTEN)
        """
        let ports = PortInventory.parse(lsofOutput: text)
        XCTAssertEqual(ports.map(\.port), [3000, 5000, 7000, 8000])
        XCTAssertEqual(ports[0].address, "127.0.0.1")
        XCTAssertEqual(ports[1].address, "[::1]")
        XCTAssertEqual(ports[2].address, "0.0.0.0")
        XCTAssertEqual(ports[3].address, "*")
        XCTAssertEqual(ports[0].process, "node")
        XCTAssertEqual(ports[0].pid, 12345)
    }

    func testOnlyListeningRowsCount() {
        let text = """
        COMMAND   PID USER   FD   TYPE   DEVICE SIZE/OFF NODE NAME
        curl    22222  agent   10u  IPv4 0x1      0t0  TCP 127.0.0.1:54321->127.0.0.1:3000 (ESTABLISHED)
        node    12345  agent   20u  IPv4 0x2      0t0  TCP 127.0.0.1:3001 (LISTEN)
        HEADER LINE WITHOUT COLUMNS
        """
        let ports = PortInventory.parse(lsofOutput: text)
        XCTAssertEqual(ports.map(\.port), [3001])
    }

    func testOnePortPerProcessEvenWithSeveralFileDescriptors() {
        let text = """
        COMMAND PID USER  FD  TYPE DEVICE SIZE/OFF NODE NAME
        node 1 u  4u  IPv4 0x1 0t0  TCP 127.0.0.1:3000 (LISTEN)
        node 1 u  5u  IPv4 0x2 0t0  TCP 127.0.0.1:3000 (LISTEN)
        node 1 u  6u  IPv6 0x3 0t0  TCP [::1]:3000 (LISTEN)
        """
        let ports = PortInventory.parse(lsofOutput: text)
        XCTAssertEqual(ports.count, 2, "same process, two distinct addresses")
        XCTAssertEqual(Set(ports.map(\.address)), ["127.0.0.1", "[::1]"])
    }

    func testLoopbackCoverageIsDecidedByTheBindAddress() {
        XCTAssertTrue(ListeningPort(address: "127.0.0.1", port: 1).coversLoopback)
        XCTAssertTrue(ListeningPort(address: "0.0.0.0", port: 1).coversLoopback)
        XCTAssertTrue(ListeningPort(address: "*", port: 1).coversLoopback)
        XCTAssertTrue(ListeningPort(address: "[::]", port: 1).coversLoopback)
        XCTAssertFalse(ListeningPort(address: "[::1]", port: 1).coversLoopback,
                       "IPv6-only loopback is not reachable through an IPv4 alias")
        XCTAssertFalse(ListeningPort(address: "192.168.1.5", port: 1).coversLoopback)
    }

    func testTheLiveCollectorSeesThisProcessOwnListener() throws {
        // A listener this test process owns: the collector, run as this uid,
        // must attribute it — which is the whole basis for the ownership gate.
        // The listener mirrors the shape every other passing socket test in
        // this suite uses: endpoint 127.0.0.1 with an any port, and the state
        // handler signalling on ready *and* failed so a refusal is heard, not
        // waited out.
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "portmap-tests.inventory")
        var failure: String?
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.signal()
            case .failed(let error): failure = "\(error)"; ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { $0.cancel() }
        listener.start(queue: queue)
        XCTAssertEqual(ready.wait(timeout: .now() + 5), .success)
        XCTAssertNil(failure)
        let port = try XCTUnwrap(listener.port?.rawValue)
        defer { listener.cancel() }

        let ports = PortInventory.collect()
        let mine = ports.first { $0.port == port }
        XCTAssertNotNil(mine, "this test's own listener was not attributed by lsof")
        XCTAssertEqual(mine?.address, "127.0.0.1")
        XCTAssertNotNil(mine?.process, "the process name should be attributed for our own uid")
    }
}
