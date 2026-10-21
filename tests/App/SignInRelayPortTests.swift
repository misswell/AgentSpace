import XCTest
@testable import AgentSpaceApp

/// The sign-in relay asks for the account's own port, and says when it could
/// not. macOS files the remembered password under `127.0.0.1:<port>`, so asking
/// for a fresh random port on every attempt is what made 「记住密码」 a checkbox
/// that never took effect (owner's report, 2026-10-21).
final class SignInRelayPortTests: XCTestCase {
    private func source(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // tests/App
            .deletingLastPathComponent()   // tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent(relativePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("\(relativePath) is not in this checkout")
        }
        return text
    }

    private func flat(_ text: String) -> String { text.filter { !$0.isWhitespace } }

    func testTheControllerAsksForTheAccountsStablePort() throws {
        let controller = flat(try source("apps/AgentSpace/Services/AccountLoginController.swift"))
        XCTAssertTrue(controller.contains("letstablePort=ScreenSharingRelay.stablePort(for:self.account.id)"),
                      "the port must come from the account, not from the listener's choice")
        XCTAssertTrue(controller.contains("letport=tryawaitrelay.start(preferredPort:stablePort)"),
                      "the relay is handed that port")
        XCTAssertTrue(controller.contains("ifport!=stablePort{loginLog.log(\"sign-inrelayfellbacktoport"),
                      "a fallback is visible in the log, because the remembered password cannot match it")
    }
}
