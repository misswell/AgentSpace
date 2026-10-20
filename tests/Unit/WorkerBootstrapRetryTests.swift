import XCTest
@testable import AgentSpaceCore

/// One press must survive launchd's own transition instead of teaching the
/// person to press again.
///
/// Measured 2026-10-20: `startWorker` answered `start failed: Bootstrap failed:
/// 125: Domain does not support specified action`, and a later press of the
/// same button worked. The helper asked `bootstrap` exactly once, so every
/// transient refusal became the person's second press. These tests fail if the
/// start path goes back to asking once, or if a refusal that waiting can fix is
/// reported as `HELPER_REJECTED` again.
final class WorkerBootstrapRetryTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // tests/Unit
            .deletingLastPathComponent()   // tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("\(relative) is not in this checkout")
        }
        // Prose about `bootstrap` must not read as a call.
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
            .joined(separator: "\n")
    }

    /// The body of a `func`, up to its own closing brace, with every
    /// whitespace character removed so a line wrap cannot hide a call.
    private func body(of function: String, in source: String) -> String {
        guard let start = source.range(of: "func \(function)(") else {
            return failed("\(function)( is gone")
        }
        let after = source[start.lowerBound...]
        guard let end = after.range(of: "\n    }\n") else {
            return failed("could not find the end of \(function)(")
        }
        return String(after[..<end.upperBound]).filter { !$0.isWhitespace }
    }

    private func failed(_ message: String) -> String {
        XCTFail(message)
        return ""
    }

    private var helperService: String {
        get throws {
            try source("native/AgentSpacePrivilegedHelper/Sources/AgentSpacePrivilegedHelper/HelperService.swift")
        }
    }

    func testTheStartPathAsksLaunchdAgainWhileTheStatusCanChange() throws {
        let start = body(of: "workerControl", in: try helperService)
        XCTAssertTrue(start.contains("runWithLaunchdRetries(commands.bootstrap)"),
                      "the bootstrap is asked once again, so a settling domain costs a press")
        XCTAssertTrue(start.contains("runWithLaunchdRetries(commands.kickstart)"),
                      "the kickstart of the same domain can be refused for the same reason")
        let retry = body(of: "runWithLaunchdRetries", in: try helperService)
        XCTAssertTrue(retry.contains("LaunchdDomain.retryDelay("),
                      "the wait must come from the tested policy, not a helper-local guess")
        XCTAssertTrue(retry.contains("Thread.sleep(forTimeInterval:pause)"),
                      "asking launchd again without waiting repeats the same refusal immediately")
        XCTAssertTrue(start.contains("letagain=CommandRunner.run(commands.bootout"),
                      "a half-removed registration (17/125) must be booted out again before the next load")
    }

    func testAnAbsentDesktopIsAnsweredWithoutSpendingTheWindow() throws {
        let start = body(of: "workerControl", in: try helperService)
        XCTAssertTrue(start.contains("LaunchdDomain.verdict("),
                      "the start path no longer reads the domain state")
        XCTAssertTrue(start.contains("\"print\",\"gui/\\(uidValue)\""),
                      "the start path must ask launchd for the account's own GUI domain")
        XCTAssertTrue(start.contains("ifverdict==.absent"),
                      "an absent domain cannot be cured by waiting and must fail at once")
    }

    func testAnExhaustedWaitIsReportedAsASessionStateNotARefusal() throws {
        let start = body(of: "workerControl", in: try helperService)
        XCTAssertTrue(start.contains("ifLaunchdDomain.isTransientStatus(bootstrapped.exitCode)"),
                      "a refused bootstrap must be classified before it is thrown")
        XCTAssertTrue(start.contains("code:.sessionNotReady"),
                      "the exhausted wait is the desktop's state, not a helper policy refusal")
    }

    /// The interface answers in its own language, and says what is missing.
    func testTheAppLocalizesTheStillStartingFailure() throws {
        let install = body(of: "installAndStartWorker",
                           in: try source("apps/AgentSpace/Models/AppModel.swift"))
        XCTAssertTrue(install.contains("start.error?.code==.sessionNotReady"),
                      "the app collapses the helper's answer back into a generic refusal")
        XCTAssertTrue(install.contains("NSLocalizedString(\"Theagentaccounthasnousabledesktopsessionyet"),
                      "the person must read a sentence and a next step, not launchctl's prose")
    }
}
