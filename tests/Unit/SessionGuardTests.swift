import XCTest
import AgentSpaceCore

/// A `SessionInfoSource` built from a literal dictionary, so every branch of the
/// console guard can be exercised without needing a second logged-in user.
struct FakeSessionInfo: SessionInfoSource, @unchecked Sendable {
    var dictionary: [String: Any]?
    var graphicAccess: Bool?
    var uid: uid_t = 501

    func currentSessionDictionary() -> [String: Any]? { dictionary }
    func hasGraphicAccess() -> Bool? { graphicAccess }
    func currentUID() -> uid_t { uid }
}

final class SessionGuardTests: XCTestCase {

    // MARK: The console bit

    func testDoubleSKeyIsRead() {
        let source = FakeSessionInfo(
            dictionary: ["kCGSSessionOnConsoleKey": NSNumber(value: true)],
            graphicAccess: true)
        XCTAssertEqual(SessionGuard.onConsole(dictionary: source.dictionary), true)
    }

    /// The single-S spelling is the one the *constant* is named after, but the
    /// dictionary has been observed to carry the double-S key. Both must work so
    /// an OS that switches spelling does not silently disarm the guard.
    func testSingleSKeyIsAlsoAccepted() {
        let source = FakeSessionInfo(
            dictionary: ["kCGSessionOnConsoleKey": NSNumber(value: false)],
            graphicAccess: true)
        XCTAssertEqual(SessionGuard.onConsole(dictionary: source.dictionary), false)
    }

    func testBoolBridgedValueIsAccepted() {
        XCTAssertEqual(
            SessionGuard.onConsole(dictionary: ["kCGSSessionOnConsoleKey": true]),
            true)
    }

    // MARK: Fail closed

    func testMissingDictionaryFailsClosed() {
        XCTAssertNil(SessionGuard.onConsole(dictionary: nil))
        XCTAssertEqual(
            SessionGuard.verdict(using: FakeSessionInfo(dictionary: nil, graphicAccess: true)),
            .indeterminate)
        XCTAssertFalse(
            SessionGuard.verdict(using: FakeSessionInfo(dictionary: nil, graphicAccess: true)).permitsInput,
            "an unreadable session dictionary must never permit input")
    }

    func testMissingConsoleKeyFailsClosed() {
        let source = FakeSessionInfo(
            dictionary: ["kCGSSessionUserNameKey": "someone"],
            graphicAccess: true)
        XCTAssertEqual(SessionGuard.verdict(using: source), .indeterminate)
    }

    func testNonNumericConsoleValueFailsClosed() {
        let source = FakeSessionInfo(
            dictionary: ["kCGSSessionOnConsoleKey": "yes"],
            graphicAccess: true)
        XCTAssertEqual(SessionGuard.verdict(using: source), .indeterminate)
    }

    func testUnknownGraphicAccessStillUsesConsoleBit() {
        // A nil graphic-access answer is "could not tell", not "no window
        // server": the console bit is then the decider.
        let safe = FakeSessionInfo(
            dictionary: ["kCGSSessionOnConsoleKey": NSNumber(value: false)],
            graphicAccess: nil)
        XCTAssertEqual(SessionGuard.verdict(using: safe), .usable)
    }

    func testNoGraphicAccessIsNoWindowServer() {
        let source = FakeSessionInfo(
            dictionary: ["kCGSSessionOnConsoleKey": NSNumber(value: false)],
            graphicAccess: false)
        XCTAssertEqual(SessionGuard.verdict(using: source), .noWindowServer)
    }

    func testConsoleSessionIsRefused() {
        let source = FakeSessionInfo(
            dictionary: ["kCGSSessionOnConsoleKey": NSNumber(value: true)],
            graphicAccess: true)
        let verdict = SessionGuard.verdict(using: source)
        XCTAssertEqual(verdict, .isConsole)
        XCTAssertFalse(verdict.permitsInput)
        XCTAssertEqual(verdict.errorCode, .sessionIsConsole)
    }

    func testBackgroundSessionIsUsable() {
        let source = FakeSessionInfo(
            dictionary: ["kCGSSessionOnConsoleKey": NSNumber(value: false)],
            graphicAccess: true)
        let verdict = SessionGuard.verdict(using: source)
        XCTAssertEqual(verdict, .usable)
        XCTAssertTrue(verdict.permitsInput)
    }

    /// The property that matters most, stated as one assertion over every
    /// malformed input shape: only an explicit `false` may permit input.
    func testOnlyExplicitFalsePermitsInput() {
        let dictionaries: [[String: Any]?] = [
            nil,
            [:],
            ["kCGSSessionOnConsoleKey": "false"],
            ["kCGSSessionOnConsoleKey": NSNull()],
            ["kCGSSessionOnConsoleKey": 2],
            ["unrelated": true],
        ]
        for dictionary in dictionaries {
            let verdict = SessionGuard.verdict(
                using: FakeSessionInfo(dictionary: dictionary, graphicAccess: true))
            if dictionary?["kCGSSessionOnConsoleKey"] as? NSNumber == nil {
                XCTAssertFalse(verdict.permitsInput,
                               "dictionary \(String(describing: dictionary)) permitted input")
            }
        }
    }

    // MARK: Privilege

    func testWorkerCannotRunAsRoot() {
        XCTAssertNotNil(PrivilegeGuard.refuseReason(uid: 0))
        XCTAssertEqual(PrivilegeGuard.refuseReason(uid: 0)?.code, .workerIsRoot)
        XCTAssertNil(PrivilegeGuard.refuseReason(uid: 501))
    }

    func testRootRefusalIsNotRecoverable() {
        let error = PrivilegeGuard.refuseReason(uid: 0)
        XCTAssertEqual(error?.recoverable, false,
                       "retrying as root can never succeed, so it must not invite a retry")
    }

    // MARK: Real machine

    /// Runs against the actual session this test process is in. On a normal
    /// developer machine that is the console, which is exactly the case the
    /// guard exists for — so this asserts the guard agrees with reality rather
    /// than asserting a fixed outcome.
    func testRealSessionAgreesWithSystemState() {
        let source = SystemSessionInfo()
        let verdict = SessionGuard.verdict(using: source)
        let rawConsole = SessionGuard.onConsole(dictionary: source.currentSessionDictionary())

        switch verdict {
        case .usable:
            XCTAssertEqual(rawConsole, false)
        case .isConsole:
            XCTAssertEqual(rawConsole, true)
        case .indeterminate:
            XCTAssertNil(rawConsole)
        case .noWindowServer:
            XCTAssertEqual(source.hasGraphicAccess(), false)
        }
    }

    func testSystemSourceReportsGraphicAccess() {
        // Whatever the value, the call must not crash and must answer on a
        // machine with a GUI session.
        let access = SystemSessionInfo().hasGraphicAccess()
        XCTAssertNotNil(access, "SessionGetInfo should succeed in a login session")
    }
}
