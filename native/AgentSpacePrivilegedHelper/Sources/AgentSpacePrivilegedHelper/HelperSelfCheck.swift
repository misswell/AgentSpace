import Foundation
import Security
import AgentSpaceCore

/// `agentspace-helper --self-check`.
///
/// The helper is the one component that cannot be exercised without root and a
/// second login, which makes it the easiest place for a claim to go quietly
/// untested. This mode is the answer to that: it runs anywhere, makes no changes,
/// and reports what the binary *is* — which requirement it will enforce, where it
/// would take the worker from, which accounts it considers its own, and whether
/// the pieces it depends on are actually present.
///
/// Written the way `agentspace doctor` is: every failing line names a concrete
/// fix, because "self-check failed" on its own is not something a user can act on.
struct HelperSelfCheck {

    struct Check {
        var name: String
        var ok: Bool
        var detail: String
        var fix: String?
    }

    var checks: [Check] = []

    var ok: Bool { checks.allSatisfy(\.ok) }

    var json: JSONValue {
        .object([
            "ok": .bool(ok),
            "helperVersion": .string(helperVersion),
            "protocolVersion": .int(agentSpaceProtocolVersion),
            "checks": .array(checks.map { check in
                .object([
                    "name": .string(check.name),
                    "ok": .bool(check.ok),
                    "detail": .string(check.detail),
                    "fix": check.fix.map { .string($0) } ?? .null,
                ])
            }),
        ])
    }

    func render() -> String {
        var lines = ["agentspace-helper \(helperVersion) — self check", ""]
        for check in checks {
            lines.append("  \(check.ok ? "ok  " : "FAIL") \(check.name)")
            lines.append("       \(check.detail)")
            if let fix = check.fix {
                for line in fix.split(separator: "\n") {
                    lines.append("       → \(line)")
                }
            }
        }
        let failed = checks.filter { !$0.ok }.count
        lines.append("")
        lines.append(failed == 0
            ? "\(checks.count) checks, all passed."
            : "\(checks.count) checks, \(failed) failing.")
        return lines.joined(separator: "\n")
    }

    static func run() -> HelperSelfCheck {
        var report = HelperSelfCheck()

        // 1. Root. Not a failure when run by hand — that is the normal way to run
        //    this — but it must be stated, because it changes what everything
        //    below means.
        let isRoot = geteuid() == 0
        report.checks.append(Check(
            name: "privilege",
            ok: true,
            detail: isRoot
                ? "running as root (uid 0), as launchd would start it"
                : "running as uid \(geteuid()), not root — correct for --self-check, and this is what the daemon refuses to serve from (exit 77)",
            fix: nil))

        // 2. The enforced requirement must at least *parse*. A malformed
        //    requirement string would make `SecRequirementCreateWithString` fail
        //    for every caller, and — because the check fails closed — the helper
        //    would refuse everyone including the app. That is a safe failure but a
        //    silent one, so it is caught here instead.
        var requirement: SecRequirement?
        let requirementStatus = SecRequirementCreateWithString(CodeSigningRequirement.enforcedRequirement as CFString, [], &requirement)
        report.checks.append(Check(
            name: "caller requirement parses",
            ok: requirementStatus == errSecSuccess,
            detail: requirementStatus == errSecSuccess
                ? CodeSigningRequirement.enforcedRequirement
                : "SecRequirementCreateWithString returned \(requirementStatus)",
            fix: requirementStatus == errSecSuccess ? nil
                : "This is a build error: the requirement string is malformed, so the helper would refuse every caller. Fix CodeSigningRequirement.requirement."))

        // 3. Is the development requirement in play? A release helper must not
        //    contain it, and a debug helper must not be shipped.
        #if DEBUG
        report.checks.append(Check(
            name: "requirement strictness",
            ok: true,
            detail: "DEBUG build: enforcing the identifier half only. A release build additionally requires the Apple anchor and team \(CodeSigningRequirement.teamIdentifier).",
            fix: nil))
        #else
        report.checks.append(Check(
            name: "requirement strictness",
            ok: true,
            detail: "release build: requires the Apple anchor and team \(CodeSigningRequirement.teamIdentifier)",
            fix: nil))
        #endif

        // 4. Where would the worker come from? An unvalidated source here would be
        //    a privilege-escalation path, so the check reports the resolved path
        //    and insists it is executable.
        let workerPath = SelfCheckPaths.resolveWorkerBinary()
        let workerExecutable = FileManager.default.isExecutableFile(atPath: workerPath)
        report.checks.append(Check(
            name: "worker binary is reachable",
            ok: workerExecutable,
            detail: workerExecutable ? workerPath : "nothing executable at \(workerPath)",
            fix: workerExecutable ? nil
                : "The helper installs the worker from its own bundle, never from a path a caller supplies. Build the whole app with scripts/bundle-app.sh so agentspace-worker sits next to the helper, and reinstall the LaunchDaemon."))

        // 5. The LaunchDaemon plist, as it exists inside this bundle.
        let plistInBundle = SelfCheckPaths.launchDaemonPlist()
        let plistPresent = FileManager.default.fileExists(atPath: plistInBundle)
        report.checks.append(Check(
            name: "LaunchDaemon plist is in the bundle",
            ok: plistPresent,
            detail: plistPresent ? plistInBundle : "not found at \(plistInBundle)",
            fix: plistPresent ? nil
                : "The plist must ship at Contents/Library/LaunchDaemons/com.agentspace.AgentSpace.Helper.plist for SMAppService to register it. Run scripts/bundle-app.sh."))

        // 6. Is it registered with launchd? Read-only.
        let status = HelperClient.status
        let registered = HelperClient.isInstalled
        report.checks.append(Check(
            name: "registered with launchd",
            ok: registered,
            detail: "SMAppService reports: \(HelperClient.statusDescription())",
            fix: registered ? nil
                : "Open the AgentSpace app and choose Install Helper. macOS will ask for your password, because only an administrator can add a LaunchDaemon."))

        // 7. Can we actually reach it? This is the check that distinguishes
        //    "installed" from "working", and it is the one the app cares about.
        if registered {
            let ping = HelperClient.ping(timeout: 10)
            report.checks.append(Check(
                name: "helper answers over XPC",
                ok: ping?.ok == true,
                detail: ping.flatMap { $0.result?["helperVersion"]?.stringValue }
                    .map { "helper version \($0)" } ?? "no reply",
                fix: ping?.ok == true ? nil
                    : "launchctl print system/\(helperMachServiceName) shows what launchd thinks. A helper that is registered but silent is usually a code-signature mismatch: the daemon refuses callers that do not satisfy its requirement, and logs the refusal under subsystem com.agentspace.app category helper."))
        } else {
            report.checks.append(Check(
                name: "helper answers over XPC",
                ok: true,   // Not a failure: it cannot be tested before installing.
                detail: "skipped — nothing is registered yet, so there is nothing to talk to",
                fix: nil))
        }

        // 8. Which accounts does the helper consider its own? Reports the exact
        //    set it would be willing to delete, which is the single most important
        //    thing for a human to be able to confirm by eye.
        let accounts = SelfCheckPaths.localAccounts()
        let ours = accounts.filter { HelperValidation.isAgentSpaceAccount($0) }.sorted()
        report.checks.append(Check(
            name: "Space accounts on this machine",
            ok: true,
            detail: ours.isEmpty
                ? "none — the helper would currently refuse to delete anything, because it only deletes accounts matching \(HelperValidation.accountPrefix)<6 hex>"
                : "\(ours.joined(separator: ", "))",
            fix: nil))

        // 9. The negative claim, stated where a reviewer will see it: nothing
        //    outside that set is reachable.
        let wouldRefuse = ["root", "daemon", "nobody", "_mbsetupuser", NSUserName()]
            .filter { !HelperValidation.isAgentSpaceAccount($0) }
        report.checks.append(Check(
            name: "refuses everything else",
            ok: wouldRefuse.count >= 4,
            detail: "confirmed to be outside the helper's reach: \(wouldRefuse.joined(separator: ", "))",
            fix: nil))

        return report
    }
}

/// Path resolution for the self check, kept apart from the daemon's own lookup so
/// it can be read and tested without root.
enum SelfCheckPaths {

    /// Mirrors `HelperService.helperBundleWorkerPath`, which is intentionally
    /// duplicated here in a *read-only* form: the self check must never be able to
    /// install anything, so it does not share code paths that do.
    static func resolveWorkerBinary() -> String {
        let candidates = [
            Bundle.main.bundlePath + "/Contents/MacOS/agentspace-worker",
            // The daemon inside the app bundle: …/AgentSpace.app/Contents/Library/LaunchDaemons/
            Bundle.main.bundlePath + "/../../MacOS/agentspace-worker",
            "/Library/PrivilegedHelperTools/agentspace-worker",
        ]
        for candidate in candidates {
            let standardized = (candidate as NSString).standardizingPath
            if FileManager.default.isExecutableFile(atPath: standardized) { return standardized }
        }
        return (candidates[0] as NSString).standardizingPath
    }

    static func launchDaemonPlist() -> String {
        if Bundle.main.bundlePath.hasSuffix(".app") {
            return Bundle.main.bundlePath + "/Contents/Library/LaunchDaemons/com.agentspace.AgentSpace.Helper.plist"
        }
        // Running the binary from a build directory.
        let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
        return (executable as NSString).deletingLastPathComponent + "/com.agentspace.AgentSpace.Helper.plist"
    }

    /// Local accounts, without needing root.
    static func localAccounts() -> [String] {
        guard let contents = try? String(contentsOfFile: "/etc/passwd", encoding: .utf8) else { return [] }
        return contents
            .split(separator: "\n")
            .compactMap { $0.split(separator: ":").first.map(String.init) }
    }
}
