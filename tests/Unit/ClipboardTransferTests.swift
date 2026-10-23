import Foundation
import XCTest
import AgentSpaceCore

/// The staging half of 「复制粘贴进子窗口」: how a file crosses from one user's
/// desktop to another's, and every rule that keeps that from becoming a file
/// *read* of the agent's home.
///
/// Everything here is exercised against a throwaway directory under `/tmp`, never
/// against a real `/Library/Application Support/AgentSpace/Runtime/...`: these
/// functions delete whole batches, and a test that pointed them at a live runtime
/// could delete a paste that had not happened yet. The pasteboard is not touched
/// either — only paths and bytes are.
final class ClipboardTransferTests: XCTestCase {

    private var root: URL!
    private var staging: ClipboardStaging!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        // Short base path: the production layout appends
        // `/clipboard/<side>/<batch>/items/<name>`, and a deep temporary path
        // turns every failure message into an unreadable one.
        root = URL(fileURLWithPath: "/tmp/clipboard-tests-\(UUID().uuidString.prefix(8).lowercased())")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        staging = ClipboardStaging(runtimeDirectory: root.path)
    }

    override func tearDownWithError() throws {
        if let root { try? fileManager.removeItem(at: root) }
        root = nil
        staging = nil
    }

    // MARK: - Fixtures

    @discardableResult
    private func makeFile(_ path: String, contents: String = "clipboard content") throws -> String {
        try fileManager.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                        withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    /// A file of `byteCount` bytes that occupies almost no disk.
    ///
    /// The size limits are 128 MiB and 512 MiB; writing those bytes for real
    /// would make this suite the thing that fills the boot volume, which is the
    /// failure the limits exist to prevent.
    private func makeSparseFile(_ path: String, byteCount: Int) throws {
        try fileManager.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                        withIntermediateDirectories: true)
        guard fileManager.createFile(atPath: path, contents: Data()) else {
            return XCTFail("could not create \(path)")
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(byteCount - 1))
        try handle.write(contentsOf: Data([0x41]))
    }

    private func items(inBatch batch: String) throws -> [String] {
        try fileManager.contentsOfDirectory(
            atPath: ClipboardStaging.itemsDirectory(inBatch: batch)).sorted()
    }

    private func carried(_ outcome: ClipboardTransfer.Outcome) -> [ClipboardFileEntry] {
        switch outcome {
        case .staged(let entries), .partial(let entries, _): return entries
        case .refused: return []
        }
    }

    private func isTruncated(_ outcome: ClipboardTransfer.Outcome) -> Bool {
        switch outcome {
        case .staged: return false
        case .partial(_, let truncated): return truncated
        case .refused: return false
        }
    }

    private func refusal(_ outcome: ClipboardTransfer.Outcome) -> AgentSpaceError? {
        if case .refused(let error) = outcome { return error }
        return nil
    }

    // MARK: - Staging files

    func testStageCopiesAFileAndAFolderIntoItems() throws {
        // A Finder copy is one item per selection, and a folder is one of them.
        // The person pastes the folder and expects the folder, not its top level
        // — so a directory has to arrive whole.
        let batch = try staging.newBatch(.inbox)
        let file = try makeFile(batch + "/report.txt", contents: "quarterly")
        let folder = batch + "/Photos"
        try makeFile(folder + "/one.png", contents: "png")
        try makeFile(folder + "/nested/two.png", contents: "png")

        let outcome = ClipboardTransfer.stage(paths: [file, folder], into: batch,
                                             sourceSide: .inbox, staging: staging)
        guard case .staged(let entries) = outcome else {
            return XCTFail("a file and a folder both fit the budget: \(outcome)")
        }
        XCTAssertEqual(entries.map(\.name).sorted(), ["Photos", "report.txt"])
        let itemsDirectory = ClipboardStaging.itemsDirectory(inBatch: batch)
        XCTAssertEqual(try items(inBatch: batch), ["Photos", "report.txt"])
        XCTAssertEqual(try String(contentsOfFile: itemsDirectory + "/report.txt", encoding: .utf8),
                       "quarterly")
        let copied = try XCTUnwrap(entries.first { $0.name == "Photos" })
        XCTAssertTrue(copied.isDirectory)
        XCTAssertEqual(copied.path, itemsDirectory + "/Photos")
        XCTAssertGreaterThan(copied.byteCount, 0)
        XCTAssertTrue(fileManager.fileExists(atPath: itemsDirectory + "/Photos/nested/two.png"),
                      "the folder must arrive with its contents")
    }

    func testStageWillNotCopyASourceOutsideTheStagingSide() throws {
        // The security boundary, at the layer that enforces it for both hosts: a
        // caller may name any path, and only paths already inside the named
        // side may be copied. Without this, `stage` is a file-reading primitive
        // for the agent's `~/.ssh`.
        let batch = try staging.newBatch(.inbox)
        let outside = try makeFile(root.path + "/outside/secret.txt", contents: "private")
        XCTAssertFalse(staging.contains(outside, side: .inbox),
                       "the fixture must really be outside the inbox side")

        let outcome = ClipboardTransfer.stage(paths: [outside], into: batch,
                                             sourceSide: .inbox, staging: staging)
        XCTAssertTrue(carried(outcome).isEmpty)
        XCTAssertTrue(isTruncated(outcome), "a refused source must be reported as partial, never as a full success")
        XCTAssertEqual(try items(inBatch: batch), [],
                       "nothing from outside the staging side may be copied in")
    }

    func testAnOversizedItemIsRefusedAloneAndSkippedAmongOthers() throws {
        let batch = try staging.newBatch(.inbox)
        let big = batch + "/movie.mov"
        try makeSparseFile(big, byteCount: ClipboardLimits.maxFileBytes + 1)

        // Alone, nothing fits: the answer is a typed refusal rather than a
        // success with nothing in it.
        let alone = ClipboardTransfer.stage(paths: [big], into: batch,
                                           sourceSide: .inbox, staging: staging)
        let error = try XCTUnwrap(refusal(alone), "a lone item over the limit must be refused: \(alone)")
        XCTAssertEqual(error.code, .badRequest)
        XCTAssertTrue(try items(inBatch: batch).isEmpty)

        // Among others, one oversized item must not lose the rest: the document
        // beside the movie still crosses, and the answer says it was partial.
        let small = try makeFile(batch + "/notes.txt", contents: "small")
        let mixed = ClipboardTransfer.stage(paths: [small, big], into: batch,
                                            sourceSide: .inbox, staging: staging)
        XCTAssertEqual(carried(mixed).map(\.name), ["notes.txt"])
        XCTAssertTrue(isTruncated(mixed))
        XCTAssertFalse(fileManager.fileExists(
            atPath: ClipboardStaging.itemsDirectory(inBatch: batch) + "/movie.mov"))
    }

    func testTheItemLimitTruncatesRatherThanRefusing() throws {
        // 32 items is a budget, not a wall: the first 32 still cross and the
        // answer says the tail was left behind. Refusing outright would turn a
        // slightly-too-large Finder selection into a paste that does nothing.
        let batch = try staging.newBatch(.inbox)
        let files = try (0..<3).map { try makeFile(batch + "/item-\($0).txt") }
        let outcome = ClipboardTransfer.stage(paths: files, into: batch, sourceSide: .inbox,
                                             staging: staging, limit: 2)
        guard case .partial(let entries, let truncated) = outcome else {
            return XCTFail("over the item limit is partial, not refused: \(outcome)")
        }
        XCTAssertEqual(entries.map(\.name), ["item-0.txt", "item-1.txt"])
        XCTAssertTrue(truncated)
    }

    // MARK: - Symbolic links

    func testASymlinkInsideTheStagingSideIsNotCarried() throws {
        // A link inside the side resolves *inside* the side, so containment
        // passes — and it is still not an item: a clipboard carries bytes, and a
        // link would carry a path. That is the difference between a copy engine
        // and a reading engine.
        let batch = try staging.newBatch(.inbox)
        let target = try makeFile(batch + "/real.txt", contents: "content")
        let link = batch + "/link.txt"
        try fileManager.createSymbolicLink(atPath: link, withDestinationPath: target)
        XCTAssertTrue(staging.contains(link, side: .inbox),
                      "the containment test admits this link; the symlink rule is what refuses it")

        let outcome = ClipboardTransfer.stage(paths: [link], into: batch,
                                             sourceSide: .inbox, staging: staging)
        XCTAssertTrue(carried(outcome).isEmpty)
        XCTAssertTrue(isTruncated(outcome))
        XCTAssertEqual(try items(inBatch: batch), [])
    }

    func testABrokenSymlinkIsNotCarriedEither() throws {
        // This is the shape that used to leak (§397), and the reason
        // `ClipboardStaging.isSymbolicLink` exists at all — do not remove the
        // check while "simplifying" the two tests above and below.
        //
        // `fileExists` follows a link, so a *broken* link reports absent.
        // `WorkspaceGuard.resolve` then falls back to resolving its enclosing
        // directory, which is inside the staging root — so containment passes.
        // A working link pointing outside is correctly refused; only the broken
        // one got through, and a link to a path that does not exist yet is
        // exactly what a later read would have followed.
        let batch = try staging.newBatch(.inbox)
        let link = batch + "/sneaky"
        try fileManager.createSymbolicLink(atPath: link,
                                           withDestinationPath: "/nonexistent-" + UUID().uuidString)
        XCTAssertFalse(fileManager.fileExists(atPath: link),
                       "a broken link reports absent — this is the trap")
        XCTAssertTrue(staging.contains(link, side: .inbox),
                      "containment alone admits a broken link; that asymmetry was the defect")

        let outcome = ClipboardTransfer.stage(paths: [link], into: batch,
                                             sourceSide: .inbox, staging: staging)
        XCTAssertTrue(carried(outcome).isEmpty, "a broken link must not become a clipboard entry")
        XCTAssertTrue(isTruncated(outcome))
        XCTAssertEqual(try items(inBatch: batch), [])
    }

    func testIsSymbolicLinkTellsLinksFromFilesAndFolders() throws {
        // The one predicate the refusal rests on, pinned directly: a regular
        // file and a folder are items, a link of either flavour is not.
        let batch = try staging.newBatch(.inbox)
        let file = try makeFile(batch + "/file.txt")
        let folder = batch + "/folder"
        try fileManager.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let working = batch + "/working"
        try fileManager.createSymbolicLink(atPath: working, withDestinationPath: file)
        let broken = batch + "/broken"
        try fileManager.createSymbolicLink(atPath: broken,
                                           withDestinationPath: "/nonexistent-" + UUID().uuidString)

        XCTAssertFalse(ClipboardStaging.isSymbolicLink(file))
        XCTAssertFalse(ClipboardStaging.isSymbolicLink(folder))
        XCTAssertTrue(ClipboardStaging.isSymbolicLink(working))
        XCTAssertTrue(ClipboardStaging.isSymbolicLink(broken),
                      "the broken case is the one the check exists for")
    }

    func testCollectSkipsASymlinkEntryTheSameWay() throws {
        // The other half of the transfer has to refuse what the first half
        // refuses, or a reader could be handed a link by a caller that never
        // went through `stage`.
        let inbox = try staging.newBatch(.inbox)
        let inboxItems = ClipboardStaging.itemsDirectory(inBatch: inbox)
        let real = try makeFile(inboxItems + "/real.txt", contents: "real")
        let link = inboxItems + "/link.txt"
        try fileManager.createSymbolicLink(atPath: link,
                                           withDestinationPath: "/nonexistent-" + UUID().uuidString)

        let pasted = try staging.newBatch(.pasted)
        let destination = ClipboardStaging.itemsDirectory(inBatch: pasted)
        let outcome = ClipboardTransfer.collect(
            entries: [ClipboardFileEntry(name: "real.txt", path: real, byteCount: 4, isDirectory: false),
                      ClipboardFileEntry(name: "link.txt", path: link, byteCount: 0, isDirectory: false)],
            into: destination, sourceSide: .inbox, staging: staging)

        XCTAssertEqual(carried(outcome).map(\.name), ["real.txt"])
        XCTAssertTrue(isTruncated(outcome))
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: destination), ["real.txt"])
    }

    // MARK: - Staging text

    func testStagedTextRoundTripsAndRefusesWhatItCannotRead() throws {
        let batch = try staging.newBatch(.inbox)
        // A files-only clipboard staged no text; nil is the answer, not an error.
        XCTAssertNil(try ClipboardTransfer.stagedText(in: batch))

        let path = try ClipboardTransfer.stage(text: "中文 text\nline two", in: batch)
        XCTAssertEqual(path, batch + "/" + ClipboardLimits.stagedTextFileName)
        XCTAssertEqual(try ClipboardTransfer.stagedText(in: batch), "中文 text\nline two")
        // Beside `items/`, not inside it: a copied file that happens to be
        // called text.txt must not collide with the staged selection.
        XCTAssertFalse(fileManager.fileExists(
            atPath: ClipboardStaging.itemsDirectory(inBatch: batch) + "/" + ClipboardLimits.stagedTextFileName))

        // Over the limit is a refusal, never a truncation: half a selection
        // looks like a whole one to the person who pastes it.
        XCTAssertThrowsError(try ClipboardTransfer.stage(
            text: String(repeating: "a", count: ClipboardLimits.maxTextBytes + 1), in: batch)) {
            XCTAssertEqual(($0 as? AgentSpaceError)?.code, .badRequest)
        }
        // A file that is over the limit on disk is refused *before* it is read,
        // so a caller cannot make the worker allocate an arbitrary file.
        try Data(repeating: 0x61, count: ClipboardLimits.maxTextBytes + 1)
            .write(to: URL(fileURLWithPath: path))
        XCTAssertThrowsError(try ClipboardTransfer.stagedText(in: batch)) {
            XCTAssertEqual(($0 as? AgentSpaceError)?.code, .badRequest)
        }
        // Invalid UTF-8 is an error rather than replacement characters: garbage
        // pasted quietly is worse than a paste that says it failed.
        try Data([0xff, 0xfe, 0x00, 0x41]).write(to: URL(fileURLWithPath: path))
        XCTAssertThrowsError(try ClipboardTransfer.stagedText(in: batch)) {
            XCTAssertEqual(($0 as? AgentSpaceError)?.code, .badRequest)
        }
    }

    // MARK: - Collecting files out

    func testCollectCopiesTheEntriesAndRefusesAPathOutsideTheNamedSide() throws {
        // The mirror of `stage`: the side that will hand the files to a person
        // makes its own copies, so neither side's later edits or deletions can
        // pull a file out from under a paste that has not happened yet.
        let inbox = try staging.newBatch(.inbox)
        let staged = try makeFile(ClipboardStaging.itemsDirectory(inBatch: inbox) + "/report.pdf",
                                  contents: "pdf bytes")
        let outside = try makeFile(root.path + "/elsewhere/photo.jpg", contents: "jpg bytes")
        let pasted = try staging.newBatch(.pasted)
        let destination = ClipboardStaging.itemsDirectory(inBatch: pasted)

        let outcome = ClipboardTransfer.collect(
            entries: [ClipboardFileEntry(name: "report.pdf", path: staged, byteCount: 9, isDirectory: false),
                      ClipboardFileEntry(name: "photo.jpg", path: outside, byteCount: 9, isDirectory: false)],
            into: destination, sourceSide: .inbox, staging: staging)

        XCTAssertEqual(carried(outcome).map(\.name), ["report.pdf"],
                       "names are carried through unchanged, and only the staged entry moves")
        XCTAssertTrue(isTruncated(outcome))
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: destination), ["report.pdf"])
        XCTAssertEqual(try String(contentsOfFile: destination + "/report.pdf", encoding: .utf8),
                       "pdf bytes")
    }

    // MARK: - Retention

    private func makeBatch(_ side: ClipboardStaging.Side, age: TimeInterval, now: Date) throws -> String {
        let batch = try staging.newBatch(side)
        try makeFile(ClipboardStaging.itemsDirectory(inBatch: batch) + "/file.txt", contents: "x")
        // Distinct modification dates rather than sleeps: `sweep` orders by
        // mtime, so the test sets the dates it needs instead of waiting for the
        // clock.
        try fileManager.setAttributes([.modificationDate: now.addingTimeInterval(-age)],
                                      ofItemAtPath: batch)
        return batch
    }

    func testSweepRemovesBatchesPastTheRetentionWindowAndKeepsTheRest() throws {
        let now = Date()
        let newest = try makeBatch(.inbox, age: 0, now: now)
        let recent = try makeBatch(.inbox, age: 60, now: now)
        let stale = try makeBatch(.inbox, age: ClipboardLimits.batchRetention + 3600, now: now)
        // A batch on another side is what the agent's board points at; sweeping
        // one side must not touch it, or the next paste reads nothing.
        let pastedStale = try makeBatch(.pasted, age: ClipboardLimits.batchRetention + 3600, now: now)

        let removed = ClipboardStaging.sweep(.inbox, staging: staging, now: now)

        XCTAssertEqual(removed, [stale], "the leftovers are reported, not just deleted")
        XCTAssertTrue(fileManager.fileExists(atPath: newest))
        XCTAssertTrue(fileManager.fileExists(atPath: recent))
        XCTAssertFalse(fileManager.fileExists(atPath: stale))
        XCTAssertTrue(fileManager.fileExists(atPath: pastedStale),
                      "sweeping the inbox side must not delete what the agent's board points at")
    }

    func testSweepRemovesTheOldestOnceASideIsOverTheBatchCount() throws {
        let now = Date()
        // Newest first: age 0 is the batch a paste is about to use.
        let batches = try (0...(ClipboardLimits.maxKeptBatches + 1)).map {
            try makeBatch(.inbox, age: TimeInterval($0), now: now)
        }
        let newest = batches[0]
        let oldest = batches[batches.count - 1]
        let secondOldest = batches[batches.count - 2]

        let removed = ClipboardStaging.sweep(.inbox, staging: staging, now: now)

        XCTAssertEqual(Set(removed), Set([oldest, secondOldest]),
                       "two batches over the budget means exactly the two oldest go")
        XCTAssertTrue(fileManager.fileExists(atPath: newest))
        XCTAssertFalse(fileManager.fileExists(atPath: oldest))
        let kept = try fileManager.contentsOfDirectory(atPath: staging.directory(.inbox))
        XCTAssertEqual(kept.count, ClipboardLimits.maxKeptBatches,
                       "the side ends at the count it is allowed, not below it")
    }

    func testSweepKeepsTheNewestBatchHoweverLargeItIs() throws {
        // The newest batch is the one a paste is about to read, so it survives
        // even when it alone is over the byte budget — the next one out is the
        // one removed instead.
        let now = Date()
        let newest = try staging.newBatch(.inbox)
        try makeSparseFile(ClipboardStaging.itemsDirectory(inBatch: newest) + "/big.bin",
                           byteCount: ClipboardLimits.maxKeptBytes + 1)
        try fileManager.setAttributes([.modificationDate: now], ofItemAtPath: newest)
        let older = try staging.newBatch(.inbox)
        try makeSparseFile(ClipboardStaging.itemsDirectory(inBatch: older) + "/big.bin",
                           byteCount: ClipboardLimits.maxKeptBytes + 1)
        try fileManager.setAttributes([.modificationDate: now.addingTimeInterval(-60)],
                                      ofItemAtPath: older)

        let removed = ClipboardStaging.sweep(.inbox, staging: staging, now: now)

        XCTAssertEqual(removed, [older], "the over-budget batch that goes is the older one")
        XCTAssertTrue(fileManager.fileExists(atPath: newest),
                      "the newest batch is never the one removed, however large")
    }

    // MARK: - Names, batch ids and the wire shape (pure)

    func testSanitizedNameAlwaysYieldsAPlainBaseName() {
        // Every name arrives from another user's pasteboard, and a name is what
        // becomes a path on this side — so a separator, a NUL, leading dots and
        // an empty remainder all have to be handled here, once, for both ends.
        let cases: [(raw: String, expected: String)] = [
            ("/etc/passwd", "passwd"),
            ("../../etc/shadow", "shadow"),
            // A Windows-style path: the drive colon is stripped, and a backslash
            // is not a separator on macOS — so what is left is a plain name and
            // the "no separator" property below is what matters, not its shape.
            ("C:\\Users\\someone\\report.docx", "\\Users\\someone\\report.docx"),
            ("a\u{0}b.txt", "ab.txt"),
            ("..hidden", "hidden"),
            ("...", "file"),
            ("..", "file"),
            ("", "file"),
            ("   ", "file"),
        ]
        for (raw, expected) in cases {
            let clean = ClipboardStaging.sanitizedName(raw)
            XCTAssertEqual(clean, expected, "sanitizedName(\(raw.debugDescription))")
            XCTAssertFalse(clean.contains("/"), "\(clean.debugDescription) must not name a directory")
            XCTAssertFalse(clean.hasPrefix("."), "\(clean.debugDescription) must not be hidden")
            XCTAssertFalse(clean.isEmpty, "\(clean.debugDescription) must name something")
            XCTAssertLessThanOrEqual(clean.utf8.count, ClipboardLimits.maxNameBytes)
        }

        // The bound counts bytes, because it exists to keep a path short: 100 CJK
        // scalars are 300 bytes, and truncating by characters would leave a name
        // half again as long as the limit.
        let cjk = String(repeating: "中", count: 100)
        XCTAssertEqual(cjk.utf8.count, 300)
        let bounded = ClipboardStaging.sanitizedName(cjk)
        XCTAssertLessThanOrEqual(bounded.utf8.count, ClipboardLimits.maxNameBytes)
        XCTAssertFalse(bounded.isEmpty)
        XCTAssertTrue(cjk.hasPrefix(bounded), "the name is cut, never rewritten")
    }

    func testUniqueDestinationAppendsTheSuffixBeforeTheExtension() {
        // Pure, with `exists` injected, so both ends make the same choice for the
        // same input. A Finder copy of two files with one name must produce two
        // files, not one overwritten one.
        func destination(_ name: String, existing: Set<String>, in directory: String = "/d") -> String {
            ClipboardStaging.uniqueDestination(for: name, in: directory) { existing.contains($0) }
        }
        XCTAssertEqual(destination("report.pdf", existing: []), "/d/report.pdf",
                       "the first choice is the name itself")
        XCTAssertEqual(destination("report.pdf", existing: ["/d/report.pdf"]), "/d/report 2.pdf")
        XCTAssertEqual(destination("report.pdf", existing: ["/d/report.pdf", "/d/report 2.pdf"]),
                       "/d/report 3.pdf")
        XCTAssertEqual(destination("notes", existing: ["/d/notes"]), "/d/notes 2",
                       "a name with no extension gets the suffix appended")
        XCTAssertEqual(destination("a.txt", existing: [], in: "/d/"), "/d/a.txt",
                       "a trailing slash on the directory does not double up")
        XCTAssertEqual(destination("../../etc/passwd", existing: []), "/d/passwd",
                       "the destination is sanitised too, not just the stage")
    }

    func testIsSafeBatchIDAcceptsOnlyAPlainDirectoryName() throws {
        // The batch name is the only caller-influenced component of a staged
        // path, so it is validated rather than escaped.
        XCTAssertTrue(ClipboardStaging.isSafeBatchID(UUID().uuidString))
        XCTAssertTrue(ClipboardStaging.isSafeBatchID(String(repeating: "a", count: 64)),
                      "64 bytes is the documented bound, and it is inclusive")
        for bad in ["", ".", "..", "a/b", "../x", "a b", "a.b", "批次",
                    String(repeating: "a", count: 65)] {
            XCTAssertFalse(ClipboardStaging.isSafeBatchID(bad),
                           "\(bad.debugDescription) must not be a batch id")
        }
        // And the directory creator enforces the same rule, so no caller can
        // name its way out of the staging root.
        XCTAssertThrowsError(try staging.newBatch(.inbox, id: "../outside")) {
            XCTAssertEqual(($0 as? AgentSpaceError)?.code, .badRequest)
        }
        XCTAssertFalse(fileManager.fileExists(atPath: root.path + "/clipboard/outside"))
    }

    func testContentsSurvivesTheWireAndKnowsWhenItIsEmpty() throws {
        let file = ClipboardFileEntry(name: "a.txt", path: "/tmp/x/a.txt",
                                      byteCount: 12, isDirectory: false)
        let folder = ClipboardFileEntry(name: "Photos", path: "/tmp/x/Photos",
                                        byteCount: 2048, isDirectory: true)
        let contents = ClipboardContents(text: "hello", files: [file, folder],
                                         totalBytes: 2060, truncated: true)

        // Round trip: what the worker answered is what the controller reads, so a
        // count or the truncation flag cannot be lost between the two.
        XCTAssertEqual(ClipboardContents(json: contents.json), contents)
        XCTAssertEqual(contents.json["hasText"]?.boolValue, true)
        XCTAssertEqual(ClipboardContents(text: nil, files: [file]).json["hasText"]?.boolValue, false,
                       "hasText distinguishes \"no text\" from \"empty text\" for a receiver reading flags")
        XCTAssertEqual(contents.json["files"]?.arrayValue?.count, 2)

        // "Nothing to paste" is its own answer, because it is the one that must
        // leave the person's clipboard alone.
        XCTAssertTrue(ClipboardContents().isEmpty)
        XCTAssertTrue(ClipboardContents(text: "").isEmpty, "an empty string is nothing to paste")
        XCTAssertFalse(ClipboardContents(text: "x").isEmpty)
        XCTAssertFalse(ClipboardContents(files: [file]).isEmpty)

        // A wire shape without the sum still reports one, and a file entry whose
        // path is not absolute cannot become a path on this side.
        XCTAssertEqual(ClipboardContents(json: .obj(["files": .array([file.json])])).totalBytes, 12)
        XCTAssertNil(ClipboardFileEntry(json: .obj([
            "name": .string("x"), "path": .string("relative.txt"), "bytes": .int(1),
        ])), "a relative path is not a staged path")
    }
}
