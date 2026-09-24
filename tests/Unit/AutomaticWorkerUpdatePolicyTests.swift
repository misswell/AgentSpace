import XCTest
@testable import AgentSpaceCore

final class AutomaticWorkerUpdatePolicyTests: XCTestCase {
    func testMismatchStartsOneRepairUntilObservedVersionChanges() {
        let id = UUID()
        var policy = AutomaticWorkerUpdatePolicy()
        XCTAssertTrue(policy.shouldUpdate(accountID: id, runningVersion: "0.1.36", expectedVersion: "0.1.40"))
        XCTAssertFalse(policy.shouldUpdate(accountID: id, runningVersion: "0.1.36", expectedVersion: "0.1.40"))
        XCTAssertTrue(policy.shouldUpdate(accountID: id, runningVersion: "0.1.38", expectedVersion: "0.1.40"))
        XCTAssertFalse(policy.shouldUpdate(accountID: id, runningVersion: "0.1.40", expectedVersion: "0.1.40"))
        XCTAssertTrue(policy.shouldUpdate(accountID: id, runningVersion: "0.1.36", expectedVersion: "0.1.40"))
    }

    func testUnknownVersionCannotTriggerAnUnverifiedInstall() {
        var policy = AutomaticWorkerUpdatePolicy()
        XCTAssertFalse(policy.shouldUpdate(accountID: UUID(), runningVersion: nil, expectedVersion: "0.1.40"))
    }
}
