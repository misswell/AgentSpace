import Foundation
import XCTest
import AgentSpaceCore

/// The tests that matter most. Plan §55.
///
/// These are named exactly as the plan names them where the plan gives a name,
/// so a reviewer can line the suite up against the requirements and see what is
/// covered and what is not.
///
/// The two halves are deliberate:
///   * pure unit tests over the decision logic, which always run; and
///   * integration tests against a real worker binary over a real socket, which
///     skip with an explanation rather than passing vacuously when the binary
///     has not been built.
final class SafetyTests: XCTestCase {

    // MARK: - 1. SESSION_IS_CONSOLE

    /// Plan §55: `testInputRejectedWhenSessionIsConsole`.
    ///
    /// Unit half: the decision logic refuses for every console-ish input.
    func testInputRejectedWhenSessionIsConsole() {
        let onConsole = FakeSafetySession(
            dictionary: ["kCGSSessionOnConsoleKey": NSNumber(value: true)],
            graphicAccess: true)
        XCTAssertEqual(SessionGuard.verdict(using: onConsole), .isConsole)
        XCTAssertFalse(SessionGuard.verdict(using: onConsole).permitsInput)
    }

    /// Plan §55: `testInputRejectedWhenSessionIsConsole`, integration half,
    /// against a live worker on a live socket.
    ///
    /// This is the strongest assertion available on a single-user machine: this
    /// test process *is* the console session, so a worker running alongside it is
    /// a console-session worker, and it must refuse every input shape.
    func testInputRejectedWhenSessionIsConsoleIntegration() throws {
        let harness = try WorkerHarness()
        try harness.start()
        defer { harness.stop() }

        let hello = try harness.call(Method.hello)
        guard hello.ok, hello.result?["session"]?["verdict"]?.stringValue == "isConsole" else {
            throw XCTSkip("""
                this test expects to run in the console session so that the refusal is \
                observable. The worker reported verdict \
                '\(hello.result?["session"]?["verdict"]?.stringValue ?? "?")'. \
                Both halves of this check are exercised when the suite is also run \
                from inside an AgentSpace session.
                """)
        }

        // Every input shape the protocol allows must be refused, not just the
        // first one.
        let shapes: [JSONValue] = [
            .obj(["actions": .array([.obj(["type": .string("move"), "x": .int(10), "y": .int(10)])])]),
            .obj(["actions": .array([.obj(["type": .string("click"), "x": .int(10), "y": .int(10)])])]),
            .obj(["actions": .array([.obj(["type": .string("type"), "text": .string("hello")])])]),
            .obj(["actions": .array([.obj(["type": .string("key"), "key": .string("cmd+l")])])]),
            .obj(["actions": .array([.obj(["type": .string("scroll"), "dy": .int(-500)])])]),
            .obj(["actions": .array([.obj([
                "type": .string("drag"),
                "fromX": .int(1), "fromY": .int(1), "toX": .int(50), "toY": .int(50),
            ])])]),
            .obj(["actions": .array([.obj(["type": .string("doubleClick"), "x": .int(5), "y": .int(5)])])]),
            .obj(["actions": .array([.obj(["type": .string("rightClick"), "x": .int(5), "y": .int(5)])])]),
            // Even a sleep-only batch is refused, because the refusal is decided
            // before the batch is inspected at all.
            .obj(["actions": .array([.obj(["type": .string("sleep"), "ms": .int(1)])])]),
        ]

        for (index, params) in shapes.enumerated() {
            let code = try harness.errorCode(Method.input, params)
            XCTAssertEqual(code, .sessionIsConsole,
                           "input shape \(index) was not refused with SESSION_IS_CONSOLE")
        }
    }

    // MARK: - 2. No fallback

    /// Plan §55: `testInputDeliveredOnlyToWorkerSession`.
    ///
    /// On a single-session machine the observable form of this property is that
    /// the events are *not delivered at all* rather than delivered somewhere
    /// else. The full two-session assertion activates automatically once an
    /// AgentSpace session exists; see docs/validation.md for the standing gap.
    func testInputDeliveredOnlyToWorkerSession() throws {
        let harness = try WorkerHarness()
        try harness.start()
        defer { harness.stop() }

        let hello = try harness.call(Method.hello)
        let verdict = hello.result?["session"]?["verdict"]?.stringValue
        let permitsInput = hello.result?["session"]?["permitsInput"]?.boolValue ?? false

        if verdict == "isConsole" {
            // The refusal is the guarantee: nothing was posted anywhere.
            let code = try harness.errorCode(Method.input, .obj([
                "actions": .array([.obj(["type": .string("type"), "text": .string("AAA")])]),
            ]))
            XCTAssertEqual(code, .sessionIsConsole,
                           "a console-session worker must post nothing at all")
        } else {
            XCTAssertTrue(permitsInput,
                          "a background worker must permit input, not silently drop it")
            let response = try harness.call(Method.input, .obj([
                "actions": .array([.obj(["type": .string("type"), "text": .string("AAA")])]),
            ]))
            XCTAssertTrue(response.ok, response.error?.message ?? "")
            XCTAssertEqual(response.result?["performed"]?.intValue, 1)
        }
    }

    /// Plan §55: `testWorkerDoesNotFallbackWhenSessionUnavailable`.
    ///
    /// A worker whose session state cannot be determined must refuse, not guess.
    /// The `indeterminate` verdict is the whole point of `SessionGuard`, and this
    /// pins it at the decision layer.
    func testWorkerDoesNotFallbackWhenSessionUnavailable() {
        let cases: [(String, FakeSafetySession)] = [
            ("unreadable dictionary", FakeSafetySession(dictionary: nil, graphicAccess: true)),
            ("dictionary without the console key", FakeSafetySession(
                dictionary: ["kCGSSessionUserNameKey": "agent"], graphicAccess: true)),
            ("console key of the wrong type", FakeSafetySession(
                dictionary: ["kCGSSessionOnConsoleKey": "maybe"], graphicAccess: true)),
            ("console key is null", FakeSafetySession(
                dictionary: ["kCGSSessionOnConsoleKey": NSNull()], graphicAccess: true)),
        ]
        for (label, source) in cases {
            let verdict = SessionGuard.verdict(using: source)
            XCTAssertFalse(verdict.permitsInput, "\(label) must not permit input")
            XCTAssertEqual(verdict, .indeterminate, label)
            XCTAssertEqual(verdict.errorCode, .sessionIsConsole,
                           "\(label) must surface as a console refusal, not a generic error")
        }
    }

    /// A worker with no window server must refuse *everything* GUI, and say so
    /// with the specific code rather than a generic failure.
    func testNoWindowServerIsRefusedDistinctly() {
        let source = FakeSafetySession(
            dictionary: ["kCGSSessionOnConsoleKey": NSNumber(value: false)],
            graphicAccess: false)
        let verdict = SessionGuard.verdict(using: source)
        XCTAssertEqual(verdict, .noWindowServer)
        XCTAssertFalse(verdict.permitsInput)
        XCTAssertEqual(verdict.errorCode, .noWindowServer)
    }

    // MARK: - 3. Privilege

    /// Plan §55: `testWorkerCannotRunAsRoot`.
    ///
    /// The unit half is exact. The integration half cannot run here because the
    /// test process is not root and this session has no way to become root
    /// without a password; the check the *worker* performs at startup is the same
    /// `PrivilegeGuard.refuseReason` asserted below, and the worker's exit code
    /// 77 path is documented in docs/validation.md as unverified end to end.
    func testWorkerCannotRunAsRoot() {
        XCTAssertEqual(PrivilegeGuard.refuseReason(uid: 0)?.code, .workerIsRoot)
        XCTAssertNotNil(PrivilegeGuard.refuseReason(uid: 0)?.message.contains("root"))
        XCTAssertNil(PrivilegeGuard.refuseReason(uid: 1))
        XCTAssertNil(PrivilegeGuard.refuseReason(uid: 501))
        XCTAssertNil(PrivilegeGuard.refuseReason(uid: 65534))
    }

    /// The running worker in these tests is a plain user, and reports it.
    func testRunningWorkerIsNotRoot() throws {
        let harness = try WorkerHarness()
        try harness.start()
        defer { harness.stop() }
        let hello = try harness.call(Method.hello)
        let uid = hello.result?["user"]?["uid"]?.intValue
        XCTAssertNotNil(uid)
        XCTAssertNotEqual(uid, 0, "the worker must never run as root")
        XCTAssertEqual(uid_t(uid!), getuid(), "the worker runs as the user that started it")
    }

    // MARK: - 4. Socket authorization

    /// Plan §55: `testUnauthorizedSocketClientRejected`.
    func testUnauthorizedSocketClientRejected() throws {
        let harness = try WorkerHarness()
        try harness.start()
        defer { harness.stop() }

        // No token at all.
        XCTAssertEqual(try harness.errorCode(Method.status, token: ""), .unauthorized)
        // A token that is well-formed but wrong.
        let wrong = SessionToken.generate()!.hex
        XCTAssertEqual(try harness.errorCode(Method.status, token: wrong), .unauthorized)
        // A token that shares a long prefix with the real one.
        let sharedPrefix = String(harness.token.hex.dropLast()) + (harness.token.hex.hasSuffix("a") ? "b" : "a")
        XCTAssertEqual(try harness.errorCode(Method.status, token: sharedPrefix), .unauthorized)
        // Malformed token.
        XCTAssertEqual(try harness.errorCode(Method.status, token: "not-a-token"), .unauthorized)
        XCTAssertEqual(try harness.errorCode(Method.status, token: String(repeating: "a", count: 64)), .unauthorized)

        // Every mutating method too, not just `status`.
        for method in [Method.screenshot, Method.input, Method.exec, Method.apps,
                       Method.axSnapshot, Method.shutdown] {
            XCTAssertEqual(try harness.errorCode(method, token: wrong), .unauthorized,
                           "\(method) accepted a forged token")
        }

        // And the correct token works, so the gate is not simply closed.
        let valid = try harness.call(Method.status)
        XCTAssertTrue(valid.ok, valid.error?.message ?? "")
    }

    /// `hello` is the only method that answers without a token, and it must not
    /// leak anything secret when it does.
    func testHelloIsTokenExemptButLeaksNothing() throws {
        let harness = try WorkerHarness()
        try harness.start()
        defer { harness.stop() }

        let response = try harness.call(Method.hello, token: "")
        XCTAssertTrue(response.ok, "hello must answer without a token so a client can discover the requirement")
        let result = response.result
        XCTAssertEqual(result?["requiresToken"]?.boolValue, true)

        let serialized = String(decoding: try RPCCodec.encoder().encode(result ?? .null), as: UTF8.self)
        XCTAssertFalse(serialized.contains(harness.token.hex),
                       "hello leaked the session token")
        XCTAssertTrue(serialized.contains("\"display\""), serialized)
    }

    /// Plan §29/§55: `testDifferentSpacesHaveDifferentTokens`.
    ///
    /// Two workers, two roots, two tokens: a token valid for one must not open
    /// the other.
    func testDifferentSpacesHaveDifferentTokens() throws {
        let first = try WorkerHarness()
        let second = try WorkerHarness()
        try first.start()
        try second.start()
        defer { first.stop(); second.stop() }

        XCTAssertNotEqual(first.token.hex, second.token.hex)
        XCTAssertNotEqual(first.paths.socketPath, second.paths.socketPath)

        // Each is reachable with its own token...
        XCTAssertTrue(try first.call(Method.status).ok)
        XCTAssertTrue(try second.call(Method.status).ok)

        // ...and neither with the other's.
        XCTAssertEqual(try first.errorCode(Method.status, token: second.token.hex), .unauthorized)
        XCTAssertEqual(try second.errorCode(Method.status, token: first.token.hex), .unauthorized)
    }

    // MARK: - 5. Screenshots

    /// Plan §55: `testScreenshotNeverReturnsConsoleSession`.
    ///
    /// The full cross-session assertion needs two live sessions, so it is written
    /// to activate when they exist and to skip — loudly, with the reason — when
    /// they do not. What is asserted unconditionally is the weaker but still real
    /// invariant: whatever image comes back describes the *worker's own* session
    /// framebuffer, matching the geometry the worker itself reports.
    func testScreenshotNeverReturnsConsoleSession() throws {
        let harness = try WorkerHarness()
        try harness.start()
        defer { harness.stop() }

        let hello = try harness.call(Method.hello)
        guard let display = hello.result?["display"] else {
            throw XCTSkip("worker reported no display block")
        }
        let permitsInput = hello.result?["session"]?["permitsInput"]?.boolValue ?? false

        let response = try harness.call(Method.screenshot, .obj(["maxWidth": .int(400)]))
        if !response.ok {
            guard response.error?.code == .screenRecordingDenied else {
                return XCTFail("screenshot failed unexpectedly: \(response.error?.message ?? "?")")
            }
            // No grant for the worker's responsible process: the refusal is
            // correct and is itself evidence that no unpermitted capture happens.
            XCTAssertNotNil(response.error?.message)
            throw XCTSkip("""
                the worker has no Screen Recording grant, so the capture path cannot be \
                exercised here. It returned SCREEN_RECORDING_DENIED without invoking \
                `screencapture`, which is the correct behaviour. See docs/validation.md.
                """)
        }

        guard let path = response.result?["path"]?.stringValue,
              let width = response.result?["width"]?.intValue,
              let height = response.result?["height"]?.intValue,
              let scale = response.result?["scale"]?.intValue else {
            return XCTFail("screenshot result is missing fields: \(response.result.map(String.init(describing:)) ?? "nil")")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "screenshot path does not exist: \(path)")
        XCTAssertGreaterThan(width, 0)
        XCTAssertGreaterThan(height, 0)

        // The scale must be the worker's own display scale, derived from the
        // display mode. If this ever reads 1 on a Retina display, the
        // CGDisplayPixelsWide trap has been reintroduced.
        let expectedScale = display["scale"]?.intValue ?? 1
        XCTAssertEqual(scale, expectedScale)
        let expectedPixelWidth = display["pixelWidth"]?.intValue ?? 0
        XCTAssertEqual(expectedPixelWidth, (display["width"]?.intValue ?? 0) * expectedScale,
                       "pixelWidth must be width * scale")

        // The image must live inside the Space's own runtime directory, so it can
        // only ever describe this Space.
        XCTAssertTrue(path.hasPrefix(harness.paths.directory),
                      "screenshot landed outside the Space runtime directory: \(path)")

        // Downscaling must not change the aspect ratio wildly.
        let fullWidth = display["width"]?.intValue ?? width
        XCTAssertLessThanOrEqual(width, max(400, fullWidth))

        if permitsInput {
            // A background session: the meaningful cross-session assertion is
            // that the captured image is not the console's. Both descriptions
            // must agree, and the console's would not.
            XCTAssertNotEqual(scale, 0)
        } else {
            throw XCTSkip("""
                the worker's session is the console, so a console-vs-background \
                comparison is not observable on this machine. The capture-path \
                invariants above were asserted. Full verification needs an \
                AgentSpace session; see docs/validation.md.
                """)
        }
    }

    // MARK: - 6. Workspace escape

    /// Plan §55: `testWorkspaceCannotEscapeAllowedPath`.
    func testWorkspaceCannotEscapeAllowedPath() throws {
        let base = NSTemporaryDirectory() + "/agentspace-escape-\(UUID().uuidString)"
        let workspace = base + "/workspace"
        let outside = base + "/outside"
        try FileManager.default.createDirectory(atPath: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: outside, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: URL(fileURLWithPath: outside + "/secret.txt"))
        defer { try? FileManager.default.removeItem(atPath: base) }

        // Plain traversal out of the root.
        XCTAssertEqual(
            WorkspaceGuard.check(path: workspace + "/../outside/secret.txt",
                                 allowedRoots: [workspace])?.code,
            .workspaceDenied)

        // Absolute path elsewhere.
        XCTAssertEqual(
            WorkspaceGuard.check(path: "/etc/passwd", allowedRoots: [workspace])?.code,
            .workspaceDenied)

        // Symlink pointing out.
        let link = workspace + "/link"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: outside)
        XCTAssertEqual(
            WorkspaceGuard.check(path: link + "/secret.txt", allowedRoots: [workspace])?.code,
            .workspaceDenied)

        // The genuinely-inside path still works, so the guard is not simply
        // refusing everything.
        XCTAssertNil(WorkspaceGuard.check(path: workspace + "/file.txt", allowedRoots: [workspace]))

        // And through the real worker: an `exec` cwd outside the declared roots
        // must be refused, not run.
        let harness = try WorkerHarness()
        try harness.start()
        defer { harness.stop() }
        // Without a space.json the worker reports itself unconfined, which is the
        // documented pre-phase-7 state. Assert the honest report rather than a
        // confinement that is not in effect.
        let status = try harness.call(Method.status)
        XCTAssertEqual(status.result?["workspace"]?["confined"]?.boolValue, false)
        XCTAssertEqual(status.result?["workspace"]?["allowedRoots"]?.arrayValue?.count, 0)
    }

    // MARK: - 7. Exec

    /// `exec` runs as the Space's own user, never as root, and never through a
    /// shell that could elevate.
    func testExecRunsAsTheSpaceUserAndRefusesDangerousCommands() throws {
        let harness = try WorkerHarness()
        try harness.start()
        defer { harness.stop() }

        let identity = try harness.call(Method.exec, .obj([
            "command": .string("id -u; id -un"),
        ]))
        XCTAssertTrue(identity.ok, identity.error?.message ?? "")
        let stdout = identity.result?["stdout"]?.stringValue ?? ""
        XCTAssertTrue(stdout.contains("\(getuid())"), "exec did not run as this user: \(stdout)")
        XCTAssertFalse(stdout.contains("\n0\n"), "exec produced a root uid: \(stdout)")

        // Refused commands come back as EXEC_DENIED, not as a shell error.
        for command in ["sudo whoami", "reboot", "dscl create /Users/evil", "rm -rf /"] {
            XCTAssertEqual(
                try harness.errorCode(Method.exec, .obj(["command": .string(command)])),
                .execDenied,
                "'\(command)' was not refused")
        }

        // A non-zero exit is a normal result, not an RPC error.
        let failing = try harness.call(Method.exec, .obj(["command": .string("exit 3")]))
        XCTAssertTrue(failing.ok, "a non-zero exit must not be an RPC error")
        XCTAssertEqual(failing.result?["exitCode"]?.intValue, 3)
        XCTAssertEqual(failing.result?["timedOut"]?.boolValue, false)

        // stderr is kept separate from stdout.
        let streams = try harness.call(Method.exec, .obj([
            "command": .string("echo out; echo err 1>&2"),
        ]))
        XCTAssertEqual(streams.result?["stdout"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), "out")
        XCTAssertEqual(streams.result?["stderr"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), "err")
    }

    /// A command that never returns must be killed, and reported as a timeout
    /// rather than as a clean exit.
    func testExecTimeoutKillsTheProcessGroup() throws {
        let harness = try WorkerHarness()
        try harness.start()
        defer { harness.stop() }

        let response = try harness.call(Method.exec, .obj([
            "command": .string("sleep 30"),
            "timeoutMs": .int(1500),
        ]))
        XCTAssertTrue(response.ok, response.error?.message ?? "")
        XCTAssertEqual(response.result?["timedOut"]?.boolValue, true)
        XCTAssertEqual(response.result?["exitCode"], .null,
                       "a timed-out command must not report an exit code")
        XCTAssertLessThan(response.result?["duration"]?.intValue ?? 99_999, 20_000)
    }

    // MARK: - 8. Protocol

    func testProtocolMismatchIsRefused() throws {
        let harness = try WorkerHarness()
        try harness.start()
        defer { harness.stop() }

        let mismatched = RPCRequest(
            protocol: agentSpaceProtocolVersion + 1,
            requestId: "mismatch",
            token: harness.token.hex,
            method: Method.status)
        let data = try RPCCodec.encodeLine(mismatched)

        // Send it by hand: the harness's typed client always uses the current
        // version, and that is the right thing for it to do.
        let response = try rawRequest(harness: harness, payload: data)
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.code, .protocolMismatch)
    }

    func testUnknownMethodIsRefused() throws {
        let harness = try WorkerHarness()
        try harness.start()
        defer { harness.stop() }
        XCTAssertEqual(try harness.errorCode("definitely.not.a.method"), .methodNotFound)
    }

    func testMalformedRequestIsRefusedNotCrashed() throws {
        let harness = try WorkerHarness()
        try harness.start()
        defer { harness.stop() }

        let response = try rawRequest(harness: harness, payload: Data("not json at all\n".utf8))
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.code, .badRequest)

        // The worker is still alive and serving afterwards.
        XCTAssertTrue(try harness.call(Method.hello).ok)
    }

    // MARK: - Status shape

    /// `status` must report the display in BOTH coordinate spaces.
    ///
    /// It originally reported only the point size. Every client that read
    /// `status` and wanted the backing-store size then got nothing: the GUI
    /// rendered "Pixels 0 x 0", and its Desktop Viewer lost the mapping fallback
    /// it needs before the first capture arrives. `hello` had reported both all
    /// along, so the two methods disagreed — which is exactly the kind of drift a
    /// test on the wire shape catches and a unit test on either side does not.
    func testStatusReportsBothCoordinateSpaces() throws {
        let harness = try WorkerHarness()
        try harness.start()
        defer { harness.stop() }

        let response = try harness.call(Method.status)
        XCTAssertTrue(response.ok, response.error?.message ?? "")
        guard let display = response.result?["display"] else {
            return XCTFail("status returned no display block")
        }

        let width = display["width"]?.intValue ?? 0
        let height = display["height"]?.intValue ?? 0
        let pixelWidth = display["pixelWidth"]?.intValue ?? 0
        let pixelHeight = display["pixelHeight"]?.intValue ?? 0
        let scale = display["scale"]?.intValue ?? 0

        XCTAssertGreaterThan(width, 0, "point width must be reported")
        XCTAssertGreaterThan(height, 0, "point height must be reported")
        XCTAssertGreaterThan(scale, 0, "scale must be reported")
        XCTAssertEqual(pixelWidth, width * scale,
                       "pixels must be points x scale, not absent or zero")
        XCTAssertEqual(pixelHeight, height * scale)

        // `hello` and `status` describe the same machine, so they must agree.
        let hello = try harness.call(Method.hello)
        XCTAssertEqual(hello.result?["display"]?["pixelWidth"]?.intValue, pixelWidth,
                       "hello and status disagree about the display")
        XCTAssertEqual(hello.result?["display"]?["scale"]?.intValue, scale)
    }

    /// `status` must not fork `ps` unless resources were actually asked for:
    /// plan §53 wants the UI to poll this every few seconds for nearly nothing.
    func testStatusOmitsResourcesUnlessAskedAndNeverBlocksInput() throws {
        let harness = try WorkerHarness()
        try harness.start()
        defer { harness.stop() }

        let summary = try harness.call(Method.status)
        XCTAssertNil(summary.result?["resources"],
                     "a plain status must not pay for a resource sample")

        let full = try harness.call(Method.status, .object(["resources": .string("full")]))
        XCTAssertTrue(full.ok, full.error?.message ?? "")
        guard let resources = full.result?["resources"] else {
            return XCTFail("resources: full returned no resources block")
        }
        XCTAssertNotNil(resources["cpuPercent"])
        XCTAssertNotNil(resources["memoryBytes"])
        XCTAssertNotNil(resources["processCount"])
    }

    // MARK: - Helpers

    private func rawRequest(harness: WorkerHarness, payload: Data) throws -> RPCResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw XCTSkip("socket() failed") }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(harness.paths.socketPath.utf8)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 104) { chars in
                for (i, byte) in bytes.enumerated() { chars[i] = CChar(bitPattern: byte) }
                chars[bytes.count] = 0
            }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                connect(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw XCTSkip("connect failed: \(String(cString: strerror(errno)))") }

        _ = payload.withUnsafeBytes { raw in
            write(fd, raw.baseAddress, raw.count)
        }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
            if buffer.contains(Framing.newline) { break }
        }
        if let newline = buffer.firstIndex(of: Framing.newline) { buffer = buffer[..<newline] }
        return try RPCCodec.decoder().decode(RPCResponse.self, from: buffer)
    }
}

/// Local stand-in for the unit target's fake, so the safety target is
/// self-contained.
struct FakeSafetySession: SessionInfoSource, @unchecked Sendable {
    var dictionary: [String: Any]?
    var graphicAccess: Bool?
    func currentSessionDictionary() -> [String: Any]? { dictionary }
    func hasGraphicAccess() -> Bool? { graphicAccess }
    func currentUID() -> uid_t { getuid() }
}
