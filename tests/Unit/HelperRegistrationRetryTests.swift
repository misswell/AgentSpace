import Foundation
import XCTest
@testable import AgentSpaceCore

/// Whether the app may ask launchd again, decided by who refused.
///
/// The two branches are not symmetric. A refusal produced by launchd still
/// settling an `unregister()` is the app's to wait out — it is the reason the
/// person pressed the button. A refusal produced by a person typing "no" is
/// theirs, and a second password prompt after it is nagging.
final class HelperRegistrationRetryTests: XCTestCase {
    private func refusal(_ code: Int) -> NSError { NSError(domain: NSCocoaErrorDomain, code: code) }

    func testATransientRefusalIsAskedAgainUntilTheBudgetIsSpent() {
        XCTAssertTrue(HelperRegistrationRetry.shouldRetry(refusal(1), attempt: 1))
        XCTAssertTrue(HelperRegistrationRetry.shouldRetry(refusal(1), attempt: 2))
        XCTAssertFalse(HelperRegistrationRetry.shouldRetry(refusal(1), attempt: HelperRegistrationRetry.maximumAttempts),
                       "the last refusal is the one reported, rather than one more prompt nobody asked for")
    }

    func testAPersonSayingNoEndsItOnTheSpot() {
        XCTAssertFalse(HelperRegistrationRetry.shouldRetry(refusal(HelperRegistrationRetry.cancelledCode), attempt: 1))
    }

    /// A budget that expires before the thing it is waiting for is a retry loop
    /// that reliably reports a transient failure as the app's own.
    func testTheBudgetOutlastsTheMeasuredTeardown() {
        let lastAttemptAfter = HelperRegistrationRetry.interval * Double(HelperRegistrationRetry.maximumAttempts - 1)
        XCTAssertGreaterThanOrEqual(lastAttemptAfter, 4, "measured on this machine: register() failed 13 ms after unregister() and succeeded 2.7 s later")
    }

    // MARK: - Every swap site pays the race

    /// The app swaps the helper from two places: 「重新安装助手…」, and the worker
    /// update that discovers a stale helper by itself. The measurement above was
    /// made on the first one, and the second kept a bare `register()` — which is
    /// how the owner came to press an update button twice, with a
    /// `HELPER_UNAVAILABLE` dialog between the two presses that was nobody's
    /// failure but ours. These tests fail if a swap site goes back to asking once.
    /// `AppModel.swift` with its doc comments removed: this test counts *calls*,
    /// and prose about `SMAppService.register()` must not read as one.
    private var appModelCode: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // tests/Unit
                .deletingLastPathComponent()   // tests
                .deletingLastPathComponent()   // repo root
                .appendingPathComponent("apps/AgentSpace/Models/AppModel.swift")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw XCTSkip("AppModel.swift is not in this checkout")
            }
            return text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
                .joined(separator: "\n")
        }
    }

    /// The body of a top-level `func`, up to its own closing brace, with every
    /// whitespace character removed so a line wrap cannot hide a call.
    private func body(of function: String, in source: String) -> String {
        guard let start = source.range(of: "func \(function)(") else {
            return failed("AppModel.swift no longer has \(function)( — the swap site this test guards moved or vanished")
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

    func testTheWorkerUpdateSwapWaitsOutTheTeardown() throws {
        let source = try appModelCode
        let swap = body(of: "reinstallHelperForWorker", in: source)
        XCTAssertTrue(swap.contains("unregister()"), "this test exists because that swap takes the daemon down")
        XCTAssertTrue(swap.contains("registerDaemon(attempts:HelperRegistrationRetry.maximumAttempts"),
                      "the worker update re-registers with one bare ask again, so its first press can lose launchd's teardown race")
    }

    func testNothingOutsideTheRetryingHelperRegistersDirectly() throws {
        let source = try appModelCode
        let registerDaemon = body(of: "registerDaemon", in: source)
        let bareCalls = source.filter { !$0.isWhitespace }.components(separatedBy: ".register()").count - 1
        let callsInside = registerDaemon.components(separatedBy: ".register()").count - 1
        XCTAssertEqual(bareCalls, callsInside,
                       "a `.register()` outside registerDaemon(attempts:) is a swap that asks launchd once")
        XCTAssertGreaterThanOrEqual(callsInside, 1, "registerDaemon must still be the one place that registers")
    }
}
