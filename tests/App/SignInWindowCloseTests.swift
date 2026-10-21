import XCTest
@testable import AgentSpaceApp

/// The sign-in sheet ends the temporary Screen Sharing window for the person.
///
/// The owner's report on 2026-10-21: 「登录了但不打开共享屏幕？因为打开了我还得手动
/// 关掉。」 The window cannot be skipped — it is where Apple's client owns the
/// authentication — but closing it afterwards is the one step a sign-in can do
/// itself. The scope rules are the point: only while no other visible window
/// exists, so a Screen Sharing session of the person's own is never ended by a
/// sign-in. The first version counted the window server's layer-0 list and a
/// running app, which is what the owner hit twice on 2026-10-21 (validation §394).
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
    /// quitting the app that opened nothing else afterwards is harmless.
    func testTheOneWindowThisSignInOpenedIsEnded() {
        XCTAssertTrue(SignInWindowPolicy.closesTemporaryWindow(visibleWindowCount: 1))
        XCTAssertTrue(SignInWindowPolicy.closesTemporaryWindow(visibleWindowCount: 0))
    }

    /// A second visible window is someone else's session — the case the policy
    /// exists to refuse. Windows that predate this sign-in are refused by the
    /// controller before the count (pinned below).
    func testAScreenSharingSessionOfThePersonsOwnIsNeverEnded() {
        XCTAssertFalse(SignInWindowPolicy.closesTemporaryWindow(visibleWindowCount: 2),
                       "quitting the app would close a second window the sign-in did not open")
    }

    /// One Screen Sharing connection is one window to a person, and five to
    /// eleven windows to the window server. Measured 2026-10-21 in AgentUse's
    /// session against a loopback server: the connection window (430×130,
    /// on screen) was AX=1 and on-screen=1 while layer-0 held a 0×0
    /// placeholder, three 1920×30 strips, the hidden 「所有连接」 browser, and
    /// a partly transparent internal window. Counting those is exactly what
    /// left the owner's window open; the test pins the shape that is a session.
    func testTheWindowServersInternalWindowsAreNotConnections() {
        XCTAssertTrue(SignInWindowPolicy.countsAsWindow(layer: 0, onScreen: true, alpha: 1, width: 430, height: 130))
        XCTAssertFalse(SignInWindowPolicy.countsAsWindow(layer: 0, onScreen: false, alpha: 1, width: 0, height: 0),
                       "a 0×0 placeholder is not a window")
        XCTAssertFalse(SignInWindowPolicy.countsAsWindow(layer: 0, onScreen: false, alpha: 1, width: 602, height: 156),
                       "the hidden connection browser is not a session")
        XCTAssertFalse(SignInWindowPolicy.countsAsWindow(layer: 0, onScreen: true, alpha: 1, width: 1920, height: 30),
                       "the screen-wide strip is not a window")
        XCTAssertFalse(SignInWindowPolicy.countsAsWindow(layer: 25, onScreen: true, alpha: 1, width: 430, height: 130),
                       "a panel above layer 0 is not a connection window")
        XCTAssertFalse(SignInWindowPolicy.countsAsWindow(layer: 0, onScreen: true, alpha: 0, width: 430, height: 130),
                       "an invisible window is not a session")
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
        XCTAssertTrue(controller.contains("guardscreenSharingPriorWindows==0"),
                      "a window that existed before this sign-in is never ended by it")
        XCTAssertTrue(controller.contains("letwindows=Self.visibleWindowsOwned(by:application.processIdentifier)"),
                      "the count is the visible one, not the window server's layer-0 list")
        XCTAssertTrue(controller.contains("SignInWindowPolicy.closesTemporaryWindow(visibleWindowCount:windows)"),
                      "the window count is the same rule the unit tests pin")
        XCTAssertTrue(controller.contains("sign-inlefttheScreenSharingappopen:italreadyowned"),
                      "a refusal says which rule refused, so the next log is readable")
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
