import AppKit
import Foundation
import os
import AgentSpaceCore

private let clipboardLog = Logger(subsystem: BundleIdentifiers.logSubsystem,
                                  category: "clipboard-bridge")

/// What one bridged keystroke ended up doing.
///
/// Separate from `AgentSpaceError?` because "the agent's board did not change"
/// and "this worker predates the feature" are not failures: the keystroke goes
/// through either way, and the only difference is whether the person is told
/// anything.
enum ClipboardBridgeOutcome: Equatable {
    /// Text and/or files crossed. `contents` is what the receiving side now
    /// has, as the receiving side measured it.
    case carried(ClipboardContents)
    /// The agent's board did not change after ⌘C, so the person's board was
    /// left exactly as it was.
    case nothingNew
    /// This account's worker answers without the clipboard methods: a stale
    /// binary. The keystroke still goes through, and the agent's own clipboard
    /// answers — which is every paste before this feature existed.
    case unsupportedWorker
    case failed(AgentSpaceError)
}

/// One line for the person about a bridged keystroke.
///
/// The distinction inside is the point: `error` is set only when the bridge
/// genuinely failed, and a window shows that through its ordinary refusal
/// surface. Everything else — a paste that carried a folder, a clipboard holding
/// an image, a worker that predates the feature — is information, because the
/// keystroke still reached the agent in all of those cases, and colouring that
/// red would teach the person to distrust a paste that worked.
struct ClipboardBridgeNotice: Equatable {
    var message: String
    /// Set only for a genuine bridge failure; the window shows that through its
    /// ordinary failure surface and everything else as information.
    var error: AgentSpaceError?
}

/// The GUI's half of 「复制粘贴进子窗口」: the person's clipboard crossing into an
/// agent's desktop on ⌘V, and back on ⌘C.
///
/// Four facts shape this file, and each is a measurement rather than a taste:
///
/// 1. **Two boards, so the transfer is a file.** `NSPasteboard.general` is per
///    Aqua session: this process can read and write the person's, and only the
///    worker can touch the agent's. What crosses is therefore staged bytes in
///    the account's runtime directory — the one directory both users can reach
///    (`RuntimePaths.applyACL`) — never a path into the person's home, which the
///    agent account cannot read at all.
/// 2. **⌘V has to wait for the transfer; ⌘C must not.** A paste reads the
///    agent's board at the instant it runs, so the bytes must be there *before*
///    the keystroke is forwarded. A copy is the mirror image: the keystroke goes
///    first, and the wait moves into `clipboard.pull`, where the worker watches
///    the board's `changeCount`.
/// 3. **Nothing is mirrored.** The person's board is read once per ⌘V and
///    written only when the agent's board actually changed after ⌘C. There is no
///    timer and no poller in this file.
/// 4. **The person's board is written the way AppKit was measured to accept
///    it.** `writeObjects([URL])` gives a files-only board (one
///    `public.file-url` item and no string type, which is exactly a Finder
///    copy); adding a fresh `NSPasteboardItem` carrying `.string` gives both
///    types. An `NSPasteboardItem` that has been through `writeObjects` once can
///    never be written again — AppKit raises `NSInternalInconsistencyException`
///    inside the call and the process dies with SIGABRT, which is not a
///    catchable Swift error — so every item is built fresh for the write it
///    belongs to, and `clearContents()` + `writeObjects` are one step on the
///    main actor.
///
/// The transport is the same `WorkerClient` every other GUI call uses
/// (`SpaceService`'s style): no second socket, no GUI-only method. What this
/// file adds is the staging the file transfer needs, not a protocol.
@MainActor
final class ClipboardBridgeClient {
    let space: AgentAccount

    /// True once this account's worker answered `METHOD_NOT_FOUND` for one of
    /// the two methods. Kept so a window driving an older worker falls back to
    /// the agent's own clipboard once and quietly, instead of raising the same
    /// note on every keystroke.
    private(set) var isUnsupported = false

    /// The agent board's `changeCount` as of this window's last read.
    ///
    /// `clipboard.pull`'s wait means "wait until the count differs from this",
    /// so a ⌘C is compared against it. Nil until this window has read the board
    /// once — a copy cannot be judged a change against a number nobody has.
    private(set) var knownChangeCount: Int?

    init(space: AgentAccount) {
        self.space = space
    }

    var needsBaseline: Bool { knownChangeCount == nil }

    /// A worker that *does* advertise the capability clears a remembered
    /// refusal: the stale binary it refused was replaced (the app's own worker
    /// updater does exactly that) and this client must not keep answering for
    /// the binary that is gone.
    func noteWorkerSupportsBridge() {
        isUnsupported = false
    }

    // MARK: - ⌘V: the person's clipboard → the agent's

    /// Stage `text` / `filePaths` in this account's runtime directory and ask
    /// the worker to put them on the agent's board.
    ///
    /// The caller forwards the ⌘V keystroke after this answers — success or
    /// failure — because a paste that silently does nothing is the one bug this
    /// feature must not introduce.
    func pushToAgent(text: String?, filePaths: [String]) async -> ClipboardBridgeOutcome {
        guard !isUnsupported else { return .unsupportedWorker }
        let space = self.space
        let result = await Task.detached(priority: .userInitiated) {
            ClipboardBridgeTransport.push(space: space, text: text, filePaths: filePaths)
        }.value
        switch result {
        case .failure(let error):
            return classify(error, method: Method.clipboardPush)
        case .success(let contents):
            // Counts only: the bytes and the names are the person's, and a log
            // is not a clipboard.
            clipboardLog.info("clipboard.push: \(contents.files.count) file(s), \(contents.text?.utf8.count ?? 0) text byte(s), truncated=\(contents.truncated)")
            return .carried(contents)
        }
    }

    // MARK: - ⌘C: the agent's clipboard → the person's

    /// Read the agent's board and, when it changed while we waited, put it on
    /// the person's board.
    ///
    /// Nothing is written when the board did not change: a ⌘C that selected
    /// nothing in the agent must leave the person's clipboard alone rather than
    /// replace it with whatever the agent copied earlier.
    func copyFromAgent() async -> ClipboardBridgeOutcome {
        guard !isUnsupported else { return .unsupportedWorker }
        guard let known = knownChangeCount else { return .nothingNew }
        let space = self.space
        let result = await Task.detached(priority: .userInitiated) {
            ClipboardBridgeTransport.pull(space: space, knownChangeCount: known,
                                          waitMilliseconds: ClipboardLimits.pullWaitMilliseconds)
        }.value
        switch result {
        case .failure(let error):
            return classify(error, method: Method.clipboardPull)
        case .success(let payload):
            knownChangeCount = payload.changeCount
            guard payload.changed, !payload.contents.isEmpty else {
                clipboardLog.info("clipboard.pull: nothing new (changeCount \(payload.changeCount))")
                return .nothingNew
            }
            if let error = PersonClipboard.write(payload.contents) {
                return .failed(error)
            }
            clipboardLog.info("clipboard.pull: \(payload.contents.files.count) file(s), \(payload.contents.text?.utf8.count ?? 0) text byte(s) on the person's board")
            return .carried(payload.contents)
        }
    }

    /// Learn the agent board's `changeCount` *before* a copy keystroke lands.
    ///
    /// `clipboard.pull`'s wait only knows "differs from this number", so the
    /// first ⌘C of a window has to have one to differ from. This read is the
    /// same read every later ⌘C makes anyway; it is done once per window, at the
    /// person's own keystroke — not on window open, which would be a read of the
    /// agent's clipboard nobody asked for.
    ///
    /// It is called *before* the keystroke is forwarded, and it is bounded: a
    /// worker that stalls must not hold the person's ⌘C. A failure here is not
    /// fatal — the copy still goes through and simply reports nothing new.
    func seedBaseline() async {
        guard !isUnsupported, knownChangeCount == nil else { return }
        let space = self.space
        let result = await Task.detached(priority: .userInitiated) {
            // `collectFiles: false`: this read wants one number, not a copy of
            // whatever the agent already had on its board. The files that matter
            // are the ones the copy keystroke is about to put there.
            ClipboardBridgeTransport.pull(space: space, knownChangeCount: nil,
                                          waitMilliseconds: 0, timeout: 1.5,
                                          collectFiles: false)
        }.value
        switch result {
        case .failure(let error):
            if classify(error, method: Method.clipboardPull) == .unsupportedWorker { return }
            clipboardLog.info("clipboard.pull could not read a baseline: \(error.code.rawValue)")
        case .success(let payload):
            knownChangeCount = payload.changeCount
        }
    }

    // MARK: - Words

    /// What crossed, in the terms the account page already uses for the same
    /// fact (§397): 「文字和文件」 / 「仅文字」 / 「仅文件」.
    static func describe(_ contents: ClipboardContents) -> String {
        let hasText = !(contents.text?.isEmpty ?? true)
        switch (hasText, contents.files.isEmpty) {
        // The first two are the account page's own words for the same fact, so
        // the two surfaces cannot describe one worker differently (§397).
        case (true, false): return NSLocalizedString("text and files", comment: "")
        case (true, true): return NSLocalizedString("text only", comment: "")
        default: return NSLocalizedString("files only", comment: "")
        }
    }

    /// The sentence a host shows after a bridged keystroke, or nil when the
    /// keystroke going through is the whole story.
    ///
    /// `pasted` picks the verb: a ⌘V carried bytes *into* the agent, a ⌘C carried
    /// them *out*.
    static func notice(for outcome: ClipboardBridgeOutcome, pasted: Bool) -> ClipboardBridgeNotice? {
        switch outcome {
        case .carried(let contents):
            var text = String(
                format: pasted
                    ? NSLocalizedString("Pasted %@ into the agent desktop.", comment: "")
                    : NSLocalizedString("Copied %@ from the agent desktop into your clipboard.", comment: ""),
                describe(contents))
            if contents.truncated {
                // Core's rule: a partial transfer still happened, and saying so
                // is what keeps it from looking like a full success.
                text += " " + NSLocalizedString(
                    "Some of the clipboard did not fit and was left behind: the limit is 32 items or 128 MB.",
                    comment: "")
            }
            return ClipboardBridgeNotice(message: text, error: nil)
        case .nothingNew:
            return nil
        case .unsupportedWorker:
            return ClipboardBridgeNotice(
                message: NSLocalizedString(
                    "Update this account's Worker to paste text and files into its desktop with ⌘V.",
                    comment: ""),
                error: nil)
        case .failed(let error):
            return ClipboardBridgeNotice(message: error.message, error: error)
        }
    }

    /// The refusal Core decided on, for a clipboard that holds something this
    /// feature does not carry. Rendered by the host as information, next to the
    /// keystroke that still went through: a refusal is not a failure.
    static func notice(for refusal: ClipboardBridgePolicy.Refusal) -> ClipboardBridgeNotice {
        ClipboardBridgeNotice(message: refusal.message, error: nil)
    }

    private func classify(_ error: AgentSpaceError,
                          method: String) -> ClipboardBridgeOutcome {
        // `METHOD_NOT_FOUND` from these two is a stale worker binary, not a
        // protocol failure: `WorkerCompatibility` already turns it into the
        // typed 「reinstall the worker」 recovery, and here it also means every
        // later keystroke should go straight to the agent's own clipboard.
        let recovered = WorkerCompatibility.recovery(for: error, method: method) ?? error
        if recovered.code == .methodNotFound {
            isUnsupported = true
            return .unsupportedWorker
        }
        return .failed(recovered)
    }
}

// MARK: - One window's bridge

/// The ⌘V/⌘C sequencing, written once so the Desktop Viewer and a Fusion proxy
/// cannot disagree about it.
///
/// The two windows differ only in where they send a keystroke and where they
/// report a line; the order of operations is a property of the feature, not of
/// the window, so it lives here:
///
/// **⌘V** — read the person's board **once**, ask `ClipboardBridgePolicy`, then:
/// `.bridge` → push, *then* send the keystroke; `.refuse` → send, then say why
/// in words; `.forward` → send. The push comes first because the agent's paste
/// reads the agent's board at the instant the keystroke lands, so bytes that
/// arrive afterwards are bytes no paste will see.
///
/// **⌘C** — if this window has never read the agent's board, read its
/// `changeCount` first (a copy can only be judged a change against a number);
/// then send the keystroke; then pull, which waits in the worker for the board to
/// move. The person's board is written only from that answer.
///
/// A keystroke is sent on **every** path — carried, refused, unsupported worker,
/// failed — because the one bug this feature must not introduce is a ⌘V that
/// silently does nothing. The only thing that stops a deferred keystroke is
/// input being revoked while the transfer was in flight, which is the same
/// refusal the worker would give it anyway.
@MainActor
final class ClipboardBridgeHost {
    private let client: ClipboardBridgeClient
    /// True while one bridge is in flight *in this window*. A second keystroke is
    /// then forwarded immediately instead of queued: a person typing at a window
    /// must never wait behind a 128 MB copy, and two pushes resolving out of
    /// order would paste them out of order too.
    private var inFlight = false

    init(space: AgentAccount) {
        self.client = ClipboardBridgeRegistry.shared.client(for: space)
    }

    /// This window stopped bridging. Only the in-flight flag is per window; the
    /// `changeCount` stays in the shared client, because the board it describes
    /// belongs to the account and not to this proxy — a second window's copy must
    /// not be mistaken for a change this window caused.
    func reset() {
        inFlight = false
    }

    /// The hook `RemoteKeyboardMonitor` asks for a clipboard keystroke.
    ///
    /// - Parameters:
    ///   - bridgingAvailable: what the window already knows about this worker's
    ///     `clipboard.bridge` — `true`/`false` from a `status` it has, or nil
    ///     when it has not looked. Nil attempts the bridge, because the only cost
    ///     of being wrong is one round trip that answers `METHOD_NOT_FOUND`: the
    ///     keystroke still goes through, and `isUnsupported` makes every later
    ///     keystroke of that account forward immediately. A probe of its own
    ///     would be worse — it would put a worker call in front of the person's
    ///     ⌘V on every window that opens.
    ///   - permitsInput: re-checked immediately before a deferred keystroke is
    ///     sent, so a console switch or a revoked grant during the transfer
    ///     still stops the key, exactly as the monitor's own check would have.
    ///   - send: this window's own keystroke path — `input.sendKeyAction` with
    ///     the RPC fallback for the viewer, `window.input` for a proxy.
    ///   - note: this window's status line. `notice.error` tells the host whether
    ///     its *failure* surface or its information surface should carry it.
    func handle(
        intent: ClipboardShortcut.Intent,
        action: InputAction,
        bridgingAvailable: Bool?,
        permitsInput: @escaping () -> Bool,
        send: @escaping (InputAction) -> Void,
        note: @escaping (ClipboardBridgeNotice) -> Void
    ) -> RemoteKeyboardMonitor.ClipboardHandling {
        if bridgingAvailable == true { client.noteWorkerSupportsBridge() }
        // A window whose worker said it cannot bridge does not read the person's
        // board at all: the keystroke is forwarded untouched, exactly as before
        // this feature existed.
        guard bridgingAvailable != false, !inFlight else { return .forward }
        inFlight = true
        // The gate is re-asked, not remembered: the monitor's own check ran before
        // the pasteboard read, and a console switch, a revoked grant or a window
        // closed during a 128 MB copy must still stop this key rather than inject
        // it into a desktop nobody permitted. False means the key did not go, and
        // then the clipboard work after it is pointless.
        let deliver: (InputAction) -> Bool = { action in
            guard permitsInput() else { return false }
            send(action)
            return true
        }
        switch intent {
        case .pasteIntoAgent:
            // One read of the person's board, at the keystroke, and never again
            // until they press ⌘V again.
            let reading = PersonClipboard.read()
            switch ClipboardBridgePolicy.decision(
                text: reading.text, filePaths: reading.filePaths,
                hasUnsupportedFormats: reading.hasUnsupportedFormats) {
            case .forward:
                inFlight = false
                return .forward
            case .refuse(let refusal):
                // Nothing crossed, the person is told why, and the keystroke goes
                // through anyway so the agent's own clipboard answers.
                let sent = deliver(action)
                inFlight = false
                if sent { note(ClipboardBridgeClient.notice(for: refusal)) }
            case .bridge(let text, let paths):
                Task { @MainActor in
                    let outcome = await client.pushToAgent(text: text, filePaths: paths)
                    let sent = deliver(action)
                    inFlight = false
                    guard sent, let message = ClipboardBridgeClient.notice(
                        for: outcome, pasted: true) else { return }
                    note(message)
                }
            }
            return .deferred

        case .copyFromAgent:
            // The keystroke is delivered first inside the task, after the
            // baseline — the agent has to copy before there is anything to
            // compare the board's count against.
            let needsBaseline = client.needsBaseline
            Task { @MainActor in
                // The baseline is read *before* the keystroke: the worker's wait
                // is "until the board's count differs from this", and the count
                // a copy will differ from has to be the one from before it. It is
                // one RPC round trip on the first ⌘C of a window only — p95
                // 3.98 ms measured in this repo (§327 row 894) — and it copies no
                // files, so the cost is one short read of an integer.
                if needsBaseline { await client.seedBaseline() }
                let sent = deliver(action)
                guard sent else { inFlight = false; return }
                let outcome = await client.copyFromAgent()
                inFlight = false
                if let message = ClipboardBridgeClient.notice(for: outcome, pasted: false) {
                    note(message)
                }
            }
            return .deferred
        }
    }
}

// MARK: - Off the main actor

/// One bridge client per account, shared by the Desktop Viewer and every Fusion
/// proxy of that account.
///
/// The *board* is one per account, so the count a ⌘C compares against must be one
/// per account too. Per-window counts would make the copy of the account's
/// clipboard that window A just pulled look like a fresh change to window B,
/// which would then write the person's board with content nobody in B copied.
/// What stays per window is only "a bridge is in flight here".
///
/// It also costs less: the baseline read — one `clipboard.pull` that only asks
/// for the board's `changeCount` — happens once per account instead of once per
/// window, and a worker that turns out to predate the feature is remembered that
/// way for every window of that account.
@MainActor
final class ClipboardBridgeRegistry {
    static let shared = ClipboardBridgeRegistry()

    private var clients: [UUID: ClipboardBridgeClient] = [:]

    func client(for space: AgentAccount) -> ClipboardBridgeClient {
        if let existing = clients[space.id] { return existing }
        let client = ClipboardBridgeClient(space: space)
        clients[space.id] = client
        return client
    }

}

/// The parts that touch the disk and the socket, so none of them can block the
/// window: staging is up to 128 MB of copies and a pull waits on the agent's
/// board. The person's pasteboard is deliberately *not* touched here — it is
/// read by the host at the keystroke and written by `PersonClipboard.write` on
/// the main actor.
enum ClipboardBridgeTransport {
    struct PullPayload: Sendable {
        /// Files rewritten to this process's own copies, so the agent's files can
        /// change or disappear without pulling a file out of a paste that has
        /// not happened yet.
        var contents: ClipboardContents
        var changeCount: Int
        var changed: Bool
    }

    static func push(space: AgentAccount, text: String?,
                     filePaths: [String]) -> Result<ClipboardContents, AgentSpaceError> {
        guard let connection = connection(for: space) else { return .failure(pathError(space)) }
        let staging = ClipboardStaging(runtimeDirectory: connection.paths.directory)
        let trimmed = (text?.isEmpty ?? true) ? nil : text

        let batchPath: String
        do {
            batchPath = try staging.newBatch(.inbox)
        } catch {
            return .failure(error as? AgentSpaceError ?? AgentSpaceError(
                code: .internalError, message: "could not stage the clipboard: \(error)"))
        }
        // This batch is "the bytes for this request". The worker moves its files
        // into `pasted/` when it carries them, so anything still here when this
        // returns is a failed paste's litter — and a failed paste must not leave
        // the person's file behind in the account's runtime directory.
        defer { try? FileManager.default.removeItem(atPath: batchPath) }

        var inline: String?
        if let trimmed {
            do {
                _ = try ClipboardTransfer.stage(text: trimmed, in: batchPath)
            } catch {
                return .failure(error as? AgentSpaceError ?? AgentSpaceError(
                    code: .internalError, message: "could not stage the clipboard text: \(error)"))
            }
            // Inline is only a saved file read for the common short selection,
            // never a second channel: 64 KiB of text cannot approach
            // `Framing.maxRequestBytes` (1 MiB) even at JSON's worst escaping of
            // six bytes per input byte, and anything larger travels as the
            // staged file alone.
            if trimmed.utf8.count <= 64 * 1024 { inline = trimmed }
        }

        let staged = stagedPersonFiles(filePaths, into: batchPath)
        let contents = ClipboardContents(
            text: trimmed, files: staged.entries,
            totalBytes: staged.entries.reduce(0) { $0 + $1.byteCount },
            truncated: staged.truncated)

        let params = JSONValue.obj([
            "batch": .string((batchPath as NSString).lastPathComponent),
            "text": inline.map(JSONValue.string) ?? .null,
            // False says "there is no staged text file", which saves the worker
            // a stat; absent would mean "look for one" (worker's `textForPush`).
            "hasText": .bool(trimmed != nil),
            "files": .array(contents.files.map(\.json)),
        ])
        do {
            let response = try connection.client.call(
                method: Method.clipboardPush, params: params,
                token: connection.token, timeout: 30)
            if let error = response.error { return .failure(error) }
            guard let result = response.result else {
                return .failure(AgentSpaceError(
                    code: .internalError,
                    message: "the worker answered clipboard.push without a result"))
            }
            // The worker's own numbers win: it measured the copy it made and what
            // its board accepted.
            return .success(ClipboardContents(
                text: trimmed, files: contents.files,
                totalBytes: result["totalBytes"]?.intValue ?? contents.totalBytes,
                truncated: result["truncated"]?.boolValue ?? contents.truncated))
        } catch {
            return .failure(AgentSpaceError(
                code: .workerOffline,
                message: "no worker is answering for '\(space.name)': \(error)"))
        }
    }

    static func pull(space: AgentAccount, knownChangeCount: Int?,
                     waitMilliseconds: Int, timeout: Double = 30,
                     collectFiles: Bool = true) -> Result<PullPayload, AgentSpaceError> {
        guard let connection = connection(for: space) else { return .failure(pathError(space)) }
        let params = JSONValue.obj([
            "waitMilliseconds": .int(waitMilliseconds),
            "knownChangeCount": knownChangeCount.map(JSONValue.int) ?? .null,
        ])
        let response: RPCResponse
        do {
            response = try connection.client.call(
                method: Method.clipboardPull, params: params,
                token: connection.token, timeout: timeout)
        } catch {
            return .failure(AgentSpaceError(
                code: .workerOffline,
                message: "no worker is answering for '\(space.name)': \(error)"))
        }
        if let error = response.error { return .failure(error) }
        guard let result = response.result else {
            return .failure(AgentSpaceError(
                code: .internalError,
                message: "the worker answered clipboard.pull without a result"))
        }
        let contents = ClipboardContents(json: result)
        let changeCount = result["changeCount"]?.intValue ?? 0
        // No baseline means this window had nothing to compare against; the
        // answer is treated as a change and reported as such rather than thrown
        // away, and `needsBaseline` keeps that path from writing the person's
        // board on a guess.
        let changed = knownChangeCount == nil || changeCount != knownChangeCount
        guard changed, collectFiles, !contents.files.isEmpty else {
            return .success(PullPayload(contents: contents, changeCount: changeCount,
                                        changed: changed))
        }

        // The worker's copies live in the agent's runtime directory, and the
        // person's paste has to outlive both that batch and the agent's next
        // copy: this side makes its own copy, exactly as
        // `ClipboardTransfer.collect`'s own documentation describes.
        //
        // `collect` skips (rather than throws) an entry whose path is outside the
        // named side. A worker that dropped the `outbox/` directory between the
        // answer and this copy — retention, or a session teardown — would then
        // deliver text with no files and no truncated flag, so the omission is
        // reported here, from the counts on both sides.
        ClipboardCache.sweep()
        guard let destination = ClipboardCache.newBatch() else {
            return .failure(AgentSpaceError(
                code: .internalError,
                message: "could not make a directory for the copied files"))
        }
        let staging = ClipboardStaging(runtimeDirectory: connection.paths.directory)
        let outcome = ClipboardTransfer.collect(
            entries: contents.files, into: destination,
            sourceSide: .outbox, staging: staging)
        let collected = ClipboardTransfer.contents(text: contents.text, outcome: outcome)
        let lost = collected.files.count < contents.files.count
        return .success(PullPayload(
            contents: ClipboardContents(
                text: collected.text, files: collected.files,
                totalBytes: collected.totalBytes,
                truncated: collected.truncated || contents.truncated || lost),
            changeCount: changeCount, changed: true))
    }

    private static func connection(for space: AgentAccount) -> SpaceConnection? {
        let connection = SpaceConnection(space: space)
        return connection.paths.socketPathFits ? connection : nil
    }

    private static func pathError(_ space: AgentAccount) -> AgentSpaceError {
        let connection = SpaceConnection(space: space)
        return AgentSpaceError(
            code: .internalError,
            message: "the runtime path for '\(space.name)' is \(connection.paths.socketPath.utf8.count) bytes, over the \(RuntimePaths.maxSocketPathBytes)-byte unix socket limit")
    }

    /// Copy the person's files into `batch`, by Core's naming rules and bounds.
    ///
    /// `ClipboardTransfer.stage` cannot be used here: it checks its *source*
    /// with `staging.contains(path, side:)`, which is the worker's security
    /// boundary — no caller may point the worker at `~/.ssh`. These paths are the
    /// person's own, read by the person's own process, so the copy is made here
    /// with the same name sanitising, the same unique-destination rule and the
    /// same 32-item / 128 MB budget. The worker's `clipboard.pull` makes the
    /// mirror-image copy for the agent's files for the same reason.
    /// Internal rather than private so `ClipboardBridgeClientTests` can drive it:
    /// what this function refuses is a security property (a link must not become
    /// the bytes the worker carries), and a property nobody can test is a claim.
    static func stagedPersonFiles(
        _ paths: [String], into batch: String
    ) -> (entries: [ClipboardFileEntry], truncated: Bool) {
        let fileManager = FileManager.default
        let items = ClipboardStaging.itemsDirectory(inBatch: batch)
        try? fileManager.createDirectory(atPath: items, withIntermediateDirectories: true)
        var entries: [ClipboardFileEntry] = []
        var bytes = 0
        var truncated = false
        for path in paths {
            if entries.count >= ClipboardLimits.maxFiles { truncated = true; break }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
                // A path can be gone between the pasteboard read and the copy;
                // one missing item must not lose the rest of a multi-file copy.
                truncated = true
                continue
            }
            // A link is not an item, for the same reason the worker refuses
            // one: copying it would carry a path instead of bytes, and a
            // Finder-copied link would make the worker refuse the *whole*
            // request — taking the text with it. Skipping it here keeps one
            // stray link from costing a paste that is otherwise fine, and the
            // `truncated` flag is how the person is told something was left
            // behind (validation §397 row 1327).
            if ClipboardStaging.isSymbolicLink(path) {
                truncated = true
                continue
            }
            let size = ClipboardStaging.byteCount(
                of: path, limit: ClipboardLimits.maxFileBytes, fileManager: fileManager)
            guard size <= ClipboardLimits.maxFileBytes,
                  bytes + size <= ClipboardLimits.maxFileBytes else {
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
            entries.append(ClipboardFileEntry(
                name: (destination as NSString).lastPathComponent,
                path: destination,
                byteCount: ClipboardStaging.byteCount(
                    of: destination, limit: ClipboardLimits.maxFileBytes,
                    fileManager: fileManager),
                isDirectory: isDirectory.boolValue))
            bytes += size
        }
        return (entries, truncated)
    }
}

// MARK: - The person's clipboard

/// The person's own `NSPasteboard.general` — the side only this process touches.
///
/// Every shape here was measured on macOS 26 rather than assumed, and the trap
/// is in `write`: a `NSPasteboardItem` that has been through `writeObjects` once
/// cannot be written again (AppKit raises `NSInternalInconsistencyException`
/// inside the call and the process aborts), so items are always built fresh for
/// the write they belong to.
@MainActor
enum PersonClipboard {
    struct Reading {
        var text: String?
        var filePaths: [String]
        /// The board holds something this feature does not carry — an image,
        /// rich text, a colour. Reported so the person is told once instead of
        /// watching ⌘V do nothing.
        var hasUnsupportedFormats: Bool
    }

    /// One read of the person's board, at the instant they pressed ⌘V. Never
    /// called anywhere else: there is no poller and no mirror.
    static func read() -> Reading {
        let board = NSPasteboard.general
        let text = board.string(forType: .string)
        let urls = (board.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let paths = urls.filter(\.isFileURL).map(\.path)
        let hasText = !(text?.isEmpty ?? true)
        let types = Set(board.types ?? [])
        return Reading(
            text: hasText ? text : nil,
            filePaths: paths,
            // Only when the board holds something we cannot carry *and* it is
            // not empty: an empty board is `.forward`, because the agent's own
            // clipboard answering is what every paste did before this feature.
            hasUnsupportedFormats: !hasText && paths.isEmpty && !types.isEmpty)
    }

    /// Put exactly `contents` on the person's board — the ⌘C half.
    ///
    /// An empty clipboard is never written: "paste what I copied" must not clear
    /// a board the agent had nothing to add to. Returns nil on success.
    static func write(_ contents: ClipboardContents) -> AgentSpaceError? {
        guard !contents.isEmpty else { return nil }
        let board = NSPasteboard.general
        let urls = contents.files.map { URL(fileURLWithPath: $0.path) }

        // Text only goes through `setString`, exactly like the worker's own text
        // write: one item, one type, nothing invented.
        if urls.isEmpty {
            guard let text = contents.text, !text.isEmpty else { return nil }
            board.clearContents()
            guard board.setString(text, forType: .string) else {
                return AgentSpaceError(code: .internalError,
                                       message: "your clipboard did not accept the copied text")
            }
            return nil
        }

        // The files as `NSURL`s: the measured shape for a files-only board, one
        // `public.file-url` item per file and no string type. The text item comes
        // first, in the order that was measured (`writeObjects([item, URL])`
        // answers two items with both `public.utf8-plain-text` and
        // `public.file-url` present), so an app that pastes the *first* item as
        // text still finds the text.
        //
        // The item is created here and never reused: AppKit aborts the process on
        // a second write of the same item, and that is not a Swift error anyone
        // can catch.
        var objects: [NSPasteboardWriting] = []
        if let text = contents.text, !text.isEmpty {
            let item = NSPasteboardItem()
            guard item.setString(text, forType: .string) else {
                return AgentSpaceError(code: .internalError,
                                       message: "your clipboard did not accept the copied text")
            }
            objects.append(item)
        }
        objects.append(contentsOf: urls.map { $0 as NSURL })
        board.clearContents()
        guard board.writeObjects(objects) else {
            return AgentSpaceError(code: .internalError,
                                   message: "your clipboard did not accept the copied files")
        }
        return nil
    }
}

// MARK: - Where pulled files are kept

/// The person's own copy of the files an agent copied.
///
/// They cannot stay at the worker's `outbox/` paths: those live in the agent
/// account's staging area, and the whole point of copying them out is that the
/// person's paste keeps working after the agent's clipboard (or that batch)
/// changes.
///
/// Caches rather than temporary storage, because "temporary" is not true for a
/// clipboard: a person may paste an hour later, and the file the paste points at
/// must still be there. The sweep applies Core's own generous window to this
/// side too.
enum ClipboardCache {
    static func root() -> String {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent(BundleIdentifiers.app, isDirectory: true)
            .appendingPathComponent("Clipboard", isDirectory: true).path
    }

    static func newBatch() -> String? {
        let path = root() + "/" + UUID().uuidString
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            return path
        } catch {
            clipboardLog.error("could not create a clipboard cache directory: \(error.localizedDescription)")
            return nil
        }
    }

    /// Remove batches past the retention window, then the oldest while there are
    /// more than Core keeps on a staging side. The newest is never removed: it is
    /// the copy a paste is about to use.
    static func sweep(now: Date = Date()) {
        let fileManager = FileManager.default
        let root = root()
        guard let names = try? fileManager.contentsOfDirectory(atPath: root) else { return }
        var batches: [(path: String, modified: Date)] = []
        for name in names where !name.hasPrefix(".") {
            let path = root + "/" + name
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            let attributes = try? fileManager.attributesOfItem(atPath: path)
            batches.append((path, (attributes?[.modificationDate] as? Date) ?? .distantPast))
        }
        batches.sort { $0.modified > $1.modified }
        var kept = 0
        for (index, batch) in batches.enumerated() {
            if index == 0 { kept = 1; continue }
            let stale = now.timeIntervalSince(batch.modified) > ClipboardLimits.batchRetention
            if stale || kept >= ClipboardLimits.maxKeptBatches {
                try? fileManager.removeItem(atPath: batch.path)
                continue
            }
            kept += 1
        }
    }
}
