import XCTest
@testable import AgentSpaceCore

/// The interval the dashboard's automatic status tick waits, resolved from the
/// Settings slider's stored value.
///
/// The property under test is the plan §53 band: an untouched slider resolves
/// to the 3 s default, nothing — not even a raw `defaults write` — can poll
/// faster than 2 s, and a configured value is honored as-is inside the band.
/// The dead-control defect this closes (validation §366) was a slider whose
/// value nothing consumed; these pins keep the loop and the control married.
final class StatusRefreshTests: XCTestCase {

    /// A scratch suite per test, so the machine's real setting never leaks in.
    private func scratchDefaults() -> UserDefaults {
        UserDefaults(suiteName: "StatusRefreshTests-\(UUID().uuidString)")!
    }

    func testAnUntouchedSliderResolvesToTheDefault() {
        let defaults = scratchDefaults()
        // No value, an explicit zero and a negative all mean "never set" —
        // `defaults doubleForKey:` answers 0.0 for a missing key.
        XCTAssertEqual(StatusRefresh.interval(from: defaults), 3)
        defaults.set(0, forKey: StatusRefresh.storageKey)
        XCTAssertEqual(StatusRefresh.interval(from: defaults), 3)
        defaults.set(-5, forKey: StatusRefresh.storageKey)
        XCTAssertEqual(StatusRefresh.interval(from: defaults), 3)
    }

    func testAConfiguredValueIsHonoredInsideTheBand() {
        let defaults = scratchDefaults()
        for value: Double in [2, 3, 5, 10] {
            defaults.set(value, forKey: StatusRefresh.storageKey)
            XCTAssertEqual(StatusRefresh.interval(from: defaults), value, "\(value) s must survive the round trip")
        }
    }

    func testNothingCanPollFasterThanThePlanFloor() {
        let defaults = scratchDefaults()
        defaults.set(1, forKey: StatusRefresh.storageKey)
        XCTAssertEqual(StatusRefresh.interval(from: defaults), 2)
        defaults.set(0.1, forKey: StatusRefresh.storageKey)
        XCTAssertEqual(StatusRefresh.interval(from: defaults), 2)
    }

    func testADefaultsWriteCannotScheduleAnAbsurdWait() {
        let defaults = scratchDefaults()
        defaults.set(100_000, forKey: StatusRefresh.storageKey)
        XCTAssertEqual(StatusRefresh.interval(from: defaults), StatusRefresh.ceiling)
        // A non-finite value is garbage in any store; the resolver treats it
        // like "never set" and answers the default.
        XCTAssertEqual(StatusRefresh.interval(stored: .infinity), StatusRefresh.defaultValue)
    }

    func testTheStorageKeyIsTheOneTheSliderWrites() {
        // The GUI's `@AppStorage` and this resolver must name the same key, or
        // the slider moves and the loop ignores it — the defect being fixed.
        XCTAssertEqual(StatusRefresh.storageKey, "statusRefreshSeconds")
    }
}
