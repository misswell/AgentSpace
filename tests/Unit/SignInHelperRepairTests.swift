import Foundation
import XCTest

/// The sign-in sheet's helper failures must end in the button that fixes them.
///
/// Measured on 2026-10-20: the owner's screen showed 「特权助手无法检查此账号。请在
/// AgentSpace 中安装或修复助手，然后重试。」 inside the dialog while the fix lived in
/// another window. A sentence that names a place is not a control; these tests
/// hold the three helper-related failures to one repair path, the button that
/// runs it, and the retry that follows a successful swap.
final class SignInHelperRepairTests: XCTestCase {
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

    private func flat(_ text: String) -> String { text.filter { !$0.isWhitespace } }

    /// Whitespace-stripped body of a function, from its declaration to the first
    /// line that is only four spaces and a closing brace. Mirrors
    /// `HelperRegistrationRetryTests`; the controller's methods sit at that depth.
    private func body(of function: String, in source: String) -> String {
        guard let start = source.range(of: "func \(function)(") else {
            XCTFail("source no longer has \(function)(")
            return ""
        }
        let after = source[start.lowerBound...]
        guard let end = after.range(of: "\n    }\n") else {
            XCTFail("could not find the end of \(function)(")
            return ""
        }
        return String(after[..<end.upperBound]).filter { !$0.isWhitespace }
    }

    /// The same function's body up to the *next* declaration, which is where a
    /// long implementation's nested closures live.
    private func region(from function: String, to next: String, in source: String) -> String {
        guard let start = source.range(of: "func \(function)("),
              let end = source.range(of: "func \(next)(", range: start.upperBound..<source.endIndex) else {
            XCTFail("could not find \(function) followed by \(next)")
            return ""
        }
        return flat(String(source[start.lowerBound..<end.lowerBound]))
    }

    /// Three different failures, one fact: the helper this app needs is not the
    /// helper that is answering. Each one must arm the sheet's repair button,
    /// because each one's fix is the same swap.
    func testEveryHelperFailureInTheSheetArmsTheRepair() throws {
        let controller = try source("apps/AgentSpace/Services/AccountLoginController.swift")
        let start = region(from: "start", to: "repairHelper", in: controller)
        XCTAssertEqual(start.components(separatedBy: "self.needsHelperRepair=true").count - 1, 3,
                       "the unreachable helper, the stale binary and the stalled probe each need the repair button")
        for key in [
            "The privileged helper could not inspect this account. Reinstall it below, then try again.",
            "The installed helper is from an earlier version of AgentSpace. Reinstall it below and allow the administrator approval, then try again.",
            "AgentSpace could not confirm the agent account's desktop session. Reinstall the helper below, then try again.",
        ] {
            XCTAssertTrue(start.contains(key.filter { !$0.isWhitespace }),
                          "a helper failure still sends the person to another window: \(key)")
        }
        XCTAssertFalse(start.contains("ReinstallitinDoctor"),
                       "the old sentence pointed at Doctor; the fix now sits beside it")
    }

    /// The button's work is the awaited swap, and a successful swap resumes the
    /// sign-in that was blocked. Anything less leaves the person to press the
    /// sign-in button again on a state they cannot tell changed.
    func testRepairAwaitsTheSwapAndThenRetriesSignIn() throws {
        let controller = try source("apps/AgentSpace/Services/AccountLoginController.swift")
        let repair = body(of: "repairHelper", in: controller)
        XCTAssertTrue(repair.contains("awaitmodel.reinstallHelperNow("),
                      "the repair must wait for the swap rather than fire and forget")
        XCTAssertTrue(repair.contains("guardrepairedelse{return}"),
                      "a refused swap must keep the sheet in its failure state")
        XCTAssertTrue(repair.contains("self.start()"),
                      "a successful swap must resume the blocked sign-in")

        let model = try source("apps/AgentSpace/Models/AppModel.swift")
        let swap = body(of: "reinstallHelperNow", in: model)
        XCTAssertFalse(model.contains("privatefuncreinstallHelperNow"),
                       "the sheet calls this swap, so it cannot be private")
        XCTAssertTrue(swap.contains("registerDaemon(attempts:HelperRegistrationRetry.maximumAttempts"),
                      "the sign-in repair shares the retrying swap")
        XCTAssertTrue(swap.contains("helperFailure=presented"),
                      "a refused swap has to reach the sheet, where no alert can present over it (§269)")
    }

    /// The control itself: a button in the sheet's action row, its own handle,
    /// and no dead "try again" beside it while the helper is what is broken.
    func testTheSheetDrawsTheRepairInsteadOfASecondFutileAttempt() throws {
        let panel = flat(try source("apps/AgentSpace/Views/AgentSignInPanel.swift"))
        XCTAssertTrue(panel.contains("controller.repairHelper()"),
                      "the sheet's button must run the repair itself")
        XCTAssertTrue(panel.contains("Text(\"ReinstallHelper…\")"),
                      "the button names the action the person already knows")
        XCTAssertTrue(panel.contains("accessibilityIdentifier(\"signInReinstallHelperButton\")"),
                      "the sheet's handle is its own and long enough for the shipped-bytes check")
        XCTAssertTrue(panel.contains("ifcontroller.needsHelperRepair{"),
                      "the repair button renders only for helper failures")
        XCTAssertTrue(panel.contains("case.failed:return!controller.needsHelperRepair"),
                      "press-again sign-in must not sit beside the repair while the helper is broken")
        XCTAssertTrue(panel.contains("HelperFailureBanner()"),
                      "a refused repair has to be visible inside the sheet")
        XCTAssertTrue(panel.contains("ProgressView(\"Reinstalling…\")"),
                      "the button reports the swap's progress where it was pressed")
    }
}
