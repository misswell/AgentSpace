import XCTest
@testable import AgentSpaceCore

final class AccountDiscoveryTests: XCTestCase {
    func testCandidatesExcludeCurrentSystemAndAdministratorAccounts() {
        let accounts = [
            LocalAccount(username: "root", uid: 0, displayName: "System Administrator", homeDirectory: "/var/root", isAdministrator: true),
            LocalAccount(username: "guofeng", uid: 501, displayName: "Guofeng", homeDirectory: "/Users/guofeng", isAdministrator: true),
            LocalAccount(username: "agentdev", uid: 502, displayName: "Agent Dev", homeDirectory: "/Users/agentdev", isAdministrator: false),
            LocalAccount(username: "qauser", uid: 503, displayName: "QA", homeDirectory: "/Users/qauser", isAdministrator: false),
        ]

        let candidates = AccountDiscovery.candidates(from: accounts, currentUsername: "guofeng")

        XCTAssertEqual(candidates.map(\.username), ["agentdev", "qauser"])
    }
}
