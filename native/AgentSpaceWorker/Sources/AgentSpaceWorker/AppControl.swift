import Foundation
import AppKit
import CoreGraphics
import AgentSpaceCore

/// Application lifecycle inside an AgentSpace. Plan §22.
enum AppControl {

    struct AppInfo {
        var pid: pid_t
        var name: String?
        var bundleID: String?
        var path: String?
        /// `regular`, `accessory` or `prohibited`. Accessory apps are menu-bar
        /// apps (`LSUIElement`); omitting them makes every launch of such an app
        /// look like a failure, so they are reported with their policy instead.
        var policy: String
        var active: Bool

        var json: JSONValue {
            var object: [String: JSONValue] = [
                "pid": .int(Int(pid)),
                "policy": .string(policy),
                "active": .bool(active),
            ]
            if let name { object["name"] = .string(name) }
            if let bundleID { object["bundleId"] = .string(bundleID) }
            if let path { object["path"] = .string(path) }
            return .object(object)
        }
    }

    /// Every app in this session — regular **and** accessory.
    ///
    /// Read through the window server's own window list rather than
    /// `NSRunningApplication`, because this process has no run loop to service
    /// workspace notifications and `NSWorkspace`'s cache goes stale (observed
    /// reporting an app as frontmost minutes after it had been killed).
    static func runningApps() -> [AppInfo] {
        var byPID: [pid_t: AppInfo] = [:]

        // Window-server view: which pids actually own on-screen windows.
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        var windowPids: Set<pid_t> = []
        if let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            for window in list {
                if let pid = window[kCGWindowOwnerPID as String] as? pid_t {
                    windowPids.insert(pid)
                }
            }
        }

        // NSWorkspace still answers the cheap questions (name, bundle id,
        // policy). The staleness that matters is "who is frontmost", which comes
        // from the window list instead — see `frontmostPID`.
        for app in NSWorkspace.shared.runningApplications {
            let policy: String
            switch app.activationPolicy {
            case .regular: policy = "regular"
            case .accessory: policy = "accessory"
            case .prohibited: policy = "prohibited"
            @unknown default: policy = "unknown"
            }
            // Include accessory apps, and any app the window server sees even
            // if AppKit calls it prohibited.
            let visible = policy == "regular" || policy == "accessory"
                || windowPids.contains(app.processIdentifier)
            guard visible else { continue }
            byPID[app.processIdentifier] = AppInfo(
                pid: app.processIdentifier,
                name: app.localizedName,
                bundleID: app.bundleIdentifier,
                path: app.bundleURL?.path,
                policy: policy,
                active: app.isActive)
        }
        return byPID.values.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    /// The pid owning the frontmost normal window, straight from the window
    /// server. Layer 0 is the normal window layer; menus, the Dock and other
    /// chrome sit above it and are skipped.
    static func frontmostPID() -> pid_t? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for window in list {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t else { continue }
            return pid
        }
        return nil
    }

    /// Resolve a user-supplied app reference to an on-disk bundle.
    ///
    /// Accepts an absolute path to a `.app`, or a name / bundle id looked up in
    /// the standard locations. Returns `APP_NOT_FOUND` with the searched
    /// locations rather than guessing.
    static func resolve(_ reference: String) throws -> URL {
        let fm = FileManager.default

        if reference.hasPrefix("/") {
            var url = URL(fileURLWithPath: reference)
            if url.pathExtension != "app" {
                // Allow "/Applications/Safari" to mean ".../Safari.app".
                let withExtension = url.appendingPathExtension("app")
                if fm.fileExists(atPath: withExtension.path) { url = withExtension }
            }
            guard fm.fileExists(atPath: url.path) else {
                throw AgentSpaceError(
                    code: .appNotFound,
                    message: "no app at '\(reference)' in the AgentSpace session.")
            }
            return url
        }

        // A bundle identifier resolves directly.
        if reference.contains(".") , !reference.contains(" "),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: reference) {
            return url
        }

        let roots = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices",
            NSHomeDirectory() + "/Applications",
        ]
        let candidateName = reference.hasSuffix(".app") ? reference : reference + ".app"
        for root in roots {
            let candidate = root + "/" + candidateName
            if fm.fileExists(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        // Last resort: an exact-name scan of the roots, so "Google Chrome"
        // finds "Google Chrome.app" wherever it sits.
        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let bare = String(entry.dropLast(4))
                if bare.caseInsensitiveCompare(reference) == .orderedSame {
                    return URL(fileURLWithPath: root + "/" + entry)
                }
            }
        }
        throw AgentSpaceError(
            code: .appNotFound,
            message: "could not find an app named '\(reference)' in the AgentSpace session. Searched: \(roots.joined(separator: ", ")). Use `apps` to list what is running, or pass an absolute path to a .app bundle.")
    }

    /// Launch and wait for the app to *actually register*.
    ///
    /// The `open` exit code only means LaunchServices accepted the request; the
    /// process may not exist yet. Returning a pid at that moment hands the agent
    /// a number it cannot use. So this polls until a pid appears, then waits for
    /// the app to own a window (or for the grace period to expire, which is the
    /// normal case for a menu-bar app).
    static func launch(_ reference: String, timeout: TimeInterval = 30) throws -> AppInfo {
        let url = try resolve(reference)
        let before = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        // Launch into *this* session: `NSWorkspace` from a process inside the
        // Aqua session starts the app in that session.
        let semaphore = DispatchSemaphore(value: 0)
        var launchError: Error?
        var launchedApp: NSRunningApplication?

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            launchedApp = app
            launchError = error
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            throw AgentSpaceError(
                code: .appLaunchTimeout,
                message: "LaunchServices did not answer within \(Int(timeout))s for \(url.path).")
        }
        if let launchError {
            throw AgentSpaceError(
                code: .appNotFound,
                message: "could not launch \(url.path): \(launchError.localizedDescription)")
        }

        let expectedPID = launchedApp?.processIdentifier
        let bundleID = launchedApp?.bundleIdentifier ?? Bundle(url: url)?.bundleIdentifier

        // Registration wait. Two signals, either is enough:
        //   1. a pid we can name, and
        //   2. that pid owns an on-screen window (not required for menu-bar apps)
        // Registration wait. `open`'s success only means LaunchServices accepted
        // the request; returning a pid at that moment hands the agent a number it
        // cannot use. So poll until the app has a pid, then give it half the
        // remaining budget to own an on-screen window — a menu-bar app never
        // will, and waiting the full budget for one would stall every launch of
        // an LSUIElement app.
        let start = Date()
        let deadline = start.addingTimeInterval(timeout)
        let windowDeadline = start.addingTimeInterval(timeout / 2)
        var resolvedPID: pid_t?
        while Date() < deadline {
            if let expectedPID, expectedPID > 0,
               NSRunningApplication(processIdentifier: expectedPID) != nil {
                resolvedPID = expectedPID
            } else if let bundleID,
                      let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                resolvedPID = running.processIdentifier
            } else {
                let after = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
                if let newPID = after.subtracting(before).first {
                    resolvedPID = newPID
                }
            }
            if let resolvedPID {
                if windowPids().contains(resolvedPID) { break }
                if Date() >= windowDeadline { break }
            }
            usleep(150_000)
        }

        guard let pid = resolvedPID else {
            throw AgentSpaceError(
                code: .appLaunchTimeout,
                message: "launched \(url.path) but it never registered a process within \(Int(timeout))s. It may be showing a modal in the AgentSpace session — take a screenshot to look.")
        }

        let app = NSRunningApplication(processIdentifier: pid)
        Log.worker.info("launched \(url.lastPathComponent) pid \(pid)")
        return AppInfo(
            pid: pid,
            name: app?.localizedName ?? url.deletingPathExtension().lastPathComponent,
            bundleID: app?.bundleIdentifier ?? bundleID,
            path: url.path,
            policy: policyName(app),
            active: app?.isActive ?? false)
    }

    private static func windowPids() -> Set<pid_t> {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var out: Set<pid_t> = []
        for window in list {
            if let pid = window[kCGWindowOwnerPID as String] as? pid_t { out.insert(pid) }
        }
        return out
    }

    static func runningApp(matching reference: String) -> NSRunningApplication? {
        // Exact pid first (the CLI and MCP pass pids around).
        if let pid = pid_t(reference), let app = NSRunningApplication(processIdentifier: pid) {
            return app
        }
        if reference.contains("."), let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: reference).first {
            return app
        }
        let target = reference.hasSuffix(".app") ? String(reference.dropLast(4)) : reference
        let byName = NSWorkspace.shared.runningApplications.first {
            ($0.localizedName ?? "").caseInsensitiveCompare(target) == .orderedSame
                || ($0.bundleURL?.deletingPathExtension().lastPathComponent ?? "")
                    .caseInsensitiveCompare(target) == .orderedSame
        }
        if let byName { return byName }
        // A path that is not running yet: resolve it and match by bundle id.
        if let url = try? resolve(reference), let bundleID = Bundle(url: url)?.bundleIdentifier {
            return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        }
        return nil
    }

    static func quit(_ reference: String, force: Bool) throws -> AppInfo {
        guard let app = runningApp(matching: reference) else {
            throw AgentSpaceError(
                code: .appNotRunning,
                message: "'\(reference)' is not running in this AgentSpace.")
        }
        let info = AppInfo(
            pid: app.processIdentifier,
            name: app.localizedName,
            bundleID: app.bundleIdentifier,
            path: app.bundleURL?.path,
            policy: policyName(app),
            active: app.isActive)

        let terminated = force ? app.forceTerminate() : app.terminate()
        guard terminated else {
            throw AgentSpaceError(
                code: .appNotRunning,
                message: "macOS refused to \(force ? "force-quit" : "quit") '\(reference)' (pid \(app.processIdentifier)).")
        }
        // Give it a moment so a follow-up `apps` sees the truth.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && !app.isTerminated {
            usleep(100_000)
        }
        if !app.isTerminated && force {
            kill(app.processIdentifier, SIGKILL)
        }
        return info
    }

    static func activate(_ reference: String) throws -> AppInfo {
        guard let app = runningApp(matching: reference) else {
            throw AgentSpaceError(
                code: .appNotRunning,
                message: "'\(reference)' is not running in this AgentSpace, so it cannot be activated. Launch it first.")
        }
        guard app.activate(options: [.activateAllWindows]) else {
            throw AgentSpaceError(
                code: .appNotRunning,
                message: "macOS refused to activate '\(reference)' (pid \(app.processIdentifier)).")
        }
        return AppInfo(
            pid: app.processIdentifier,
            name: app.localizedName,
            bundleID: app.bundleIdentifier,
            path: app.bundleURL?.path,
            policy: policyName(app),
            active: true)
    }

    private static func policyName(_ app: NSRunningApplication?) -> String {
        guard let app else { return "unknown" }
        switch app.activationPolicy {
        case .regular: return "regular"
        case .accessory: return "accessory"
        case .prohibited: return "prohibited"
        @unknown default: return "unknown"
        }
    }
}
