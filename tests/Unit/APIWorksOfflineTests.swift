import XCTest
@testable import AgentSpaceCore

/// The API must work with **no network at all**.
///
/// The owner's requirement, in their words: 「我不希望必须联网才能用，需要在无网
/// 情况下也能用」. Loopback is the one address that satisfies it — it is created by
/// the kernel before any interface comes up, it survives Wi-Fi being off, and it
/// is never reachable from another machine, which is the correct default for a
/// control surface that can drive a desktop.
///
/// The first version of this feature defaulted to a virtual address that only
/// exists once a tunnel is up, so on a plane the API could not start at all.
/// These tests pin the corrected default and the reason for it.
final class APIWorksOfflineTests: XCTestCase {

    func testTheDefaultBindingIsLoopback() {
        let configuration = APIConfiguration(enabled: true)
        XCTAssertEqual(configuration.bindMode, "loopback",
                       "the default must be the address that exists without a network")
    }

    func testLoopbackIsTheHostThatAlwaysExists() {
        let network = VirtualNetworkConfig(
            pool: IPv4Network("100.64.0.0/24")!,
            hub: IPv4Address("100.64.0.1")!,
            controller: IPv4Address("100.64.0.2")!,
            local: IPv4Address("100.64.0.10")!)
        let policy = APIConfiguration(enabled: true, bindMode: "loopback", port: 8787)
            .policy(network: network)
        XCTAssertEqual(policy?.host, "127.0.0.1")
        XCTAssertEqual(policy?.port, 8787)
    }

    func testAVirtualBindingIsOptInAndNamesTheVirtualAddress() {
        let network = VirtualNetworkConfig(
            pool: IPv4Network("100.64.0.0/24")!,
            hub: IPv4Address("100.64.0.1")!,
            controller: IPv4Address("100.64.0.2")!,
            local: IPv4Address("100.64.0.10")!)
        let policy = APIConfiguration(enabled: true, bindMode: "virtualNetwork", port: 8787)
            .policy(network: network)
        XCTAssertEqual(policy?.host, "100.64.0.10")
    }

    func testAnUnknownBindModeIsRefusedRatherThanGuessed() {
        let network = VirtualNetworkConfig(
            pool: IPv4Network("100.64.0.0/24")!,
            hub: IPv4Address("100.64.0.1")!,
            controller: IPv4Address("100.64.0.2")!,
            local: IPv4Address("100.64.0.10")!)
        // A value from a newer build must not silently become loopback: that
        // would expose a service on a different interface than the one a person
        // configured.
        XCTAssertNil(APIConfiguration(enabled: true, bindMode: "carrier-pigeon").policy(network: network))
    }

    func testTheListenerStartsOnLoopbackWithNoNetworkConfiguration() throws {
        // A committed network configuration is not needed to listen on loopback,
        // which is the whole point: the API is useful before any tunnel exists.
        let server = APIServer(configuration: .init(
            policy: .loopback(port: 0),
            service: APIAgentService(root: NSTemporaryDirectory()),
            tokenPaths: VirtualNetworkPaths(root: NSTemporaryDirectory() + "/offline-\(UUID().uuidString)")))
        try server.start()
        defer { server.stop() }
        XCTAssertGreaterThan(server.boundPort, 0)
    }

    func testAVirtualAddressThatIsNotOnAnInterfaceIsRefused() {
        // The complement: a virtual binding must fail loudly when the tunnel is
        // down, rather than bind somewhere else or report success.
        let server = APIServer(configuration: .init(
            policy: .virtualNetwork(IPv4Address("100.64.0.10")!, port: 18799),
            service: APIAgentService(root: NSTemporaryDirectory()),
            isBindAddressAvailable: { _ in false }))
        XCTAssertThrowsError(try server.start())
    }

    func testTheOfflineDefaultDoesNotDependOnTheVirtualNetworkFiles() {
        // No configuration directory, no tokens, no tunnel: loopback still works.
        let root = NSTemporaryDirectory() + "/offline-empty-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        XCTAssertNil(VirtualNetworkStore(paths: VirtualNetworkPaths(root: root)).load())
        XCTAssertTrue(APITokenStore.load(paths: VirtualNetworkPaths(root: root)).tokens.isEmpty)

        let server = APIServer(configuration: .init(
            policy: .loopback(port: 0),
            service: APIAgentService(root: root),
            tokenPaths: VirtualNetworkPaths(root: root)))
        XCTAssertNoThrow(try server.start())
        server.stop()
    }
}
