import XCTest
import AgentSpaceCore
@testable import AgentSpaceApp

/// The flapping fix, pinned: a reconcile pass must KEEP a healthy,
/// identity-matching forwarder — the §404 review found every pass creating a
/// new one, tearing the listener down every other cycle.
final class PortMapPlanTests: XCTestCase {

    private func startedForwarder(external: UInt16, internalPort: UInt16,
                                  host: String = "127.0.0.1") throws -> PortForwarder {
        let forwarder = PortForwarder(
            accountID: UUID(), externalPort: external, internalPort: internalPort,
            listenHost: host)
        try forwarder.start(gate: { true })
        return forwarder
    }

    private func freePort() -> UInt16 {
        // Any free port below the handout range works for identity purposes.
        AgentPortAllocator.choose(
            account: UUID(), port: 8080,
            isFree: { !TCPProbe.answers(host: "127.0.0.1", port: $0, timeout: 0.3) }) ?? 28080
    }

    func testAHealthyIdentityMatchingForwarderIsKept() throws {
        let external = freePort()
        let mapping = PortMapping(account: UUID(), port: 8080, external: external)
        let forwarder = try startedForwarder(external: external, internalPort: 8080)
        defer { forwarder.stop() }

        let plan = PortMapRuntime.forwarderPlan(for: mapping, aliasAddress: nil, existing: [mapping.id: forwarder])
        XCTAssertTrue(plan.keepPrimary === forwarder, "a running forwarder on the right endpoint must be kept, not recreated")
        XCTAssertFalse(plan.recreatePrimary)
        XCTAssertNil(plan.keepAlias)
        XCTAssertFalse(plan.recreateAlias, "no alias address means no alias forwarder")
    }

    func testAStoppedOrStaleIdentityForwarderIsRecreated() throws {
        let account = UUID()
        let external = freePort()
        // Stopped: right identity, not running.
        let stopped = PortForwarder(accountID: account, externalPort: external, internalPort: 8080)
        var plan = PortMapRuntime.forwarderPlan(
            for: PortMapping(account: account, port: 8080, external: external),
            aliasAddress: nil, existing: [PortMapping(account: account, port: 8080, external: external).id: stopped])
        XCTAssertNil(plan.keepPrimary)
        XCTAssertTrue(plan.recreatePrimary)

        // Running, but the mapping was recreated with a different external
        // port under the same key — keeping it would serve the old endpoint.
        let wrongPort = try startedForwarder(external: freePort(), internalPort: 8080)
        defer { wrongPort.stop() }
        plan = PortMapRuntime.forwarderPlan(
            for: PortMapping(account: account, port: 8080, external: external),
            aliasAddress: nil, existing: [PortMapping(account: account, port: 8080, external: 9999).id: wrongPort])
        XCTAssertNil(plan.keepPrimary, "an endpoint mismatch must not be kept")
        XCTAssertTrue(plan.recreatePrimary)
    }

    func testAliasForwardersAreKeptOnlyOnTheirOwnAddressAndPort() throws {
        let account = UUID()
        let mapping = PortMapping(account: account, port: 8080, external: freePort())
        let alias = try XCTUnwrap(AgentSpaceCore.IPv4Address("127.100.203.5"))
        let key = mapping.id + "#alias"

        // An alias listener cannot be started without root (§400 row 1363),
        // so the alias keep condition is pinned by identity alone; the running
        // half of the condition is what the primary tests above pin.
        let matching = PortForwarder(
            accountID: account, externalPort: 8080, internalPort: 8080,
            listenHost: alias.description)
        let rightIdentity = PortMapRuntime.forwarderPlan(
            for: mapping, aliasAddress: alias, existing: [key: matching])
        XCTAssertNil(rightIdentity.keepAlias, "not running means recreate")
        XCTAssertTrue(rightIdentity.recreateAlias)

        // A forwarder on a different account address no longer matches at all.
        let otherAlias = try XCTUnwrap(AgentSpaceCore.IPv4Address("127.100.203.6"))
        let mismatch = PortMapRuntime.forwarderPlan(
            for: mapping, aliasAddress: otherAlias, existing: [key: matching])
        XCTAssertNil(mismatch.keepAlias)
        XCTAssertTrue(mismatch.recreateAlias)

        // No alias address on the interface means no alias forwarder at all.
        let none = PortMapRuntime.forwarderPlan(
            for: mapping, aliasAddress: nil, existing: [key: matching])
        XCTAssertNil(none.keepAlias)
        XCTAssertFalse(none.recreateAlias)
    }
}
