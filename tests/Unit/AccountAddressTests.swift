import XCTest
@testable import AgentSpaceCore

/// The fixed per-account address: the deterministic allocator, the choice
/// record, and the helper's own validation of the operation that serves it.
final class AccountAddressTests: XCTestCase {

    private var tempRoot: String = ""

    override func setUpWithError() throws {
        tempRoot = NSTemporaryDirectory() + "/account-address-tests-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: tempRoot)
    }

    private var paths: VirtualNetworkPaths { VirtualNetworkPaths(root: tempRoot) }

    // MARK: The allocator

    func testEveryAccountLandsInsideTheRangeAndKeepsClearOfItsEdges() {
        for _ in 0..<200 {
            let id = UUID()
            let address = AgentLoopbackAddress.address(for: id)
            let table = AgentLoopbackAddress.addresses(for: [id])
            XCTAssertEqual(address, table[id])
            XCTAssertTrue(AgentLoopbackAddress.isAlias(address!), "outside 127.100/16: \(address!)")
            let low = address!.rawValue & 0xffff
            XCTAssertNotEqual(low, 0, "the .0.0 spelling is never handed out")
            XCTAssertNotEqual(low, 0xffff, "the .255.255 spelling is never handed out")
        }
    }

    func testTheTableIsStableRegardlessOfOrderAndDuplicates() {
        let accounts = (0..<12).map { _ in UUID() }
        XCTAssertEqual(
            AgentLoopbackAddress.addresses(for: accounts),
            AgentLoopbackAddress.addresses(for: accounts.reversed()))
        XCTAssertEqual(
            AgentLoopbackAddress.addresses(for: accounts),
            AgentLoopbackAddress.addresses(for: accounts + accounts))
    }

    func testAccountsNeverShareAnAddress() {
        let accounts = (0..<500).map { _ in UUID() }
        let table = AgentLoopbackAddress.addresses(for: accounts)
        XCTAssertEqual(table.count, accounts.count)
        XCTAssertEqual(Set(table.values.map(\.rawValue)).count, accounts.count)
    }

    func testOneAccountComputesItsOwnTableEntryAmongItsNeighbours() {
        let a = UUID(), b = UUID(), c = UUID()
        let table = AgentLoopbackAddress.addresses(for: [a, b, c])
        XCTAssertEqual(AgentLoopbackAddress.address(for: b, among: [a, c]), table[b])
    }

    // MARK: The helper's own gate

    /// `HelperValidation` is the security boundary, so the alias operation is
    /// attacked here like every other one: everything outside the feature's
    /// own /16 must be refused, and the two edge addresses with it.
    func testTheHelperRefusesEveryAddressOutsideItsOwnRange() {
        let accounts = ["_agentspace_a1b2c3"]
        let outside = [
            "127.0.0.1", "127.0.0.2", "127.1.2.3", "127.101.0.1", "127.99.255.255",
            "10.0.0.1", "192.168.1.1", "8.8.8.8", "0.0.0.0", "255.255.255.255",
        ]
        for address in outside {
            for operation in [HelperOperation.addLoopbackAlias, .removeLoopbackAlias] {
                let request = HelperRequest(operation: operation, address: address)
                let problem = HelperValidation.validate(request, existingAccounts: Set(accounts))
                XCTAssertNotNil(problem, "\(operation.rawValue) accepted \(address)")
                XCTAssertTrue(problem!.message.contains("127.100.0.0/16"),
                              "the refusal should say what the operation's whole world is")
            }
        }
        // The range's own first and last addresses are refused too — the
        // allocator never hands them out and root must not be asked for them.
        for address in ["127.100.0.0", "127.100.255.255"] {
            XCTAssertNotNil(HelperValidation.validate(
                HelperRequest(operation: .addLoopbackAlias, address: address),
                existingAccounts: Set(accounts)), "\(address) is never handed out")
        }
        // Malformed spellings never reach the range check at all.
        for address in ["127.100.1.2.3", "127.100.1", "not-an-address", "", "127.100.01.1"] {
            XCTAssertNotNil(HelperValidation.validate(
                HelperRequest(operation: .addLoopbackAlias, address: address),
                existingAccounts: Set(accounts)), "\(address) is not a dotted-quad the helper will parse")
        }
    }

    func testTheHelperAcceptsTheRangeItOwns() {
        let request = HelperRequest(operation: .addLoopbackAlias, address: "127.100.4.5")
        XCTAssertNil(HelperValidation.validate(request, existingAccounts: ["_agentspace_a1b2c3"]))
        XCTAssertNil(HelperValidation.validate(
            HelperRequest(operation: .removeLoopbackAlias, address: "127.100.199.37"),
            existingAccounts: []))
    }

    func testAnAddresslessAliasRequestIsRefused() {
        XCTAssertNotNil(HelperValidation.validate(
            HelperRequest(operation: .addLoopbackAlias),
            existingAccounts: []))
    }

    /// The request shape is additive: a record with the new field decodes, and
    /// an old-shaped record still does. The daemon that does not know the
    /// operation refuses it at decode — that is the version story, and this
    /// pins the wire spelling.
    func testTheRequestCarriesTheAddressAcrossTheWire() throws {
        let request = HelperRequest(operation: .addLoopbackAlias, address: "127.100.4.5")
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(HelperRequest.self, from: data)
        XCTAssertEqual(decoded.address, "127.100.4.5")
        XCTAssertEqual(decoded.operation, .addLoopbackAlias)

        let legacy = try JSONDecoder().decode(HelperRequest.self, from: Data("""
        {"id":"x","operation":"helperStatus"}
        """.utf8))
        XCTAssertNil(legacy.address, "old records decode unchanged, address absent")
    }
}
