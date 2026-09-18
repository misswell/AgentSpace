import Foundation
import AppKit
import AgentSpaceCore

/// The worker's method implementations. Plan §21.
///
/// One rule runs through all of this: **every operation that could touch the
/// human's desktop re-checks the session verdict at the moment it runs.** The
/// check is not cached at startup, because a session can become the console at
/// any instant — that is precisely what fast user switching does.
struct Operations {
    let context: WorkerContext

    static let workerVersion = "0.1.0"

    // MARK: - Dispatch

    func dispatch(method: String, params: JSONValue) -> Result<JSONValue, AgentSpaceError> {
        do {
            switch method {
            case Method.hello: return .success(try hello())
            case Method.status: return .success(try status(params: params))
            case Method.screenshot: return .success(try screenshot(params: params))
            case Method.input: return .success(try input(params: params))
            case Method.apps: return .success(try apps())
            case Method.launch: return .success(try launch(params: params))
            case Method.quit, Method.forceQuit:
                return .success(try quit(params: params, force: method == Method.forceQuit))
            case Method.activate: return .success(try activate(params: params))
            case Method.exec: return .success(try exec(params: params))
            case Method.axSnapshot: return .success(try axSnapshot(params: params))
            case Method.axFrontmost: return .success(try axFrontmost())
            case Method.axWindows: return .success(try axWindows(params: params))
            case Method.axPerform: return .success(try axPerform(params: params))
            case Method.shutdown: return .success(try shutdown(params: params))
            default:
                return .failure(AgentSpaceError(
                    code: .methodNotFound,
                    message: "unknown method '\(method)'"))
            }
        } catch let error as AgentSpaceError {
            return .failure(error)
        } catch {
            return .failure(AgentSpaceError(
                code: .internalError,
                message: "unexpected failure in \(method): \(error)"))
        }
    }

    // MARK: - hello

    /// Non-sensitive liveness facts. Answers without a token, because it is how
    /// a client discovers that a token is required.
    func hello() throws -> JSONValue {
        let geometry = ScreenCapture.mainDisplayGeometry()
        let verdict = context.sessionVerdict()
        return .obj([
            "protocol": .int(agentSpaceProtocolVersion),
            "worker": .obj([
                "version": .string(Operations.workerVersion),
                "pid": .int(Int(getpid())),
            ]),
            "space": .obj([
                "id": .string(context.spaceID.uuidString),
                "name": .string(context.spaceName),
            ]),
            "user": .obj([
                "uid": .int(Int(context.uid)),
                "name": .string(context.username),
                "home": .string(context.home),
            ]),
            "session": .obj([
                "verdict": .string(verdictName(verdict)),
                "onConsole": .bool(verdict == .isConsole || verdict == .indeterminate),
                "permitsInput": .bool(verdict.permitsInput),
                "windowServer": .bool(verdict != .noWindowServer),
            ]),
            "display": .obj([
                "width": .int(geometry.width),
                "height": .int(geometry.height),
                "pixelWidth": .int(geometry.pixelWidth),
                "pixelHeight": .int(geometry.pixelHeight),
                "scale": .int(geometry.scale),
            ]),
            "permissions": .obj([
                "screenRecording": .bool(ScreenCapture.permissionGranted()),
                "accessibility": .bool(AccessibilityBridge.trusted()),
            ]),
            "requiresToken": .bool(true),
        ])
    }

    // MARK: - status

    func status(params: JSONValue) throws -> JSONValue {
        let verdict = context.sessionVerdict()
        let permissions = PermissionState(
            screenRecording: ScreenCapture.permissionGranted(),
            accessibility: AccessibilityBridge.trusted())
        let state = currentState(verdict: verdict, permissions: permissions)
        let geometry = ScreenCapture.mainDisplayGeometry()

        var object: [String: JSONValue] = [
            "space": .string(context.spaceName),
            "spaceId": .string(context.spaceID.uuidString),
            "uid": .int(Int(context.uid)),
            "user": .string(context.username),
            "state": .string(state.rawValue),
            "stateLabel": .string(state.displayName),
            "acceptsInput": .bool(state.acceptsInput),
            "worker": .bool(true),
            "workerPid": .int(Int(getpid())),
            "workerUptimeSeconds": .int(Int(Date().timeIntervalSince(context.startedAt))),
            "screenRecording": .bool(permissions.screenRecording),
            "accessibility": .bool(permissions.accessibility),
            "session": .obj([
                "verdict": .string(verdictName(verdict)),
                "onConsole": .bool(verdict == .isConsole || verdict == .indeterminate),
            ]),
            "display": .obj([
                "width": .int(geometry.width),
                "height": .int(geometry.height),
                "scale": .int(geometry.scale),
            ]),
            "workspace": .obj([
                "confined": .bool(!context.allowedRoots.isEmpty),
                "allowedRoots": .array(context.allowedRoots.map { .string($0) }),
                "writableRoots": .array(context.writableRoots.sorted().map { .string($0) }),
            ]),
        ]
        // Resource sampling forks `ps`, so it is opt-in: plan §53 wants status
        // polling every 2-5s to be nearly free.
        if params["resources"]?.stringValue == "full" {
            object["resources"] = Resources.sample(uid: context.uid).json
        }
        return .object(object)
    }

    /// The state the dashboard shows.
    ///
    /// `indeterminate` maps to `.console` rather than `.error` on purpose: from
    /// the outside, "we cannot prove this session is a background one" and "this
    /// session is the console" have the same consequence — no input — and
    /// collapsing them keeps a caller from treating the unprovable case as the
    /// safe one.
    func currentState(verdict: SessionVerdict, permissions: PermissionState) -> SpaceState {
        switch verdict {
        case .isConsole, .indeterminate: return .console
        case .noWindowServer: return .error
        case .usable:
            return permissions.allGranted ? .ready : .needsPermission
        }
    }

    private func verdictName(_ verdict: SessionVerdict) -> String {
        switch verdict {
        case .usable: return "usable"
        case .isConsole: return "isConsole"
        case .noWindowServer: return "noWindowServer"
        case .indeterminate: return "indeterminate"
        }
    }

    // MARK: - screenshot

    func screenshot(params: JSONValue) throws -> JSONValue {
        // A screenshot is not input, so being on the console is not a refusal —
        // capturing the console is exactly what the human sees anyway. What it
        // must never do is capture the *wrong* session: because `screencapture`
        // runs inside this process's own session, it captures this session by
        // construction.
        let verdict = context.sessionVerdict()
        guard verdict != .noWindowServer, verdict != .indeterminate else {
            throw AgentSpaceError(
                code: .noWindowServer,
                message: "this AgentSpace session has no window server, so there is no framebuffer to capture.")
        }
        guard ScreenCapture.permissionGranted() else {
            throw AgentSpaceError(
                code: .screenRecordingDenied,
                message: "Screen Recording is not granted to agentspace-worker in this session.")
        }

        let fm = FileManager.default
        try? fm.createDirectory(atPath: context.screenshotsDirectory, withIntermediateDirectories: true)

        let destination: String
        if let explicit = params["path"]?.stringValue, !explicit.isEmpty {
            // A caller-supplied path is a write target: confine it.
            if let error = WorkspaceGuard.check(
                path: explicit,
                allowedRoots: context.allowedRoots,
                requireWrite: true,
                writableRoots: context.writableRoots) {
                throw error
            }
            destination = WorkspaceGuard.resolve(explicit)
        } else {
            let stamp = Int(Date().timeIntervalSince1970 * 1000)
            destination = context.screenshotsDirectory + "/shot-\(stamp).png"
        }

        let maxWidth = params["maxWidth"]?.intValue
        if let maxWidth, maxWidth <= 0 {
            throw AgentSpaceError(code: .badRequest, message: "maxWidth must be a positive integer")
        }
        let displayIndex = params["display"]?.intValue

        let result = try ScreenCapture.capture(
            to: destination,
            maxWidth: maxWidth,
            display: displayIndex)

        var json = result.json
        if params["inline"]?.boolValue == true {
            guard let data = fm.contents(atPath: result.path) else {
                throw AgentSpaceError(
                    code: .internalError,
                    message: "captured \(result.path) but could not read it back")
            }
            var object = json.objectValue ?? [:]
            object["pngBase64"] = .string(data.base64EncodedString())
            json = .object(object)
        }
        return json
    }

    // MARK: - input

    /// The one operation where getting the order wrong puts events on the
    /// human's screen. Plan §12/§13.
    func input(params: JSONValue) throws -> JSONValue {
        // (1) Session safety, first and unconditionally.
        let verdict = context.sessionVerdict()
        switch verdict {
        case .isConsole:
            Log.input.error("refused input: session is on the console")
            throw AgentSpaceError(
                code: .sessionIsConsole,
                message: "refusing to inject input: the '\(context.spaceName)' session is currently on the console, so events would land on the user's own screen.")
        case .indeterminate:
            Log.input.error("refused input: session state could not be determined")
            throw AgentSpaceError(
                code: .sessionIsConsole,
                message: "refusing to inject input: this session's console state could not be determined (CGSessionCopyCurrentDictionary did not answer). AgentSpace fails closed rather than risk posting events onto the user's screen.")
        case .noWindowServer:
            throw AgentSpaceError(
                code: .noWindowServer,
                message: "refusing to inject input: this session has no window server, so there is no event stream to post into.")
        case .usable:
            break
        }

        // (2) A daemon without Accessibility could post nothing anyway, so say
        // that rather than accepting a batch that will silently do nothing.
        guard AccessibilityBridge.trusted() else {
            throw AgentSpaceError(
                code: .accessibilityDenied,
                message: "Accessibility is not granted to agentspace-worker in this session, so synthetic input cannot be delivered.")
        }

        // (3) Validate the *entire* batch before performing any of it.
        guard let rawActions = params["actions"] else {
            throw AgentSpaceError(code: .invalidAction, message: #"input requires an "actions" array"#)
        }
        let actions: [InputAction]
        switch InputAction.parseBatch(rawActions) {
        case .success(let parsed): actions = parsed
        case .failure(let error): throw error
        }

        // (4) Coordinate sanity against the real display, so a pixel/point mix-up
        // is a clear INVALID_COORDINATE rather than a click in the wrong place.
        let geometry = ScreenCapture.mainDisplayGeometry()
        for (index, action) in actions.enumerated() {
            switch action {
            case .move(let x, let y), .click(let x, let y, _, _, _):
                if let error = CoordinateRules.validate(x: x, y: y, geometry: geometry) {
                    throw AgentSpaceError(
                        code: error.code,
                        message: "action \(index): \(error.message)")
                }
            case .drag(let fx, let fy, let tx, let ty, _, _):
                for (label, x, y) in [("fromX/fromY", fx, fy), ("toX/toY", tx, ty)] {
                    if let error = CoordinateRules.validate(x: x, y: y, geometry: geometry) {
                        throw AgentSpaceError(
                            code: error.code,
                            message: "action \(index) \(label): \(error.message)")
                    }
                }
            default:
                break
            }
        }

        // (5) Keyboard and mouse events need somewhere to land. Posting into a
        // session with no frontmost app is a silent no-op, and a silent no-op is
        // worse than an error because the agent believes it worked.
        let needsTarget = actions.contains { action in
            if case .sleep = action { return false }
            return true
        }
        if needsTarget {
            let frontmost = AppControl.frontmostPID()
            if frontmost == nil || frontmost == getpid() {
                throw AgentSpaceError(
                    code: .noInputTarget,
                    message: "no app is frontmost in the '\(context.spaceName)' session, so the events would be delivered to nothing.")
            }
        }

        // (6) Perform, in order. Nothing above this line has a side effect.
        var performed = 0
        for action in actions {
            do {
                try InputSynthesizer.perform(action)
            } catch let error as AgentSpaceError {
                throw AgentSpaceError(
                    code: error.code,
                    message: "after \(performed) action(s): \(error.message)",
                    recoverable: error.recoverable)
            }
            performed += 1
        }
        Log.input.info("performed \(performed) input action(s) in \(context.spaceName)")
        return .obj(["performed": .int(performed)])
    }

    // MARK: - apps

    func apps() throws -> JSONValue {
        let list = AppControl.runningApps()
        return .obj([
            "count": .int(list.count),
            "apps": .array(list.map(\.json)),
        ])
    }

    func launch(params: JSONValue) throws -> JSONValue {
        guard let reference = params["app"]?.stringValue, !reference.isEmpty else {
            throw AgentSpaceError(code: .badRequest, message: #"launch requires a non-empty "app" string"#)
        }
        let timeout = Double(params["timeoutSeconds"]?.intValue ?? 30)
        let app = try AppControl.launch(reference, timeout: max(1, min(timeout, 300)))
        return app.json
    }

    func quit(params: JSONValue, force: Bool) throws -> JSONValue {
        guard let reference = params["app"]?.stringValue, !reference.isEmpty else {
            throw AgentSpaceError(code: .badRequest, message: #"quit requires a non-empty "app" string"#)
        }
        return try AppControl.quit(reference, force: force).json
    }

    func activate(params: JSONValue) throws -> JSONValue {
        guard let reference = params["app"]?.stringValue, !reference.isEmpty else {
            throw AgentSpaceError(code: .badRequest, message: #"activate requires a non-empty "app" string"#)
        }
        return try AppControl.activate(reference).json
    }

    // MARK: - exec

    func exec(params: JSONValue) throws -> JSONValue {
        guard let command = params["command"]?.stringValue, !command.isEmpty else {
            throw AgentSpaceError(code: .badRequest, message: #"exec requires a non-empty "command" string"#)
        }
        var cwd: String?
        if let raw = params["cwd"]?.stringValue, !raw.isEmpty {
            let resolved = WorkspaceGuard.resolve(raw)
            // Confinement is only enforced when the Space declared roots. When it
            // has none, `status.workspace.confined` is false and this is a
            // documented gap until phase 7 rather than a silent one.
            if !context.allowedRoots.isEmpty {
                if let error = WorkspaceGuard.check(
                    path: resolved,
                    allowedRoots: context.allowedRoots,
                    requireWrite: true,
                    writableRoots: context.writableRoots) {
                    throw error
                }
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw AgentSpaceError(
                    code: .badRequest,
                    message: "cwd '\(resolved)' is not an existing directory in the AgentSpace session.")
            }
            cwd = resolved
        }

        var environment: [String: String] = [:]
        if let raw = params["env"]?.objectValue {
            for (key, value) in raw {
                guard let string = value.stringValue else {
                    throw AgentSpaceError(
                        code: .badRequest,
                        message: "env['\(key)'] must be a string")
                }
                environment[key] = string
            }
        }
        // HOME/USER/LOGNAME/TMPDIR are forced to the agent user's own, never the
        // caller's: overridable identity in a shell is a confused-deputy bug.
        environment["HOME"] = context.home
        environment["USER"] = context.username
        environment["LOGNAME"] = context.username
        environment.removeValue(forKey: "DISPLAY")

        let timeoutMs = params["timeoutMs"]?.intValue ?? 120_000
        guard timeoutMs > 0, timeoutMs <= 3_600_000 else {
            throw AgentSpaceError(
                code: .badRequest,
                message: "timeoutMs must be between 1 and 3600000")
        }

        let result = try ShellExec.run(
            command: command,
            cwd: cwd,
            environment: environment,
            timeoutMs: timeoutMs,
            stdin: params["stdin"]?.stringValue)

        if result.timedOut {
            var object = result.json.objectValue ?? [:]
            object["note"] = .string("the process group was terminated after \(timeoutMs)ms")
            return .object(object)
        }
        return result.json
    }

    // MARK: - accessibility

    private func targetPid(_ params: JSONValue) -> pid_t? {
        if let pid = params["pid"]?.intValue { return pid_t(pid) }
        return AppControl.frontmostPID()
    }

    func axSnapshot(params: JSONValue) throws -> JSONValue {
        try AccessibilityBridge.requireTrust()
        guard let pid = targetPid(params) else {
            throw AgentSpaceError(
                code: .noInputTarget,
                message: "no pid given and no app is frontmost in this AgentSpace, so there is no accessibility tree to read.")
        }
        return AccessibilityBridge.snapshot(
            pid: pid,
            maxDepth: params["maxDepth"]?.intValue ?? AccessibilityBridge.maxDepth,
            maxNodes: params["maxNodes"]?.intValue ?? AccessibilityBridge.maxNodes,
            interestingOnly: params["interestingOnly"]?.boolValue ?? true)
    }

    func axFrontmost() throws -> JSONValue {
        try AccessibilityBridge.requireTrust()
        guard let pid = AppControl.frontmostPID() else {
            throw AgentSpaceError(
                code: .noInputTarget,
                message: "no app is frontmost in this AgentSpace.")
        }
        let app = NSRunningApplication(processIdentifier: pid)
        var object: [String: JSONValue] = [
            "pid": .int(Int(pid)),
            "name": .string(app?.localizedName ?? "unknown"),
        ]
        if let bundleID = app?.bundleIdentifier { object["bundleId"] = .string(bundleID) }
        if let focused = AccessibilityBridge.copyAttribute(
            AccessibilityBridge.appElement(pid: pid),
            kAXFocusedUIElementAttribute as String) {
            object["focusedElement"] = AccessibilityBridge.describe(
                focused as! AXUIElement, depth: 0)
        }
        return .object(object)
    }

    func axWindows(params: JSONValue) throws -> JSONValue {
        try AccessibilityBridge.requireTrust()
        guard let pid = targetPid(params) else {
            throw AgentSpaceError(
                code: .noInputTarget,
                message: "no pid given and no app is frontmost in this AgentSpace.")
        }
        return AccessibilityBridge.windows(pid: pid)
    }

    func axPerform(params: JSONValue) throws -> JSONValue {
        try AccessibilityBridge.requireTrust()
        guard let pid = targetPid(params) else {
            throw AgentSpaceError(
                code: .noInputTarget,
                message: "no pid given and no app is frontmost in this AgentSpace.")
        }
        let role = params["role"]?.stringValue
        let titleContains = params["titleContains"]?.stringValue
        let identifier = params["identifier"]?.stringValue

        // `click: true` means "find it and click where it is", which goes
        // through the session event tap like every other click.
        if params["click"]?.boolValue == true {
            return try AccessibilityBridge.clickElement(
                pid: pid, role: role, titleContains: titleContains, identifier: identifier)
        }
        guard let action = params["action"]?.stringValue, !action.isEmpty else {
            throw AgentSpaceError(
                code: .badRequest,
                message: #"ax.perform requires "action" (e.g. AXPress) or "click": true"#)
        }
        return try AccessibilityBridge.perform(
            pid: pid, action: action, role: role, titleContains: titleContains, identifier: identifier)
    }

    // MARK: - shutdown

    func shutdown(params: JSONValue) throws -> JSONValue {
        let reason = params["reason"]?.stringValue ?? "requested"
        Log.worker.info("shutdown requested: \(reason)")
        // Exit on a delay so the reply reaches the client first.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            exit(0)
        }
        return .obj(["stopping": .bool(true), "reason": .string(reason)])
    }
}

/// Actual resource usage for a uid, aggregated from the process table.
///
/// Deliberately not "allocated" numbers: a Space is not a VM, so the honest
/// figure is what its processes are really using (plan §30).
enum Resources {
    struct Sample {
        var cpuPercent: Double
        var memoryBytes: UInt64
        var processCount: Int

        var json: JSONValue {
            .obj([
                "cpuPercent": .double(cpuPercent),
                "memoryBytes": .int(Int(memoryBytes)),
                "processCount": .int(processCount),
            ])
        }
    }

    /// One `ps` invocation, filtered to the uid. Called at most every couple of
    /// seconds by the UI, so the fork cost is acceptable and avoids the
    /// private-API surface of `proc_pidinfo` across a `libproc` boundary.
    static func sample(uid: uid_t) -> Sample {
        var sample = Sample(cpuPercent: 0, memoryBytes: 0, processCount: 0)
        guard let output = runPS() else { return sample }
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3, let lineUID = uid_t(fields[0]), lineUID == uid else { continue }
            guard let rssKilobytes = UInt64(fields[1]), let cpu = Double(fields[2]) else { continue }
            sample.processCount += 1
            sample.memoryBytes += rssKilobytes * 1024
            sample.cpuPercent += cpu
        }
        return sample
    }

    private static func runPS() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "uid=,rss=,pcpu="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
