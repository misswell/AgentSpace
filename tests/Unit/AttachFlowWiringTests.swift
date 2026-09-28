import Foundation
import XCTest

/// The connect flow must end somewhere useful, and the wiring that makes that
/// true is app-side (`AppModel`, `ProvisioningView`, `SpaceDetailView`) —
/// outside the Core module the unit tests import. These tests read the source
/// the way `HelperRegistrationRetryTests` does, so a refactor that silently
/// severs the bridge — a wizard that finishes into a dead end, a guide request
/// raised while the sheet is still up, a record nobody advances — fails here
/// rather than in front of the next person holding the software for the first
/// time.
final class AttachFlowWiringTests: XCTestCase {
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

    /// The completion overlay must know what to point at: an attach whose
    /// saved record says needsLogin owes the sign-in instructions, and every
    /// other successful attach owes authorization — decided from what the
    /// attach actually saved, not assumed.
    func testTheNextStepIsDecidedFromTheSavedAccountState() throws {
        let appModel = try source("apps/AgentSpace/Models/AppModel.swift")
        XCTAssertTrue(
            appModel.contains("account.state == .needsLogin ? .finishSetup : .authorize"),
            "attachAccount must read the saved record's state to pick the completion's next step")
        XCTAssertTrue(
            appModel.contains("attachedSpaceID = account.id"),
            "the bridge needs the new account's id to select it and open its guide")
    }

    /// The bridge's primary button closes the wizard before raising the guide
    /// request: a window presents one sheet at a time (§269), so a request
    /// raised while the wizard sheet is still coming down is swallowed and
    /// the button reads as dead.
    func testTheBridgeClosesTheWizardBeforeRaisingTheGuideRequest() throws {
        let doctorView = try source("apps/AgentSpace/Views/DoctorView.swift")
        let bridge = body(of: "AttachSuccessInstructions", in: doctorView)
        XCTAssertTrue(bridge.contains("showingNewSpace=false"),
                      "the bridge must close the New Agent wizard, not leave it open on a finished step")
        XCTAssertTrue(bridge.contains("permissionGuideRequest=id"),
                      "the bridge must raise the guide request for the attached account")
        XCTAssertTrue(bridge.contains("asyncAfter"),
                      "the guide request must wait for the wizard sheet to finish coming down (§269)")
    }

    /// The account page must carry the one remaining step where it cannot be
    /// missed: a worker that answers while grants are missing earns a banner
    /// whose button opens the guide — not prose the user has to hunt for.
    func testTheAccountPageBannersTheMissingGrantsOfAnAnsweringWorker() throws {
        let detail = try source("apps/AgentSpace/Views/SpaceDetailView.swift")
        XCTAssertTrue(detail.contains("snapshot.workerOnline"),
                      "the banner condition reads the live snapshot")
        XCTAssertTrue(detail.contains("setupBannerAuthorize"),
                      "the banner's button is the one that opens the guide")
        // The old local-state sheet could not be raised from the wizard's
        // completion step; the request-driven one can.
        XCTAssertFalse(detail.contains("@State private var showingPermissionGuide"),
                       "the guide sheet is request-driven now; a local flag reintroduces the dead end")
    }

    /// The registry record must advance when a refresh proves it stale: a
    /// worker that started after the attach's probe lost forever read as
    /// Sleeping over an answering worker.
    func testReloadReconcilesRecordedStates() throws {
        let appModel = try source("apps/AgentSpace/Models/AppModel.swift")
        XCTAssertTrue(appModel.contains("reconcileStates(registry:"),
                      "reload must run the reconciliation")
        XCTAssertTrue(appModel.contains("SpaceState.reconciled("),
                      "the reconcile decision is Core's, so the CLI and the GUI cannot disagree")
    }

    /// The body of a top-level declaration, whitespace-stripped, so a line
    /// wrap cannot hide a call. Mirrors HelperRegistrationRetryTests.
    private func body(of declaration: String, in source: String) -> String {
        guard let start = source.range(of: "struct \(declaration)") else {
            return failed("\(declaration) moved or vanished")
        }
        let after = source[start.lowerBound...]
        guard let end = after.range(of: "\n}\n") else {
            return failed("could not find the end of \(declaration)")
        }
        return String(after[..<end.upperBound]).filter { !$0.isWhitespace }
    }

    private func failed(_ message: String) -> String {
        XCTFail(message)
        return ""
    }
}
