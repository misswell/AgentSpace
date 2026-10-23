import Foundation
import AppKit
import AgentSpaceCore

/// The agent-side half of the clipboard bridge: `clipboard.push` and
/// `clipboard.pull`.
///
/// `ClipboardTransfer` in Core owns everything the two hosts must agree on —
/// the limit numbers, the staging layout, the naming rules, the retention
/// policy. This file owns only what needs *this* process and *this* session:
/// moving the staged bytes and driving `NSPasteboard.general`, which in an agent
/// account's Aqua session **is** the agent's clipboard. Nothing here reaches for
/// the person's board or their session; the controller (the Desktop Viewer or a
/// Fusion proxy) owns that side and calls these two methods.
///
/// Both methods start with `Operations.requireDesktopSession`, so a worker whose
/// session is on the physical console refuses instead of reading or writing
/// whatever board the person is using — that refusal is the product
/// (AGENTS.md §3), and it is the first thing either method does.
///
/// ## Why one serial lane
///
/// `NSPasteboard.general` is a single shared object in the session, and
/// `SocketServer` serves its RPC connections from a **concurrent** queue, so two
/// clipboard calls really can be in flight at once. Two pushes interleaving
/// `clearContents()` and `writeObjects(…)` would put one request's items on the
/// board beside another's, and — measured on macOS 26 — a `NSPasteboardItem`
/// that has already been through `writeObjects` can never be written again: AppKit
/// raises `NSInternalInconsistencyException` inside the call and the process dies
/// with SIGABRT, which is not a catchable Swift error. So every board access in
/// this worker goes through one serial lane, and every item is built fresh for
/// the write it belongs to (never cached on the context or the connection).
///
/// The lane is deliberately *not* the main queue: this process's main thread is
/// parked in `accept()` for its whole life (`SocketServer.serve`), so nothing
/// services the main queue and `DispatchQueue.main.sync` would deadlock rather
/// than hop. `clipboard.read` / `clipboard.write` have driven the same board from
/// the RPC queue since 0.1.82, and both directions here are the same shape: one
/// short, synchronous read or write.
enum ClipboardBridge {
    /// Every pasteboard access in this worker goes through here. See above.
    private static let board = DispatchQueue(label: BundleIdentifiers.worker + ".clipboard")

    /// Run `body` on the clipboard lane.
    ///
    /// `clipboard.read` and `clipboard.write` predate this file and are not part
    /// of the bridge, but `SocketServer` serves every RPC on a *concurrent* queue,
    /// so they can run beside a push and each would touch `NSPasteboard.general`
    /// from its own thread. Nothing about their params or results changes by
    /// taking the lane; what changes is that two clipboard calls can no longer be
    /// inside AppKit at the same time.
    static func onBoard<T>(_ body: () throws -> T) rethrows -> T {
        try board.sync(execute: body)
    }

    /// How often `clipboard.pull` re-reads `changeCount` while it waits for the
    /// ⌘C keystroke the person pressed to arrive. Small enough that a copy is
    /// answered as soon as it lands, coarse enough that a 2 s wait is 80 reads of
    /// one integer rather than a spin.
    private static let changeCountPollMilliseconds = 25

    // MARK: - clipboard.push

    /// Carry the person's clipboard into the agent's.
    ///
    /// Params: `{ "batch": "<inbox batch name>", "text": String?, "files":
    /// [ClipboardFileEntry], "hasText": Bool? }`. The bytes are already in this
    /// account's runtime directory when the call arrives — the controller staged
    /// them there because it is the one directory both users can reach
    /// (`RuntimePaths.applyACL`), and the agent account cannot read the person's
    /// home at all.
    ///
    /// The files are **moved**, not copied: `inbox/` is "the bytes for this
    /// request" and `pasted/` is "what the agent's board points at", so a paste
    /// ten minutes later still finds the file. `ClipboardTransfer.collect` makes
    /// the copy into `pasted/` and the inbox batch is then removed — that pair is
    /// the move, and it is done in this order so a failure mid-way leaves the
    /// bytes recoverable rather than gone. The retention sweep handles whatever an
    /// interrupted request left behind.
    static func push(params: JSONValue,
                     staging: ClipboardStaging,
                     fileManager: FileManager = .default) throws -> JSONValue {
        guard let rawBatch = params["batch"]?.stringValue,
              ClipboardStaging.isSafeBatchID(rawBatch) else {
            throw AgentSpaceError(code: .badRequest,
                                  message: "clipboard.push requires a staging batch directory name")
        }
        let inboxBatch = staging.directory(.inbox) + "/" + rawBatch

        // Decode before touching anything: a malformed request must cost no
        // observation and no mutation.
        var requested = try requestedFiles(params["files"])
        // The controller refuses more than this before it stages anything
        // (`ClipboardBridgePolicy`), but the bound is enforced here too: the
        // worker is the side that would pay for a caller that ignored it, and the
        // tail is not carried rather than the request failing.
        var truncated = requested.count > ClipboardLimits.maxFiles
        if requested.count > ClipboardLimits.maxFiles {
            requested = Array(requested.prefix(ClipboardLimits.maxFiles))
        }

        // The security boundary. The controller can write into `inbox/`; it
        // cannot tell this worker to read `~/.ssh` and put it on the agent's
        // board. `contains` resolves symlinks against the staging root first, so
        // a staged symlink pointing outside is refused too.
        for file in requested where !staging.contains(file.path, side: .inbox) {
            Log.input.error("clipboard.push refused a path outside the inbox staging directory")
            throw AgentSpaceError(
                code: .badRequest,
                message: "clipboard.push may only carry files staged in the inbox directory")
        }
        // A symbolic link is refused here rather than copied: `contains` resolves
        // a link that has a target, but a *broken* link cannot be resolved, so
        // `fileExists` reports it absent and the containment test falls back to
        // its enclosing directory — which is how a link to somewhere private would
        // otherwise reach the agent's board (measured on macOS 26, §397).
        for file in requested where ClipboardStaging.isSymbolicLink(file.path) {
            Log.input.error("clipboard.push refused a symbolic link in the staging directory")
            throw AgentSpaceError(
                code: .badRequest,
                message: "clipboard.push does not carry symbolic links")
        }

        let text = try textForPush(params: params, inboxBatch: inboxBatch, fileManager: fileManager)

        // Swept *before* the new batch exists, because `sweep` only guarantees the
        // newest batch survives: sweeping after creating mine could delete the
        // batch an answer was already handed out for, and the agent's board still
        // points at whatever the previous push wrote.
        let sweptPasted = ClipboardStaging.sweep(.pasted, staging: staging,
                                                 fileManager: fileManager)

        // Only a request that actually carries files needs a `pasted/` batch; a
        // text-only paste gets no empty directory left behind.
        var collected: [ClipboardFileEntry] = []
        var pastedBatch: String?
        if !requested.isEmpty {
            let entries = requested.map { file -> ClipboardFileEntry in
                var isDirectory: ObjCBool = false
                _ = fileManager.fileExists(atPath: file.path, isDirectory: &isDirectory)
                return ClipboardFileEntry(
                    name: ClipboardStaging.sanitizedName(
                        file.name ?? (file.path as NSString).lastPathComponent),
                    path: file.path,
                    byteCount: ClipboardStaging.byteCount(
                        of: file.path, limit: ClipboardLimits.maxFileBytes,
                        fileManager: fileManager),
                    isDirectory: file.isDirectory ?? isDirectory.boolValue)
            }
            let batch = try staging.newBatch(.pasted)
            pastedBatch = batch
            let pastedItems = ClipboardStaging.itemsDirectory(inBatch: batch)
            switch ClipboardTransfer.collect(entries: entries, into: pastedItems,
                                             sourceSide: .inbox, staging: staging,
                                             fileManager: fileManager) {
            case .refused(let error):
                // Nothing fitted — the first item alone was over the limit. The
                // inbox batch is left alone: the controller staged bytes this
                // worker could not carry, and deleting them would make the
                // refusal look like a successful transfer.
                try? fileManager.removeItem(atPath: batch)
                throw error
            case .staged(let staged):
                collected = staged
            case .partial(let staged, _):
                collected = staged
                truncated = true
            }
            // Nothing landed, so no board will point at this batch. Removing it
            // keeps the "a pasted batch is what the board points at" rule true, and
            // the push still answers honestly — `truncated`, with whatever text
            // there was — instead of failing the whole request because the files
            // could not be carried. The board is still written (an empty one when
            // the request carried no text), which is the same thing
            // `clipboard.write` does for empty text: the ⌘V that follows finds
            // what the person copied, not the agent's previous clipboard.
            if collected.isEmpty {
                try? fileManager.removeItem(atPath: batch)
                pastedBatch = nil
                truncated = true
            }
        }

        do {
            try writeBoard(text: text, files: collected)
        } catch {
            // The board never got these paths, so nothing will ever point at
            // them: remove the copy rather than leave the person's file in a
            // directory no clipboard and no sweep-for-the-newest-batch protects.
            if let pastedBatch { try? fileManager.removeItem(atPath: pastedBatch) }
            throw error
        }

        let textBytes = text?.utf8.count ?? 0
        let totalBytes = collected.reduce(0) { $0 + $1.byteCount }

        // The request has been carried, so its input is spent: remove the inbox
        // batch instead of leaving the person's files staged until the retention
        // sweep ages them out. Best effort — the controller removes its own batch
        // as well, and a failure here costs disk, not correctness.
        try? fileManager.removeItem(atPath: inboxBatch)
        let sweptInbox = ClipboardStaging.sweep(.inbox, staging: staging, fileManager: fileManager)
        Log.input.info("""
            clipboard.push: \(collected.count) file(s), \(textBytes) text byte(s), \
            \(totalBytes) file byte(s), truncated=\(truncated); \
            swept inbox=\(sweptInbox.count) pasted=\(sweptPasted.count)
            """)

        return .obj([
            "written": .bool(true),
            "textBytes": .int(textBytes),
            "files": .int(collected.count),
            "totalBytes": .int(totalBytes),
            "truncated": .bool(truncated),
        ])
    }

    /// One file the controller says it staged. Only `path` is load-bearing — the
    /// name, the byte count and the directory flag are advisory, because the
    /// worker measures the copy it makes and sanitizes the name it creates.
    private struct RequestedFile {
        var name: String?
        var path: String
        var isDirectory: Bool?
    }

    private static func requestedFiles(_ value: JSONValue?) throws -> [RequestedFile] {
        let raw = value?.arrayValue ?? []
        var files: [RequestedFile] = []
        files.reserveCapacity(raw.count)
        for element in raw {
            // `ClipboardFileEntry` is the contract's shape; decode through it
            // where it can, and fall back to the two fields that matter so a
            // caller that sends only name and path still works.
            if let entry = ClipboardFileEntry(json: element) {
                files.append(RequestedFile(name: entry.name, path: entry.path,
                                           isDirectory: entry.isDirectory))
                continue
            }
            guard let path = element["path"]?.stringValue, path.hasPrefix("/") else {
                throw AgentSpaceError(
                    code: .badRequest,
                    message: "clipboard.push files entries need an absolute path")
            }
            files.append(RequestedFile(name: element["name"]?.stringValue,
                                       path: path,
                                       isDirectory: element["directory"]?.boolValue))
        }
        return files
    }

    /// Where the agent-bound text is.
    ///
    /// The controller may send it inline (a short selection fits in one request
    /// line) or stage it as a file and say `hasText` — `ClipboardLimits`'
    /// rationale: a 1 MiB selection does not fit `Framing.maxRequestBytes` once
    /// JSON escaping multiplies it, so the file is the channel for the large
    /// case and both ends read it with the same bound. Absent `hasText` means
    /// "look for a staged file", which is what a staged push sends.
    private static func textForPush(params: JSONValue, inboxBatch: String,
                                    fileManager: FileManager) throws -> String? {
        if let inline = params["text"]?.stringValue {
            try SessionResource.validateText(inline)
            return inline
        }
        guard params["hasText"]?.boolValue ?? true else { return nil }
        return try ClipboardTransfer.stagedText(in: inboxBatch, fileManager: fileManager)
    }

    // MARK: - clipboard.pull

    /// Carry the agent's clipboard out to the person.
    ///
    /// Params: `{ "waitMilliseconds": Int?, "knownChangeCount": Int? }`.
    /// Result: `ClipboardContents.json` plus `"batch"` (the `outbox/` batch name
    /// the controller copies out of, or null when nothing was carried) and
    /// `"changeCount"` (the board's count at the moment it was read, so a caller
    /// that was waiting can tell "nothing new" from "read it again").
    ///
    /// The wait exists because the ⌘C the person pressed reaches the agent as an
    /// asynchronous keystroke: the reply cannot be there the instant the caller
    /// asks. A caller that supplies `knownChangeCount` gets up to
    /// `min(waitMilliseconds, maxPullWaitMilliseconds)` of reading instead of a
    /// race.
    static func pull(params: JSONValue,
                     staging: ClipboardStaging,
                     fileManager: FileManager = .default) throws -> JSONValue {
        let requestedWait = params["waitMilliseconds"]?.intValue
            ?? ClipboardLimits.pullWaitMilliseconds
        let waitMilliseconds = min(max(requestedWait, 0),
                                   ClipboardLimits.maxPullWaitMilliseconds)
        let knownChangeCount = params["knownChangeCount"]?.intValue

        let state = try snapshot(waitMilliseconds: waitMilliseconds,
                                 knownChangeCount: knownChangeCount)
        // An empty string on the board is nothing to paste; reporting it as text
        // would make `hasText` lie to the controller.
        let text = (state.text?.isEmpty ?? true) ? nil : state.text

        var files: [ClipboardFileEntry] = []
        var truncated = false
        var outboxBatch: String?
        var outboxItems: String?
        var copiedBytes = 0

        for url in state.fileURLs {
            if files.count >= ClipboardLimits.maxFiles {
                truncated = true
                break
            }
            let path = url.path
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
                // A path can be gone by the time the paste is read, or be a
                // Finder file-reference URL that does not resolve. One missing
                // item must not lose the rest of the copy.
                truncated = true
                continue
            }
            // A link on the agent's board is not content to carry out: copying it
            // would put a path on the person's clipboard that they cannot follow,
            // and the same broken-link loophole applies in this direction.
            if ClipboardStaging.isSymbolicLink(path) {
                truncated = true
                continue
            }
            let size = ClipboardStaging.byteCount(
                of: path, limit: ClipboardLimits.maxFileBytes, fileManager: fileManager)
            if size > ClipboardLimits.maxFileBytes {
                truncated = true
                continue
            }
            if copiedBytes + size > ClipboardLimits.maxFileBytes {
                truncated = true
                continue
            }
            if outboxItems == nil {
                let batch = try staging.newBatch(.outbox)
                outboxBatch = batch
                let items = ClipboardStaging.itemsDirectory(inBatch: batch)
                do {
                    try fileManager.createDirectory(atPath: items,
                                                    withIntermediateDirectories: true)
                } catch {
                    throw AgentSpaceError(
                        code: .internalError,
                        message: "could not create the clipboard outbox: \(error)")
                }
                outboxItems = items
            }
            guard let items = outboxItems else { continue }
            // These are the agent's own files, not staged ones, so
            // `ClipboardTransfer.stage` cannot be used: it checks `contains` for
            // the side it is given, and the only side that would admit these paths
            // does not exist. The copy is this worker's own, into its own batch,
            // bounded here by the same limits.
            let destination = ClipboardStaging.uniqueDestination(
                for: url.lastPathComponent, in: items) {
                    fileManager.fileExists(atPath: $0)
                }
            do {
                try fileManager.copyItem(atPath: path, toPath: destination)
            } catch {
                // Unreadable is a skip, never a failure of the whole paste: the
                // agent may hold a file whose mode excludes it, another app's
                // temporary file, or one that was deleted mid-copy.
                truncated = true
                continue
            }
            files.append(ClipboardFileEntry(
                name: (destination as NSString).lastPathComponent,
                path: destination,
                byteCount: ClipboardStaging.byteCount(
                    of: destination, limit: ClipboardLimits.maxFileBytes,
                    fileManager: fileManager),
                isDirectory: isDirectory.boolValue))
            copiedBytes += size
        }

        // A batch that ended up carrying nothing is not an answer the controller
        // can use; remove it rather than leaving an empty directory behind.
        if files.isEmpty, let outboxBatch {
            try? fileManager.removeItem(atPath: outboxBatch)
        }

        let contents = ClipboardContents(text: text, files: files,
                                         totalBytes: copiedBytes, truncated: truncated)
        var fields: [String: JSONValue] = [:]
        if case .object(let base) = contents.json { fields = base }
        // The batch name, not the path: the controller derives `outbox/` itself
        // from the same runtime directory, and a name is what
        // `ClipboardStaging.isSafeBatchID` can keep checking.
        fields["batch"] = (files.isEmpty ? nil : outboxBatch)
            .map { JSONValue.string(($0 as NSString).lastPathComponent) } ?? .null
        fields["changeCount"] = .int(state.changeCount)

        let swept = ClipboardStaging.sweep(.outbox, staging: staging, fileManager: fileManager)
        Log.session.info("""
            clipboard.pull: \(files.count) file(s), \(copiedBytes) byte(s), \
            text=\(text?.utf8.count ?? 0) byte(s), truncated=\(truncated), \
            waited=\(state.waitedMilliseconds)ms, changeCount=\(state.changeCount); \
            swept outbox=\(swept.count)
            """)
        return .obj(fields)
    }

    /// What the board held at one instant.
    private struct BoardSnapshot {
        var text: String?
        var fileURLs: [URL]
        var changeCount: Int
        var waitedMilliseconds: Int
    }

    /// Wait for the board to change (when asked to) and read it once.
    ///
    /// The wait is a series of one-value lane hops rather than one long hold: the
    /// lane exists to keep a `clearContents()` and its `writeObjects(…)` from
    /// interleaving, not to be owned for two seconds, and a ⌘V arriving while a
    /// ⌘C is still waiting must not queue behind it. Each hop does nothing but read
    /// `changeCount`, which is why a 2 s wait costs 80 short hops and never a spin.
    ///
    /// The *read* is then one uninterrupted board read, so the text and the files a
    /// caller receives come from the same clipboard — a copy that landed between
    /// two separate reads cannot produce text from one and files from another.
    /// Text over the limit is `BAD_REQUEST`, the same rule as `clipboard.read`: the
    /// caller is told, rather than handed a silently truncated selection it would
    /// believe was whole.
    private static func snapshot(waitMilliseconds: Int,
                                 knownChangeCount: Int?) throws -> BoardSnapshot {
        var waited = 0
        if let knownChangeCount {
            while waited < waitMilliseconds {
                let current = board.sync { NSPasteboard.general.changeCount }
                if current != knownChangeCount { break }
                Thread.sleep(forTimeInterval:
                    Double(changeCountPollMilliseconds) / 1000)
                waited += changeCountPollMilliseconds
            }
        }
        return try board.sync {
            let pasteboard = NSPasteboard.general
            let text = pasteboard.string(forType: .string)
            if let text { try SessionResource.validateText(text) }
            let urls = (pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) ?? []).compactMap(Self.fileURL(from:))
            return BoardSnapshot(text: text, fileURLs: urls,
                                 changeCount: pasteboard.changeCount,
                                 waitedMilliseconds: waited)
        }
    }

    /// The file URL an object read off the board stands for, if it is one.
    ///
    /// `readObjects(forClasses: [NSURL.self], …)` answers `[Any]` and what a given
    /// application actually left there varies: some boards hand back an `NSURL`,
    /// some a `URL`, and a WebKit or Electron copy can leave a `file://` string
    /// under a type that still reads as a URL object. All three mean the same
    /// thing, and the file-existence check downstream is what decides whether the
    /// path is usable.
    private static func fileURL(from object: Any) -> URL? {
        if let url = object as? URL { return url.isFileURL ? url : nil }
        if let url = object as? NSURL { return url.isFileURL ? url as URL : nil }
        if let string = object as? String,
           let url = URL(string: string), url.isFileURL { return url }
        return nil
    }

    // MARK: - The agent's board

    /// Put exactly `text` and `files` on the agent's board, as one write.
    ///
    /// The shapes are measured on macOS 26, not assumed:
    ///
    /// - `writeObjects([URL])` answers items:1 carrying `public.file-url` and
    ///   **no** string type. That is what a files-only copy has to look like: a
    ///   text paste into a files-only board must find nothing rather than invent
    ///   text out of the paths.
    /// - `writeObjects([NSPasteboardItem(.string), URL])` answers items:2 with
    ///   both types present, and both `string(forType: .string)` and
    ///   `readObjects(forClasses: [NSURL.self], options:
    ///   [.urlReadingFileURLsOnly: true])` then read back what was written — so
    ///   text and files can travel together, which is what an app that copies a
    ///   selection and a file reference needs.
    ///
    /// A text-only clipboard goes through `setString` exactly like
    /// `clipboard.write` does, so an empty string still clears the board.
    ///
    /// Every `NSPasteboardItem` is created here and never cached: an item that has
    /// been through `writeObjects` once cannot be written a second time, and
    /// AppKit raises an uncatchable exception inside the call when it is tried —
    /// so the clear and the write are also one uninterrupted step inside the
    /// lane, with no moment where the board is half-filled.
    private static func writeBoard(text: String?, files: [ClipboardFileEntry]) throws {
        try board.sync {
            let pasteboard = NSPasteboard.general
            if files.isEmpty {
                pasteboard.clearContents()
                guard let text, !text.isEmpty else { return }
                guard pasteboard.setString(text, forType: .string) else {
                    throw AgentSpaceError(
                        code: .internalError,
                        message: "the agent clipboard could not accept text")
                }
                return
            }
            // The exact shape measured on macOS 26: a text `NSPasteboardItem`
            // first, then one `NSURL` per file. That answers items:2 (or 1+n)
            // with both `public.utf8-plain-text` and `public.file-url` present,
            // and both `string(forType: .string)` and
            // `readObjects(forClasses: [NSURL.self], options:
            // [.urlReadingFileURLsOnly: true])` read back what was written.
            //
            // `NSURL` objects, not `NSPasteboardItem`s carrying a `.fileURL`
            // string: the URL shape is the one measured to answer
            // `public.file-url` alone for a files-only copy, so a text paste
            // into a files-only board finds nothing rather than inventing text
            // out of the paths.
            var objects: [NSPasteboardWriting] = []
            if let text, !text.isEmpty {
                let item = NSPasteboardItem()
                guard item.setString(text, forType: .string) else {
                    throw AgentSpaceError(
                        code: .internalError,
                        message: "the agent clipboard could not accept text")
                }
                objects.append(item)
            }
            objects.append(contentsOf: files.map {
                URL(fileURLWithPath: $0.path) as NSURL
            })
            pasteboard.clearContents()
            guard pasteboard.writeObjects(objects) else {
                throw AgentSpaceError(
                    code: .internalError,
                    message: "the agent clipboard could not accept the pasted items")
            }
        }
    }
}
