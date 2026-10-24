import XCTest
@testable import AgentSpaceCore

/// The generated external ports and the persisted mapping list.
final class PortMapTests: XCTestCase {

    private var tempRoot: String = ""

    override func setUpWithError() throws {
        tempRoot = NSTemporaryDirectory() + "/portmap-tests-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: tempRoot)
    }

    private var paths: VirtualNetworkPaths { VirtualNetworkPaths(root: tempRoot) }

    // MARK: The allocator

    func testCandidatesStayInsideTheHandoutRange() {
        for _ in 0..<200 {
            let account = UUID()
            let port = UInt16.random(in: 1...65_535)
            for candidate in AgentPortAllocator.candidates(account: account, port: port) {
                XCTAssertTrue(AgentPortAllocator.range.contains(candidate),
                              "\(candidate) outside \(AgentPortAllocator.range)")
            }
        }
    }

    func testCandidatesAreDeterministicAndDistinct() {
        let account = UUID()
        let port: UInt16 = 3000
        let first = AgentPortAllocator.candidates(account: account, port: port)
        let second = AgentPortAllocator.candidates(account: account, port: port)
        XCTAssertEqual(first, second, "the CLI, the app and the tests must walk one order")
        XCTAssertEqual(Set(first).count, first.count, "a salted rehash must not revisit a port")
        XCTAssertGreaterThan(first.count, 16, "the order must outlive a busy stretch")
    }

    func testTheOrderAbsorbsFirstChoiceCollisions() {
        // First choices collide by birthday over a 2,000-slot range — that is
        // expected, not a defect. What matters is the allocation *resolving*
        // them: walking the same deterministic order with the taken set, many
        // mappings must all end up with distinct ports.
        var taken = Set<UInt16>()
        var handed: [UInt16] = []
        for _ in 0..<300 {
            let account = UUID()
            let port = UInt16.random(in: 1024...65_535)
            let external = AgentPortAllocator.choose(
                account: account, port: port, isFree: { !taken.contains($0) })
            XCTAssertNotNil(external, "the order ran dry before 300 mappings")
            taken.insert(external!)
            handed.append(external!)
        }
        XCTAssertEqual(Set(handed).count, handed.count,
                       "two mappings were handed the same port despite the taken set")
    }

    func testChooseHonoursTheCallersNotionOfFree() {
        let account = UUID()
        let port: UInt16 = 3000
        let order = AgentPortAllocator.candidates(account: account, port: port)
        // Everything busy → nil; the second candidate free → exactly that one.
        XCTAssertNil(AgentPortAllocator.choose(account: account, port: port, isFree: { _ in false }))
        XCTAssertEqual(
            AgentPortAllocator.choose(account: account, port: port, isFree: { $0 == order[1] }),
            order[1])
    }

    /// The rules for a person-chosen port (`map 8080 28080`): outside the
    /// generated range, above the privileged floor, and never the service's
    /// own port on 127.0.0.1.
    func testManualPortChoicesAreValidated() {
        XCTAssertNil(AgentPortAllocator.manualPortProblem(28080, internal: 8080))
        XCTAssertNotNil(AgentPortAllocator.manualPortProblem(8080, internal: 8080),
                        "the service's own port is held by the service itself")
        XCTAssertNotNil(AgentPortAllocator.manualPortProblem(80, internal: 8080),
                        "ports below 1024 are the system's")
        XCTAssertNotNil(AgentPortAllocator.manualPortProblem(45_123, internal: 8080),
                        "the generated range is the generator's, not a menu")
    }

    // MARK: The store

    func testTheStoreRoundTripsMappings() throws {
        let store = PortMapStore(paths: paths)
        let account = UUID()
        XCTAssertTrue(try store.add(account: account, port: 3000, external: 45_000))
        // The same (account, port) again is a no-op even with a new external.
        XCTAssertFalse(try store.add(account: account, port: 3000, external: 45_001))
        // Another account's port 3000 is a different mapping, but not one that
        // may steal the first one's external port.
        XCTAssertTrue(try store.add(account: UUID(), port: 3000, external: 45_100))
        XCTAssertFalse(try store.add(account: account, port: 8787, external: 45_000),
                       "two mappings must never share an external port")
        XCTAssertTrue(try store.add(account: account, port: 8787, external: 45_200))

        let reloaded = PortMapStore(paths: paths).load()
        XCTAssertEqual(reloaded.mappings.count, 3)
        XCTAssertEqual(reloaded.version, 1)
        XCTAssertEqual(
            PortMapStore(paths: paths).mappings(account: account).map(\.port).sorted(),
            [3000, 8787])
        XCTAssertEqual(store.externalPortsInUse(), [45_000, 45_100, 45_200])

        XCTAssertTrue(try store.remove(account: account, port: 3000))
        XCTAssertFalse(try store.remove(account: account, port: 3000), "already gone")
        XCTAssertEqual(PortMapStore(paths: paths).load().mappings.count, 2)
        // The freed external port is free again.
        XCTAssertEqual(store.externalPortsInUse(), [45_100, 45_200])
    }

    func testAMissingOrCorruptFileIsAnEmptyMapNotACrash() throws {
        XCTAssertEqual(PortMapStore(paths: paths).load().mappings.count, 0)
        try FileManager.default.createDirectory(atPath: paths.directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: URL(fileURLWithPath: paths.portMapPath))
        XCTAssertEqual(PortMapStore(paths: paths).load().mappings.count, 0)
        // And the broken bytes do not trap the next write.
        XCTAssertTrue(try PortMapStore(paths: paths).add(account: UUID(), port: 4000, external: 45_300))
        XCTAssertEqual(PortMapStore(paths: paths).load().mappings.count, 1)
    }

    func testTheStoreLivesUnderTheNetworkDirectory() {
        XCTAssertEqual(paths.portMapPath, tempRoot + "/Network/port-map.json")
    }

    func testAMappingNamesItsEndpoint() {
        let mapping = PortMapping(account: UUID(), port: 3000, external: 45_013)
        XCTAssertEqual(mapping.endpoint, "127.0.0.1:45013")
        XCTAssertEqual(mapping.id, "\(mapping.account.uuidString.lowercased())/3000")
    }
}
