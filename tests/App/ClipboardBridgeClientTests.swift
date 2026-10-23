import XCTest
import AgentSpaceCore
@testable import AgentSpaceApp

/// What the person's own half of the bridge refuses *before* the worker sees it.
///
/// The worker is the security boundary — it refuses any path outside its inbox
/// (§397 row 1327). This file pins the other side of that contract: the copy the
/// GUI stages must never contain something the worker can only refuse, because a
/// refusal costs the whole request including its text. The two properties here
/// were both found the hard way: a *broken* symlink passes a containment test
/// (`fileExists` follows links, so an unresolvable one reads as absent), and a
/// person who copies a link in the Finder would otherwise lose a paste that was
/// perfectly good apart from one item.
final class ClipboardBridgeClientTests: XCTestCase {
    private var root: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // A short, per-test directory: `ClipboardStaging` builds real paths from
        // it, and the staging rules are about paths.
        root = "/tmp/clipboard-client-tests-" + UUID().uuidString.prefix(8)
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(atPath: root) }
        try super.tearDownWithError()
    }

    private func write(_ name: String, _ contents: String, in directory: String) -> String {
        let path = directory + "/" + name
        try? Data(contents.utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    /// A link copied in the Finder is skipped, and the rest of the copy survives.
    ///
    /// This is the shape that made the whole push fail before the fix: the staged
    /// copy of the link became a link inside `inbox/`, and `clipboard.push`
    /// refuses a request that names one.
    func testASymbolicLinkIsSkippedAndTheOtherFilesStillCross() throws {
        let source = root + "/source"
        try FileManager.default.createDirectory(atPath: source, withIntermediateDirectories: true)
        let real = write("report.txt", "the real file", in: source)
        let link = source + "/shortcut"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)

        let batch = root + "/batch"
        try FileManager.default.createDirectory(atPath: batch, withIntermediateDirectories: true)
        let staged = ClipboardBridgeTransport.stagedPersonFiles([real, link], into: batch)

        XCTAssertEqual(staged.entries.map(\.name), ["report.txt"],
                       "the link must be skipped, the real file carried")
        XCTAssertTrue(staged.truncated, "a skipped item is what `truncated` means")
        let stagedContents = try FileManager.default.contentsOfDirectory(
            atPath: ClipboardStaging.itemsDirectory(inBatch: batch))
        XCTAssertEqual(stagedContents.filter { $0 != ".DS_Store" }, ["report.txt"],
                       "nothing that the worker would have to refuse may be staged")
    }

    /// A *broken* link is skipped too — the case that used to pass the containment
    /// test in the worker, because `fileExists` follows the link and reports an
    /// unresolvable one as absent.
    ///
    /// Do not "simplify" the check away by relying on `fileExists`: that is exactly
    /// the reasoning that let this through once (§397 row 1327).
    func testABrokenSymbolicLinkIsSkippedRatherThanStaged() throws {
        let source = root + "/broken-source"
        try FileManager.default.createDirectory(atPath: source, withIntermediateDirectories: true)
        let link = source + "/dangling"
        try FileManager.default.createSymbolicLink(
            atPath: link, withDestinationPath: "/nonexistent-" + UUID().uuidString)

        // The property that made this a leak: the file manager cannot see it.
        XCTAssertFalse(FileManager.default.fileExists(atPath: link))
        XCTAssertTrue(ClipboardStaging.isSymbolicLink(link))

        let batch = root + "/batch-broken"
        try FileManager.default.createDirectory(atPath: batch, withIntermediateDirectories: true)
        let staged = ClipboardBridgeTransport.stagedPersonFiles([link], into: batch)

        XCTAssertTrue(staged.entries.isEmpty)
        XCTAssertTrue(staged.truncated)
    }

    /// A folder is one item, whatever is inside it — the Finder case.
    func testAFolderIsStagedWholeAsOneEntry() throws {
        let source = root + "/folder-source"
        let nested = source + "/inner"
        try FileManager.default.createDirectory(atPath: nested, withIntermediateDirectories: true)
        _ = write("a.txt", "one", in: source)
        _ = write("b.txt", "two", in: nested)

        let batch = root + "/batch-folder"
        try FileManager.default.createDirectory(atPath: batch, withIntermediateDirectories: true)
        let staged = ClipboardBridgeTransport.stagedPersonFiles([source], into: batch)

        XCTAssertEqual(staged.entries.count, 1)
        XCTAssertTrue(staged.entries[0].isDirectory)
        XCTAssertEqual(staged.entries[0].name, "folder-source")
        let copied = try FileManager.default.contentsOfDirectory(
            atPath: staged.entries[0].path).sorted()
        XCTAssertEqual(copied, ["a.txt", "inner"], "the tree crosses, not just the name")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: staged.entries[0].path + "/inner/b.txt"))
    }

    /// Two files with the same name both survive, under names that cannot collide.
    func testTheSameNameFromTwoPlacesGetsADistinctDestination() throws {
        let a = root + "/a", b = root + "/b"
        for directory in [a, b] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        let first = write("notes.txt", "from a", in: a)
        let second = write("notes.txt", "from b", in: b)

        let batch = root + "/batch-dupes"
        try FileManager.default.createDirectory(atPath: batch, withIntermediateDirectories: true)
        let staged = ClipboardBridgeTransport.stagedPersonFiles([first, second], into: batch)

        XCTAssertEqual(staged.entries.count, 2)
        XCTAssertNotEqual(staged.entries[0].name, staged.entries[1].name)
        XCTAssertEqual(staged.entries[0].name, "notes.txt")
        let secondContents = try String(contentsOfFile: staged.entries[1].path, encoding: .utf8)
        XCTAssertEqual(secondContents, "from b", "the second copy is the second file")
    }

    /// A path that no longer exists is skipped, not fatal — a Finder copy can
    /// outlive a file that moved between the pasteboard read and the copy.
    func testAVanishedPathIsSkippedWithoutLosingTheRest() throws {
        let source = root + "/vanish-source"
        try FileManager.default.createDirectory(atPath: source, withIntermediateDirectories: true)
        let real = write("kept.txt", "kept", in: source)
        let gone = source + "/gone.txt"

        let batch = root + "/batch-vanish"
        try FileManager.default.createDirectory(atPath: batch, withIntermediateDirectories: true)
        let staged = ClipboardBridgeTransport.stagedPersonFiles([gone, real], into: batch)

        XCTAssertEqual(staged.entries.map(\.name), ["kept.txt"])
        XCTAssertTrue(staged.truncated)
    }
}
