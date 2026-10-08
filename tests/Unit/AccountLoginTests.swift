import XCTest
@testable import AgentSpaceCore

final class AccountLoginTests: XCTestCase {
    private var account: AgentAccount {
        AgentAccount(name: "Agent", username: "agentlogin", uid: 503)
    }

    func testLoginRevalidatesIdentityAndStandardUserEligibility() {
        var local = LocalAccount(username: "agentlogin", uid: 503,
            displayName: "Agent", homeDirectory: "/Users/agentlogin", isAdministrator: false)
        XCTAssertTrue(AccountLogin.permits(account, candidates: [local]))
        XCTAssertFalse(AccountLogin.permits(account, candidates: [local], currentUID: 503),
                       "An alternate username for the controller's uid is still the controller")
        local.uid = 504
        XCTAssertFalse(AccountLogin.permits(account, candidates: [local]), "Recreated username is another account")
        local.uid = 503
        local.isAdministrator = true
        XCTAssertFalse(AccountLogin.permits(account, candidates: [local]))
        local.isAdministrator = false
        local.isHidden = true
        XCTAssertFalse(AccountLogin.permits(account, candidates: [local]))
        XCTAssertFalse(AccountLogin.permits(account, candidates: []))
    }

    func testLoginURLCarriesOnlyUsernameAndLoopbackPort() throws {
        let url = try XCTUnwrap(AccountLogin.url(username: "agent @name", port: 5911))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "vnc")
        XCTAssertEqual(components.host, "127.0.0.1")
        XCTAssertEqual(components.port, 5911)
        XCTAssertEqual(components.user, "agent @name")
        XCTAssertNil(components.password)
        XCTAssertNil(components.query)
        XCTAssertNil(AccountLogin.url(username: "agent", port: 5900))
        XCTAssertNil(AccountLogin.url(username: "agent", port: 0))
        XCTAssertNil(AccountLogin.url(username: "", port: 5911))
    }

    func testOnlyTheTargetAccountsProvenGraphicalSessionCompletesLogin() {
        func response(username: String = "agentlogin", uid: Int = 503, graphical: JSONValue = .bool(true)) -> HelperResponse {
            HelperResponse(id: "probe", result: .obj([
                "username": .string(username), "uid": .int(uid), "hasGraphicalSession": graphical]))
        }
        XCTAssertTrue(AccountLogin.hasSession(response(), for: account))
        XCTAssertFalse(AccountLogin.hasSession(response(username: NSUserName()), for: account))
        XCTAssertFalse(AccountLogin.hasSession(response(uid: 501), for: account))
        XCTAssertFalse(AccountLogin.hasSession(response(graphical: .bool(false)), for: account))
        XCTAssertFalse(AccountLogin.hasSession(response(graphical: .string("true")), for: account))
        XCTAssertFalse(AccountLogin.hasSession(HelperResponse(id: "probe", result: .obj([:])), for: account))
        XCTAssertFalse(AccountLogin.hasSession(HelperResponse(id: "probe", error: AgentSpaceError(
            code: .helperUnavailable, message: "unavailable")), for: account))
    }
}
