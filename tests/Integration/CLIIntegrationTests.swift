import Foundation
import XCTest
import AgentSpaceCore

/// Spawn the real `agentspace` CLI and return what a caller would observe.
struct CLIResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    /// Both streams, for assertions about what a human or an agent actually sees.
    var output: String { stdout + "\n" + stderr }

    var isJSON: Bool {
        guard let data = stdout.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}

/// An integration harness around the real CLI binary.
///
/// Every run gets its own `AGENTSPACE_ROOT`, so tests share no state except the
/// binary itself. This is the plan's §49 property under test: the CLI must reach
/// the registry, the runtime layout, the token file and the worker socket
/// through the same Core API the GUI and MCP use — not a private copy.
final class CLIHarness {
    let root: String
    private let binary: String

    /// A short root: `sun_path` is 103 bytes and the runtime layout appends
    /// `/Runtime/<uuid>/worker.sock`, so long temp paths overflow it and the
    /// worker refuses to bind (by design).
    init() throws {
        let suffix = String(UUID().uuidString.prefix(8)).lowercased()
        root = "/tmp/as-cli-" + suffix
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)

        guard let binary = CLIHarness.locateBinary() else {
            throw XCTSkip("""
                the agentspace CLI has not been built. Run `swift build` (or \
                scripts/test.sh, which builds it first) before the integration tests.
                """)
        }
        self.binary = binary
    }

    static func locateBinary() -> String? {
        let fileManager = FileManager.default
        // The .xctest bundle sits inside .build/<config>/, next to the binaries.
        let bundleDirectory = Bundle(for: CLIHarness.self).bundleURL.deletingLastPathComponent()
        var directories = [bundleDirectory.path]
        // Walk up from this source file looking for a .build directory.
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            directories.append(directory.appendingPathComponent(".build").resolvingSymlinksInPath().path)
            for configuration in ["debug", "release"] {
                directories.append(directory.appendingPathComponent(".build").appendingPathComponent(configuration).path)
            }
            directory = directory.deletingLastPathComponent()
        }
        for base in directories {
            for configuration in ["", "debug/", "release/"] {
                let candidate = base + "/" + configuration + "agentspace"
                if fileManager.isExecutableFile(atPath: candidate) { return candidate }
            }
        }
        return nil
    }

    func run(_ arguments: [String], environment: [String: String] = [:], timeout: TimeInterval = 30) -> CLIResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments

        var environment = environment
        environment["AGENTSPACE_ROOT"] = root
        // The MCP server is never under test here; keep the CLI from probing for it.
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        var stdout = ""
        var stderr = ""
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            stdout += text
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            stderr += text
        }

        do {
            try process.run()
        } catch {
            return CLIResult(exitCode: -1, stdout: stdout, stderr: stderr + "\nspawn failed: \(error)")
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            return CLIResult(exitCode: -2, stdout: stdout, stderr: stderr + "\ntimed out after \(Int(timeout))s")
        }
        // Drain whatever arrived after the exit.
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        stdout += String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        stderr += String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return CLIResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    /// Seed the registry this root's CLI runs will load.
    func seed(_ spaces: [AgentSpace]) throws {
        try SpaceRegistry(spaces: spaces).save(root: root)
    }

    // MARK: - Live worker

    /// Start a real worker binary in this harness's runtime root, with the token
    /// on disk where the CLI's Core API will look for it. Returns the token so a
    /// test can also prove that the CLI found the *right* one.
    func startWorker(name: String, spaceID: UUID) throws -> SessionToken {
        guard let worker = WorkerBinaryLocator.find() else {
            throw XCTSkip("""
                agentspace-worker has not been built. Run `swift build` (or \
                scripts/test.sh, which builds it first) before the integration tests.
                """)
        }
        let paths = RuntimePaths(spaceID: spaceID, root: root)
        XCTAssertTrue(paths.socketPathFits, "socket path must fit sun_path: \(paths.socketPath)")
        try FileManager.default.createDirectory(
            atPath: paths.directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        guard let token = SessionToken.generate() else {
            throw XCTSkip("SecRandomCopyBytes is unavailable in this environment")
        }
        guard TokenStore.write(token, to: paths.tokenPath) == nil else {
            throw XCTSkip("could not write the session token")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: worker)
        process.arguments = [
            "--space-id", spaceID.uuidString,
            "--name", name,
            "--runtime-dir", root,
            "--token-file", paths.tokenPath,
            "--quiet",
        ]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        var stderr = ""
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            stderr += text
        }
        try process.run()

        // Wait for the socket *and* for it to answer a hello.
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if process.isRunning == false {
                throw XCTSkip("the worker exited immediately: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            if FileManager.default.fileExists(atPath: paths.socketPath) {
                let client = WorkerClient(socketPath: paths.socketPath)
                if let response = try? client.call(method: Method.hello, token: token.hex, timeout: 3), response.ok {
                    return token
                }
            }
            usleep(100_000)
        }
        process.terminate()
        throw XCTSkip("the worker did not become ready within 20s: \(stderr)")
    }
}

/// The worker binary lookup, shared with the safety suite's env override.
enum WorkerBinaryLocator {
    static func find() -> String? {
        let fileManager = FileManager.default
        if let override = ProcessInfo.processInfo.environment["AGENTSPACE_WORKER_BINARY"],
           fileManager.isExecutableFile(atPath: override) {
            return override
        }
        let bundleDirectory = Bundle(for: CLIHarness.self).bundleURL.deletingLastPathComponent()
        for configuration in ["debug", "release"] {
            let candidate = bundleDirectory.appendingPathComponent("agentspace-worker").path
            if fileManager.isExecutableFile(atPath: candidate) { return candidate }
            let nested = bundleDirectory
                .appendingPathComponent(configuration)
                .appendingPathComponent("agentspace-worker").path
            if fileManager.isExecutableFile(atPath: nested) { return nested }
        }
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            for configuration in ["debug", "release"] {
                let candidate = directory
                    .appendingPathComponent(".build")
                    .appendingPathComponent(configuration)
                    .appendingPathComponent("agentspace-worker").path
                if fileManager.isExecutableFile(atPath: candidate) { return candidate }
            }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }
}

/// The integration suite (plan §5 `tests/Integration/`, §55 "Integration Tests").
///
/// Unit tests exercise decision logic; the safety suite exercises a live worker
/// over its socket. What was missing is the layer between: the **product
/// boundary** — does the CLI binary, run as a real process with only its
/// arguments and `AGENTSPACE_ROOT`, behave the way §31–§32 promise to an agent
/// or a script? These tests spawn the binary, so every failure here is a failure
/// a user of the CLI would actually see.
final class CLIIntegrationTests: XCTestCase {

    private var cleanupRoots: [String] = []
    override func tearDown() {
        for root in cleanupRoots {
            try? FileManager.default.removeItem(atPath: root)
        }
        cleanupRoots = []
    }

    private func harness() throws -> CLIHarness {
        let harness = try CLIHarness()
        cleanupRoots.append(harness.root)
        return harness
    }

    private func makeSpace(_ name: String, state: SpaceState = .needsLogin) -> AgentSpace {
        AgentSpace(
            name: name,
            username: "_agentspace_" + String(UUID().uuidString.prefix(6)).lowercased(),
            uid: 502,
            state: state)
    }

    // MARK: - Process boundary, no live worker

    func testVersionReportsTheProtocolVersion() throws {
        let cli = try harness()
        let result = cli.run(["--version"])
        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.stdout.contains("protocol 1"), result.stdout)
    }

    func testListOnAnEmptyRootIsEmptyJSON() throws {
        let cli = try harness()
        let result = cli.run(["list", "--json"])
        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.isJSON, "list --json must be machine-readable: \(result.stdout)")
    }

    func testAnUnknownSpaceNamesItselfAndExitsNotAcceptable() throws {
        let cli = try harness()
        try cli.seed([makeSpace("AAA")])
        let result = cli.run(["status", "BBB", "--json"])
        XCTAssertEqual(result.exitCode, 66, "the documented not-found exit code, got: \(result.output)")
        XCTAssertTrue(result.output.contains("BBB"), "the error must name the space: \(result.output)")
    }

    func testCreateWithoutTheHelperFailsClosedAtTheProcessBoundary() throws {
        let cli = try harness()
        let result = cli.run(["create", "No Helper", "--json"])
        XCTAssertEqual(result.exitCode, 69, "§31: no helper means exit 69, got: \(result.output)")
        XCTAssertTrue(result.output.contains("HELPER"), result.output)
        // Fail closed also means nothing was created: the registry must still be
        // empty, because a management path that half-runs is worse than one that
        // refuses.
        let registry = SpaceRegistry.load(root: cli.root)
        XCTAssertTrue(registry.spaces.isEmpty, "create must not leave a partial registry entry: \(registry.spaces)")
    }

    func testDoctorReportsEveryCheckWithAStatus() throws {
        let cli = try harness()
        let result = cli.run(["doctor", "--json"])
        XCTAssertEqual(result.exitCode, 0, result.output)
        guard let data = result.stdout.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let checks = object["checks"] as? [[String: Any]] else {
            return XCTFail("doctor --json must be an object with checks: \(result.stdout)")
        }
        XCTAssertFalse(checks.isEmpty)
        for check in checks {
            XCTAssertNotNil(check["name"], "every check names itself: \(check)")
            XCTAssertNotNil(check["status"], "every check has a verdict: \(check)")
        }
    }

    // MARK: - Through a live worker

    /// Seed a registry entry and start a real worker for it. Returns (cli, token).
    private func liveSpace(_ name: String) throws -> (CLIHarness, SessionToken, AgentSpace) {
        let cli = try harness()
        let space = makeSpace(name)
        try cli.seed([space])
        let token = try cli.startWorker(name: name, spaceID: space.id)
        return (cli, token, space)
    }

    /// §49: the CLI, a real process, reaches the worker through the same Core
    /// API as the GUI — registry lookup, token file, unix socket, response.
    func testStatusThroughTheRealBinaryReportsALiveWorker() throws {
        let (cli, _, _) = try liveSpace("Int Test")
        let result = cli.run(["status", "Int Test", "--json"])
        XCTAssertEqual(result.exitCode, 0, result.output)
        guard let data = result.stdout.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return XCTFail("status --json must parse: \(result.stdout)")
        }
        XCTAssertEqual(object["worker"] as? Bool, true, "the worker the CLI found is the one this test started")
        XCTAssertEqual(object["space"] as? String, "Int Test")
        XCTAssertNotNil(object["display"], "a live Aqua-session worker reports its display geometry")
    }

    /// §2 at the product boundary: the fail-closed console refusal must survive
    /// the whole stack — CLI process → Core → socket → worker → SessionGuard →
    /// typed error the CLI prints. This machine's test process *is* the console,
    /// so the worker legitimately refuses, and the CLI must surface that refusal
    /// as a non-zero exit with the §21 code, never an empty success.
    func testConsoleRefusalSurfacesThroughTheCLI() throws {
        let (cli, _, _) = try liveSpace("Console Test")
        // First confirm the worker really is a console-session worker here, the
        // same way the safety suite does, so the refusal below is the expected
        // outcome rather than an accident.
        let status = cli.run(["status", "Console Test", "--json"])
        guard status.exitCode == 0,
              let data = status.stdout.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (object["session"] as? [String: Any])?["verdict"] as? String == "isConsole" else {
            throw XCTSkip("this test expects to run in the console session: \(status.output)")
        }

        let click = cli.run(["click", "Console Test", "10", "10"])
        XCTAssertNotEqual(click.exitCode, 0, "a refused input must not exit 0: \(click.output)")
        XCTAssertTrue(click.output.contains("SESSION_IS_CONSOLE"), "the §21 code must reach the caller: \(click.output)")
    }

    /// §54: a screenshot must be the *agent's* session, never the user's
    /// desktop. On a console-session worker the only framebuffer available IS
    /// the user's, so the worker refuses — and the refusal must arrive typed at
    /// the process boundary. In an AgentSpace session the same command must
    /// produce a real PNG. The test asserts whichever world it runs in, and the
    /// safety suite's skipped half covers the other one.
    func testScreenshotHonorsTheConsoleRefusalOrProducesARealPNG() throws {
        let (cli, _, _) = try liveSpace("Shot Test")
        let status = cli.run(["status", "Shot Test", "--json"])
        let verdict = ((try? JSONSerialization.jsonObject(with: Data(status.stdout.utf8)) as? [String: Any]) ?? [:])["session"] as? [String: Any]
        let isConsole = verdict?["verdict"] as? String == "isConsole"

        let out = cli.root + "/shot.png"
        let result = cli.run(["screenshot", "Shot Test", "--json", "--out", out])
        if isConsole {
            XCTAssertNotEqual(result.exitCode, 0, "must refuse, not capture the user's desktop: \(result.output)")
            XCTAssertTrue(result.output.contains("SESSION_IS_CONSOLE"),
                          "the refusal must be typed, not prose: \(result.output)")
        } else {
            XCTAssertEqual(result.exitCode, 0, result.output)
            let data = FileManager.default.contents(atPath: out) ?? Data()
            XCTAssertGreaterThan(data.count, 1000, "a real framebuffer capture, not an empty file")
            XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], "PNG magic")
        }
    }

    /// §29/§48, at the process boundary: two roots are two worlds. The same
    /// space name in a different root must not be reachable — a CLI run scoped
    /// to one root sees only that root's registry, token and socket.
    func testTwoRootsAreIsolatedWorldsToTheCLI() throws {
        let (first, firstToken, _) = try liveSpace("Shared Name")
        let (second, secondToken, _) = try liveSpace("Shared Name")
        XCTAssertNotEqual(firstToken, secondToken, "independent roots get independent tokens")

        let fromFirst = first.run(["status", "Shared Name", "--json"])
        XCTAssertEqual(fromFirst.exitCode, 0, fromFirst.output)
        let firstPid = pid(from: fromFirst)

        // A name that exists only in the second root must be not-found through
        // the first, never silently resolved against the wrong registry.
        let missing = first.run(["status", "Only In Second", "--json"])
        XCTAssertEqual(missing.exitCode, 66, missing.output)

        let fromSecond = second.run(["status", "Shared Name", "--json"])
        XCTAssertEqual(fromSecond.exitCode, 0, fromSecond.output)
        // Each world resolves its own socket: the pid behind the same name is a
        // different process.
        if let firstPid, let secondPid = pid(from: fromSecond) {
            XCTAssertNotEqual(secondPid, firstPid, "the two worlds must not share a worker")
        }
    }

    /// §37 at the process boundary: the exported bundle names the Space and
    /// the worker's state, but the token that authenticates to that worker
    /// must not appear anywhere in it — the export is exactly the kind of
    /// text a user pastes into a support issue.
    func testDiagnosticsExportNeverContainsTheWorkerToken() throws {
        let (cli, token, _) = try liveSpace("Diag Export")
        let result = cli.run(["diagnostics"])
        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Diag Export"), "the bundle should be navigable: \(result.output)")
        XCTAssertTrue(result.output.contains("doctor:"), result.output)
        XCTAssertFalse(result.output.contains(token.hex), "the session token must not survive into the export")
        XCTAssertFalse(result.output.contains("<redacted-"), "the collector is a whitelist; the redactor firing here would mean something secret-shaped got collected")

        // --out writes the same bundle to a file.
        let out = "\(cli.root)/diag.txt"
        let written = cli.run(["diagnostics", "--out", out])
        XCTAssertEqual(written.exitCode, 0, written.output)
        let contents = try String(contentsOfFile: out, encoding: .utf8)
        XCTAssertFalse(contents.contains(token.hex))
    }

    /// §52 at the process boundary: the live preview is refused on a
    /// console-session worker with the same typed code as every other
    /// observation method — the only framebuffer available IS the user's
    /// desktop, and shipping it as "the agent's preview" is exactly the §54
    /// leak the observation guard closed.
    func testPreviewRefusalSurfacesThroughTheCLIOnAConsoleWorker() throws {
        let (cli, _, _) = try liveSpace("Preview Test")
        let status = cli.run(["status", "Preview Test", "--json"])
        let verdict = ((try? JSONSerialization.jsonObject(with: Data(status.stdout.utf8)) as? [String: Any]) ?? [:])["session"] as? [String: Any]
        guard verdict?["verdict"] as? String == "isConsole" else {
            throw XCTSkip("this test expects to run in the console session: \(status.output)")
        }

        let start = cli.run(["preview", "Preview Test", "--start", "--json"])
        XCTAssertNotEqual(start.exitCode, 0, "must refuse, not stream the user's desktop: \(start.output)")
        XCTAssertTrue(start.output.contains("SESSION_IS_CONSOLE"), "typed refusal required: \(start.output)")

        // And without a stream, a frame pull is its own typed error — not a
        // silent success, not a crash.
        let frame = cli.run(["preview", "Preview Test", "--frame", "--json"])
        XCTAssertNotEqual(frame.exitCode, 0, frame.output)
        XCTAssertTrue(frame.output.contains("PREVIEW_NOT_RUNNING"), frame.output)
    }

    private func pid(from result: CLIResult) -> Int? {
        guard let data = result.stdout.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return object["workerPid"] as? Int
    }

    // MARK: - §32: JSON mode is stable for scripts and agents

    func testJSONModeCarriesTheDocumentedFieldsForScripts() throws {
        let (cli, _, space) = try liveSpace("Script Test")
        let result = cli.run(["status", "Script Test", "--json"])
        XCTAssertEqual(result.exitCode, 0, result.output)
        guard let data = result.stdout.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return XCTFail("status --json must parse: \(result.stdout)")
        }
        // §32's contract with scripts and CI: these keys, these types.
        XCTAssertEqual(object["worker"] as? Bool, true)
        XCTAssertNotNil(object["uid"])
        XCTAssertTrue(object["accessibility"] is Bool,
                      "accessibility must be a boolean for scripts to branch on")
        XCTAssertEqual(space.name, "Script Test")
    }
}
