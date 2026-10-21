import XCTest
@testable import AgentSpaceApp

/// The sign-in sheet ends the temporary Screen Sharing window for the person.
///
/// The owner's report on 2026-10-21: 「登录了但不打开共享屏幕？因为打开了我还得手动
/// 关掉。」 The window cannot be skipped — it is where Apple's client owns the
/// authentication — but closing it afterwards is the one step a sign-in can do
/// itself. The scope rules are the point: only the app this sheet launched, and
/// only while it owns no other window, so a Screen Sharing session of the
/// person's own is never ended by a sign-in.
final class SignInWindowCloseTests: XCTestCase {
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

    /// The window exists only because this sign-in opened it, so it goes with
    /// the sign-in. A zero-window case is the person having closed it already;
    /// quitting the idle app afterwards is harmless.
    func testTheOneWindowThisSignInOpenedIsEnded() {
        XCTAssertTrue(SignInWindowPolicy.closesTemporaryWindow(launchedByAgentSpace: true, windowCount: 1))
        XCTAssertTrue(SignInWindowPolicy.closesTemporaryWindow(launchedByAgentSpace: true, windowCount: 0))
    }

    /// Two refusals, both about someone else's session: an app that was already
    /// running before the click, and an app that owns more than the window this
    /// sheet opened.
    func testAScreenSharingSessionOfThePersonsOwnIsNeverEnded() {
        XCTAssertFalse(SignInWindowPolicy.closesTemporaryWindow(launchedByAgentSpace: false, windowCount: 1),
                       "a person already sharing another screen keeps that session")
        XCTAssertFalse(SignInWindowPolicy.closesTemporaryWindow(launchedByAgentSpace: true, windowCount: 2),
                       "quitting the app would close a second window the sign-in did not open")
    }

    /// The connected step is the only place the window is ended, and it is
    /// ended through one call: the connection must be established before the
    /// window can go away. `.connected` is also where the person is told it
    /// happened, so a message and an action cannot drift apart.
    func testTheWindowIsEndedOnlyWhenTheDesktopIsConnected() throws {
        let raw = try source("apps/AgentSpace/Services/AccountLoginController.swift")
        let controller = flat(raw)
        XCTAssertTrue(controller.contains("case.connected:self.phase=.connectednote(nil)self.closeTemporarySystemWindow()"),
                      "the close belongs to the step that has just proved the desktop is up")
        XCTAssertEqual(raw.components(separatedBy: "terminate()").count - 1, 1,
                       "one quit path, so no other branch can end a Screen Sharing window")
        XCTAssertTrue(controller.contains("guardclosesTemporaryWindow,!screenSharingWasRunning"),
                      "the sheet's context and who launched the app both gate the quit")
        XCTAssertTrue(controller.contains("SignInWindowPolicy.closesTemporaryWindow(launchedByAgentSpace:!screenSharingWasRunning,windowCount:windows)"),
                      "the window count is the same rule the unit tests pin")
    }

    /// Only the sign-in intent closes the window. The same page offers
    /// 「用屏幕共享打开该桌面」 to watch and approve, and the guide lives inside
    /// that window while the person approves panes; closing either would end
    /// the thing the person opened.
    func testOnlyTheSignInIntentCarriesTheClose() throws {
        let panel = flat(try source("apps/AgentSpace/Views/AgentSignInPanel.swift"))
        XCTAssertTrue(panel.contains("letcloses=closesTemporaryWindow&&context==.login"),
                      "the guide's inline panel keeps the window it is watching")
        XCTAssertTrue(panel.contains("closesTemporaryWindow:closes"),
                      "the controller is handed the effective value, not the raw parameter")
        let detail = flat(try source("apps/AgentSpace/Views/SpaceDetailView.swift"))
        XCTAssertTrue(detail.contains("DesktopSheet(account:space,closesWindowWhenConnected:urgent)"),
                      "the urgent door signs in; the Open-this-desktop door keeps the window")
        let sheet = flat(try source("apps/AgentSpace/Views/AccountLoginView.swift"))
        XCTAssertTrue(sheet.contains("closesTemporaryWindow:closesWindowWhenConnected"),
                      "the sheet forwards its intent to the panel")
        XCTAssertTrue(panel.contains("controller.closedTemporaryWindow?NSLocalizedString(\"AgentSpaceclosedthetemporaryScreenSharingwindow."),
                      "a window that was not ended keeps the sentence that asks the person to close it")
    }
}
