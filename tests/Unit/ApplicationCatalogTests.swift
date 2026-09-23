import XCTest
import AgentSpaceCore

/// The rules behind the Fusion app picker. They live in Core precisely so this
/// file can exist: the worker's scan needs a session, a filesystem and readable
/// bundles, while every decision that could be wrong — which entries count, how
/// duplicates collapse, what a search matches — is pure and pinned here.
final class ApplicationCatalogTests: XCTestCase {

    private func app(_ name: String, id: String? = nil, path: String, version: String? = nil,
                     pid: Int? = nil) -> InstalledApplication {
        InstalledApplication(name: name, bundleIdentifier: id, path: path, version: version, pid: pid)
    }

    // MARK: - What counts as an application

    func testAnEntryIsOfferedOnlyWhenItIsABundleWithItsExecutable() {
        XCTAssertTrue(ApplicationCatalog.isLaunchable(entryName: "Safari.app", executableExists: true))
        // A directory named for an app but carrying no binary: offering it turns
        // a click in the picker into an error dialog.
        XCTAssertFalse(ApplicationCatalog.isLaunchable(entryName: "Broken.app", executableExists: false))
        XCTAssertFalse(ApplicationCatalog.isLaunchable(entryName: "README.md", executableExists: true))
        XCTAssertFalse(ApplicationCatalog.isLaunchable(entryName: "Applications", executableExists: true))
        // Not a suffix match to be clever about: `.app` is the extension.
        XCTAssertFalse(ApplicationCatalog.isLaunchable(entryName: "WhatsApp", executableExists: true))
    }

    // MARK: - What a picker shows

    func testDaemonsAndMenuBarAgentsAreKeptOutOfTheDefaultList() {
        let regular = ApplicationCatalog.ActivationProfile()
        let agent = ApplicationCatalog.ActivationProfile(isAgentApp: true)
        let daemon = ApplicationCatalog.ActivationProfile(isBackgroundOnly: true)

        XCTAssertTrue(ApplicationCatalog.isOffered(
            entryName: "Safari.app", executableExists: true, profile: regular))
        XCTAssertFalse(ApplicationCatalog.isOffered(
            entryName: "AddPrinter.app", executableExists: true, profile: agent),
            "a menu-bar agent has no window of its own to fuse")
        XCTAssertFalse(ApplicationCatalog.isOffered(
            entryName: "AddressBookUrlForwarder.app", executableExists: true, profile: daemon),
            "a background-only service never has one")
    }

    func testAskingForEverythingListsThemButStillNotTheUnlaunchable() {
        let daemon = ApplicationCatalog.ActivationProfile(isBackgroundOnly: true)
        XCTAssertTrue(ApplicationCatalog.isOffered(
            entryName: "AddPrinter.app", executableExists: true, profile: daemon, includingAgents: true),
            "--all is the caller saying it knows what it is doing")
        XCTAssertFalse(ApplicationCatalog.isOffered(
            entryName: "Broken.app", executableExists: false, profile: daemon, includingAgents: true),
            "no flag makes a bundle without its executable launchable")
    }

    /// The plist trap this rule exists for: reading only `as? Bool` left every
    /// `/System/Library/CoreServices` daemon in the default list, because those
    /// bundles spell the flag `"1"`.
    func testPlistFlagsAreReadAsBooleansNumbersOrStrings() {
        XCTAssertTrue(ApplicationCatalog.readsAsTrue(true))
        XCTAssertTrue(ApplicationCatalog.readsAsTrue(1))
        XCTAssertTrue(ApplicationCatalog.readsAsTrue("1"))
        XCTAssertTrue(ApplicationCatalog.readsAsTrue("YES"))
        XCTAssertTrue(ApplicationCatalog.readsAsTrue(" true "))
        XCTAssertFalse(ApplicationCatalog.readsAsTrue(false))
        XCTAssertFalse(ApplicationCatalog.readsAsTrue(0))
        XCTAssertFalse(ApplicationCatalog.readsAsTrue("0"))
        XCTAssertFalse(ApplicationCatalog.readsAsTrue("no"))
        XCTAssertFalse(ApplicationCatalog.readsAsTrue(nil))
        XCTAssertFalse(ApplicationCatalog.readsAsTrue("not a flag"))
    }

    // MARK: - The name on the row

    func testTheNamePrefersTheSystemsOwnAnswerThenNonEmptyPlistValues() {
        // The measured case: `/Applications/三局通.app` carries an empty
        // `CFBundleDisplayName`, and `??` does not catch the empty string — the
        // picker grew a row with no name on it.
        XCTAssertEqual(
            ApplicationCatalog.displayName(
                fileName: "三局通.app", filesystemName: "三局通",
                infoDisplayName: "", infoName: ""),
            "三局通")
        XCTAssertEqual(
            ApplicationCatalog.displayName(
                fileName: "Safari.app", filesystemName: "Safari",
                infoDisplayName: "Safari", infoName: "Safari"),
            "Safari",
            "the filesystem answer already has the localization")
        XCTAssertEqual(
            ApplicationCatalog.displayName(
                fileName: "Thing.app", filesystemName: nil, infoDisplayName: "  ",
                infoName: "Thing (internal)"),
            "Thing (internal)",
            "whitespace is empty too")
        XCTAssertEqual(
            ApplicationCatalog.displayName(
                fileName: "Anonymous.app", filesystemName: nil, infoDisplayName: nil, infoName: nil),
            "Anonymous",
            "and the file name is always a name")
    }

    /// The other name trap, measured on this Mac: `displayName(atPath:)` keeps
    /// the extension, so the row read 「活动监视器.app」.
    func testTheTrailingAppExtensionIsStrippedFromWhicheverNameWins() {
        XCTAssertEqual(
            ApplicationCatalog.displayName(
                fileName: "Activity Monitor.app", filesystemName: "活动监视器.app",
                infoDisplayName: nil, infoName: nil),
            "活动监视器")
        XCTAssertEqual(
            ApplicationCatalog.displayName(
                fileName: "Thing.app", filesystemName: nil, infoDisplayName: "Thing.app", infoName: nil),
            "Thing")
        XCTAssertEqual(
            ApplicationCatalog.displayName(
                fileName: "com.example.thing.app", filesystemName: nil, infoDisplayName: nil, infoName: nil),
            "com.example.thing")
    }

    /// No bundle in the shipped catalog may come back nameless — the rule above
    /// is what the worker applies, and this is the same rule stated as the
    /// property the picker depends on.
    func testANamelessBundleStillGetsTheFileName() {
        let name = ApplicationCatalog.displayName(
            fileName: "com.example.thing.app", filesystemName: "", infoDisplayName: "", infoName: "")
        XCTAssertFalse(name.isEmpty)
        XCTAssertEqual(name, "com.example.thing")
    }

    // MARK: - One list out of six directories

    func testTheFirstRootWinsADuplicateBundleAndNoAppAppearsTwice() {
        let merged = ApplicationCatalog.merge([
            [app("Safari", id: "com.apple.Safari", path: "/Applications/Safari.app")],
            [app("Safari", id: "com.apple.Safari", path: "/System/Applications/Safari.app"),
             app("Notes", id: "com.apple.Notes", path: "/System/Applications/Notes.app")],
        ])
        XCTAssertEqual(merged.map(\.name), ["Notes", "Safari"])
        XCTAssertEqual(merged.first { $0.name == "Safari" }?.path, "/Applications/Safari.app",
                       "the earlier root wins, so the copy a person sees is the one resolve() would find")
    }

    func testDuplicateDetectionIgnoresIdentifierCase() {
        let merged = ApplicationCatalog.merge([
            [app("Safari", id: "com.apple.Safari", path: "/Applications/Safari.app")],
            [app("Safari", id: "com.apple.safari", path: "/System/Applications/Safari.app")],
        ])
        XCTAssertEqual(merged.count, 1, "two spellings of one bundle id are one application")
    }

    func testBundlesWithoutAnIdentifierAreNotCollapsedTogether() {
        // Two anonymous bundles are two applications. Falling back to the path
        // is what keeps them apart; using an empty identifier as the key would
        // have shown one of them and hidden the other.
        let merged = ApplicationCatalog.merge([[
            app("Tool A", id: nil, path: "/Applications/Tool A.app"),
            app("Tool B", id: nil, path: "/Applications/Tool B.app"),
        ]])
        XCTAssertEqual(merged.count, 2)
    }

    func testTheListIsOrderedByNameCaseInsensitively() {
        let merged = ApplicationCatalog.merge([[
            app("zoom.us", id: "us.zoom.xos", path: "/Applications/zoom.us.app"),
            app("Finder", id: "com.apple.finder", path: "/System/Library/CoreServices/Finder.app"),
            app("alfred", id: "com.runningwithcrayons.Alfred", path: "/Applications/Alfred.app"),
            app("Calendar", id: "com.apple.iCal", path: "/System/Applications/Calendar.app"),
        ]])
        XCTAssertEqual(merged.map(\.name), ["alfred", "Calendar", "Finder", "zoom.us"],
                       "case-insensitive, or every capitalized app sorts before every lowercase one")
    }

    func testHomeApplicationsComeFromTheGivenHome() {
        let roots = ApplicationCatalog.searchRoots(home: "/Users/agentuse")
        XCTAssertEqual(roots.last, "/Users/agentuse/Applications")
        XCTAssertTrue(roots.contains("/Applications"))
        XCTAssertTrue(roots.contains("/System/Applications"))
        XCTAssertEqual(Set(roots).count, roots.count, "a root listed twice would scan twice")
    }

    // MARK: - The search field

    func testSearchMatchesNameIdentifierAndFileName() {
        let safari = app("Safari", id: "com.apple.Safari", path: "/Applications/Safari.app")
        XCTAssertTrue(ApplicationCatalog.matches(safari, query: "saf"), "by name, case-insensitively")
        XCTAssertTrue(ApplicationCatalog.matches(safari, query: "com.apple.safari"), "by bundle id")
        XCTAssertTrue(ApplicationCatalog.matches(safari, query: "safari.app"), "by file name")
        XCTAssertFalse(ApplicationCatalog.matches(safari, query: "chrome"))
    }

    func testAnEmptyOrWhitespaceQueryDoesNotHideAnything() {
        let apps = [app("Safari", id: "com.apple.Safari", path: "/Applications/Safari.app")]
        XCTAssertEqual(ApplicationCatalog.filtered(apps, query: nil).count, 1)
        XCTAssertEqual(ApplicationCatalog.filtered(apps, query: "").count, 1)
        XCTAssertEqual(ApplicationCatalog.filtered(apps, query: "   ").count, 1,
                       "a field holding spaces is not a search for nothing")
    }

    func testASearchIsTrimmedBeforeItIsApplied() {
        let notes = app("Notes", id: "com.apple.Notes", path: "/System/Applications/Notes.app")
        XCTAssertTrue(ApplicationCatalog.matches(notes, query: "  notes  "),
                      "a paste with a trailing space still finds the app")
    }

    // MARK: - The record the picker shows

    func testRunningAppsAreMarkedAndOthersAreNot() {
        XCTAssertTrue(app("Safari", id: "com.apple.Safari", path: "/Applications/Safari.app", pid: 421).isRunning)
        XCTAssertFalse(app("Safari", id: "com.apple.Safari", path: "/Applications/Safari.app").isRunning)
    }
}
