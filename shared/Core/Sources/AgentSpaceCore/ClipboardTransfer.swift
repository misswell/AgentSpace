import Foundation

/// Moving a person's clipboard across the two desktops — the core half of
/// 「复制粘贴进子窗口」.
///
/// The product already had a *text* clipboard for agents (`clipboard.read` /
/// `clipboard.write`, 0.1.82+, MCP `clipboard_read` / `clipboard_write`). What
/// that pair could not do is carry what a person actually copies in the Finder:
/// a file. And it was an agent API — nothing in the Desktop Viewer or a Fusion
/// proxy ever connected the person's clipboard to the agent's.
///
/// Four facts shape the design, and each is a macOS fact rather than taste:
///
/// 1. **The agent account cannot read the person's files.** Its home is 0700 and
///    the whole product is built on that. So a file cannot be handed over as a
///    path: the bytes have to cross, through a directory both users can reach.
///    The per-account runtime directory is exactly that directory — it already
///    carries the two-user inherited ACL for sockets, tokens and screenshots
///    (`RuntimePaths.applyACL`).
/// 2. **`NSPasteboard.general` is per Aqua session.** The person's clipboard and
///    the agent's are two different boards, so "paste" is a transfer rather than
///    a shared object. That is why this file describes staging directories and
///    change counts instead of a sync flag.
/// 3. **A paste is not the moment the file was copied.** The agent may paste ten
///    minutes later, so the file a paste will read must outlive the request that
///    staged it.
/// 4. **Text does not have to travel as JSON.** One JSON line is capped at 1 MiB
///    (`Framing.maxRequestBytes`) and JSON escaping can multiply a string, so
///    the agent-bound text is staged as a file beside the files and read by the
///    worker — the same channel, the same limit, no escaping. The person-bound
///    direction is a *response* (64 MiB ceiling), so text can travel inline
///    there.
///
/// The transfer is **on demand**: the person's clipboard is read only at the
/// instant they press ⌘V in an agent window, and written only at the instant
/// they press ⌘C. Nothing here polls, and nothing here mirrors.
///
/// Layout, inside the account's own runtime directory:
///
/// ```
/// <runtime>/clipboard/
///   inbox/<batch>/…    written by the controller; read and moved by the worker
///   pasted/<batch>/…   the worker's copy of inbox files — where the agent's
///                      clipboard points, so it outlives the transfer
///   outbox/<batch>/…   the worker's copies of agent-side files, which the
///                      controller copies out and puts on the person's board
/// ```
///
/// Everything here is policy and pure data: no AppKit, no `NSPasteboard`. The
/// worker owns the agent's board, the GUI owns the person's, and this file is
/// the contract between them so the two ends cannot disagree about a limit, a
/// name or a path.
public enum ClipboardLimits {
    /// Text keeps the 1 MiB the existing text clipboard (and `ax.setValue`)
    /// already enforce. `SessionResource` is the single owner of that number.
    public static let maxTextBytes = SessionResource.maxTextBytes
    /// A Finder copy of a folder is one item, however many files are inside it.
    /// The count is bounded because each entry costs a pasteboard item.
    public static let maxFiles = 32
    /// Bytes are bounded because these copies are *made*: pushing doubles the
    /// disk the clipboard holds, and pulling makes a second copy for the other
    /// user. 128 MiB is a handful of screenshots, a source tree, or a document —
    /// and small enough that a runaway copy cannot fill the boot volume.
    public static let maxFileBytes = 128 * 1024 * 1024
    /// How many batches a side keeps before the oldest are removed. Both
    /// clipboards hold paths, so deleting a batch breaks a paste that has not
    /// happened yet — that is why the window is generous rather than tight.
    public static let maxKeptBatches = 8
    public static let maxKeptBytes = 512 * 1024 * 1024
    /// A batch nobody has touched for this long is litter from a failed paste.
    public static let batchRetention: TimeInterval = 7 * 24 * 60 * 60
    /// Staged names come from another user's pasteboard, so a name is data:
    /// bounded and stripped of separators before it becomes a path.
    public static let maxNameBytes = 200
    /// The file the staged text lives in, inside a batch's root. The files
    /// themselves live in the batch's `items/` directory, so a copied file that
    /// happens to be called 「text.txt」 cannot collide with it.
    public static let stagedTextFileName = "text.txt"
    public static let itemsDirectoryName = "items"
    /// How long `clipboard.pull` may wait for the agent's board to change after
    /// the person pressed ⌘C. The keystroke is delivered asynchronously, so the
    /// answer is not there the instant this is asked; 800 ms is longer than any
    /// measured copy of a selection and far below a person's patience.
    public static let pullWaitMilliseconds = 800
    /// The bound the worker honours whatever a caller asks for.
    public static let maxPullWaitMilliseconds = 2_000
}

/// One file (or folder) that crosses the boundary.
public struct ClipboardFileEntry: Codable, Equatable, Sendable {
    /// The base name the other side will see, already through
    /// `ClipboardStaging.sanitizedName`.
    public var name: String
    /// Absolute path as *the side that created it* can read it: for `push` a
    /// path inside `inbox/`, for `pull` a path inside `outbox/`.
    public var path: String
    public var byteCount: Int
    public var isDirectory: Bool

    public init(name: String, path: String, byteCount: Int, isDirectory: Bool) {
        self.name = name
        self.path = path
        self.byteCount = byteCount
        self.isDirectory = isDirectory
    }

    public var json: JSONValue {
        .obj(["name": .string(name), "path": .string(path),
              "bytes": .int(byteCount), "directory": .bool(isDirectory)])
    }

    public init?(json: JSONValue) {
        guard let name = json["name"]?.stringValue,
              let path = json["path"]?.stringValue, path.hasPrefix("/"),
              let bytes = json["bytes"]?.intValue, bytes >= 0 else { return nil }
        self.name = name
        self.path = path
        self.byteCount = bytes
        self.isDirectory = json["directory"]?.boolValue ?? false
    }
}

/// What one side of the transfer ended up with.
///
/// `text` and `files` are independent: a Finder copy carries files, a text
/// selection carries text, and some apps write both. Either may be absent. The
/// receiving side puts on its clipboard exactly what is here — never a merge
/// with what it had, because "paste what I copied" has one meaning.
public struct ClipboardContents: Equatable, Sendable {
    public var text: String?
    public var files: [ClipboardFileEntry]
    /// Sum of `files`, so a receiver can report the cost without walking again.
    public var totalBytes: Int
    /// True when the source held more than the limits allow and the tail was
    /// left behind (too many files, or text over 1 MiB). The transfer still
    /// happened; saying so is what keeps it from looking like a full success.
    public var truncated: Bool

    public init(text: String? = nil, files: [ClipboardFileEntry] = [],
                totalBytes: Int = 0, truncated: Bool = false) {
        self.text = text
        self.files = files
        self.totalBytes = totalBytes
        self.truncated = truncated
    }

    public var isEmpty: Bool { (text?.isEmpty ?? true) && files.isEmpty }

    public var json: JSONValue {
        .obj([
            "text": text.map(JSONValue.string) ?? .null,
            "hasText": .bool(text != nil),
            "files": .array(files.map(\.json)),
            "totalBytes": .int(totalBytes),
            "truncated": .bool(truncated),
        ])
    }

    public init(json: JSONValue) {
        let text = json["text"]?.stringValue
        let files = (json["files"]?.arrayValue ?? []).compactMap(ClipboardFileEntry.init(json:))
        self.init(text: text,
                  files: files,
                  totalBytes: json["totalBytes"]?.intValue ?? files.reduce(0) { $0 + $1.byteCount },
                  truncated: json["truncated"]?.boolValue ?? false)
    }
}

/// The staging directories both ends agree on.
///
/// A value over a root path, so a test can point it at `/tmp` and the worker and
/// the GUI derive the same directories from the same runtime path without either
/// inventing a layout.
public struct ClipboardStaging: Sendable {
    public enum Side: String, Sendable, CaseIterable {
        /// Controller → worker. The controller writes, the worker moves.
        case inbox
        /// Worker → controller. The worker writes, the controller copies out.
        case outbox
        /// Files the worker moved out of `inbox` to put on the agent's own
        /// board. Separate from `inbox` because they must outlive the transfer.
        case pasted
    }

    /// The account's runtime directory — `/Library/Application
    /// Support/AgentSpace/Runtime/<uuid>` in production, a temporary directory
    /// in tests.
    public let runtimeDirectory: String

    public init(runtimeDirectory: String) {
        self.runtimeDirectory = runtimeDirectory
    }

    public var root: String { runtimeDirectory + "/clipboard" }

    public func directory(_ side: Side) -> String { root + "/" + side.rawValue }

    /// Where a batch keeps the items it carries. The text file sits beside this
    /// directory rather than inside it, so the directory's contents are exactly
    /// the clipboard's files.
    public static func itemsDirectory(inBatch batch: String) -> String {
        batch + "/" + ClipboardLimits.itemsDirectoryName
    }

    /// Create `clipboard/<side>/<id>/` and return its path.
    @discardableResult
    public func newBatch(_ side: Side, id: String = UUID().uuidString,
                         fileManager: FileManager = .default) throws -> String {
        guard Self.isSafeBatchID(id) else {
            throw AgentSpaceError(code: .badRequest, message: "clipboard batch id must be a plain name")
        }
        let batch = directory(side) + "/" + id
        do {
            try fileManager.createDirectory(atPath: batch, withIntermediateDirectories: true)
        } catch {
            throw AgentSpaceError(
                code: .internalError,
                message: "could not create the clipboard staging directory \(batch): \(error)")
        }
        return batch
    }

    /// Is `path` a real path inside one of this side's batches?
    ///
    /// Symlinks are resolved first, which is the whole point: the worker must not
    /// be talked into copying an agent file outside the staging area because a
    /// staged symlink pointed there. Delegates to `WorkspaceGuard`, the
    /// repository's one implementation of "is this path inside that root".
    public func contains(_ path: String, side: Side) -> Bool {
        guard path.hasPrefix("/"), !path.contains("\0") else { return false }
        return WorkspaceGuard.contains(WorkspaceGuard.resolve(path),
                                       WorkspaceGuard.resolve(directory(side)))
    }

    /// A batch directory name is the only user-influenced component of a staged
    /// path, so it is validated rather than escaped.
    public static func isSafeBatchID(_ id: String) -> Bool {
        guard !id.isEmpty, id.utf8.count <= 64 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        return id.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Turn whatever the other side called a file into a base name this side can
    /// safely create.
    ///
    /// Deliberately not "trust the sender": the name arrives from another user's
    /// pasteboard, and a name is what becomes a path on this side. Separators, a
    /// NUL, leading dots and an empty remainder are all handled here, once, for
    /// both ends.
    public static func sanitizedName(_ raw: String) -> String {
        let last = raw.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? raw
        var cleaned = last.replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        // Byte-bounded rather than character-bounded, because the limit exists
        // to keep a path short and a string of CJK scalars costs three bytes each.
        while cleaned.utf8.count > ClipboardLimits.maxNameBytes, !cleaned.isEmpty {
            cleaned.removeLast()
        }
        if cleaned.isEmpty { cleaned = "file" }
        return cleaned
    }

    /// Is this path a symbolic link?
    ///
    /// A clipboard carries files and folders, and a symlink is neither. It is
    /// also the one item that would carry a *path* across the boundary instead of
    /// bytes, which is exactly what this whole design refuses to do: linking the
    /// agent's `~/.ssh` into a staging directory is how a copy engine becomes a
    /// reading engine. `WorkspaceGuard.resolve` refuses a link whose target is
    /// outside the staging root, but a link that does not resolve yet cannot be
    /// resolved at all — measured on macOS 26: `fileExists` follows the link, so a
    /// **broken** link reports absent, the resolver falls back to its enclosing
    /// directory, and the path passes a containment test that a *working* link
    /// would fail. Refusing links outright makes the rule one sentence instead of
    /// two behaviours, and costs nothing real: nobody pastes a symlink expecting
    /// the thing it points at to arrive later.
    public static func isSymbolicLink(_ path: String) -> Bool {
        (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isSymbolicLinkKey]))?
            .isSymbolicLink == true
    }

    /// A destination path for `name` inside `directory` that nothing occupies
    /// yet, by appending ` 2`, ` 3`, … before the extension.
    ///
    /// Pure: the caller supplies `exists`, so the rule is testable without a
    /// filesystem and both ends make the same choice for the same input.
    public static func uniqueDestination(for name: String, in directory: String,
                                         exists: (String) -> Bool) -> String {
        let clean = sanitizedName(name)
        let base = directory.hasSuffix("/") ? String(directory.dropLast()) : directory
        var candidate = base + "/" + clean
        guard exists(candidate) else { return candidate }
        let ext = (clean as NSString).pathExtension
        let stem = ext.isEmpty ? clean : String(clean.dropLast(ext.count + 1))
        var suffix = 2
        repeat {
            let numbered = ext.isEmpty ? "\(stem) \(suffix)" : "\(stem) \(suffix).\(ext)"
            candidate = base + "/" + numbered
            if !exists(candidate) { return candidate }
            suffix += 1
        } while suffix < 10_000
        return base + "/" + clean
    }

    // MARK: - Retention

    /// Remove batches on one side that are stale or over budget.
    ///
    /// Both clipboards hold *paths*, so deleting a batch breaks a paste that has
    /// not happened yet. The policy is therefore generous and ordered: anything
    /// untouched for `batchRetention` goes first, then the oldest batches while
    /// the side is over `maxKeptBatches` or `maxKeptBytes`. The newest batch is
    /// never removed, however large, because it is the one a paste is about to
    /// use.
    ///
    /// Returns the batches it removed, so a caller can log rather than assume.
    @discardableResult
    public static func sweep(_ side: Side, staging: ClipboardStaging,
                             now: Date = Date(),
                             fileManager: FileManager = .default) -> [String] {
        let root = staging.directory(side)
        guard let names = try? fileManager.contentsOfDirectory(atPath: root) else { return [] }
        var batches: [(path: String, modified: Date, bytes: Int)] = []
        for name in names where isSafeBatchID(name) {
            let path = root + "/" + name
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            let attributes = try? fileManager.attributesOfItem(atPath: path)
            let modified = (attributes?[.modificationDate] as? Date) ?? .distantPast
            batches.append((path, modified, byteCount(of: path, fileManager: fileManager)))
        }
        batches.sort { $0.modified > $1.modified }

        var removed: [String] = []
        var keptCount = 0
        var keptBytes = 0
        for (index, batch) in batches.enumerated() {
            let stale = now.timeIntervalSince(batch.modified) > ClipboardLimits.batchRetention
            let overCount = keptCount >= ClipboardLimits.maxKeptBatches
            let overBytes = keptBytes + batch.bytes > ClipboardLimits.maxKeptBytes
            // The newest batch survives even when it is the one that is large.
            let mustKeep = index == 0
            if !mustKeep && (stale || overCount || overBytes) {
                if (try? fileManager.removeItem(atPath: batch.path)) != nil {
                    removed.append(batch.path)
                }
                continue
            }
            keptCount += 1
            keptBytes += batch.bytes
        }
        return removed
    }

    /// Bytes under `path`, not following directory symlinks and bounded: a staged
    /// folder can be large, and this number drives a deletion decision rather
    /// than a quota, so it stops early once it is past every budget that matters.
    public static func byteCount(of path: String, limit: Int = ClipboardLimits.maxKeptBytes,
                                 fileManager: FileManager = .default) -> Int {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return 0 }
        guard isDirectory.boolValue else {
            return (try? fileManager.attributesOfItem(atPath: path))?[.size] as? Int ?? 0
        }
        var total = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let walker = fileManager.enumerator(at: URL(fileURLWithPath: path),
                                                  includingPropertiesForKeys: keys,
                                                  options: [],
                                                  errorHandler: { _, _ in true }) else { return 0 }
        for case let url as URL in walker {
            if let values = try? url.resourceValues(forKeys: Set(keys)),
               values.isRegularFile == true {
                total += values.fileSize ?? 0
            }
            if total > limit { return total }
        }
        return total
    }
}

/// What the person's ⌘V means, decided from the local clipboard alone.
///
/// Pure so the decision is testable without a pasteboard, a window or a worker —
/// and so the two hosts (the Desktop Viewer and a Fusion proxy) cannot disagree
/// about when a keystroke is bridged and when it is just forwarded.
public enum ClipboardBridgePolicy {
    public enum Decision: Equatable, Sendable {
        /// Nothing this feature can carry: send the keystroke as it is and let
        /// the agent's own clipboard answer. This is the common case for an
        /// empty clipboard.
        case forward
        /// Carry this to the agent first, then send the keystroke.
        case bridge(text: String?, filePaths: [String])
        /// Nothing is carried and the person is told why — but the keystroke
        /// still goes through, because a refusal must never look like a dead
        /// keyboard.
        case refuse(Refusal)

        /// True when the keystroke is sent immediately, as it always was.
        public var forwardsImmediately: Bool {
            switch self {
            case .bridge: return false
            case .forward, .refuse: return true
            }
        }
    }

    public enum Refusal: Equatable, Sendable {
        case textTooLarge
        case tooManyFiles
        /// Images and rich text are the one gap a person will actually hit, and
        /// it is a gap rather than a bug: the transfer carries plain text and
        /// files. Saying so once per keystroke is the difference between "the
        /// product is broken" and "this content is not carried yet".
        case unsupportedFormats

        public var message: String {
            switch self {
            case .textTooLarge:
                return NSLocalizedString(
                    "The text you copied is larger than the 1 MB AgentSpace can paste into an agent desktop.",
                    comment: "")
            case .tooManyFiles:
                return NSLocalizedString(
                    "You copied more than 32 items. AgentSpace pastes files and folders one clipboard at a time, up to 32 items.",
                    comment: "")
            case .unsupportedFormats:
                return NSLocalizedString(
                    "AgentSpace pastes plain text and files. This clipboard holds something else (an image or rich text), so the agent's own clipboard answers instead.",
                    comment: "")
            }
        }
    }

    /// - Parameters:
    ///   - text: the local clipboard's plain text, if any.
    ///   - filePaths: absolute paths read off the local clipboard's file URLs.
    ///   - hasUnsupportedFormats: an image, rich text, or anything else this
    ///     feature does not carry. Reported by the host so the person is told
    ///     what is not bridged instead of watching a paste do nothing.
    public static func decision(text: String?,
                                filePaths: [String],
                                hasUnsupportedFormats: Bool) -> Decision {
        let trimmed = (text?.isEmpty ?? true) ? nil : text
        if let trimmed, trimmed.utf8.count > ClipboardLimits.maxTextBytes {
            return .refuse(.textTooLarge)
        }
        if filePaths.count > ClipboardLimits.maxFiles {
            return .refuse(.tooManyFiles)
        }
        if trimmed != nil || !filePaths.isEmpty {
            return .bridge(text: trimmed, filePaths: filePaths)
        }
        if hasUnsupportedFormats {
            return .refuse(.unsupportedFormats)
        }
        return .forward
    }
}

/// Which keystroke is a clipboard bridge, read off the event the same way
/// `KeyboardForwarding` reads one.
///
/// Only the *intent* is decided here; both hosts act on it identically. ⌘C and
/// ⌘V with any extra modifiers still count (⌘⇧V is "paste and match style" and
/// ⌘⌥C is a copy of a style attribute) because they are all a paste or a copy as
/// far as the board is concerned — the keystroke itself is forwarded unchanged
/// afterwards.
public enum ClipboardShortcut {
    public enum Intent: Equatable, Sendable {
        /// The agent's clipboard should end up with what the person copied.
        case pasteIntoAgent
        /// The person's clipboard should end up with what the agent copied.
        case copyFromAgent
    }

    public static func intent(characters: String?,
                              charactersIgnoringModifiers: String?,
                              command: Bool,
                              control: Bool) -> Intent? {
        // Command is what makes it a clipboard shortcut on macOS; Control is
        // the Emacs-style alternative some terminal users use, and it is only a
        // copy/paste inside a terminal that understands it, so it is not
        // bridged — the agent's own board answers.
        guard command, !control else { return nil }
        guard let base = charactersIgnoringModifiers?.lowercased(), base.count == 1 else { return nil }
        switch base {
        case "v": return .pasteIntoAgent
        case "c": return .copyFromAgent
        default: return nil
        }
    }
}

/// Stage and collect staged files, so the two ends of the wire are one
/// implementation rather than two nearly-identical ones.
///
/// The controller and the worker each do one half of this, with different
/// privileges: the controller can read the person's clipboard and the account's
/// runtime directory; the worker can read the account's own files and set the
/// account's board. Everything they share — copying, naming, limits, refusal
/// rather than truncation — is here, and is tested against a temporary
/// directory rather than against a live desktop.
public enum ClipboardTransfer {
    public enum Outcome: Equatable, Sendable {
        /// The files landed; `entries` name the copies on the receiving side.
        case staged([ClipboardFileEntry])
        /// Some landed and the rest did not fit the budget. Still useful, and
        /// reported as partial rather than as a failure or a full success.
        case partial([ClipboardFileEntry], truncated: Bool)
        /// Nothing fitted: the first file alone is larger than the limit.
        case refused(AgentSpaceError)
    }

    /// Copy `paths` into `batch`, naming them with `ClipboardStaging`'s rules.
    ///
    /// Each path is checked with `contains` against `sourceSide` first, so a
    /// caller cannot use this to copy the agent's `~/.ssh` into a staging
    /// directory: the bound is the staging root, not the caller's honesty.
    /// Directories are copied whole, because a Finder copy of a folder is one
    /// item and the person expects the folder.
    public static func stage(paths: [String],
                             into batch: String,
                             sourceSide: ClipboardStaging.Side,
                             staging: ClipboardStaging,
                             limit: Int = ClipboardLimits.maxFiles,
                             fileManager: FileManager = .default) -> Outcome {
        let items = ClipboardStaging.itemsDirectory(inBatch: batch)
        try? fileManager.createDirectory(atPath: items, withIntermediateDirectories: true)
        var entries: [ClipboardFileEntry] = []
        var bytes = 0
        var truncated = false
        for path in paths {
            if entries.count >= limit { truncated = true; break }
            guard staging.contains(path, side: sourceSide) else {
                // Not this caller's to copy. Skipped rather than refused so one
                // stray entry in a multi-file copy does not lose the rest; the
                // reason is logged by the caller, which knows the batch.
                truncated = true
                continue
            }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
                truncated = true
                continue
            }
            // A link is not an item (see `isSymbolicLink`): copying it would hand
            // the far side a path instead of content, and a link pointing outside
            // the staging root is precisely the smuggling route this file exists
            // to close.
            if ClipboardStaging.isSymbolicLink(path) {
                truncated = true
                continue
            }
            let size = ClipboardStaging.byteCount(of: path, limit: ClipboardLimits.maxFileBytes,
                                                  fileManager: fileManager)
            if size > ClipboardLimits.maxFileBytes {
                if entries.isEmpty { return .refused(AgentSpaceError(
                    code: .badRequest,
                    message: "the clipboard item is larger than the 128 MB AgentSpace can stage")) }
                truncated = true
                continue
            }
            if bytes + size > ClipboardLimits.maxFileBytes {
                truncated = true
                continue
            }
            let name = ClipboardStaging.sanitizedName((path as NSString).lastPathComponent)
            let destination = ClipboardStaging.uniqueDestination(for: name, in: items) {
                fileManager.fileExists(atPath: $0)
            }
            do {
                try fileManager.copyItem(atPath: path, toPath: destination)
            } catch {
                truncated = true
                continue
            }
            let copiedName = (destination as NSString).lastPathComponent
            entries.append(ClipboardFileEntry(
                name: copiedName, path: destination,
                byteCount: ClipboardStaging.byteCount(of: destination, limit: ClipboardLimits.maxFileBytes,
                                                      fileManager: fileManager),
                isDirectory: isDirectory.boolValue))
            bytes += size
        }
        return truncated ? .partial(entries, truncated: true) : .staged(entries)
    }

    /// Stage text for the worker to read, in `batch`.
    ///
    /// Written as a file rather than sent as JSON because a JSON line is capped
    /// at 1 MiB and escaping can multiply the bytes; a 1 MiB text selection is
    /// exactly the case this has to carry. The file is the same bound on disk as
    /// it is on the wire, and the worker re-checks it.
    public static func stage(text: String, in batch: String,
                             fileManager: FileManager = .default) throws -> String {
        try SessionResource.validateText(text)
        let path = batch + "/" + ClipboardLimits.stagedTextFileName
        do {
            try Data(text.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            throw AgentSpaceError(code: .internalError,
                                  message: "could not stage the clipboard text: \(error)")
        }
        return path
    }

    /// Read back text staged by `stage(text:in:)`, or nil when nothing was
    /// staged (a files-only clipboard).
    ///
    /// Bounded before reading: the worker must not be made to allocate an
    /// arbitrary file because a caller named it as clipboard text.
    public static func stagedText(in batch: String,
                                  fileManager: FileManager = .default) throws -> String? {
        let path = batch + "/" + ClipboardLimits.stagedTextFileName
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int else { return nil }
        guard size <= ClipboardLimits.maxTextBytes else {
            throw AgentSpaceError(code: .badRequest,
                                  message: "staged clipboard text exceeds the 1 MiB limit")
        }
        guard let data = fileManager.contents(atPath: path) else { return nil }
        guard let text = String(data: data, encoding: .utf8) else {
            throw AgentSpaceError(code: .badRequest,
                                  message: "staged clipboard text is not valid UTF-8")
        }
        return text
    }

    /// Copy staged entries out of a batch into `destination`, for the side that
    /// will hand them to a person.
    ///
    /// This is the half that makes a pulled file readable *after* the agent's
    /// clipboard changes: the controller puts its own copies on the person's
    /// board, so neither side's later edits or deletions can pull the file out
    /// from under the other.
    public static func collect(entries: [ClipboardFileEntry],
                               into destination: String,
                               sourceSide: ClipboardStaging.Side,
                               staging: ClipboardStaging,
                               fileManager: FileManager = .default) -> Outcome {
        try? fileManager.createDirectory(atPath: destination, withIntermediateDirectories: true)
        var collected: [ClipboardFileEntry] = []
        var truncated = false
        for entry in entries {
            guard staging.contains(entry.path, side: sourceSide) else {
                truncated = true
                continue
            }
            if ClipboardStaging.isSymbolicLink(entry.path) {
                truncated = true
                continue
            }
            let name = ClipboardStaging.sanitizedName(entry.name)
            let target = ClipboardStaging.uniqueDestination(for: name, in: destination) {
                fileManager.fileExists(atPath: $0)
            }
            do {
                try fileManager.copyItem(atPath: entry.path, toPath: target)
            } catch {
                truncated = true
                continue
            }
            collected.append(ClipboardFileEntry(
                name: (target as NSString).lastPathComponent, path: target,
                byteCount: ClipboardStaging.byteCount(of: target, limit: ClipboardLimits.maxFileBytes,
                                                      fileManager: fileManager),
                isDirectory: entry.isDirectory))
        }
        return truncated ? .partial(collected, truncated: true) : .staged(collected)
    }

    /// The same `Outcome`, as the answer a caller can act on.
    public static func contents(text: String?, outcome: Outcome) -> ClipboardContents {
        switch outcome {
        case .staged(let entries):
            return ClipboardContents(text: text, files: entries,
                                     totalBytes: entries.reduce(0) { $0 + $1.byteCount })
        case .partial(let entries, let truncated):
            return ClipboardContents(text: text, files: entries,
                                     totalBytes: entries.reduce(0) { $0 + $1.byteCount },
                                     truncated: truncated)
        case .refused:
            return ClipboardContents(text: text)
        }
    }
}
