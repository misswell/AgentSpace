import XCTest
@testable import AgentSpaceCore

/// macOS file privacy (`FilePrivacy`), which is the third grant and the reason a
/// disk metric may not read wherever it likes.
///
/// Both sides are injected. A unit test that probed a real account's home would
/// be the exact side effect this type exists to keep out of a polling path: one
/// TCC gate check per protected container, and on the folder gates a dialog
/// nobody in a background session is there to answer.
final class FilePrivacyTests: XCTestCase {

    private var exists: ((String) -> Bool)!
    private var reader: ((String) -> Bool)!

    override func setUp() {
        super.setUp()
        exists = FilePrivacy.exists
        reader = FilePrivacy.reader
    }

    override func tearDown() {
        FilePrivacy.exists = exists
        FilePrivacy.reader = reader
        super.tearDown()
    }

    func testTheFirstProbeThatExistsAnswersForTheWholeHome() {
        FilePrivacy.exists = { $0.hasSuffix("Library/Cookies/Cookies.sqlite") }
        var asked: [String] = []
        let granted = FilePrivacy.granted(home: "/h") {
            asked.append($0)
            return $0 == "/h/Library/Cookies/Cookies.sqlite"
        }
        XCTAssertTrue(granted)
        // One gated file is enough: Full Disk Access is a single grant, so a
        // second and third check would be two more gate round trips per poll for
        // an answer this already gave.
        XCTAssertEqual(asked, ["/h/Library/Cookies/Cookies.sqlite"])
    }

    func testADeniedProbeMeansNotGranted() {
        FilePrivacy.exists = { _ in true }
        XCTAssertFalse(FilePrivacy.granted(home: "/h") { _ in false })
    }

    /// A home where no probe file exists yet cannot be told either way, and the
    /// safe reading of "cannot tell" is "keep out".
    func testAnUnanswerableProbeIsReportedAsNotGranted() {
        FilePrivacy.exists = { _ in false }
        XCTAssertFalse(FilePrivacy.granted(home: "/h") { _ in true })
        XCTAssertNil(FilePrivacy.probe(home: "/h"))
    }

    /// The probe must not read somewhere the walk would not already have skipped:
    /// a check for a grant is allowed to cost one open, not to enter a folder
    /// that has its own prompt.
    func testEveryProbeSitsBehindARootTheWalkSkips() {
        for probe in FilePrivacy.probeSubpaths {
            let root = String(probe.split(separator: "/").first ?? "")
            XCTAssertTrue(FilePrivacy.protectedSubpaths.contains(root),
                          "\(probe) is probed but \(root) is not skipped")
        }
    }

    /// The three gates that **prompt** on first read. If one of these ever leaves
    /// the list, a status poll can raise a dialog in a session nobody is watching.
    func testThePromptingFolderGatesAreSkipped() {
        for name in ["Desktop", "Documents", "Downloads"] {
            XCTAssertTrue(FilePrivacy.protectedSubpaths.contains(name),
                          "\(name) prompts on first read and must never be walked ungranted")
        }
    }

    /// `Library` is skipped as a whole rather than container by container, because
    /// the per-app gate is evaluated for every protected bundle inside it.
    func testThePerAppDataRootIsSkippedAsOneDecision() {
        XCTAssertTrue(FilePrivacy.protectedSubpaths.contains("Library"))
    }

    func testRegisteringDoesNothingWhenThereIsNothingToOpen() {
        // No probe file exists, so this must not fall through to an open of some
        // other path in the account's home.
        FilePrivacy.exists = { _ in false }
        FilePrivacy.registerForFullDiskAccess(home: "/nonexistent-home")
    }
}
