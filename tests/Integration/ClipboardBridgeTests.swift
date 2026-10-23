import Foundation
import XCTest
import AgentSpaceCore

/// The clipboard bridge against a *real* worker on a *real* unix socket.
///
/// The unit suites assert the rules; what they cannot assert is that the binary
/// which ships answers `clipboard.push` / `clipboard.pull` at all, that the
/// bytes on disk end up where `ClipboardTransfer` says they will, and that the
/// session gate runs *before* the staging directory is touched. Those are
/// properties of the whole path — framing, token gate, session check, staging,
/// pasteboard — so a stub would prove nothing about them.
///
/// One rule, and it is absolute: **this suite never touches `NSPasteboard`.** The
/// worker spawned here is asked what it answered and the files on disk under
/// `<runtime>/clipboard/` are inspected; the person's board is never read,
/// written or asserted on. Two of the three cases below therefore run on any
/// Mac, including the console session, by asserting the *refusal* — which is the
/// product (AGENTS.md §3) — and the third skips with its reason when the only
/// session available is the console one.
private final class ClipboardWorkerHarness {
    let root: String
    let spaceID: UUID
    let token: SessionToken
    let paths: RuntimePaths
    private var process: Process?
    private(set) var stderr = ""

    /// A deliberately short root: `sun_path` is 103 bytes and the layout adds
    /// `/Runtime/<uuid>/worker.sock` (57 more), so a deep temporary path
    /// overflows it and the worker refuses to bind by design.
    init() throws {
        let suffix = String(UUID().uuidString.prefix(8)).lowercased()
        root = "/tmp/as-clip-" + suffix
        spaceID = UUID()
        guard let generated = SessionToken.generate() else {
            throw XCTSkip("SecRandomCopyBytes is unavailable in this environment")
        }
        token = generated
        paths = RuntimePaths(spaceID: spaceID, root: root)
        XCTAssertTrue(paths.socketPathFits,
                      "harness socket path must fit sun_path: \(paths.socketPath)")
        try FileManager.default.createDirectory(
            atPath: paths.directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        guard TokenStore.write(token, to: paths.tokenPath) == nil else {
            throw XCTSkip("could not write the session token to \(paths.tokenPath)")
        }
    }

    deinit { stop() }

    private static func locateWorkerBinary() -> String? {
        let fileManager = FileManager.default
        if let override = ProcessInfo.processInfo.environment["AGENTSPACE_WORKER_BINARY"],
           fileManager.isExecutableFile(atPath: override) {
            return override
        }
        // The .xctest bundle sits inside .build/<config>/, next to the binaries.
        let bundleDirectory = Bundle(for: ClipboardWorkerHarness.self).bundleURL
            .deletingLastPathComponent()
        for configuration in ["debug", "release"] {
            for candidate in [bundleDirectory.appendingPathComponent("agentspace-worker").path,
                              bundleDirectory.appendingPathComponent(configuration)
                                  .appendingPathComponent("agentspace-worker").path] {
                if fileManager.isExecutableFile(atPath: candidate) { return candidate }
            }
        }
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            for configuration in ["debug", "release"] {
                let candidate = directory.appendingPathComponent(".build")
                    .appendingPathComponent(configuration)
                    .appendingPathComponent("agentspace-worker").path
                if fileManager.isExecutableFile(atPath: candidate) { return candidate }
            }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }

    func start(timeout: TimeInterval = 20) throws {
        guard let binary = Self.locateWorkerBinary() else {
            throw XCTSkip("""
                agentspace-worker has not been built. Run `swift build` (or \
                scripts/test.sh, which builds it first) before this suite.
                """)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        // A harness that starts a worker to assert refusals must not pay the
        // fifteen-second desktop wait for a diagnosis it already has: the
        // readiness answer is re-read per call either way.
        var environment = ProcessInfo.processInfo.environment
        environment["AGENTSPACE_DESKTOP_READY_TIMEOUT"] = "0"
        process.environment = environment
        process.arguments = [
            "--space-id", spaceID.uuidString,
            "--name", "Clipboard Test Space",
            "--runtime-dir", root,
            "--token-file", paths.tokenPath,
            "--quiet",
        ]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.stderr += text
        }
        try process.run()
        self.process = process

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if process.isRunning == false {
                throw XCTSkip("""
                    the worker exited immediately (status \(process.terminationStatus)): \
                    \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                    """)
            }
            if FileManager.default.fileExists(atPath: paths.socketPath),
               let response = try? client(token: nil).call(method: Method.hello, token: nil,
                                                           timeout: 3),
               response.ok {
                return
            }
            usleep(100_000)
        }
        stop()
        throw XCTSkip("the worker did not become ready within \(Int(timeout))s: \(stderr)")
    }

    func stop() {
        guard let process else { return }
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(3)
            while process.isRunning && Date() < deadline { usleep(50_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        self.process = nil
        try? FileManager.default.removeItem(atPath: root)
    }

    func client(token override: String?) -> WorkerClient {
        WorkerClient(socketPath: paths.socketPath)
    }

    func call(_ method: String, _ params: JSONValue = .object([:]),
              file: StaticString = #filePath, line: UInt = #line) throws -> RPCResponse {
        do {
            return try client(token: token.hex).call(method: method, params: params,
                                                     token: token.hex, timeout: 30)
        } catch {
            XCTFail("transport error calling \(method): \(error)", file: file, line: line)
            throw error
        }
    }

    /// True when the worker is serving the console session, which is the normal
    /// state when `swift test` runs at a Mac a person is using.
    func isConsoleSession() throws -> Bool {
        let hello = try call(Method.hello)
        return hello.result?["session"]?["verdict"]?.stringValue == "isConsole"
    }
}

final class ClipboardBridgeTests: XCTestCase {

    private var harness: ClipboardWorkerHarness!
    private var root: String!

    override func setUpWithError() throws {
        harness = try ClipboardWorkerHarness()
        root = harness.root
        try harness.start()
    }

    override func tearDownWithError() throws {
        harness?.stop()
        harness = nil
        if let root { try? FileManager.default.removeItem(atPath: root) }
        root = nil
    }

    private var staging: ClipboardStaging { ClipboardStaging(runtimeDirectory: harness.paths.directory) }

    /// A real file staged the way the controller stages one: inside a fresh
    /// `inbox/` batch. Nothing outside this directory is ever named by this
    /// suite, so a failure cannot be blamed on a path the person owns.
    private func stageFile(_ name: String, contents: String = "clipboard file") throws -> (batch: String, entry: ClipboardFileEntry) {
        let batch = try staging.newBatch(.inbox)
        let items = ClipboardStaging.itemsDirectory(inBatch: batch)
        try FileManager.default.createDirectory(atPath: items, withIntermediateDirectories: true)
        let path = items + "/" + name
        try Data(contents.utf8).write(to: URL(fileURLWithPath: path))
        return (batch, ClipboardFileEntry(name: name, path: path,
                                          byteCount: contents.utf8.count, isDirectory: false))
    }

    // MARK: - Always runs: the capability and the fail-closed ordering

    func testStatusAdvertisesTheClipboardBridgeWithTheSharedLimits() throws {
        // The account page decides whether to offer a ⌘V bridge from this block,
        // and its numbers must be Core's numbers: a second copy of "32 items" in
        // the worker is a limit the two ends could disagree about.
        let response = try harness.call(Method.status)
        XCTAssertTrue(response.ok, "status must answer without a usable desktop: \(response.error?.message ?? "")")
        let clipboard = try XCTUnwrap(response.result?["clipboard"], "status carries a clipboard capability block")
        XCTAssertEqual(clipboard["bridge"]?.boolValue, true)
        XCTAssertEqual(clipboard["files"]?.boolValue, true)
        XCTAssertEqual(clipboard["maxTextBytes"]?.intValue, ClipboardLimits.maxTextBytes)
        XCTAssertEqual(clipboard["maxFiles"]?.intValue, ClipboardLimits.maxFiles)
        XCTAssertEqual(clipboard["maxFileBytes"]?.intValue, ClipboardLimits.maxFileBytes)
    }

    func testTheSessionGateRunsBeforeTheStagingDirectoryIsTouched() throws {
        // On a machine whose session is the console, the refusal is the product:
        // a console-session worker must not read or write the board the person is
        // using. The *ordering* is what this asserts — `requireDesktopSession`
        // runs first, so the staged bytes are still in `inbox/` afterwards and no
        // `pasted/` batch was created. A worker that staged first and refused
        // after would have moved the person's file for nothing.
        guard try harness.isConsoleSession() else {
            throw XCTSkip("""
                this case asserts the console refusal, so it needs a worker whose session is \
                the console — the normal state of `swift test` at a Mac someone is using. \
                The round-trip case below covers the usable session.
                """)
        }
        let (batch, entry) = try stageFile("refused.txt")
        let inboxFile = entry.path

        let push = try harness.call(Method.clipboardPush, .obj([
            "batch": .string((batch as NSString).lastPathComponent),
            "text": .string("must not arrive"),
            "files": .array([entry.json]),
        ]))
        XCTAssertFalse(push.ok)
        XCTAssertEqual(push.error?.code, .sessionIsConsole)

        let pull = try harness.call(Method.clipboardPull, .obj([
            "waitMilliseconds": .int(0),
            "knownChangeCount": .int(0),
        ]))
        XCTAssertFalse(pull.ok)
        XCTAssertEqual(pull.error?.code, .sessionIsConsole)

        // Nothing moved, nothing was created: a refusal costs no observation and
        // no mutation.
        XCTAssertTrue(FileManager.default.fileExists(atPath: inboxFile),
                      "a refused push must leave the staged bytes where it found them")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.directory(.inbox)),
                       [(batch as NSString).lastPathComponent])
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.directory(.pasted)),
                       "a refused push must not create a pasted batch")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.directory(.outbox)),
                       "a refused pull must not create an outbox batch")
    }

    // MARK: - The round trip: a usable (background) session

    func testPushThenPullRoundTripsTextAndAFile() throws {
        guard try !harness.isConsoleSession() else {
            throw XCTSkip("""
                A pushes and pulls need a worker serving a background Aqua session, and this \
                Mac's `swift test` runs as the console user — the worker correctly refuses \
                with SESSION_IS_CONSOLE (asserted by the case above). The same round trip was \
                measured against a worker in the AgentUse account; run this case from inside \
                an agent session to exercise it here.
                """)
        }
        // Text travels as a staged file, the channel a 1 MiB selection needs
        // because one JSON line is capped at 1 MiB and escaping can multiply it.
        // Sending `hasText` without `text` is exactly what the controller does
        // for a large selection, and it exercises the file channel rather than
        // the inline shortcut.
        let text = "贴板 text from the person\nsecond line"
        let (batch, entry) = try stageFile("quarterly report.pdf", contents: "pdf bytes")
        _ = try ClipboardTransfer.stage(text: text, in: batch)

        let push = try harness.call(Method.clipboardPush, .obj([
            "batch": .string((batch as NSString).lastPathComponent),
            "hasText": .bool(true),
            "files": .array([entry.json]),
        ]))
        XCTAssertTrue(push.ok, "push must carry a staged text and file: \(push.error?.message ?? "")")
        let result = try XCTUnwrap(push.result)
        XCTAssertEqual(result["written"]?.boolValue, true)
        XCTAssertEqual(result["textBytes"]?.intValue, text.utf8.count,
                       "the answer counts the bytes it actually put on the board")
        XCTAssertEqual(result["files"]?.intValue, 1)
        XCTAssertEqual(result["totalBytes"]?.intValue, "pdf bytes".utf8.count)
        XCTAssertEqual(result["truncated"]?.boolValue, false)

        // The move is what keeps a paste ten minutes later working: the inbox
        // batch is spent, and `pasted/` holds the copy the agent's board points
        // at. Asserting the disk, not the board — the board is the worker's.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: staging.directory(.inbox) + "/" + (batch as NSString).lastPathComponent),
                       "the inbox batch is spent once it has been carried")
        let pastedBatches = try FileManager.default.contentsOfDirectory(atPath: staging.directory(.pasted))
        XCTAssertEqual(pastedBatches.count, 1, "one push makes exactly one pasted batch")
        let pastedItems = ClipboardStaging.itemsDirectory(
            inBatch: staging.directory(.pasted) + "/" + pastedBatches[0])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: pastedItems),
                       ["quarterly report.pdf"])
        XCTAssertEqual(try String(contentsOfFile: pastedItems + "/quarterly report.pdf",
                                  encoding: .utf8), "pdf bytes")

        // Pull it back the way the person's ⌘C does. The board was just written,
        // so the answer is this clipboard.
        let pull = try harness.call(Method.clipboardPull,
                                    .obj(["waitMilliseconds": .int(0)]))
        XCTAssertTrue(pull.ok, "pull must answer: \(pull.error?.message ?? "")")
        let pulled = ClipboardContents(json: try XCTUnwrap(pull.result))
        XCTAssertEqual(pulled.text, text, "the text the agent's board holds came back")
        XCTAssertEqual(pulled.files.count, 1)
        XCTAssertEqual(pulled.files.first?.name, "quarterly report.pdf")
        XCTAssertEqual(pulled.truncated, false)

        // The pulled file is a *copy in the outbox*, so the controller can put it
        // on the person's board and the agent's board can change underneath it.
        let batchName = try XCTUnwrap(pull.result?["batch"]?.stringValue)
        XCTAssertTrue(ClipboardStaging.isSafeBatchID(batchName),
                      "the answer names a batch, not a path: \(batchName)")
        let outboxFile = ClipboardStaging.itemsDirectory(
            inBatch: staging.directory(.outbox) + "/" + batchName) + "/quarterly report.pdf"
        XCTAssertTrue(FileManager.default.fileExists(atPath: outboxFile),
                      "the outbox holds the agent's copy at \(outboxFile)")
        XCTAssertNotEqual(try XCTUnwrap(pulled.files.first).path,
                          staging.directory(.pasted) + "/" + pastedBatches[0] + "/items/quarterly report.pdf",
                          "the person's side receives its own copy, never the agent's path")
        XCTAssertNotNil(pull.result?["changeCount"]?.intValue,
                        "the count is what lets the next ⌘C tell \"nothing new\" from \"read again\"")
    }

    func testPullWithNoKnownChangeCountAnswersImmediately() throws {
        guard try !harness.isConsoleSession() else {
            throw XCTSkip("""
                a pull needs a usable background session; this Mac's test process is the \
                console user, so the worker refuses with SESSION_IS_CONSOLE.
                """)
        }
        // The wait exists only to catch a ⌘C that has not landed yet. A caller
        // with no baseline has nothing to compare against, so asking it to wait
        // two seconds would make a ⌘C feel broken for no reason — the worker must
        // answer at once. The threshold is generous (1.5 s against a requested
        // 2 s) so a loaded machine cannot make this flaky; the property under
        // test is "it does not wait", not a latency number.
        let started = Date()
        let response = try harness.call(Method.clipboardPull, .obj([
            "waitMilliseconds": .int(ClipboardLimits.maxPullWaitMilliseconds),
        ]))
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertTrue(response.ok, "pull must answer: \(response.error?.message ?? "")")
        XCTAssertLessThan(elapsed, 1.5,
                          "a pull with no knownChangeCount must not wait \(elapsed)s")
    }

    func testPullReturnsAsSoonAsTheAgentsBoardChanges() throws {
        guard try !harness.isConsoleSession() else {
            throw XCTSkip("""
                a waiting pull needs a usable background session and a board this test may \
                write through the worker; this Mac's test process is the console user.
                """)
        }
        // The wait must end at the change, not at the timeout: the person's ⌘C is
        // delivered asynchronously, and the whole point of `knownChangeCount` is
        // to turn that race into an answer. The change is made through the
        // worker's own `clipboard.write` on a second connection — the same
        // concurrent-queue situation the board lane exists for — so the pull's
        // polling hops really do see another request's write.
        let baseline = try harness.call(Method.clipboardPull, .obj(["waitMilliseconds": .int(0)]))
        let knownChangeCount = try XCTUnwrap(baseline.result?["changeCount"]?.intValue)
        let changedText = "copied while the pull waited"
        let socketPath = harness.paths.socketPath
        let token = harness.token.hex

        // A second connection, writing 150 ms later — the same concurrent-queue
        // situation the worker's board lane exists for, and what a real ⌘C looks
        // like from the pull's side. It goes through `WorkerClient` directly so a
        // transport failure in this thread cannot raise an XCTest assertion off
        // the test's own queue; the pull's answer is the assertion.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
            _ = try? WorkerClient(socketPath: socketPath).call(
                method: Method.clipboardWrite,
                params: .obj(["text": .string(changedText)]),
                token: token, timeout: 10)
        }
        let started = Date()
        let response = try harness.call(Method.clipboardPull, .obj([
            "waitMilliseconds": .int(ClipboardLimits.maxPullWaitMilliseconds),
            "knownChangeCount": .int(knownChangeCount),
        ]))
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertTrue(response.ok, "pull must answer: \(response.error?.message ?? "")")
        XCTAssertLessThan(elapsed, 1.5, "the pull must return at the change, not at the timeout")
        XCTAssertEqual(ClipboardContents(json: try XCTUnwrap(response.result)).text, changedText,
                       "the answer is the clipboard that arrived during the wait")
        XCTAssertNotEqual(response.result?["changeCount"]?.intValue, knownChangeCount,
                          "a changed board answers a different count, which the next ⌘C compares against")
    }
}
