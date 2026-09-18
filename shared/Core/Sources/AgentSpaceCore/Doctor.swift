import Foundation
import CoreGraphics
import ApplicationServices

/// `agentspace doctor` — plan §38.
///
/// Every failing check must come with a concrete fix. A doctor that says "✗" and
/// stops has moved the problem, not solved it.
public enum Doctor {

    public enum Status: String {
        case pass
        case warn
        case fail
        case skip
    }

    public struct Check {
        public var name: String
        public var status: Status
        public var detail: String
        public var fix: String?

        public init(name: String, status: Status, detail: String, fix: String? = nil) {
            self.name = name
            self.status = status
            self.detail = detail
            self.fix = fix
        }

        public var symbol: String {
            switch status {
            case .pass: return "✓"
            case .warn: return "!"
            case .fail: return "✗"
            case .skip: return "–"
            }
        }
    }

    public struct Report {
        public var checks: [Check]

        public init(checks: [Check]) { self.checks = checks }

        public var failed: Int { checks.filter { $0.status == .fail }.count }
        public var warned: Int { checks.filter { $0.status == .warn }.count }
        public var ok: Bool { failed == 0 }

        public var json: JSONValue {
            .obj([
                "ok": .bool(ok),
                "failed": .int(failed),
                "warned": .int(warned),
                "checks": .array(checks.map { check in
                    var object: [String: JSONValue] = [
                        "name": .string(check.name),
                        "status": .string(check.status.rawValue),
                        "detail": .string(check.detail),
                    ]
                    if let fix = check.fix { object["fix"] = .string(fix) }
                    return .object(object)
                }),
            ])
        }

        /// Human output. Secrets are never part of a check, so no redaction is
        /// needed here — but `detail` strings are still funnelled through
        /// `Redaction` on the way out, in case a future check embeds a path that
        /// contains something sensitive.
        public func render() -> String {
            var lines: [String] = []
            for check in checks {
                lines.append("\(check.symbol) \(check.name)")
                if check.status != .pass {
                    lines.append("    \(Redaction.scrubString(check.detail))")
                    if let fix = check.fix {
                        lines.append("    → \(fix)")
                    }
                }
            }
            lines.append("")
            if ok {
                lines.append(warned == 0
                    ? "All checks passed."
                    : "\(checks.count) checks, \(warned) warning(s). AgentSpace can run.")
            } else {
                lines.append("\(checks.count) checks, \(failed) failure(s), \(warned) warning(s).")
            }
            return lines.joined(separator: "\n")
        }
    }

    public static func run(root: String? = nil) -> Report {
        var checks: [Check] = []

        // 1. Apple Silicon. Plan §3: v1 is arm64 only.
        var machine = "unknown"
        var size = 0
        if sysctlbyname("hw.machine", nil, &size, nil, 0) == 0 {
            var buffer = [CChar](repeating: 0, count: max(size, 1))
            if sysctlbyname("hw.machine", &buffer, &size, nil, 0) == 0 {
                machine = String(cString: buffer)
            }
        }
        checks.append(Check(
            name: "Apple Silicon",
            status: machine == "arm64" ? .pass : .fail,
            detail: "hw.machine = \(machine)",
            fix: machine == "arm64"
                ? nil
                : "AgentSpace v1 supports Apple Silicon only. Intel Macs are out of scope."))

        // 2. macOS version. Plan §3: 26+.
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        checks.append(Check(
            name: "macOS \(versionString)",
            status: version.majorVersion >= 26 ? .pass : .fail,
            detail: "AgentSpace v1 requires macOS 26 or later; this is \(versionString).",
            fix: version.majorVersion >= 26 ? nil : "Upgrade to macOS 26 or later."))

        // 3. Current session safety. This is the one the CLI can answer about
        // itself, and it is the same verdict the worker computes.
        let verdict = SessionGuard.currentVerdict()
        switch verdict {
        case .usable:
            checks.append(Check(
                name: "Input isolated",
                status: .pass,
                detail: "this process is in a background Aqua session; input can be posted without reaching the console."))
        case .isConsole:
            checks.append(Check(
                name: "Input isolated",
                status: .warn,
                detail: "this process's session is the physical console. That is correct for the AgentSpace app and CLI — they never post input — but a worker running here would refuse every input call.",
                fix: "If this is an AgentSpace worker session, fast-user-switch back to your own account. Input resumes automatically."))
        case .indeterminate:
            checks.append(Check(
                name: "Input isolated",
                status: .warn,
                detail: "CGSessionCopyCurrentDictionary did not answer, so the console state is unknown. AgentSpace fails closed: input would be refused.",
                fix: "Re-run from a normal GUI login. If this persists, capture `agentspace doctor --json` in a bug report."))
        case .noWindowServer:
            checks.append(Check(
                name: "Input isolated",
                status: .warn,
                detail: "this session has no window server (SessionGetInfo reports sessionHasGraphicAccess = false).",
                fix: "Run from a GUI login, not ssh."))
        }

        // 4. Window server availability, reported separately because it is the
        // single fact that decides whether a worker can do anything at all.
        let graphicAccess = SystemSessionInfo().hasGraphicAccess()
        checks.append(Check(
            name: "WindowServer",
            status: graphicAccess == true ? .pass : .fail,
            detail: "SessionGetInfo sessionHasGraphicAccess = \(graphicAccess.map(String.init) ?? "unknown")",
            fix: graphicAccess == true ? nil : "The session needs a real GUI login."))

        // 5. Display geometry — and the scale trap that this project has already
        // been bitten by, asserted rather than assumed.
        let geometry = SessionProbeGeometry.current()
        let pixelsWide = CGDisplayPixelsWide(CGMainDisplayID())
        let consistent = geometry.scale <= 1 || pixelsWide == geometry.width
        checks.append(Check(
            name: "Display geometry",
            status: consistent ? .pass : .warn,
            detail: "\(geometry.width)x\(geometry.height) points, \(geometry.pixelWidth)x\(geometry.pixelHeight) pixels, scale \(geometry.scale), CGDisplayPixelsWide = \(pixelsWide)",
            fix: consistent ? nil : "CGDisplayPixelsWide disagrees with the display mode; AgentSpace uses the display mode (verified correct). Report this as a bug."))

        // 6. Privileged helper. Plan §7: SMAppService registers a LaunchDaemon.
        checks.append(helperCheck())

        // 7. Fast User Switching. Plan §10: the whole approach depends on it.
        checks.append(fastUserSwitchingCheck())

        // 8. Spaces and their workers.
        let resolvedRoot = root ?? AgentSpaceEnvironment.rootOverride ?? RuntimePaths.root
        let registry = SpaceRegistry.load(root: resolvedRoot)
        if registry.spaces.isEmpty {
            checks.append(Check(
                name: "AgentSpaces",
                status: .warn,
                detail: "no Spaces are registered yet.",
                fix: "Create one with the AgentSpace app. Creating a Space needs the privileged helper, because it makes a macOS user."))
        } else {
            checks.append(Check(
                name: "AgentSpaces",
                status: .pass,
                detail: "\(registry.spaces.count) registered: \(registry.spaces.map(\.name).joined(separator: ", "))"))
            for space in registry.spaces {
                checks.append(workerCheck(for: space))
            }
        }

        // 9. Unix socket path budget. Plan §20 puts the socket under a long
        // path; `sun_path` silently truncates past 103 bytes, which would
        // produce a socket nobody can find.
        let samplePath = AgentSpaceEnvironment.paths(spaceID: UUID()).socketPath
        checks.append(Check(
            name: "Unix socket path",
            status: RuntimePaths.socketPathFits(samplePath) ? .pass : .fail,
            detail: "\(samplePath) is \(samplePath.utf8.count) of \(RuntimePaths.maxSocketPathBytes) bytes",
            fix: RuntimePaths.socketPathFits(samplePath) ? nil : "Shorten AGENTSPACE_ROOT."))

        // 10. Workspace confinement, per Space.
        for space in registry.spaces {
            let paths = AgentSpaceEnvironment.paths(spaceID: space.id)
            let record = paths.directory + "/space.json"
            let confined = FileManager.default.fileExists(atPath: record)
            checks.append(Check(
                name: "Workspace confinement (\(space.name))",
                status: confined ? .pass : .warn,
                detail: confined
                    ? "space.json declares allowedRoots; exec cwd and screenshot output are confined to them."
                    : "no space.json, so the worker does not confine exec cwd to a workspace. This is expected before phase 7.",
                fix: confined ? nil : "Phase 7 adds the workspace editor that writes space.json."))
        }

        // 11. CLI's own TCC view, flagged as advisory because TCC attributes a
        // grant to the *responsible* process, which for a CLI is the terminal.
        let ownAX = AXIsProcessTrusted()
        let ownSR = CGPreflightScreenCaptureAccess()
        checks.append(Check(
            name: "This process's TCC grants (advisory)",
            status: .pass,
            detail: "Accessibility = \(ownAX), Screen Recording = \(ownSR). TCC attributes grants to the responsible process, so for a CLI this reflects your terminal, not the worker.",
            fix: nil))

        return Report(checks: checks)
    }

    private static func workerCheck(for space: AgentSpace) -> Check {
        let paths = AgentSpaceEnvironment.paths(spaceID: space.id)
        guard FileManager.default.fileExists(atPath: paths.socketPath) else {
            return Check(
                name: "Worker (\(space.name))",
                status: .warn,
                detail: "no socket at \(paths.socketPath) — the worker is not running.",
                fix: "The AgentSpace user must be logged in through the GUI once. After that, `agentspace start \(space.name)`.")
        }
        // Ask the worker rather than guessing from the pid file.
        do {
            let client = WorkerClient(socketPath: paths.socketPath)
            let response = try client.call(method: Method.hello, token: nil, timeout: 5)
            guard response.ok, let session = response.result?["session"] else {
                let message = response.error?.message ?? "worker answered without a session block"
                return Check(
                    name: "Worker (\(space.name))",
                    status: .fail,
                    detail: message,
                    fix: "Restart the worker in the AgentSpace session: `agentspace restart \(space.name)`.")
            }
            let permits = session["permitsInput"]?.boolValue ?? false
            let onConsole = session["onConsole"]?.boolValue ?? true
            return Check(
                name: "Worker (\(space.name))",
                status: permits ? .pass : .warn,
                detail: permits
                    ? "running, uid \(response.result?["user"]?["uid"]?.intValue ?? -1), input permitted."
                    : "running but refusing input (onConsole = \(onConsole)).",
                fix: permits ? nil : "Switch away from the AgentSpace desktop in the fast-user-switching menu; it is currently on the console.")
        } catch {
            return Check(
                name: "Worker (\(space.name))",
                status: .fail,
                detail: "socket exists but the worker did not answer: \(error)",
                fix: "Remove the stale socket and restart: `agentspace restart \(space.name)`. If it keeps happening, check \(paths.workerLogPath).")
        }
    }

    /// Fast User Switching, read from the login window's own preference file.
    /// The privileged helper, asked the way the app asks.
    ///
    /// This used to test for `/Library/LaunchDaemons/<id>.plist`, which is where a
    /// *SMJobBless* helper goes. AgentSpace uses `SMAppService` (plan §7), whose
    /// LaunchDaemon lives **inside the app bundle** and is registered by launchd
    /// from there; nothing is ever written to `/Library/LaunchDaemons`. The old
    /// check therefore warned forever, including on a machine where the helper was
    /// working perfectly — and a check that cannot pass teaches people to ignore
    /// warnings.
    ///
    /// `HelperInstallation` resolves the bundle that actually contains this
    /// executable, so the app and the CLI (which lives in `Contents/Helpers`) give
    /// the same answer, and then asks the question that cannot be wrong: does it
    /// answer?
    static func helperCheck() -> Check {
        let state = HelperInstallation.inspect()
        if state.isReachable {
            return Check(
                name: "Privileged helper",
                status: .pass,
                detail: "installed, registered and answering (\(state.summary)).",
                fix: nil)
        }
        return Check(
            name: "Privileged helper",
            status: .warn,
            detail: "not available: \(state.summary). Creating and deleting Spaces needs it; driving an existing Space does not.",
            fix: state.fix)
    }

    private static func fastUserSwitchingCheck() -> Check {
        let path = "/Library/Preferences/.GlobalPreferences.plist"
        guard let dictionary = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            return Check(
                name: "Fast User Switching",
                status: .warn,
                detail: "could not read \(path).",
                fix: "Enable it manually: System Settings → Control Center → Fast User Switching → Show in Menu Bar.")
        }
        // `MultipleSessionEnabled` is what actually permits a second concurrent
        // GUI session; the menu-extra key only controls whether the menu shows.
        let enabled = (dictionary["MultipleSessionEnabled"] as? NSNumber)?.boolValue
        return Check(
            name: "Fast User Switching",
            status: enabled == true ? .pass : .warn,
            detail: "MultipleSessionEnabled = \(enabled.map(String.init) ?? "unset")",
            fix: enabled == true
                ? nil
                : "System Settings → Control Center → Fast User Switching → Show in Menu Bar. Without it there is no way to give an AgentSpace its own GUI session.")
    }
}

/// Bundle identifiers in one place, so the namespace is configured rather than
/// scattered through the source (plan §58).
public enum BundleIdentifiers {
    public static let app = "com.agentspace.AgentSpace"
    public static let helper = "com.agentspace.AgentSpace.Helper"
    public static let worker = "com.agentspace.AgentSpace.Worker"
    public static let workerLaunchAgent = "com.agentspace.AgentSpace.Worker"
    public static let cli = "agentspace"
    public static let mcp = "@agentspace/mcp"
}

/// Display geometry for the doctor, isolated so the check is easy to read.
public enum SessionProbeGeometry {
    public static func current() -> DisplayGeometry {
        let displayID = CGMainDisplayID()
        let bounds = CGDisplayBounds(displayID)
        let mode = CGDisplayCopyDisplayMode(displayID)
        return DisplayGeometry(
            modeWidth: mode?.width ?? Int(bounds.width),
            modePixelWidth: mode?.pixelWidth ?? Int(bounds.width),
            boundsWidth: Int(bounds.width.rounded()),
            boundsHeight: Int(bounds.height.rounded()))
    }
}
