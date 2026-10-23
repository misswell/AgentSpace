import XCTest
@testable import AgentSpaceCore

/// The local-network probe, tested against recorded command output rather than a
/// live machine.
///
/// `netstat` text is the part that changes between macOS releases, and a parser
/// that silently drops a route would report a clean conflict check that never
/// looked at that route. So the parsing is a pure function with the exact shapes
/// this Mac produces.
final class LocalNetworkProbeTests: XCTestCase {

    func testParsesSubnetAndHostRoutes() {
        let text = """
        Routing tables

        Internet:
        Destination        Gateway            Flags        Netif Expire
        default            192.168.1.1        UGScg          en0
        127                127.0.0.1          UCS            lo0
        127.0.0.1          127.0.0.1          UH             lo0
        169.254            link#12            UCS            en0      !
        192.168.1          link#12            UCS            en0      !
        192.168.1.1/32     8a:1b:2c:3d:4e:5f  UHLWIir       en0   1188
        100.64.0.10/32     100.64.0.1         UGSc           utun7
        """
        let networks = LocalNetworkProbe.parseRoutes(text)
        XCTAssertTrue(networks.contains(IPv4Network("192.168.1.0/24")!))
        XCTAssertTrue(networks.contains(IPv4Network("192.168.1.1/32")!))
        XCTAssertTrue(networks.contains(IPv4Network("100.64.0.10/32")!))
        XCTAssertTrue(networks.contains(IPv4Network("127.0.0.0/8")!))
        // A default route covers everything and must never be reported as an
        // overlapping network.
        XCTAssertFalse(networks.contains { $0.prefixLength == 0 })
    }

    func testHeaderAndGarbageLinesAreIgnored() {
        XCTAssertTrue(LocalNetworkProbe.parseRoutes("Destination Gateway Flags\n").isEmpty)
        XCTAssertTrue(LocalNetworkProbe.parseRoutes("").isEmpty)
        XCTAssertTrue(LocalNetworkProbe.parseRoutes("not a route\n").isEmpty)
        XCTAssertTrue(LocalNetworkProbe.parseRoutes("300.1.1.1/24 link#1\n").isEmpty)
    }

    func testRoutesAreDeduplicated() {
        let text = """
        192.168.1          link#12            UCS            en0
        192.168.1          link#12            UCS            en0
        """
        XCTAssertEqual(LocalNetworkProbe.parseRoutes(text).count, 1)
    }

    func testPrefixLengthRequiresAContiguousMask() {
        XCTAssertEqual(LocalNetworkProbe.prefixLength(0xffff_ff00), 24)
        XCTAssertEqual(LocalNetworkProbe.prefixLength(0xffff_0000), 16)
        XCTAssertEqual(LocalNetworkProbe.prefixLength(0xffff_ffff), 32)
        XCTAssertEqual(LocalNetworkProbe.prefixLength(0), 0)
        // A hole (255.0.255.0) is not a network.
        XCTAssertNil(LocalNetworkProbe.prefixLength(0xff00_ff00))
    }

    func testLiveSnapshotIsReadableOnThisMac() throws {
        let snapshot = LocalNetworkProbe.snapshot()
        XCTAssertTrue(snapshot.complete, "the probe could not read this Mac's interfaces and routes")
        XCTAssertFalse(snapshot.addresses.isEmpty, "no IPv4 address on a machine that is on the network")
        // Loopback is always present, and it must be visible rather than filtered:
        // the validator needs it to refuse a pool that would claim 127/8.
        XCTAssertTrue(snapshot.addresses.contains { $0.isLoopback })
    }

    func testLiveSnapshotNeverReportsADefaultRouteAsANetwork() throws {
        let snapshot = LocalNetworkProbe.snapshot()
        XCTAssertFalse(snapshot.routes.contains { $0.prefixLength == 0 })
    }
}
