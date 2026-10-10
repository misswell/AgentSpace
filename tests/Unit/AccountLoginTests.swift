import XCTest
@testable import AgentSpaceCore

final class AccountLoginTests: XCTestCase {
    func testAnExistingGraphicalSessionCannotCompleteLoginBeforeItsDesktopIsUnlocked() {
        XCTAssertFalse(AccountLogin.isReady(workerOnline: true, sessionVerdict: "usable", desktopReady: false))
        XCTAssertFalse(AccountLogin.isReady(workerOnline: true, sessionVerdict: "usable", desktopReady: nil))
        XCTAssertFalse(AccountLogin.isReady(workerOnline: true, sessionVerdict: "isConsole", desktopReady: true))
        XCTAssertFalse(AccountLogin.isReady(workerOnline: true, sessionVerdict: nil, desktopReady: true))
        XCTAssertFalse(AccountLogin.isReady(workerOnline: false, sessionVerdict: "usable", desktopReady: true))
        XCTAssertTrue(AccountLogin.isReady(workerOnline: true, sessionVerdict: "usable", desktopReady: true))
    }

    /// Measured on 2026-10-09: the owner signed in to AgentUse successfully and
    /// the sheet kept spinning, because the desktop was sitting
    /// on its own lock screen — a wait with a different answer than "no session
    /// yet", and one the person could only act on if the interface said so.
    func testEachUnfinishedSignInNamesWhatItIsWaitingFor() {
        XCTAssertEqual(
            AccountLogin.wait(workerOnline: true, sessionVerdict: "usable", desktopReady: false, desktopLocked: true),
            .desktopLocked)
        XCTAssertEqual(
            AccountLogin.wait(workerOnline: false, sessionVerdict: nil, desktopReady: nil, desktopLocked: false),
            .workerOffline)
        XCTAssertEqual(
            AccountLogin.wait(workerOnline: true, sessionVerdict: "usable", desktopReady: nil, desktopLocked: false),
            .desktopNotReady)
        XCTAssertNil(
            AccountLogin.wait(workerOnline: true, sessionVerdict: "usable", desktopReady: true, desktopLocked: false))
        // A locked desktop is not "not ready": the answer a person can act on is
        // the one that says unlock it.
        XCTAssertEqual(
            AccountLogin.wait(workerOnline: true, sessionVerdict: "usable", desktopReady: false, desktopLocked: true)?.logLabel
                .contains("locked"), true)
    }

    /// The exemption the deadline needs, stated as a property rather than as a
    /// constant in the polling loop: `0.1.75` answered "no wall clock once a
    /// session exists" for every remaining condition, which is right for a lock
    /// screen and wrong for a Worker that never comes online — that wait is
    /// AgentSpace's own work and would have spun forever.
    func testOnlyTheLockScreenIsExemptFromGivingUp() {
        XCTAssertEqual(AccountLogin.Wait.allCases,
                       [.probeFailed, .noSession, .workerOffline, .desktopLocked, .desktopNotReady])
        for wait in AccountLogin.Wait.allCases {
            XCTAssertEqual(wait.waitsOnAPerson, wait == .desktopLocked,
                           "\(wait) must not be exempt unless only a person can end it")
        }
    }

    /// `hasGraphicalSession == false` was not one answer but three, and the sheet
    /// acted as if all of them meant "macOS has not signed this account in yet":
    /// a helper that never replied, one that replied unusable, and one that named
    /// a different account all produced the same spinner and the same blame.
    /// Measured 2026-10-10, where the probe itself was the thing that was broken.
    func testAnUnusableProbeIsNeverReportedAsNoSession() {
        func answer(_ fields: [String: JSONValue]) -> HelperResponse {
            HelperResponse(id: "probe", result: .obj(["username": .string("agentlogin"), "uid": .int(503)]
                .merging(fields) { _, new in new }))
        }
        XCTAssertEqual(AccountLogin.probe(answer(["sessionDomain": .string("graphical"),
            "hasGraphicalSession": .bool(true)]), for: account), .graphicalSession)
        XCTAssertEqual(AccountLogin.probe(answer(["sessionDomain": .string("absent"),
            "hasGraphicalSession": .bool(false)]), for: account), .noSession)
        XCTAssertEqual(AccountLogin.probe(answer(["sessionDomain": .string("unusable"),
            "hasGraphicalSession": .bool(false), "detail": .string("gui/503: refused with exit 1")]),
            for: account), .unusable(detail: "gui/503: refused with exit 1"))
        // No answer, an error answer, and an answer about somebody else are each
        // unusable — none of them is evidence about this account.
        XCTAssertNotEqual(AccountLogin.probe(nil, for: account), .noSession)
        XCTAssertNotEqual(AccountLogin.probe(HelperResponse(id: "probe", error: AgentSpaceError(
            code: .helperUnavailable, message: "unavailable")), for: account), .noSession)
        let wrongAccount = AccountLogin.probe(HelperResponse(id: "probe", result: .obj([
            "username": .string("someoneelse"), "uid": .int(503),
            "sessionDomain": .string("graphical")])), for: account)
        guard case .unusable(let detail) = wrongAccount else {
            return XCTFail("an answer about another account must not complete a sign-in: \(wrongAccount)")
        }
        XCTAssertTrue(detail.contains("someoneelse"), detail)
        // A helper from before the field existed still gets its yes and its no.
        XCTAssertEqual(AccountLogin.probe(answer(["hasGraphicalSession": .bool(true)]), for: account),
                       .graphicalSession)
        XCTAssertEqual(AccountLogin.probe(answer(["hasGraphicalSession": .bool(false)]), for: account),
                       .noSession)
        XCTAssertEqual(AccountLogin.probe(answer([:]), for: account),
                       .unusable(detail: "the answer carries no sessionDomain or hasGraphicalSession field"))
    }

    /// The reason and the condition are one decision, so the sheet can never
    /// explain a wait that is already over — or sit silently on one that is not.
    func testTheWaitReasonAndTheReadinessConditionCannotDisagree() {
        for workerOnline in [true, false] {
            for verdict in [Optional<String>.some("usable"), .some("isConsole"), .some("locked"), nil] {
                for ready in [Optional<Bool>.some(true), .some(false), nil] {
                    for locked in [true, false] {
                        let isReady = AccountLogin.isReady(workerOnline: workerOnline, sessionVerdict: verdict, desktopReady: ready)
                        let wait = AccountLogin.wait(workerOnline: workerOnline, sessionVerdict: verdict, desktopReady: ready, desktopLocked: locked)
                        XCTAssertEqual(wait == nil, isReady,
                                       "ready=\(isReady) wait=\(String(describing: wait)) for \(workerOnline)/\(String(describing: verdict))/\(String(describing: ready))/\(locked)")
                        // A wait on AgentSpace's own work is a wait that has to
                        // end; only the one a person answers is open-ended.
                        XCTAssertEqual(wait?.waitsOnAPerson ?? false, wait == .desktopLocked)
                    }
                }
            }
        }
    }

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
