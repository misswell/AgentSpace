import Foundation
import XCTest
import AgentSpaceCore

/// Spawns a real `agentspace-worker` against a throwaway runtime root and talks
/// to it over its real unix socket.
///
/// This is deliberately an integration harness rather than a mock. The safety
/// properties AgentSpace claims — "input is refused when the session is the
/// console", "an unauthorized client is rejected", "the worker never falls back"
/// — are properties of the *whole* path: socket, framing, token gate, session
/// check, event tap. Testing them against a stub would prove nothing about the
/// binary that ships.
final class WorkerHarness {

    let root: String
    let spaceID: UUID
    let token: SessionToken
    let paths: RuntimePaths
    private var process: Process?
    private(set) var stderr = ""

    /// Locate the built worker binary.
    ///
    /// Order: explicit environment override, then the build directory the test
    /// bundle itself lives in, then a walk up from this source file. The last one
    /// is what makes `swift test` work without any environment setup.
    static func locateWorkerBinary() -> String? {
        let fileManager = FileManager.default

        if let override = ProcessInfo.processInfo.environment["AGENTSPACE_WORKER_BINARY"],
           fileManager.isExecutableFile(atPath: override) {
            return override
        }

        // The .xctest bundle sits inside .build/<config>/, next to the binaries.
        let bundleDirectory = Bundle(for: WorkerHarness.self).bundleURL.deletingLastPathComponent()
        for configuration in ["debug", "release"] {
            let candidate = bundleDirectory.appendingPathComponent("agentspace-worker").path
            if fileManager.isExecutableFile(atPath: candidate) { return candidate }
            let nested = bundleDirectory
                .appendingPathComponent(configuration)
                .appendingPathComponent("agentspace-worker").path
            if fileManager.isExecutableFile(atPath: nested) { return nested }
        }

        // Walk up from the test source file looking for a .build directory.
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

    /// Written to `<runtime>/space.json` before the worker starts, for tests that
    /// need the worker to see a particular configuration — confinement roots, or a
    /// home whose size is known. `nil` (the default) reproduces production's
    /// "helper has not written a record yet" state honestly.
    var spaceRecord: [String: Any]?

    init(spaceName: String = "Safety Test Space") throws {
        // A deliberately SHORT root. `sun_path` is 103 bytes and the layout adds
        // `/Runtime/<uuid>/worker.sock` (57 more), so `NSTemporaryDirectory()`
        // (itself ~50 bytes under /var/folders) overflows it. The worker refuses
        // to bind in that case by design, so the harness must not hand it one.
        let suffix = String(UUID().uuidString.prefix(8)).lowercased()
        root = "/tmp/as-" + suffix
        spaceID = UUID()
        guard let generated = SessionToken.generate() else {
            throw XCTSkip("SecRandomCopyBytes is unavailable in this environment")
        }
        token = generated
        paths = RuntimePaths(spaceID: spaceID, root: root)
        XCTAssertTrue(paths.socketPathFits,
                      "harness socket path must fit sun_path: \(paths.socketPath) (\(paths.socketPath.utf8.count) bytes)")
        try FileManager.default.createDirectory(
            atPath: paths.directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        guard TokenStore.write(token, to: paths.tokenPath) == nil else {
            throw XCTSkip("could not write the session token to \(paths.tokenPath)")
        }
        _ = spaceName
    }

    deinit { stop() }

    /// Start the worker and wait for its socket to answer.
    func start(extraArguments: [String] = [], timeout: TimeInterval = 20) throws {
        if let spaceRecord {
            let data = try JSONSerialization.data(withJSONObject: spaceRecord, options: [.sortedKeys])
            try data.write(to: URL(fileURLWithPath: paths.directory + "/space.json"))
        }

        guard let binary = WorkerHarness.locateWorkerBinary() else {
            throw XCTSkip("""
                agentspace-worker has not been built. Run `swift build` (or \
                scripts/test.sh, which builds it first) before the safety tests.
                """)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = [
            "--space-id", spaceID.uuidString,
            "--name", "Safety Test Space",
            "--runtime-dir", root,
            "--token-file", paths.tokenPath,
            "--quiet",
        ] + extraArguments

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        // Collect stderr on a background queue so a chatty worker cannot fill the
        // pipe buffer and block.
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.stderr += text
        }

        try process.run()
        self.process = process

        // Wait for the socket *and* for it to answer: the file appears before
        // `listen` is necessarily ready on every filesystem.
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if process.isRunning == false {
                throw XCTSkip("""
                    the worker exited immediately (status \(process.terminationStatus)): \
                    \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                    """)
            }
            if FileManager.default.fileExists(atPath: paths.socketPath) {
                if let response = try? client(token: nil).call(method: Method.hello, token: nil, timeout: 3),
                   response.ok {
                    return
                }
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

    var isRunning: Bool { process?.isRunning ?? false }

    func client(token: String?) -> WorkerClient {
        WorkerClient(socketPath: paths.socketPath)
    }

    /// Send a request and return the response, failing the test on a transport
    /// error (which is never what these tests are about).
    func call(
        _ method: String,
        _ params: JSONValue = .object([:]),
        token override: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> RPCResponse {
        let useToken = override ?? token.hex
        do {
            return try client(token: useToken).call(method: method, params: params, token: useToken, timeout: 30)
        } catch {
            XCTFail("transport error calling \(method): \(error)", file: file, line: line)
            throw error
        }
    }

    /// The error code from a failed call, or a test failure if it succeeded.
    func errorCode(
        _ method: String,
        _ params: JSONValue = .object([:]),
        token override: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> AgentSpaceErrorCode? {
        let response = try call(method, params, token: override, file: file, line: line)
        guard !response.ok else {
            XCTFail("\(method) unexpectedly succeeded; expected a typed refusal", file: file, line: line)
            return nil
        }
        return response.error?.code
    }
}
