import Foundation
import XCTest

/// A worker that starts with privacy grants missing must ask macOS to
/// register itself and prompt, so the entries and the dialog are waiting in
/// the account's session when the person switches in to approve. Measured
/// 2026-09-28: the asking existed only behind the app's authorization
/// buttons, so a fresh attach produced no prompt and two empty privacy
/// lists — the person sat in the account's session with nothing to approve
/// and no entry to add by hand (TCC's file picker refuses bare binaries).
final class WorkerSetupPromptTests: XCTestCase {
    private var workerMain: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // tests/Unit
                .deletingLastPathComponent()   // tests
                .deletingLastPathComponent()   // repo root
                .appendingPathComponent("native/AgentSpaceWorker/Sources/AgentSpaceWorker/main.swift")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw XCTSkip("worker main.swift is not in this checkout")
            }
            return text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
                .joined(separator: "\n")
        }
    }

    func testStartupAsksForBothGrantsWhenMissing() throws {
        let main = try workerMain
        let stripped = main.filter { !$0.isWhitespace }
        // Both asking calls, gated on the missing-grant preflights — a worker
        // that already has the grants must not touch TCC at startup.
        XCTAssertTrue(stripped.contains("if!AXIsProcessTrusted(){"),
                      "the ask is gated on the accessibility preflight")
        XCTAssertTrue(stripped.contains("if!CGPreflightScreenCaptureAccess(){"),
                      "the ask is gated on the screen-recording preflight")
        XCTAssertTrue(stripped.contains("AXIsProcessTrustedWithOptions(optionsasCFDictionary)"),
                      "accessibility must be asked with the prompting variant, not the silent preflight")
        XCTAssertTrue(stripped.contains("CGRequestScreenCaptureAccess()"),
                      "screen recording must be asked with the requesting variant")
    }

    /// The ask never fires in a harness: smoke and integration tests run
    /// workers with an overridden root, and a dialog raised mid-CI is a gate
    /// that hangs. The gate is therefore the *resolved* root.
    ///
    /// It used to be the absence of `AGENTSPACE_ROOT`, which is not a harness
    /// signal: measured 2026-10-09 with `ps eww` against the installed worker,
    /// launchd gives it `AGENTSPACE_ROOT=/Library/Application
    /// Support/AgentSpace` — the production path — so that test exempted the one
    /// worker the prompt belongs to, and the ask never ran on a real machine.
    func testTheAskIsExemptInOverriddenRootsAndWaitsForADesktop() throws {
        let main = try workerMain
        let stripped = main.filter { !$0.isWhitespace }
        XCTAssertTrue(
            stripped.contains("ifpaths.root==RuntimePaths.root,desktopReadiness.isReady{"),
            "the ask runs in the production installation and is exempt for a temporary root")
        // The ask sits after the desktop wait, before the sockets bind — the
        // bind is what makes the worker answer, and setup must not depend on
        // an RPC to happen.
        let askRange = try XCTUnwrap(stripped.range(of: "askedmacOStoregistertheworkerandprompt"))
        let bindRange = try XCTUnwrap(stripped.range(of: "server.bind()"))
        XCTAssertLessThan(askRange.lowerBound, bindRange.lowerBound,
                          "the ask happens at startup, not after a client asks first")
    }
}
