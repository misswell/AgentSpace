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
}
