import Foundation
import XCTest

/// The door must not go back to being a state machine's accident.
///
/// `SignInDoorVisibilityTests` decides *when* an account is offered the Screen
/// Sharing entry; these tests hold the two wiring facts that decide whether the
/// person can actually reach it: that both authorization surfaces draw it, and
/// that the guide draws the sign-in flow *inside itself* rather than as a sheet
/// over a sheet, which a window cannot present (§269) and which would drop the
/// relay the moment it closed.
final class SignInDoorWiringTests: XCTestCase {
    private func source(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // tests/Unit
            .deletingLastPathComponent()   // tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent(relativePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("\(relativePath) is not in this checkout")
        }
        return text
    }

    /// Whitespace-stripped, so a line wrap cannot hide a call. Mirrors
    /// `AttachFlowWiringTests`.
    private func flat(_ text: String) -> String { text.filter { !$0.isWhitespace } }

    /// The permissions card is where a stuck authorization is re-read, so that
    /// is where the way back into the other session has to sit — permanently.
    func testThePermissionsCardDrawsTheDoor() throws {
        let detail = flat(try source("apps/AgentSpace/Views/SpaceDetailView.swift"))
        XCTAssertTrue(detail.contains("ifsnapshot.offersSignInDoor{signInDoor(snapshot)}"),
                      "the card must offer the door whenever the account is not the human's own console")
        // The regression this round exists to end: an entry gated on the worker
        // being broken, so it hid itself as soon as signing in worked.
        XCTAssertFalse(detail.contains("if!snapshot.workerOnline||snapshot.desktopLocked{"),
                       "the door must never again appear only while the account is offline or locked")
        // One door per page: the account page must not carry a second copy of
        // the same identifier, which §344's dedup rule and layer 4 both read.
        XCTAssertEqual(try source("apps/AgentSpace/Views/SpaceDetailView.swift")
            .components(separatedBy: "accessibilityIdentifier(\"signInAgent\")").count - 1, 1,
                       "the account page carries the sign-in entry exactly once")
    }

    /// The guide is the sheet a person lives in while approving, so the door has
    /// to be in it — inline, because the Screen Sharing path stays alive only
    /// while the view that opened it is on screen.
    func testTheAuthorizationGuideCarriesTheSignInPanelInline() throws {
        let guide = flat(try source("apps/AgentSpace/Views/PermissionGuideView.swift"))
        XCTAssertTrue(guide.contains("ifsnapshot.offersSignInDoor{signInDoor(snapshot.space)}"),
                      "the guide must carry the same door the card does")
        XCTAssertTrue(guide.contains("AgentSignInPanel(account:space,model:model,context:.authorization)"),
                      "the guide embeds the panel; a second sheet cannot present over this one (§269)")
        XCTAssertFalse(guide.contains(".sheet("),
                       "the guide opens no sheet of its own — the panel it needs is already inside it")
    }

    /// Both surfaces share one flow, and that flow owns the relay's lifetime.
    func testTheSheetAndThePanelAreTheSameFlow() throws {
        let sheet = flat(try source("apps/AgentSpace/Views/AccountLoginView.swift"))
        XCTAssertTrue(sheet.contains("AgentSignInPanel(account:account,model:model)"),
                      "the sheet is chrome around the shared panel, not a second copy of the flow")
        let panelPath = "apps/AgentSpace/Views/AgentSignInPanel.swift"
        let panel = flat(try source(panelPath))
        XCTAssertTrue(panel.contains(".onDisappear{controller.stop()}"),
                      "the panel owns the relay, so leaving either surface closes the temporary path")
        XCTAssertTrue(try source(panelPath).contains("controller.phase != .connected"),
                      "a connected guide panel keeps itself on screen: hiding it would drop the window being watched")
    }
}
