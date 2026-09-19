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
        /// Machine-readable name of the one in-app action that fixes this
        /// check, so the GUI can offer a button instead of terminal advice.
        /// The core names the action; the app supplies the behaviour.
        public var actionHint: String?

        public init(name: String, status: Status, detail: String, fix: String? = nil,
                    actionHint: String? = nil) {
            self.name = name
            self.status = status
            self.detail = detail
            self.fix = fix
            self.actionHint = actionHint
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
                    ? NSLocalizedString("All checks passed.", comment: "")
                    : String(format: NSLocalizedString("%ld checks, %ld warning(s). AgentSpace can run.", comment: ""), checks.count, warned))
            } else {
                lines.append(String(format: NSLocalizedString("%ld checks, %ld failure(s), %ld warning(s).", comment: ""), checks.count, failed, warned))
            }
            return lines.joined(separator: "\n")
        }
    }

    /// `orphanedAccounts` is the set of AgentSpace-named macOS accounts that
    /// have no Space record. `nil` means the caller could not ask the helper,
    /// and the check is omitted rather than faked as a pass.
    public static func run(root: String? = nil, orphanedAccounts: [String]? = nil) -> Report {
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
            name: NSLocalizedString("Apple Silicon", comment: ""),
            status: machine == "arm64" ? .pass : .fail,
            detail: "hw.machine = \(machine)",
            fix: machine == "arm64"
                ? nil
                : "AgentSpace v1 supports Apple Silicon only. Intel Macs are out of scope."))

        // 2. macOS version. Plan §3: 26+.
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        checks.append(Check(
            name: String(format: NSLocalizedString("macOS %@", comment: ""), versionString),
            status: version.majorVersion >= 26 ? .pass : .fail,
            detail: "AgentSpace v1 requires macOS 26 or later; this is \(versionString).",
            fix: version.majorVersion >= 26 ? nil : "Upgrade to macOS 26 or later."))

        // 3. Current session safety. This is the one the CLI can answer about
        // itself, and it is the same verdict the worker computes.
        let verdict = SessionGuard.currentVerdict()
        switch verdict {
        case .usable:
            checks.append(Check(
                name: NSLocalizedString("Input isolated", comment: ""),
                status: .pass,
                detail: "this process is in a background Aqua session; input can be posted without reaching the console."))
        case .isConsole:
            checks.append(Check(
                name: NSLocalizedString("Input isolated", comment: ""),
                status: .warn,
                detail: "this process's session is the physical console. That is correct for the AgentSpace app and CLI — they never post input — but a worker running here would refuse every input call.",
                fix: "If this is an AgentSpace worker session, fast-user-switch back to your own account. Input resumes automatically."))
        case .indeterminate:
            checks.append(Check(
                name: NSLocalizedString("Input isolated", comment: ""),
                status: .warn,
                detail: "CGSessionCopyCurrentDictionary did not answer, so the console state is unknown. AgentSpace fails closed: input would be refused.",
                fix: "Re-run from a normal GUI login. If this persists, capture `agentspace doctor --json` in a bug report."))
        case .noWindowServer:
            checks.append(Check(
                name: NSLocalizedString("Input isolated", comment: ""),
                status: .warn,
                detail: "this session has no window server (SessionGetInfo reports sessionHasGraphicAccess = false).",
                fix: "Run from a GUI login, not ssh."))
        }

        // 4. Window server availability, reported separately because it is the
        // single fact that decides whether a worker can do anything at all.
        let graphicAccess = SystemSessionInfo().hasGraphicAccess()
        checks.append(Check(
            name: NSLocalizedString("WindowServer", comment: ""),
            status: graphicAccess == true ? .pass : .fail,
            detail: "SessionGetInfo sessionHasGraphicAccess = \(graphicAccess.map(String.init) ?? "unknown")",
            fix: graphicAccess == true ? nil : "The session needs a real GUI login."))

        // 5. Display geometry — and the scale trap that this project has already
        // been bitten by, asserted rather than assumed.
        let geometry = SessionProbeGeometry.current()
        let pixelsWide = CGDisplayPixelsWide(CGMainDisplayID())
        let consistent = geometry.scale <= 1 || pixelsWide == geometry.width
        checks.append(Check(
            name: NSLocalizedString("Display geometry", comment: ""),
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

        // A quarantined registry means the index failed to decode at some
        // point: every Space "disappeared" once, and the evidence of what was
        // there sits in a quarantine file. Diagnosed here, not discovered by a
        // user asking where their Spaces went.
        let corrupt = SpaceRegistry.corruptRegistryFiles(root: resolvedRoot)
        if !corrupt.isEmpty {
            checks.append(Check(
                name: NSLocalizedString("Registry integrity", comment: ""),
                status: .fail,
                detail: "the Space registry failed to decode \(corrupt.count) time(s); it was quarantined, not discarded: \(corrupt.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))",
                fix: "Inspect the quarantined file(s) under \(resolvedRoot)/Spaces/ — they hold the pre-corruption bytes. Recover Spaces by hand into a fresh index.json or recreate them; delete the quarantine files when done."))
        }

        if registry.spaces.isEmpty {
            checks.append(Check(
                name: NSLocalizedString("AgentSpaces", comment: ""),
                status: .warn,
                detail: "no Spaces are registered yet.",
                fix: "Create one with the AgentSpace app. Creating a Space needs the privileged helper, because it makes a macOS user."))
        } else {
            checks.append(Check(
                name: NSLocalizedString("AgentSpaces", comment: ""),
                status: .pass,
                detail: "\(registry.spaces.count) registered: \(registry.spaces.map(\.name).joined(separator: ", "))"))
            for space in registry.spaces {
                checks.append(contentsOf: workerChecks(for: space, root: resolvedRoot))
            }
        }

        // 9. Unix socket path budget. Plan §20 puts the socket under a long
        // path; `sun_path` silently truncates past 103 bytes, which would
        // produce a socket nobody can find.
        let samplePath = AgentSpaceEnvironment.paths(spaceID: UUID()).socketPath
        checks.append(Check(
            name: NSLocalizedString("Unix socket path", comment: ""),
            status: RuntimePaths.socketPathFits(samplePath) ? .pass : .fail,
            detail: "\(samplePath) is \(samplePath.utf8.count) of \(RuntimePaths.maxSocketPathBytes) bytes",
            fix: RuntimePaths.socketPathFits(samplePath) ? nil : "Shorten AGENTSPACE_ROOT."))

        // 10. Workspace confinement, per Space.
        for space in registry.spaces {
            let paths = AgentSpaceEnvironment.paths(spaceID: space.id)
            let record = paths.directory + "/space.json"
            let confined = FileManager.default.fileExists(atPath: record)
            checks.append(Check(
                name: String(format: NSLocalizedString("Workspace confinement (%@)", comment: ""), space.name),
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
            name: NSLocalizedString("This process's TCC grants (advisory)", comment: ""),
            status: .pass,
            detail: "Accessibility = \(ownAX), Screen Recording = \(ownSR). TCC attributes grants to the responsible process, so for a CLI this reflects your terminal, not the worker.",
            fix: nil))

        // 12. Orphaned accounts: AgentSpace-named macOS users with no Space
        // record. Reality check: the first real create hit a macOS 26 removed
        // tool, the helper's own cleanup reported success without removing the
        // dslocal record, and the result was an account the app could neither
        // list nor delete. This check makes that state visible, and the app
        // turns it into a button.
        if let orphans = orphanedAccounts {
            if orphans.isEmpty {
                checks.append(Check(
                    name: NSLocalizedString("Orphaned accounts", comment: ""),
                    status: .pass,
                    detail: "Every AgentSpace-named account on this Mac belongs to a Space in the registry.",
                    fix: nil))
            } else {
                checks.append(Check(
                    name: NSLocalizedString("Orphaned accounts", comment: ""),
                    status: .fail,
                    detail: String(
                        format: NSLocalizedString("AgentSpace-named accounts with no Space record, left behind by an interrupted creation: %@.", comment: ""),
                        orphans.joined(separator: ", ")),
                    fix: NSLocalizedString("Use Delete Orphaned Accounts — the helper removes the named accounts and their homes. Nothing else on this Mac is touched.", comment: ""),
                    actionHint: "deleteOrphans"))
            }
        }

        return Report(checks: checks)
    }

    /// Per-Space checks: the worker itself plus the two TCC grants §38 wants
    /// named — asked *of the worker*, not of this console process, whose grants
    /// are a different question entirely (the advisory check above).
    private static func workerChecks(for space: AgentAccount, root resolvedRoot: String) -> [Check] {
        // The overridden root must reach *every* path this check derives: a
        // doctor run against a harness (or a non-default) root that quietly
        // looked at the default runtime would report the wrong machine.
        let paths = RuntimePaths(spaceID: space.id, root: resolvedRoot)
        guard FileManager.default.fileExists(atPath: paths.socketPath) else {
            // "No socket" has three distinct root causes with three distinct
            // fixes; name the one that actually applies instead of always
            // blaming the worker.
            if !FileManager.default.fileExists(atPath: paths.directory) {
                return [Check(
                    name: String(format: NSLocalizedString("Worker (%@)", comment: ""), space.name),
                    status: .warn,
                    detail: "the runtime directory \(paths.directory) does not exist — the Space was never provisioned on this machine.",
                    fix: "Create the Space again, or run the helper's prepareRuntimeDirectory for it.")]
            }
            if !FileManager.default.fileExists(atPath: paths.tokenPath) {
                return [Check(
                    name: String(format: NSLocalizedString("Worker (%@)", comment: ""), space.name),
                    status: .warn,
                    detail: "the session token is missing from \(paths.directory) — the worker has never run here, or the runtime directory was reset.",
                    fix: "Start the worker once so it mints a token: `agentspace start \(space.name)`.")]
            }
            return [Check(
                name: String(format: NSLocalizedString("Worker (%@)", comment: ""), space.name),
                status: .warn,
                detail: "no socket at \(paths.socketPath) — the worker is not running.",
                fix: "The AgentSpace user must be logged in through the GUI once. After that, `agentspace start \(space.name)`.")]
        }
        // Ask the worker rather than guessing from the pid file.
        var results: [Check] = []
        do {
            let client = WorkerClient(socketPath: paths.socketPath)
            let response = try client.call(method: Method.hello, token: nil, timeout: 5)
            guard response.ok, let session = response.result?["session"] else {
                let message = response.error?.message ?? "worker answered without a session block"
                results.append(Check(
                    name: String(format: NSLocalizedString("Worker (%@)", comment: ""), space.name),
                    status: .fail,
                    detail: message,
                    fix: "Restart the worker in the AgentSpace session: `agentspace restart \(space.name)`."))
                return results
            }
            let permits = session["permitsInput"]?.boolValue ?? false
            let onConsole = session["onConsole"]?.boolValue ?? true
            results.append(Check(
                name: String(format: NSLocalizedString("Worker (%@)", comment: ""), space.name),
                status: permits ? .pass : .warn,
                detail: permits
                    ? "running, uid \(response.result?["user"]?["uid"]?.intValue ?? -1), input permitted."
                    : "running but refusing input (onConsole = \(onConsole)).",
                fix: permits ? nil : "Switch away from the AgentSpace desktop in the fast-user-switching menu; it is currently on the console."))

            // The worker's *own* grants, via the authenticated status call. The
            // advisory TCC check earlier in this report looked at whatever
            // process ran the doctor; the grants that matter are the worker's,
            // and they are per-Space.
            if let tokenHex = TokenStore.read(from: paths.tokenPath)?.hex,
               let status = try? client.call(method: Method.status, params: .obj([:]), token: tokenHex, timeout: 5),
               status.ok, let body = status.result {
                let granted = body["accessibility"]?.boolValue ?? false
                results.append(Check(
                    name: String(format: NSLocalizedString("Accessibility (%@)", comment: ""), space.name),
                    status: granted ? .pass : .fail,
                    detail: granted ? "granted to the worker." : "not granted to the worker.",
                    fix: granted ? nil : "In the AgentSpace user's session, open System Settings → Privacy & Security → Accessibility and enable agentspace-worker. The AgentSpace Setup window appears once after the first login."))
                let recording = body["screenRecording"]?.boolValue ?? false
                results.append(Check(
                    name: String(format: NSLocalizedString("Screen Recording (%@)", comment: ""), space.name),
                    status: recording ? .pass : .fail,
                    detail: recording ? "granted to the worker." : "not granted to the worker.",
                    fix: recording ? nil : "In the AgentSpace user's session, open System Settings → Privacy & Security → Screen Recording and enable agentspace-worker."))
            }
        } catch {
            results.append(Check(
                name: String(format: NSLocalizedString("Worker (%@)", comment: ""), space.name),
                status: .fail,
                detail: "socket exists but the worker did not answer: \(error)",
                fix: "Remove the stale socket and restart: `agentspace restart \(space.name)`. If it keeps happening, check \(paths.workerErrLogPath)."))
        }
        return results
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
                name: NSLocalizedString("Privileged helper", comment: ""),
                status: .pass,
                detail: "installed, registered and answering (\(state.summary)).",
                fix: nil)
        }
        return Check(
            name: NSLocalizedString("Privileged helper", comment: ""),
            status: .warn,
            detail: "not available: \(state.summary). Creating and deleting Spaces needs it; driving an existing Space does not.",
            fix: state.fix)
    }

    private static func fastUserSwitchingCheck() -> Check {
        let path = "/Library/Preferences/.GlobalPreferences.plist"
        guard let dictionary = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            return Check(
                name: NSLocalizedString("Fast User Switching", comment: ""),
                status: .warn,
                detail: "could not read \(path).",
                fix: "Enable it manually: System Settings → Control Center → Fast User Switching → Show in Menu Bar.")
        }
        // `MultipleSessionEnabled` is what actually permits a second concurrent
        // GUI session; the menu-extra key only controls whether the menu shows.
        let enabled = (dictionary["MultipleSessionEnabled"] as? NSNumber)?.boolValue
        return Check(
            name: NSLocalizedString("Fast User Switching", comment: ""),
            status: enabled == true ? .pass : .warn,
            detail: "MultipleSessionEnabled = \(enabled.map(String.init) ?? "unset")",
            fix: enabled == true
                ? nil
                : "System Settings → Control Center → Fast User Switching → Show in Menu Bar. Without it there is no way to give an AgentSpace its own GUI session.")
    }
}

/// Bundle identifiers in one place, so the namespace is configured rather than
/// scattered through the source (plan §58). Derived names (plist file names,
/// the §37 log subsystem, mach-service and queue labels) also live here, so a
/// namespace change is one edit — and the helper's signature requirement, read
/// from these same constants, cannot silently disagree with what was signed.
public enum BundleIdentifiers {
    public static let app = "com.agentspace.AgentSpace"
    public static let helper = "com.agentspace.AgentSpace.Helper"
    public static let worker = "com.agentspace.AgentSpace.Worker"
    public static let workerLaunchAgent = "com.agentspace.AgentSpace.Worker"
    public static let cli = "agentspace"
    public static let mcp = "@agentspace/mcp"

    /// The launchd plist file name for the helper daemon (§47).
    public static let helperPlist = helper + ".plist"

    /// The OSLog subsystem every AgentSpace process logs under (§37). Deliberately
    /// *not* the app's bundle id: log filters are written and shared as this
    /// string, and changing one without the other would break every documented
    /// `log show` command.
    public static let logSubsystem = "com.agentspace.app"
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
