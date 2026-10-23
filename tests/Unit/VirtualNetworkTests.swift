import XCTest
@testable import AgentSpaceCore

/// The virtual-network rules, attacked from the outside.
///
/// Every assertion here is a claim about what a person can and cannot be given:
/// an address that is not in the pool, a duplicate, a pool that quietly eats a
/// physical LAN, or a "success" that was only a saved JSON file.
final class VirtualNetworkTests: XCTestCase {

    private func config(
        pool: String = "100.64.0.0/24",
        hub: String = "100.64.0.1",
        controller: String = "100.64.0.2",
        local: String = "100.64.0.10",
        port: Int = 8787,
        nodes: [VirtualNode] = []
    ) -> VirtualNetworkConfig {
        VirtualNetworkConfig(
            pool: IPv4Network(pool)!,
            hub: IPv4Address(hub)!,
            controller: IPv4Address(controller)!,
            local: IPv4Address(local)!,
            apiPort: port,
            nodes: nodes)
    }

    // MARK: - Parsing

    func testAddressParsingRejectsWhatTheTunnelCannotUse() {
        XCTAssertNotNil(IPv4Address("100.64.0.10"))
        for bad in ["", "100.64.0", "100.64.0.10.1", "0100.64.0.10", "100.64.0.256",
                    " 100.64.0.10", "100.64.0.10 ", "100.64.0.-1", "a.b.c.d", "100.64.0.10/24"] {
            XCTAssertNil(IPv4Address(bad), "\(bad) must not parse")
        }
    }

    func testAddressRoundTripsThroughOneSpelling() {
        XCTAssertEqual(IPv4Address("100.64.0.10")?.description, "100.64.0.10")
        XCTAssertEqual(IPv4Address(rawValue: 0x6440_000a).description, "100.64.0.10")
    }

    func testNetworkNormalisesToItsNetworkAddress() {
        XCTAssertEqual(IPv4Network("100.64.0.77/24")?.description, "100.64.0.0/24")
        XCTAssertEqual(IPv4Network("100.64.0.0/24")?.broadcast.description, "100.64.0.255")
        XCTAssertEqual(IPv4Network("100.64.0.0/24")?.firstHost.description, "100.64.0.1")
        XCTAssertEqual(IPv4Network("100.64.0.0/24")?.lastHost.description, "100.64.0.254")
        XCTAssertEqual(IPv4Network("100.64.0.0/24")?.hostCount, 254)
        XCTAssertNil(IPv4Network("100.64.0.0/33"))
        XCTAssertNil(IPv4Network("100.64.0.0"))
    }

    func testPrivateAndSharedRanges() {
        XCTAssertTrue(IPv4Address("10.1.2.3")!.isPrivate)
        XCTAssertTrue(IPv4Address("172.16.0.1")!.isPrivate)
        XCTAssertTrue(IPv4Address("172.31.255.254")!.isPrivate)
        XCTAssertFalse(IPv4Address("172.32.0.1")!.isPrivate)
        XCTAssertTrue(IPv4Address("192.168.1.1")!.isPrivate)
        XCTAssertTrue(IPv4Address("100.64.0.1")!.isSharedAddressSpace)
        XCTAssertFalse(IPv4Address("100.128.0.1")!.isSharedAddressSpace)
        XCTAssertFalse(IPv4Address("8.8.8.8")!.isPrivate)
        XCTAssertTrue(IPv4Address("127.0.0.1")!.isLoopback)
        XCTAssertTrue(IPv4Address("169.254.1.1")!.isLinkLocal)
        XCTAssertTrue(IPv4Address("224.0.0.1")!.isMulticast)
    }

    // MARK: - The happy path

    func testDefaultLayoutIsInsideThePoolAndValid() {
        let pool = IPv4Network("100.64.7.0/24")!
        let layout = VirtualAddressAllocator.defaultLayout(pool: pool)
        XCTAssertEqual(layout.hub.description, "100.64.7.1")
        XCTAssertEqual(layout.controller.description, "100.64.7.2")
        XCTAssertEqual(layout.local.description, "100.64.7.11")

        let candidate = VirtualNetworkConfig(
            pool: pool, hub: layout.hub, controller: layout.controller, local: layout.local)
        let validation = VirtualNetworkValidator.validate(
            candidate, local: LocalNetworkSnapshot(complete: true))
        XCTAssertTrue(validation.isValid, "\(validation.conflicts)")
    }

    func testHostRoutesArePreciseNotTheWholePool() {
        let candidate = config(nodes: [
            VirtualNode(name: "Laptop", role: .node, address: IPv4Address("100.64.0.11")!),
        ])
        // Four addresses, four /32 routes — never one route for the /24. A
        // single pool route would capture traffic to a physical LAN that
        // happens to use 100.64.0.0/24.
        XCTAssertEqual(candidate.hostRoutes.count, 4)
        XCTAssertEqual(Set(candidate.hostRoutes.map(\.description)),
                       ["100.64.0.1", "100.64.0.2", "100.64.0.10", "100.64.0.11"])
    }

    // MARK: - Refusals

    func testAddressOutsideThePoolIsRefused() {
        let validation = VirtualNetworkValidator.validate(config(local: "100.64.1.10"))
        XCTAssertTrue(validation.conflicts.contains { $0.kind == .addressOutsidePool })
        XCTAssertFalse(validation.isValid)
    }

    func testNetworkAndBroadcastAddressesCannotBeAssigned() {
        XCTAssertTrue(VirtualNetworkValidator.validate(config(hub: "100.64.0.0"))
            .conflicts.contains { $0.kind == .addressReserved })
        XCTAssertTrue(VirtualNetworkValidator.validate(config(controller: "100.64.0.255"))
            .conflicts.contains { $0.kind == .addressReserved })
    }

    func testDuplicateAddressesAreRefusedAcrossRolesAndNodes() {
        let duplicate = config(nodes: [
            VirtualNode(name: "Laptop", role: .node, address: IPv4Address("100.64.0.10")!),
        ])
        let validation = VirtualNetworkValidator.validate(duplicate)
        XCTAssertTrue(validation.conflicts.contains { $0.kind == .duplicateAddress })
        XCTAssertFalse(validation.isValid)

        let roles = config(controller: "100.64.0.1")
        XCTAssertTrue(VirtualNetworkValidator.validate(roles)
            .conflicts.contains { $0.kind == .duplicateAddress })
    }

    func testPoolTooSmallForTheAssignedNodes() {
        // /29 has six usable addresses; seven assigned nodes cannot fit.
        var candidate = config(pool: "100.64.0.0/29", hub: "100.64.0.1",
                               controller: "100.64.0.2", local: "100.64.0.3")
        candidate.nodes = (1...5).map {
            VirtualNode(name: "n\($0)", role: .node, address: IPv4Address(rawValue: 0x6440_0003 + UInt32($0)))
        }
        let validation = VirtualNetworkValidator.validate(candidate)
        XCTAssertTrue(validation.conflicts.contains { $0.kind == .poolTooSmall })
    }

    func testTooNarrowAndTooWidePoolsAreRefused() {
        XCTAssertTrue(VirtualNetworkValidator.validate(config(pool: "100.64.0.0/30", hub: "100.64.0.1",
                                                             controller: "100.64.0.2", local: "100.64.0.1"))
            .conflicts.contains { $0.kind == .poolTooSmall })
        XCTAssertTrue(VirtualNetworkValidator.validate(config(pool: "100.0.0.0/8", hub: "100.0.0.1",
                                                             controller: "100.0.0.2", local: "100.0.0.3"))
            .conflicts.contains { $0.kind == .poolTooSmall })
    }

    func testPublicPoolNeedsTheAdvancedOverride() {
        let candidate = config(pool: "203.0.113.0/24", hub: "203.0.113.1",
                               controller: "203.0.113.2", local: "203.0.113.10")
        let refused = VirtualNetworkValidator.validate(candidate)
        XCTAssertFalse(refused.isValid)
        XCTAssertTrue(refused.overrideable.contains { $0.kind == .poolNotPrivate })

        var allowed = candidate
        allowed.allowNonPrivatePool = true
        XCTAssertTrue(VirtualNetworkValidator.validate(allowed).isValid)
    }

    func testPortOutsideTheAllowedRangeIsRefused() {
        XCTAssertTrue(VirtualNetworkValidator.validate(config(port: 80))
            .conflicts.contains { $0.kind == .invalidPort })
        XCTAssertTrue(VirtualNetworkValidator.validate(config(port: 70000))
            .conflicts.contains { $0.kind == .invalidPort })
        XCTAssertTrue(VirtualNetworkValidator.validate(config(port: 8787)).isValid)
    }

    // MARK: - Local overlap

    func testOverlappingLocalNetworkIsOverrideableButIdenticalAddressIsNot() {
        let local = LocalNetworkSnapshot(
            addresses: [IPv4Address("192.168.1.5")!],
            interfaceNetworks: [IPv4Network("192.168.1.0/24")!],
            routes: [IPv4Network("192.168.1.0/24")!])
        let overlapping = config(pool: "192.168.1.0/24", hub: "192.168.1.1",
                                 controller: "192.168.1.2", local: "192.168.1.10")
        let refused = VirtualNetworkValidator.validate(overlapping, local: local)
        XCTAssertFalse(refused.isValid)
        XCTAssertTrue(refused.overrideable.contains { $0.kind == .overlapsLocalNetwork })

        // The override is only for the subnet. If this Mac already holds the
        // exact address, no override is offered — a host route cannot make two
        // identical addresses work.
        let colliding = LocalNetworkSnapshot(
            addresses: [IPv4Address("192.168.1.10")!],
            interfaceNetworks: [IPv4Network("192.168.1.0/24")!],
            routes: [IPv4Network("192.168.1.10/32")!])
        let blocked = VirtualNetworkValidator.validate(overlapping, local: colliding)
        XCTAssertTrue(blocked.conflicts.contains { $0.kind == .addressInUseLocally })
        var overridden = overlapping
        overridden.allowOverlap = true
        let stillBlocked = VirtualNetworkValidator.validate(overridden, local: colliding)
        XCTAssertFalse(stillBlocked.isValid,
                       "an identical local address must stay refused even with the overlap override")
    }

    func testOverlapOverrideAppliesWhenOnlyTheSubnetCollides() {
        let local = LocalNetworkSnapshot(
            addresses: [IPv4Address("10.0.0.5")!],
            interfaceNetworks: [IPv4Network("10.0.0.0/8")!],
            routes: [IPv4Network("10.0.0.0/8")!])
        var candidate = config(pool: "10.20.30.0/24", hub: "10.20.30.1",
                               controller: "10.20.30.2", local: "10.20.30.10")
        XCTAssertFalse(VirtualNetworkValidator.validate(candidate, local: local).isValid)
        candidate.allowOverlap = true
        XCTAssertTrue(VirtualNetworkValidator.validate(candidate, local: local).isValid)
    }

    func testUnknownLocalSnapshotIsReportedAsUnverifiedNotAsClean() {
        let validation = VirtualNetworkValidator.validate(config(local: "100.64.0.10"))
        XCTAssertTrue(validation.isValid)
        XCTAssertTrue(validation.hasUnverifiedConflicts)
        XCTAssertTrue(validation.conflicts.contains {
            $0.kind == .overlapsLocalNetwork && $0.severity == .warning
        })
    }

    func testEveryConflictCarriesARemediation() {
        let validation = VirtualNetworkValidator.validate(
            config(pool: "203.0.113.0/24", hub: "203.0.113.1",
                   controller: "203.0.113.2", local: "203.0.113.2", port: 1),
            local: .unknown)
        XCTAssertFalse(validation.conflicts.isEmpty)
        for conflict in validation.conflicts {
            XCTAssertFalse(conflict.remediation.isEmpty,
                           "\(conflict.kind) has no remediation, so the UI can only show a dead end")
            XCTAssertFalse(conflict.detail.isEmpty)
        }
    }

    // MARK: - Node keys

    func testNodeWithoutAKeyIsAWarningAndAMalformedKeyIsBlocking() {
        let missing = config(nodes: [
            VirtualNode(name: "Laptop", role: .node, address: IPv4Address("100.64.0.11")!),
        ])
        XCTAssertTrue(VirtualNetworkValidator.validate(missing).isValid)
        XCTAssertTrue(VirtualNetworkValidator.validate(missing).warnings.contains {
            $0.kind == .missingNodeKey
        })

        let malformed = config(nodes: [
            VirtualNode(name: "Laptop", role: .node, address: IPv4Address("100.64.0.11")!,
                        publicKey: "not-a-key"),
        ])
        XCTAssertFalse(VirtualNetworkValidator.validate(malformed).isValid)
    }

    func testWireGuardKeyShape() {
        let valid = Data(repeating: 7, count: 32).base64EncodedString()
        XCTAssertTrue(WireGuardKey.isValidPublicKey(valid))
        XCTAssertFalse(WireGuardKey.isValidPublicKey(""))
        XCTAssertFalse(WireGuardKey.isValidPublicKey("AAAA"))
        XCTAssertFalse(WireGuardKey.isValidPublicKey(Data(repeating: 1, count: 31).base64EncodedString()))
    }

    // MARK: - Allocation

    func testPoolChoiceIsDeterministicForASeedAndAvoidsLocalNetworks() {
        let local = LocalNetworkSnapshot(
            interfaceNetworks: [IPv4Network("192.168.1.0/24")!],
            routes: [])
        let first = VirtualAddressAllocator.choosePool(seed: 42, excluding: local)
        let second = VirtualAddressAllocator.choosePool(seed: 42, excluding: local)
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.overlaps(IPv4Network("192.168.1.0/24")!))
        XCTAssertEqual(first.prefixLength, 24)
        XCTAssertTrue(first.firstHost.isPrivate || first.firstHost.isSharedAddressSpace)
    }

    func testDifferentSeedsDoNotAllProduceTheSamePool() {
        let local = LocalNetworkSnapshot(complete: true)
        let pools = Set((0..<32).map { VirtualAddressAllocator.choosePool(seed: UInt64($0), excluding: local) })
        XCTAssertGreaterThan(pools.count, 1, "every installation would claim the same pool")
    }

    func testNextFreeAddressSkipsRolesAndExistingNodes() {
        var candidate = config()
        XCTAssertEqual(VirtualAddressAllocator.nextFreeAddress(in: candidate)?.description, "100.64.0.3")
        candidate.nodes = [
            VirtualNode(name: "a", role: .node, address: IPv4Address("100.64.0.3")!),
            VirtualNode(name: "b", role: .node, address: IPv4Address("100.64.0.4")!),
        ]
        XCTAssertEqual(VirtualAddressAllocator.nextFreeAddress(in: candidate)?.description, "100.64.0.5")
    }

    func testNextFreeAddressReturnsNilWhenThePoolIsFull() {
        let candidate = config(pool: "100.64.0.0/29", hub: "100.64.0.1",
                               controller: "100.64.0.2", local: "100.64.0.3",
                               nodes: (4...6).map {
                                   VirtualNode(name: "n\($0)", role: .node,
                                               address: IPv4Address(rawValue: 0x6440_0000 + UInt32($0)))
                               })
        XCTAssertNil(VirtualAddressAllocator.nextFreeAddress(in: candidate))
    }

    // MARK: - Store

    func testCommitKeepsThePreviousVersionForRollback() throws {
        let root = NSTemporaryDirectory() + "/agentspace-net-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = VirtualNetworkStore(paths: VirtualNetworkPaths(root: root))

        var first = config()
        first.version = 1
        try store.commit(first)

        var second = config(local: "100.64.0.20")
        second.version = 2
        try store.commit(second)

        XCTAssertEqual(store.load()?.version, 2)
        XCTAssertEqual(store.loadPrevious()?.version, 1)

        let restored = try store.restorePrevious()
        XCTAssertEqual(restored?.version, 1)
        XCTAssertEqual(store.load()?.version, 1)
        XCTAssertNil(store.loadPrevious(), "a second restore must not resurrect a stale file")
    }

    func testCandidateIsWrittenWithoutCommittingIt() throws {
        let root = NSTemporaryDirectory() + "/agentspace-net-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = VirtualNetworkStore(paths: VirtualNetworkPaths(root: root))
        var committed = config()
        committed.version = 1
        try store.commit(committed)

        var candidate = config(local: "100.64.0.30")
        candidate.version = 2
        try store.saveCandidate(candidate)

        XCTAssertEqual(store.load()?.version, 1, "writing a candidate must not move the committed version")
        XCTAssertEqual(store.loadCandidate(version: 2)?.local.description, "100.64.0.30")
    }

    // MARK: - Migration plan

    func testMigrationPlanNamesEveryAddressChangeAndOfflineNode() {
        let current = config()
        var candidate = config(local: "100.64.0.20")
        candidate.version = 2
        candidate.nodes = [
            VirtualNode(id: "laptop", name: "Laptop", role: .node,
                        address: IPv4Address("100.64.0.11")!),
        ]
        let plan = NetworkMigrationPlan.plan(from: current, to: candidate, offlineNodes: ["laptop"])
        XCTAssertEqual(plan.fromVersion, 1)
        XCTAssertEqual(plan.toVersion, 2)
        XCTAssertEqual(plan.addressChanges.map(\.node), ["This Mac"])
        XCTAssertEqual(plan.offlineNodes, ["Laptop"],
                       "an offline node must be named, never silently reported as migrated")
        XCTAssertEqual(plan.steps.first, .validateCandidate)
        XCTAssertEqual(plan.steps.last, .cleanupOldAddresses)
        XCTAssertFalse(plan.isNoOp)
    }

    func testUnchangedConfigurationProducesANoOpPlan() {
        let plan = NetworkMigrationPlan.plan(from: config(), to: config(), offlineNodes: [])
        XCTAssertTrue(plan.isNoOp)
        XCTAssertTrue(plan.addressChanges.isEmpty)
    }

    // MARK: - Round trip

    func testConfigurationSurvivesAStoreRoundTrip() throws {
        let root = NSTemporaryDirectory() + "/agentspace-net-rt-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = VirtualNetworkStore(paths: VirtualNetworkPaths(root: root))
        let candidate = config(nodes: [
            VirtualNode(name: "Laptop", role: .node,
                        address: IPv4Address("100.64.0.11")!,
                        publicKey: Data(repeating: 9, count: 32).base64EncodedString(),
                        lastKnownNetworks: [IPv4Network("192.168.1.0/24")!]),
        ])
        try store.commit(candidate)
        let decoded = try XCTUnwrap(store.load())
        XCTAssertEqual(decoded.pool.description, "100.64.0.0/24")
        XCTAssertEqual(decoded.local.description, "100.64.0.10")
        XCTAssertEqual(decoded.nodes.first?.publicKey, candidate.nodes.first?.publicKey)
        XCTAssertEqual(decoded.nodes.first?.lastKnownNetworks, candidate.nodes.first?.lastKnownNetworks)
        XCTAssertEqual(decoded.hostRoutes, candidate.hostRoutes)
        // Second precision, deliberately: the store uses the same `.iso8601`
        // strategy as the Space registry, so one date format is not two.
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970,
                       candidate.createdAt.timeIntervalSince1970, accuracy: 1.0)
    }
}
