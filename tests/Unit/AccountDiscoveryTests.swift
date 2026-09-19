import XCTest
@testable import AgentSpaceCore

final class AccountDiscoveryTests: XCTestCase {
    func testCandidatesExcludeCurrentSystemAndAdministratorAccounts() {
        let accounts = [
            LocalAccount(username: "root", uid: 0, displayName: "System Administrator", homeDirectory: "/var/root", isAdministrator: true),
            LocalAccount(username: "guofeng", uid: 501, displayName: "Guofeng", homeDirectory: "/Users/guofeng", isAdministrator: true),
            LocalAccount(username: "agentdev", uid: 502, displayName: "Agent Dev", homeDirectory: "/Users/agentdev", isAdministrator: false),
            LocalAccount(username: "qauser", uid: 503, displayName: "QA", homeDirectory: "/Users/qauser", isAdministrator: false),
            LocalAccount(username: "_hidden", uid: 504, displayName: "Hidden", homeDirectory: "/Users/_hidden", isAdministrator: false, isHidden: true),
        ]

        let candidates = AccountDiscovery.candidates(from: accounts, currentUsername: "guofeng")

        XCTAssertEqual(candidates.map(\.username), ["agentdev", "qauser"])
    }

    func testAStandardUserWithAnUnderscoreUsernameIsStillAttachable() {
        let legacyNamedUser = LocalAccount(
            username: "_agentspace_a5b707",
            uid: 503,
            displayName: "AgentUse",
            homeDirectory: "/Users/_agentspace_a5b707",
            isAdministrator: false)

        let candidates = AccountDiscovery.candidates(
            from: [legacyNamedUser],
            currentUsername: "guofeng")

        XCTAssertEqual(candidates.map(\.username), ["_agentspace_a5b707"])
    }
}
