import XCTest
import Foundation
import AgentSpaceCore

/// The API over a real socket, with real HTTP bytes.
///
/// The unit tests above prove the routing and authentication decisions; this
/// proves the part a client actually meets: that a listener binds only where it
/// is told, that an unauthenticated request is refused before any agent is
/// touched, and that a failure comes back as the documented JSON shape rather
/// than as a dropped connection.
final class APIServerLiveTests: XCTestCase {

    private var root = ""
    private var server: APIServer?

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "/agentspace-api-live-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(
            atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        server?.stop()
        server = nil
        try? FileManager.default.removeItem(atPath: root)
    }

    /// Start on an ephemeral port and read back the one the kernel chose.
    ///
    /// The earlier version probed for a free port, closed it, and rebound — which
    /// is a race against every other process on the machine, and it flaked the
    /// pre-existing `ScreenSharingRelayTests` by taking the port it had just
    /// released. Binding 0 through the product's own path removes the window.
    private func startServer(tokens: VirtualNetworkPaths) throws -> APIServer {
        let server = APIServer(configuration: .init(
            policy: .loopback(port: 0),
            service: APIAgentService(root: root),
            tokenPaths: tokens,
            networkStatus: { .obj(["connected": .bool(false), "pool": .string("100.64.0.0/24")]) }))
        try server.start()
        self.server = server
        XCTAssertGreaterThan(server.boundPort, 0, "the listener never reported a bound port")
        return server
    }

    /// One request over a fresh TCP connection; returns the whole response.
    private func sendRaw(port: Int, _ data: Data) throws -> Data {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw NSError(domain: "socket", code: 1) }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else {
            throw NSError(domain: "connect", code: Int(errno))
        }
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            response.append(contentsOf: buffer[0..<n])
        }
        return response
    }

    private func split(_ response: Data) -> (status: Int, headers: String, body: Data) {
        guard let range = response.range(of: Data("\r\n\r\n".utf8)) else {
            return (0, "", response)
        }
        let head = String(data: response[..<range.lowerBound], encoding: .utf8) ?? ""
        let status = Int(head.split(separator: " ").dropFirst().first.map(String.init) ?? "") ?? 0
        return (status, head, Data(response[range.upperBound...]))
    }

    /// Build a request from its lines, so the CRLFs are explicit and identical
    /// in every test. A multi-line Swift literal is easy to get subtly wrong
    /// (and a request with bare LFs is refused by the parser, correctly).
    private func http(_ lines: [String], body: String = "") -> Data {
        var text = lines.joined(separator: "\r\n") + "\r\n\r\n"
        text += body
        return Data(text.utf8)
    }

    // MARK: - Tests

    func testHealthIsServedWithoutAToken() throws {
        let port = try startServer(tokens: VirtualNetworkPaths(root: root)).boundPort
        let response = try sendRaw(port: port, http([
            "GET /healthz HTTP/1.1",
            "Host: 127.0.0.1",
        ]))
        let parsed = split(response)
        XCTAssertEqual(parsed.status, 200)
        let json = try JSONDecoder().decode(JSONValue.self, from: parsed.body)
        XCTAssertEqual(json["ok"]?.boolValue, true)
        XCTAssertEqual(json["agents"]?.intValue, 0)
    }

    func testEveryOtherEndpointRefusesAMissingToken() throws {
        let port = try startServer(tokens: VirtualNetworkPaths(root: root)).boundPort
        let id = UUID().uuidString
        for path in ["/v1/agents", "/v1/agents/\(id)/status", "/v1/network/status"] {
            let response = try sendRaw(port: port, http([
                "GET \(path) HTTP/1.1",
                "Host: x",
            ]))
            let parsed = split(response)
            XCTAssertEqual(parsed.status, 401, path)
            let json = try JSONDecoder().decode(JSONValue.self, from: parsed.body)
            XCTAssertEqual(json["error"]?["code"]?.stringValue, "UNAUTHORIZED", path)
        }
    }

    func testAWrongTokenIsRefusedAndARealOneIsAccepted() throws {
        let paths = VirtualNetworkPaths(root: root)
        let (_, secret) = try APITokenStore.create(name: "live", scopes: [.read], paths: paths)
        let port = try startServer(tokens: paths).boundPort

        let wrong = try sendRaw(port: port, http([
            "GET /v1/agents HTTP/1.1",
            "Host: x",
            "Authorization: Bearer not-the-secret",
        ]))
        XCTAssertEqual(split(wrong).status, 401)

        let accepted = try sendRaw(port: port, http([
            "GET /v1/agents HTTP/1.1",
            "Host: x",
            "Authorization: Bearer \(secret)",
        ]))
        XCTAssertEqual(split(accepted).status, 200)
    }

    func testATokenWithoutTheScopeIsForbiddenNotAccepted() throws {
        let paths = VirtualNetworkPaths(root: root)
        let (_, secret) = try APITokenStore.create(name: "reader", scopes: [.read], paths: paths)
        let port = try startServer(tokens: paths).boundPort
        let id = UUID().uuidString
        let response = try sendRaw(port: port, http([
            "POST /v1/agents/\(id)/input HTTP/1.1",
            "Host: x",
            "Authorization: Bearer \(secret)",
            "Content-Type: application/json",
            "Content-Length: 2",
        ], body: "{}"))
        let parsed = split(response)
        XCTAssertEqual(parsed.status, 403)
        let json = try JSONDecoder().decode(JSONValue.self, from: parsed.body)
        XCTAssertTrue(json["error"]?["message"]?.stringValue?.contains("control") ?? false)
    }

    func testAnUnknownAgentIs404AndNeverFallsBackToTheConsole() throws {
        let paths = VirtualNetworkPaths(root: root)
        let (_, secret) = try APITokenStore.create(name: "reader", scopes: [.read], paths: paths)
        let port = try startServer(tokens: paths).boundPort
        let response = try sendRaw(port: port, http([
            "GET /v1/agents/\(UUID().uuidString)/status HTTP/1.1",
            "Host: x",
            "Authorization: Bearer \(secret)",
        ]))
        let parsed = split(response)
        XCTAssertEqual(parsed.status, 404)
        let json = try JSONDecoder().decode(JSONValue.self, from: parsed.body)
        XCTAssertEqual(json["ok"]?.boolValue, false)
    }

    func testAnOfflineAgentIs503NotA200() throws {
        let paths = VirtualNetworkPaths(root: root)
        let (_, secret) = try APITokenStore.create(name: "reader", scopes: [.read], paths: paths)

        // A registered agent whose worker never started: the registry resolves,
        // the socket does not exist, and the answer must say so.
        let id = UUID()
        let account = AgentAccount(
            id: id, name: "Offline", username: "agentuse", uid: 503,
            state: .offline, createdAt: Date())
        var registry = SpaceRegistry.load(root: root)
        registry.spaces = [account]
        try registry.save(root: root)

        let port = try startServer(tokens: paths).boundPort
        let response = try sendRaw(port: port, http([
            "GET /v1/agents/\(id.uuidString)/status HTTP/1.1",
            "Host: x",
            "Authorization: Bearer \(secret)",
        ]))
        let parsed = split(response)
        XCTAssertEqual(parsed.status, 503,
                       "an agent whose worker is not running must not answer 200")
        let json = try JSONDecoder().decode(JSONValue.self, from: parsed.body)
        XCTAssertEqual(json["error"]?["code"]?.stringValue, "WORKER_OFFLINE")
        XCTAssertEqual(json["error"]?["recoverable"]?.boolValue, true)
    }

    func testTheServerRefusesToStartOnAWildcardOrForeignAddress() {
        for host in ["0.0.0.0", "8.8.8.8"] {
            let server = APIServer(configuration: .init(
                policy: APIListenPolicy(kind: .virtualNetwork(address: IPv4Address(host)!, port: 1)),
                service: APIAgentService(root: root)))
            XCTAssertThrowsError(try server.start(), host)
        }
    }
}
