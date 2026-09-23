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
    /// The §52 live preview lifecycle. The factory closure injects the real
    /// ScreenCaptureKit source; there is no other place capture can come from.
    let preview: PreviewController
    let windowCatalog: WindowCatalog
    let windowStreams: WindowStreamManager
    let inputLease: InputLeaseManager
    let frames: FrameManager

    static let workerVersion = agentSpaceVersion

    init(context: WorkerContext, preview: PreviewController? = nil, frames: FrameManager? = nil) {
        self.context = context
        self.preview = preview ?? PreviewController(idleTimeout: 10) { fps in
            ScreenCaptureFrameSource()
        }
        self.windowCatalog = WindowCatalog()
        self.windowStreams = WindowStreamManager()
        self.inputLease = InputLeaseManager(duration: 5)
        self.frames = frames ?? FrameManager(context: context)
    }

    // MARK: - Dispatch

    func dispatch(method: String, params: JSONValue) -> Result<JSONValue, AgentSpaceError> {
        do {
            switch method {
            case Method.hello: return .success(try hello())
            case Method.status: return .success(try status(params: params))
            case Method.screenshot: return .success(try screenshot(params: params))
            case Method.input: return .success(try input(params: params))
            case Method.apps: return .success(try apps())
            case Method.appsAvailable: return .success(try appsAvailable(params: params))
            case Method.launch: return .success(try launch(params: params))
            case Method.quit, Method.forceQuit:
                return .success(try quit(params: params, force: method == Method.forceQuit))
            case Method.activate: return .success(try activate(params: params))
            case Method.exec: return .success(try exec(params: params))
            case Method.axSnapshot: return .success(try axSnapshot(params: params))
            case Method.axFrontmost: return .success(try axFrontmost())
            case Method.axWindows: return .success(try axWindows(params: params))
            case Method.axElementAt: return .success(try axElementAt(params: params))
            case Method.axPerform: return .success(try axPerform(params: params))
            case Method.openSystemSettings: return .success(try openSystemSettings(params: params))
            case Method.shutdown: return .success(try shutdown(params: params))
            case Method.previewStart: return .success(try previewStart(params: params))
            case Method.previewFrame: return .success(try previewFrame())
            case Method.previewStop: return .success(try previewStop())
            case Method.frameOpen: return .success(try frameOpen(params: params))
            case Method.frameClose: return .success(try frameClose(params: params))
            case Method.frameConfigure: return .success(try frameConfigure(params: params))
            case Method.frameRequestFull: return .success(try frameRequestFull(params: params))
            case Method.frameStats: return .success(try frameStats(params: params))
            case Method.windowList: return .success(try windowList())
            case Method.windowStreamStart: return .success(try windowStreamStart(params: params))
            case Method.windowStreamFrame: return .success(try windowStreamFrame(params: params))
            case Method.windowStreamStop: return .success(try windowStreamStop(params: params))
            case Method.windowInput: return .success(try windowInput(params: params))
            case Method.windowHumanClaim: return .success(try windowHumanClaim(params: params))
            case Method.windowActivate: return .success(try windowActivate(params: params))
            case Method.windowClose: return .success(try windowAction(params: params, action: .close))
            case Method.windowMinimize: return .success(try windowAction(params: params, action: .minimize))
            case Method.windowSetFrame: return .success(try windowSetFrame(params: params))
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

    /// Fail-closed for every method that observes or manipulates the GUI
    /// session (plan §2, §12, §54).
    ///
    /// The console refusal is not only about *injecting* events. When this
    /// session IS the console, the framebuffer, the window list and the
    /// accessibility tree belong to the human's desktop: capturing or reading
    /// them would hand the agent the user's private screen — a leak through the
    /// observation channel, found empirically by the integration suite (a
    /// console-session worker happily returned a 3840px PNG of the user's
    /// desktop). So a console-session worker answers only what cannot reveal
    /// anyone's desktop: hello, status, exec and shutdown. Everything else
    /// refuses with SESSION_IS_CONSOLE.
    private func requireDesktopSession(_ what: String) throws {
        let verdict = context.sessionVerdict()
        guard verdict == .usable else {
            Log.input.error("refused \(what): desktop session is not usable")
            let message: String
            switch verdict {
            case .isConsole:
                message = "the session is currently on the physical console"
            case .indeterminate:
                message = "the session's console state could not be determined"
            case .noWindowServer:
                message = "the session has no WindowServer"
            case .usable:
                preconditionFailure("handled by guard")
            }
            throw AgentSpaceError(
                code: verdict.errorCode,
                message: "refusing to \(what): \(message). AgentSpace requires a provably background Aqua desktop.")
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
                "fileAccess": .bool(FilePrivacy.granted(home: context.home)),
            ]),
            "requiresToken": .bool(true),
        ])
    }

    // MARK: - status

    func status(params: JSONValue) throws -> JSONValue {
        let verdict = context.sessionVerdict()
        let desktopReadiness = context.desktopReadiness()
        let fileAccess = FilePrivacy.granted(home: context.home)
        let permissions = PermissionState(
            screenRecording: ScreenCapture.permissionGranted(),
            accessibility: AccessibilityBridge.trusted(),
            fileAccess: fileAccess)
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
            "fileAccess": .bool(fileAccess),
            "session": .obj([
                "verdict": .string(verdictName(verdict)),
                "onConsole": .bool(verdict == .isConsole || verdict == .indeterminate),
            ]),
            // Why input would be refused, without having to try it: the same
            // verdict the input path gates on, so a client can show "the desktop
            // is still coming up" instead of reporting a mysterious failed click.
            "desktop": .obj([
                "ready": .bool(desktopReadiness.isReady),
                "missing": .array(desktopReadiness.gaps.map { .string($0.rawValue) }),
                "summary": .string(desktopReadiness.summary),
            ]),
            // Both coordinate spaces, as `hello` already reported them. Sending
            // only the point size here meant a client that read `status` alone
            // saw `pixelWidth: 0` — the GUI rendered "Pixels 0 x 0", and its
            // Desktop Viewer lost the fallback it needs to map a click before the
            // first capture arrives.
            "display": .obj([
                "width": .int(geometry.width),
                "height": .int(geometry.height),
                "pixelWidth": .int(geometry.pixelWidth),
                "pixelHeight": .int(geometry.pixelHeight),
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
        if let resources = params["resources"]?.stringValue, resources == "full" || resources == "disk" {
            // Disk is a separate request from CPU/memory: it costs a directory walk
            // over the agent's whole home, and the app's 2–5 s status poll must not
            // pay for that (§53).
            object["resources"] = Resources.sample(
                uid: context.uid,
                includeDisk: resources == "disk",
                home: context.home,
                fileAccess: permissions.fileAccess ?? false).json
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
        // Reverses an earlier, reasoned-but-wrong call documented right here:
        // "capturing the console is exactly what the human sees anyway" is
        // precisely the problem — it is a picture of the user's private desktop,
        // delivered to the agent. §54: a screenshot must never be the user's
        // desktop, and on the console there is nothing else to capture.
        try requireDesktopSession("take a screenshot")
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
        // "Input received" — logged before any refusal, so the log carries what
        // was asked for as well as what happened to it. The three lines this
        // path emits (received here, posted in `InputSynthesizer`, result at the
        // bottom) exist because "my click did nothing" and "my click never
        // arrived" are different reports, and only the log can separate them
        // after the fact.
        let requested = params["actions"]?.arrayValue ?? []
        let requestedKinds = requested.compactMap { $0["type"]?.stringValue }.joined(separator: ",")
        Log.input.info("input received: \(requested.count) action(s) [\(requestedKinds)] in '\(self.context.spaceName)' as uid \(self.context.uid)")

        // (1) Session safety, first and unconditionally.
        try requireDesktopSession("inject input")
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

        // (1b) Desktop readiness — the ordering rule's third step
        // (*Session → Desktop Ready → Capture → Input*). The checks above ask
        // whether posting would land on a *person*; this one asks whether there
        // is a desktop to land on at all. A session whose Dock and Finder are
        // not up is a bare window server, which is the state behind the report
        // 「输入失败 / no app is frontmost」: the refusal now names the missing
        // part instead of letting the events disappear. Re-read on every call,
        // so a session that finishes coming up becomes usable without a worker
        // restart.
        let readiness = context.desktopReadiness()
        if let refusal = DesktopReadinessCheck.refusal(readiness, spaceName: context.spaceName) {
            Log.input.error("refused input: \(readiness.summary)")
            throw refusal
        }

        guard inputLease.automationAllowed() else {
            throw AgentSpaceError(
                code: .inputBusyByHuman,
                message: String(format: "Fusion input is owned by a person for another %.1f seconds.", inputLease.remaining()))
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

        // (5) Keyboard events need a responder. Pointer events do not: the window
        // server hit-tests them by point, so a click on the Dock lands on the Dock
        // even when this session has no window open — measured by posting exactly
        // such a click into a session with zero layer-0 windows, which launched the
        // app whose tile it hit (`tests/probes/DockClickProbe.swift`). Refusing
        // pointer actions here did not prevent a silent no-op; it *was* one, and it
        // was unescapable, because that first Dock click is how a window gets open.
        let needsResponder = actions.contains { $0.needsResponder }
        if needsResponder {
            let frontmost = AppControl.frontmostPID()
            if frontmost == nil || frontmost == getpid() {
                throw AgentSpaceError(
                    code: .noInputTarget,
                    message: "no app window is open in the '\(context.spaceName)' session, so there is nothing to type into. Pointer input still works — click an app in the Dock to open a window.")
            }
        }

        // (6) Perform, in order. Nothing above this line has a side effect.
        var performed = 0
        var channels: [JSONValue] = []
        for action in actions {
            do {
                channels.append(.string(try InputSynthesizer.perform(action).rawValue))
            } catch let error as AgentSpaceError {
                throw AgentSpaceError(
                    code: error.code,
                    message: "after \(performed) action(s): \(error.message)",
                    recoverable: error.recoverable)
            }
            performed += 1
        }
        let channelNames = channels.compactMap { $0.stringValue }.joined(separator: ",")
        Log.input.info("input result: performed \(performed) action(s), channels [\(channelNames)] in '\(self.context.spaceName)'")
        // `performed` counts, in order, what each action actually did. A scroll
        // that named a point and reached no scroll area comes back as
        // `scrolledViaWheel`, which is the honest answer in a session that is not
        // on the console: the event was posted, and no app will see it (§315). A
        // count alone cannot say that, and the caller that cannot tell has no way
        // to learn that "it worked" and "it moved nothing" were the same word.
        return .obj(["performed": .int(performed), "channels": .array(channels)])
    }

    // MARK: - apps

    func apps() throws -> JSONValue {
        // On the console this would enumerate the USER's running apps.
        try requireDesktopSession("list apps")
        let list = AppControl.runningApps()
        return .obj([
            "count": .int(list.count),
            "apps": .array(list.map(\.json)),
        ])
    }

    /// Every application *installed* in this session — the list a Fusion app
    /// picker needs before anything has been launched, as opposed to the running
    /// list `apps` answers.
    ///
    /// The session gate is the same one `launch` uses and for the same reason:
    /// on the console these are the user's applications, and this is the reply a
    /// client would use to decide what to put in front of them.
    func appsAvailable(params: JSONValue) throws -> JSONValue {
        try requireDesktopSession("list the applications installed in the session")
        return ApplicationService.available(
            query: params["query"]?.stringValue,
            limit: params["limit"]?.intValue ?? ApplicationCatalog.defaultLimit,
            icons: params["icons"]?.boolValue ?? true,
            includingAgents: params["all"]?.boolValue ?? false)
    }

    func launch(params: JSONValue) throws -> JSONValue {
        // Launching from the console would open windows on the user's desktop.
        try requireDesktopSession("launch an application")
        guard let reference = params["app"]?.stringValue, !reference.isEmpty else {
            throw AgentSpaceError(code: .badRequest, message: #"launch requires a non-empty "app" string"#)
        }
        let timeout = Double(params["timeoutSeconds"]?.intValue ?? 30)
        let app = try AppControl.launch(reference, timeout: max(1, min(timeout, 300)))
        return app.json
    }

    /// Open a fixed privacy pane in this worker's Aqua session. This is a
    /// setup-only convenience: it does not inspect the desktop or synthesize
    /// input, so it remains available while the user is looking at this
    /// account's console session during first-time permission setup. The closed
    /// `SystemSettingsPane` enum is the URL allow-list.
    func openSystemSettings(params: JSONValue) throws -> JSONValue {
        guard let raw = params["pane"]?.stringValue,
              let pane = SystemSettingsPane(rawValue: raw),
              let url = URL(string: pane.urlString) else {
            throw AgentSpaceError(
                code: .badRequest,
                message: #"systemSettings.open requires pane "accessibility", "screenRecording" or "fullDiskAccess""#)
        }

        // A preflight check only tells us that TCC is currently denied; it does
        // not create the process's entry in the target user's privacy list and
        // it never shows a prompt. This method is reached only from the user's
        // explicit authorization button, so ask macOS to register the worker
        // before opening the corresponding pane. The settings window remains
        // the source of truth and the user still makes the final decision.
        switch pane {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        case .fullDiskAccess:
            // No prompt for this grant, so registration is the whole job: the
            // denied read is what puts agentspace-worker in the list the panel
            // below then shows.
            FilePrivacy.registerForFullDiskAccess(home: context.home)
        }
        guard NSWorkspace.shared.open(url) else {
            throw AgentSpaceError(
                code: .internalError,
                message: "System Settings did not accept the \(raw) privacy-pane URL in the AgentSpace session.")
        }
        return .obj([
            "pane": .string(pane.rawValue),
            "url": .string(pane.urlString),
        ])
    }

    func quit(params: JSONValue, force: Bool) throws -> JSONValue {
        try requireDesktopSession(force ? "force-quit an application" : "quit an application")
        guard let reference = params["app"]?.stringValue, !reference.isEmpty else {
            throw AgentSpaceError(code: .badRequest, message: #"quit requires a non-empty "app" string"#)
        }
        return try AppControl.quit(reference, force: force).json
    }

    func activate(params: JSONValue) throws -> JSONValue {
        try requireDesktopSession("activate an application")
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
            // Confinement is only enforced when the agent declared roots. When it
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
        // The AX tree is desktop content — window titles, focused elements,
        // button labels — and on the console all of it belongs to the user.
        try requireDesktopSession("read the accessibility tree")
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
        try requireDesktopSession("read the frontmost application")
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
        try requireDesktopSession("read the window list")
        try AccessibilityBridge.requireTrust()
        guard let pid = targetPid(params) else {
            throw AgentSpaceError(
                code: .noInputTarget,
                message: "no pid given and no app is frontmost in this AgentSpace.")
        }
        return AccessibilityBridge.windows(pid: pid)
    }

    /// Plan §18's `ax.elementAt`: what is under this point? The agent's usual
    /// loop is screenshot → pick a spot → ask what element lives there, before
    /// deciding to click or to reach it through an action instead of geometry.
    func axElementAt(params: JSONValue) throws -> JSONValue {
        try requireDesktopSession("read the element under a point")
        try AccessibilityBridge.requireTrust()
        guard let x = params["x"]?.doubleValue, let y = params["y"]?.doubleValue else {
            throw AgentSpaceError(
                code: .invalidCoordinate,
                message: #"ax.elementAt needs "x" and "y", in points, of the location to inspect."#)
        }
        if let problem = CoordinateRules.validate(x: x, y: y, geometry: nil) {
            throw problem
        }
        let (element, pid) = try AccessibilityBridge.elementAt(x: Float(x), y: Float(y))
        var object: [String: JSONValue] = [
            "pid": .int(Int(pid)),
            "point": .obj(["x": .double(x), "y": .double(y)]),
            "element": AccessibilityBridge.describe(element, depth: 0),
        ]
        if let app = NSRunningApplication(processIdentifier: pid) {
            object["appName"] = .string(app.localizedName ?? "unknown")
            if let bundleID = app.bundleIdentifier { object["bundleId"] = .string(bundleID) }
        }
        return .object(object)
    }

    func axPerform(params: JSONValue) throws -> JSONValue {
        try requireDesktopSession("perform an accessibility action")
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

    // MARK: - preview (§52)

    func previewStart(params: JSONValue) throws -> JSONValue {
        // Same fail-closed posture as observation elsewhere: a console-session
        // worker has no background desktop to preview — the only framebuffer is
        // the user's, and §54 forbids shipping that to anyone.
        try requireDesktopSession("run the live preview")
        guard ScreenCapture.permissionGranted() else {
            throw AgentSpaceError(
                code: .screenRecordingDenied,
                message: "Screen Recording is not granted to agentspace-worker in this session.")
        }
        let requested = params["maxFPS"]?.intValue ?? 5
        let fps = try preview.start(maxFPS: requested)
        return .obj(["streaming": .bool(true), "fps": .int(fps)])
    }

    func previewFrame() throws -> JSONValue {
        // A failed start leaves no stream to inspect. Preserve the stable
        // PREVIEW_NOT_RUNNING contract for that case; only an already-running
        // stream should be re-checked for a session transition below.
        guard preview.isRunning else {
            throw AgentSpaceError(code: .previewNotRunning, message: "no preview stream is running for this agent.")
        }
        guard let data = try preview.frame(sessionVerdict: context.sessionVerdict()) else {
            // A running stream may have stopped itself after going idle.
            throw AgentSpaceError(code: .previewNotRunning, message: "the preview stream went idle and stopped itself; call preview.start again.")
        }
        return .obj(["inline": .string(data.base64EncodedString())])
    }

    func previewStop() throws -> JSONValue {
        preview.stop()
        return .obj(["streaming": .bool(false)])
    }

    // MARK: - Binary frame engine

    func frameOpen(params: JSONValue) throws -> JSONValue {
        try requireDesktopSession("open a frame stream")
        guard ScreenCapture.permissionGranted() else { throw AgentSpaceError(code: .screenRecordingDenied, message: "Screen Recording is not granted to agentspace-worker in this session.") }
        guard let targetValue = params["target"] else { throw AgentSpaceError(code: .badRequest, message: "frame.open requires a target") }
        let target = try CaptureTarget(jsonValue: targetValue)
        if case .window(let identity) = target { _ = try windowCatalog.window(matching: identity) }
        let preference = FramePreference(rawValue: params["preferredMode"]?.stringValue ?? "auto") ?? .auto
        let config = FrameOpenConfiguration(target: target, maxFPS: max(1, min(60, params["maxFPS"]?.intValue ?? 15)), targetPixelWidth: max(0, params["targetPixelWidth"]?.intValue ?? 0), targetPixelHeight: max(0, params["targetPixelHeight"]?.intValue ?? 0), preferredMode: preference)
        let publisher = try frames.open(config)
        return .obj([
            "streamID": .string(publisher.streamID.uuidString),
            "frameSocketPath": .string(context.paths.frameSocketPath),
            "surfaceGeneration": .int(1),
            "actualFPS": .int(config.maxFPS),
            "availableModes": .array([.string("sharedBGRA"), .string("h264")]),
            "workerInstanceID": .string(frames.workerInstanceID.uuidString),
            "sessionGeneration": .int(Int(truncatingIfNeeded: frames.sessionGeneration)),
        ])
    }

    func frameClose(params: JSONValue) throws -> JSONValue {
        frames.close(try frameStreamID(params)); return .obj(["streaming": .bool(false)])
    }

    func frameConfigure(params: JSONValue) throws -> JSONValue {
        // Configuration changes currently rebuild through close/open at the UI
        // debounce boundary. Keep the additive method explicit and honest.
        _ = try frameStreamID(params)
        return .obj(["reopenRequired": .bool(true)])
    }

    func frameRequestFull(params: JSONValue) throws -> JSONValue {
        guard let publisher = frames.publisher(try frameStreamID(params)) else { throw AgentSpaceError(code: .previewNotRunning, message: "frame stream is not running") }
        publisher.shared.requestFull(); return .obj(["requested": .bool(true)])
    }

    /// Everything the worker knows about one stream, or about all of them when no
    /// stream is named.
    ///
    /// The unnamed form exists because the streams worth diagnosing are not the
    /// reader's own: a Desktop window is opened by the app, and its UUID is not
    /// discoverable from a terminal. `frameMode`, `encoderActive` and the
    /// activation counters say which path the pixels took; the drop and
    /// termination counters say what was thrown away on the way; the percentile is
    /// capture→publish, which is the only segment this process can measure end to
    /// end. Arrival→screen belongs to the viewer, and this reply does not pretend
    /// to know it.
    func frameStats(params: JSONValue) throws -> JSONValue {
        if let raw = params["streamID"]?.stringValue {
            guard let id = UUID(uuidString: raw), let publisher = frames.publisher(id) else {
                throw AgentSpaceError(code: .previewNotRunning, message: "frame stream is not running")
            }
            return frameStatsJSON(publisher.stats())
        }
        let live = frames.live()
        var reply: [String: JSONValue] = [
            "workerInstanceID": .string(frames.workerInstanceID.uuidString),
            "sessionGeneration": .int(Int(frames.sessionGeneration)),
            "openStreams": .int(live.count),
            "streams": .array(live.map { publisher in frameStatsJSON(publisher.stats(), extra: [
                "streamID": .string(publisher.streamID.uuidString),
                "target": publisher.target.jsonValue,
            ])}),
        ]
        // The case this exists for: `openStreams` is zero and no stream below
        // carries a failure, because the stream that was asked for never got far
        // enough to own one. This is the only place that answer can come from.
        if let failure = frames.recentAllocationFailure() {
            reply["recentAllocationFailure"] = Self.allocationFailureJSON(failure)
        }
        return .obj(reply)
    }

    private func frameStatsJSON(_ value: FrameStats, extra: [String: JSONValue] = [:]) -> JSONValue {
        var fields: [String: JSONValue] = [
            "workerInstanceID": .string(frames.workerInstanceID.uuidString),
            "sessionGeneration": .int(Int(frames.sessionGeneration)),
            "framesCaptured": .int(Int(value.framesCaptured)),
            "framesPublished": .int(Int(value.framesPublished)),
            "framesDropped": .int(Int(value.framesDropped)),
            "framesMerged": .int(Int(value.framesMerged)),
            "fullFrames": .int(Int(value.fullFrames)),
            "deltaFrames": .int(Int(value.deltaFrames)),
            "unacknowledgedDrops": .int(Int(value.unacknowledgedDrops)),
            "heartbeatsSent": .int(Int(value.heartbeatsSent)),
            "captureTerminations": .int(Int(value.captureTerminations)),
            "modeSwitchCount": .int(Int(value.modeSwitchCount)),
            "socketReconnects": .int(Int(value.socketReconnects)),
            "sharedBytes": .int(Int(value.sharedBytes)),
            "videoBytes": .int(Int(value.videoBytes)),
            "captureFPS": .double(value.captureFPS),
            "publishFPS": .double(value.publishFPS),
            "dirtyRatio": .double(value.dirtyRatio),
            "fullFrameRatio": .double(value.fullFrameRatio),
            "pendingDamageArea": .int(Int(value.pendingDamageArea)),
            "mappingBytes": .int(value.mappingBytes),
            "frameMode": .string(value.frameMode),
            "encoderActive": .bool(value.encoderActive),
            "videoEncoderActivations": .int(Int(value.videoEncoderActivations)),
            "videoEncoderInvalidations": .int(Int(value.videoEncoderInvalidations)),
            "videoEncoderFailures": .int(Int(value.videoEncoderFailures)),
            "captureToPublishP50": .double(value.captureToPublishP50),
            "captureToPublishP95": .double(value.captureToPublishP95),
        ]
        // Omitted rather than answered as null when nothing has failed: this
        // reply is read by a person comparing two of them, and a key that is
        // always present is a key that says nothing about the one time it matters.
        if let failure = value.allocationFailure { fields["allocationFailure"] = Self.allocationFailureJSON(failure) }
        // Also omitted while there is no capture to describe. A reader that finds
        // them can answer "what resolution is this stream at, and was it trimmed?"
        // without inverting `mappingBytes` itself — which is what §320 row 832 had
        // to do to read a 1280×543 buffer out of 5,564,544 bytes.
        if let width = value.captureWidth { fields["captureWidth"] = .int(width) }
        if let height = value.captureHeight { fields["captureHeight"] = .int(height) }
        if let capped = value.captureCapped { fields["captureCapped"] = .bool(capped) }
        for (key, field) in extra { fields[key] = field }
        return .obj(fields)
    }

    /// A shared buffer the kernel refused, as a value. Which call, which errno,
    /// and what was asked for — never the name, whose only content is random.
    static func allocationFailureJSON(_ failure: SharedFrameAllocationFailure) -> JSONValue {
        var fields: [String: JSONValue] = [
            "operation": .string(failure.operation.rawValue),
            "systemErrorCode": .int(Int(failure.systemErrorCode)),
            "systemErrorName": .string(failure.systemErrorName),
            "message": .string(failure.message),
        ]
        if failure.requestedBytes > 0 {
            fields["requestedBytes"] = .int(failure.requestedBytes)
        }
        if let attemptedNameBytes = failure.attemptedNameBytes {
            fields["attemptedNameBytes"] = .int(Int(attemptedNameBytes))
        }
        return .obj(fields)
    }

    private func frameStreamID(_ params: JSONValue) throws -> UUID {
        guard let raw = params["streamID"]?.stringValue, let id = UUID(uuidString: raw) else { throw AgentSpaceError(code: .badRequest, message: "a valid streamID is required") }
        return id
    }

    // MARK: - Fusion windows

    func windowList() throws -> JSONValue {
        try requireDesktopSession("list Fusion windows")
        return .array(windowCatalog.windows().map(\.jsonValue))
    }

    func windowStreamStart(params: JSONValue) throws -> JSONValue {
        try requireDesktopSession("capture a Fusion window")
        guard ScreenCapture.permissionGranted() else {
            throw AgentSpaceError(code: .screenRecordingDenied, message: "Screen Recording is not granted to agentspace-worker in this session.")
        }
        let identity = try windowIdentity(params)
        let window = try windowCatalog.window(matching: identity)
        let fps = try windowStreams.start(window: window, maxFPS: params["maxFPS"]?.intValue ?? 15)
        return .obj(["streaming": .bool(true), "fps": .int(fps)])
    }

    func windowStreamFrame(params: JSONValue) throws -> JSONValue {
        let identity = try windowIdentity(params)
        let seen = params["seenSequence"]?.intValue
        let frame = try windowStreams.pull(
            identity: identity, verdict: context.sessionVerdict(), newerThanSequence: seen)
        guard !frame.unchanged else {
            // The proxy is already showing exactly this frame. Saying so without
            // a payload is the whole point: the pull still kept the stream
            // alive, and an idle window stops costing a JPEG round trip.
            return .obj(["unchanged": .bool(true), "sequence": .int(frame.sequence)])
        }
        guard let data = frame.data else {
            throw AgentSpaceError(code: .previewNotRunning, message: "the window stream has not produced a frame yet")
        }
        return .obj([
            "inline": .string(data.base64EncodedString()),
            "sequence": .int(frame.sequence),
        ])
    }

    func windowStreamStop(params: JSONValue) throws -> JSONValue {
        windowStreams.stop(identity: try windowIdentity(params))
        return .obj(["streaming": .bool(false)])
    }

    func windowInput(params: JSONValue) throws -> JSONValue {
        try requireDesktopSession("inject Fusion input")
        // A proxy press is a `CGEvent` into that session like any other, so the
        // same ordering rule applies: no event before the desktop is up. See
        // `input(params:)` step (1b) for why this is asked per call.
        let readiness = context.desktopReadiness()
        if let refusal = DesktopReadinessCheck.refusal(readiness, spaceName: context.spaceName) {
            Log.input.error("refused Fusion input: \(readiness.summary)")
            throw refusal
        }
        guard AccessibilityBridge.trusted() else {
            throw AgentSpaceError(code: .accessibilityDenied, message: "Accessibility is not granted to agentspace-worker in this session.")
        }
        let window = try windowCatalog.window(matching: windowIdentity(params))
        let action = try WindowInputRouter.prepare(params: params, window: window)
        if action.isHover {
            // Pointer travel is not a person taking control. Forwarding it
            // anyway would activate the agent's app and raise its window, so
            // the cursor crossing a proxy in the main session would change
            // which app the agent is working in — the opposite of isolation.
            // It is only meaningful while a human already holds the lease,
            // i.e. mid-gesture inside this very proxy.
            guard inputLease.deliversHover() else {
                return .obj(["performed": .int(0), "skipped": .string("hover")])
            }
            return .obj(["performed": .int(1), "channel": .string(try WindowInputRouter.perform(action).rawValue)])
        }
        try WindowInputRouter.activate(window: window)
        inputLease.claimHuman()
        // The channel rides along here too, so a proxy can tell a scroll that
        // moved its document from one that only posted an event — the same
        // distinction `input` reports, for the same reason.
        return .obj(["performed": .int(1), "channel": .string(try WindowInputRouter.perform(action).rawValue)])
    }

    /// Claim the human lease for a proxy the person is pressing inside.
    ///
    /// Deliberately not an input path: it activates nothing and posts nothing.
    /// A press must be able to pause automation before the gesture it starts is
    /// complete, and completing a gesture must not depend on this call
    /// succeeding — `window.input` claims the lease again on its own.
    func windowHumanClaim(params: JSONValue) throws -> JSONValue {
        try requireDesktopSession("take control of a Fusion window")
        // Resolving the identity is what makes a claim expire with its window:
        // a proxy whose remote window is gone can no longer hold the lease.
        _ = try windowCatalog.window(matching: windowIdentity(params))
        inputLease.claimHuman()
        return .obj(["claimed": .bool(true), "remainingSeconds": .double(inputLease.remaining())])
    }

    func windowActivate(params: JSONValue) throws -> JSONValue {
        try requireDesktopSession("activate a Fusion window")
        let window = try windowCatalog.window(matching: windowIdentity(params))
        let info = try AppControl.activate(String(window.pid)).json
        // App-level activation leaves whichever window the app last focused on
        // top; a Fusion proxy is about one window, so raise that one too.
        try WindowActions.raise(window: window)
        return info
    }

    func windowAction(params: JSONValue, action: WindowActions.Action) throws -> JSONValue {
        try requireDesktopSession("change a Fusion window")
        let window = try windowCatalog.window(matching: windowIdentity(params))
        try WindowActions.perform(action, window: window)
        return .obj(["performed": .bool(true)])
    }

    func windowSetFrame(params: JSONValue) throws -> JSONValue {
        try requireDesktopSession("resize a Fusion window")
        let window = try windowCatalog.window(matching: windowIdentity(params))
        guard let value = params["frame"],
              let x = value["x"]?.doubleValue, let y = value["y"]?.doubleValue,
              let width = value["width"]?.doubleValue, width > 40,
              let height = value["height"]?.doubleValue, height > 40 else {
            throw AgentSpaceError(code: .badRequest, message: "window.setFrame requires a frame with x, y, width and height")
        }
        try WindowActions.setFrame(
            CGRectValue(x: x, y: y, width: width, height: height), window: window)
        return .obj(["performed": .bool(true)])
    }

    private func windowIdentity(_ params: JSONValue) throws -> WindowIdentity {
        guard let rawID = params["windowId"]?.intValue,
              let rawPID = params["pid"]?.intValue,
              let rawGeneration = params["generation"]?.intValue,
              let windowID = UInt32(exactly: rawID),
              let pid = Int32(exactly: rawPID),
              let generation = UInt64(exactly: rawGeneration) else {
            throw AgentSpaceError(code: .badRequest, message: "window request requires windowId, pid and generation")
        }
        return WindowIdentity(pid: pid, windowID: windowID, generation: generation)
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
/// Deliberately not "allocated" numbers: an agent is not a VM, so the honest
/// figure is what its processes are really using (plan §30).
enum Resources {
    struct Sample {
        var cpuPercent: Double
        var memoryBytes: UInt64
        var processCount: Int
        /// Allocated bytes under the agent's home, or `nil` when it was not
        /// measured. `nil` rather than `0`, because "we did not look" and "it is
        /// empty" are different claims and only one of them is honest (plan §30
        /// asks for Disk, but a zero would be read as a measured zero).
        var diskBytes: UInt64?
        /// True when the walk hit its budget and `diskBytes` is a lower bound.
        var diskTruncated = false
        /// True when macOS-protected folders were left out because this process
        /// has no Full Disk Access. Without this flag the number reads as "this
        /// account owns little disk" exactly when it owns the most.
        var diskExcludesProtected = false

        var json: JSONValue {
            var object: [String: JSONValue] = [
                "cpuPercent": .double(cpuPercent),
                "memoryBytes": .int(Int(memoryBytes)),
                "processCount": .int(processCount),
            ]
            object["diskBytes"] = diskBytes.map { .int(Int($0)) } ?? .null
            if diskTruncated { object["diskTruncated"] = .bool(true) }
            if diskExcludesProtected { object["diskExcludesProtected"] = .bool(true) }
            return .obj(object)
        }
    }

    /// One `ps` invocation, filtered to the uid. Called at most every couple of
    /// seconds by the UI, so the fork cost is acceptable and avoids the
    /// private-API surface of `proc_pidinfo` across a `libproc` boundary.
    static func sample(
        uid: uid_t,
        includeDisk: Bool = false,
        home: String? = nil,
        fileAccess: Bool = false
    ) -> Sample {
        var sample = Sample(cpuPercent: 0, memoryBytes: 0, processCount: 0)
        if let output = runPS() {
            // Parsing lives in Core (ResourcesParsing) so tests can pin the
            // contract without forking /bin/ps.
            let totals = ResourcesParsing.accumulate(output, uid: uid)
            sample.processCount = totals.processCount
            sample.memoryBytes = totals.memoryBytes
            sample.cpuPercent = totals.cpuPercent
        }
        if includeDisk, let home {
            // Protected folders stay out of the walk until the grant exists: a
            // metric that reads `Documents` spends a privacy decision the user
            // never agreed to spend, and in a background session the resulting
            // dialog has nobody to answer it.
            let measured = DiskUsage.allocatedBytes(
                under: home,
                skip: fileAccess ? [] : Set(FilePrivacy.protectedSubpaths))
            sample.diskBytes = measured.bytes
            sample.diskTruncated = measured.truncated
            sample.diskExcludesProtected = measured.skippedProtected
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
