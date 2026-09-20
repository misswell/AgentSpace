import XCTest
@testable import AgentSpaceCore

final class AppVisibilityTests: XCTestCase {
    // §22: the apps list must include regular apps, accessory apps
    // (LSUIElement menu-bar apps), and anything the window server sees.
    // The predicate is the whole rule, so each branch is pinned here.

    func testRegularAppsAreAlwaysVisible() {
        XCTAssertTrue(AppVisibility.isVisible(policy: "regular", pid: 100, windowPids: []))
        XCTAssertTrue(AppVisibility.isVisible(policy: "regular", pid: 100, windowPids: [100]))
    }

    func testAccessoryMenuBarAppsAreVisibleWithoutWindows() {
        // An LSUIElement menu-bar app owns no window; hiding it would make
        // every launch of one look like a failed launch (§22).
        XCTAssertTrue(AppVisibility.isVisible(policy: "accessory", pid: 200, windowPids: []))
    }

    func testProhibitedAppsAreVisibleOnlyThroughAWindow() {
        // AppKit calls some processes "prohibited" even while the window
        // server still shows their windows; the window server outranks it.
        XCTAssertTrue(AppVisibility.isVisible(policy: "prohibited", pid: 300, windowPids: [300]))
        XCTAssertFalse(AppVisibility.isVisible(policy: "prohibited", pid: 300, windowPids: []))
    }

    func testUnknownPoliciesFollowTheSameWindowRule() {
        // An unknown policy from a future SDK must not silently hide a
        // windowed app — and must not surface a windowless one either.
        XCTAssertTrue(AppVisibility.isVisible(policy: "unknown", pid: 400, windowPids: [400]))
        XCTAssertFalse(AppVisibility.isVisible(policy: "unknown", pid: 400, windowPids: []))
    }

    func testAWindowOwnedByAnotherPidDoesNotMakeAnAppVisible() {
        XCTAssertFalse(AppVisibility.isVisible(policy: "prohibited", pid: 500, windowPids: [501]))
    }
}

final class AppBundleCompatibilityTests: XCTestCase {
    func testAnOldGUIRequestsRelaunchAfterTheAppWasReplacedOnDisk() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentSpace-bundle-\(UUID().uuidString)")
        let contents = root.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let plist: [String: Any] = ["CFBundleShortVersionString": "0.1.11"]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))

        XCTAssertTrue(AppBundleCompatibility.requiresRelaunch(
            runningVersion: "0.1.10", bundleURL: root))
        XCTAssertFalse(AppBundleCompatibility.requiresRelaunch(
            runningVersion: "0.1.11", bundleURL: root))
    }
}
