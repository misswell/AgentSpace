import XCTest
@testable import AgentSpaceCore

final class WindowSleepPolicyTests: XCTestCase {
    private let now: TimeInterval = 1_000_000

    func testUnknownStoredValuesFallBackToTheDefault() {
        XCTAssertEqual(WindowSleepPolicy.parse(nil), 30)
        XCTAssertEqual(WindowSleepPolicy.parse(7), 30, "a hand-edited interval no picker offered must not become the interval")
        XCTAssertEqual(WindowSleepPolicy.parse(45), 30)
        XCTAssertEqual(WindowSleepPolicy.parse(-5), 30)
    }

    func testEveryOfferedOptionParsesToItself() {
        for option in WindowSleepPolicy.options {
            XCTAssertEqual(WindowSleepPolicy.parse(option), option)
        }
        XCTAssertTrue(WindowSleepPolicy.options.contains(WindowSleepPolicy.default))
    }

    func testThirtyMinutesMeansAsleepAtTheBoundary() {
        let minutes = 30
        XCTAssertFalse(WindowSleepPolicy.shouldSleep(now: now, lastActivity: now - 30 * 60 + 1, minutes: minutes))
        XCTAssertTrue(WindowSleepPolicy.shouldSleep(now: now, lastActivity: now - 30 * 60, minutes: minutes))
        XCTAssertTrue(WindowSleepPolicy.shouldSleep(now: now, lastActivity: now - 31 * 60, minutes: minutes))
    }

    func testNeverNeverSleeps() {
        XCTAssertFalse(WindowSleepPolicy.shouldSleep(now: now, lastActivity: now - 365 * 24 * 3600, minutes: 0))
    }

    func testAFutureActivityTimestampCannotSleepTheWindow() {
        XCTAssertFalse(WindowSleepPolicy.shouldSleep(now: now, lastActivity: now + 60, minutes: 5))
    }
}
