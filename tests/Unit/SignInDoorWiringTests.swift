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
    /// is where the way back into the other session has to sit — permanently,
    /// and *first* when nothing below it can work without it.
    func testThePermissionsCardDrawsTheDoor() throws {
        let raw = try source("apps/AgentSpace/Views/SpaceDetailView.swift")
        let detail = flat(raw)
        XCTAssertTrue(detail.contains("ifsnapshot.offersSignInDoor,snapshot.signInDoorIsUrgent{signInDoor(snapshot)}"),
                      "while the worker is offline or the desktop is locked the card must lead with the door")
        XCTAssertTrue(detail.contains("ifsnapshot.offersSignInDoor,!snapshot.signInDoorIsUrgent{signInDoor(snapshot)}"),
                      "a healthy account keeps the door on the same card, after the grant buttons")
        // The regression this round exists to end: an entry gated on the worker
        // being broken, so it hid itself as soon as signing in worked.
        XCTAssertFalse(detail.contains("if!snapshot.workerOnline||snapshot.desktopLocked{"),
                       "the door must never again appear only while the account is offline or locked")
        // One handle per surface, and this surface's own: the card and the viewer's
        // locked overlay can be on screen at the same moment, so a name that means
        // "press the door" has to say which door. The old shared `signInAgent` is
        // also 11 bytes — a Swift small string, which an optimized build keeps
        // inside the String's own words, so `scripts/release.sh`'s read of the
        // shipped bundle cannot see it at all (validation §386).
        XCTAssertEqual(raw.components(separatedBy: "accessibilityIdentifier(\"agentSignInDoorCard\")").count - 1, 2,
                       "both door branches must carry the handle; only one renders, so the page still shows one door")
        XCTAssertFalse(raw.contains("accessibilityIdentifier(\"agentViewerSignInDoor\")"),
                       "one handle per surface, so a byte check can attribute it to one view")
        XCTAssertFalse(raw.contains("accessibilityIdentifier(\"signInAgent\")"),
                       "the shared short handle is retired; a name under 16 bytes cannot be checked in the shipped bytes")
        // Placement, measured on the source's own order: the urgent call has to
        // precede the first grant button, the healthy one follow the caption
        // that explains those buttons. An owner's screenshot caught the cost of
        // getting this wrong — a sleeping account, no visible way to sign in.
        let urgent = raw.range(of: "if snapshot.offersSignInDoor, snapshot.signInDoorIsUrgent {")
        let firstGrantButton = raw.range(of: "identifier: \"openAgentAccessibilitySettings\"")
        let healthy = raw.range(of: "if snapshot.offersSignInDoor, !snapshot.signInDoorIsUrgent {")
        XCTAssertNotNil(urgent)
        XCTAssertNotNil(firstGrantButton)
        XCTAssertNotNil(healthy)
        if let urgent, let firstGrantButton, let healthy {
            XCTAssertLessThan(urgent.lowerBound, firstGrantButton.lowerBound,
                              "the urgent door must sit above the buttons that cannot work without that session")
            XCTAssertGreaterThan(healthy.lowerBound, firstGrantButton.lowerBound,
                                 "the healthy door belongs after the grant buttons it supplements")
        }
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
        XCTAssertTrue(sheet.contains("AgentSignInPanel(account:account,model:model,closesTemporaryWindow:closesWindowWhenConnected)"),
                      "the sheet is chrome around the shared panel, not a second copy of the flow")
        let panelPath = "apps/AgentSpace/Views/AgentSignInPanel.swift"
        let panel = flat(try source(panelPath))
        XCTAssertTrue(panel.contains(".onDisappear{controller.stop()}"),
                      "the panel owns the relay, so leaving either surface closes the temporary path")
        XCTAssertTrue(try source(panelPath).contains("controller.phase != .connected"),
                      "a connected guide panel keeps itself on screen: hiding it would drop the window being watched")
    }
}
