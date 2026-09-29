import AppKit
import Foundation
import AgentSpaceCore

@MainActor
final class FusionManager {
    static let shared = FusionManager()
    private var sessions: [UUID: FusionSession] = [:]

    func openWindow(_ remote: RemoteWindow, for space: AgentAccount) {
        if sessions[space.id] == nil {
            let session = FusionSession(space: space)
            sessions[space.id] = session
            session.start()
        }
        sessions[space.id]?.open(remote)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeApps(for spaceID: UUID) {
        sessions.removeValue(forKey: spaceID)?.stop()
    }

    // MARK: - The app picker's verbs

    /// Bring one application up in the Space **and open its window here**.
    ///
    /// Launching and seeing used to be two separate trips: the picker launched
    /// on the agent desktop and dismissed, and the owner read the silence as
    /// 「无法启动应用窗口」 — the app *did* start, just where nobody watching
    /// this Mac could see it, and the window required a second visit to
    /// 「打开应用」. One click means one outcome, so after the launch or
    /// activation lands, the app's first on-screen window is opened as a local
    /// proxy. A fresh launch can take a beat to produce that window, hence the
    /// brief poll; the session's `open` deduplicates by window identity, so an
    /// activation that finds an already-fused window simply raises it.
    func fuse(app: InstalledApplication, in space: AgentAccount, completion: @escaping (AgentSpaceError?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Built inside the closure: `SpaceService` is not Sendable, and
            // capturing one here is exactly what the compiler warns about.
            let service = SpaceService()
            let wasRunning = app.isRunning
            let error = wasRunning
                ? service.activate(space, app: app.path)
                : service.launch(space, app: app.path)
            guard error == nil else {
                Task { @MainActor in completion(error) }
                return
            }

            var opened: RemoteWindow?
            let deadline = Date().addingTimeInterval(wasRunning ? 2 : 8)
            while Date() < deadline {
                if case .success(let windows) = service.windows(for: space), let match = windows.first(where: {
                    ($0.bundleIdentifier != nil && $0.bundleIdentifier == app.bundleIdentifier)
                        || (app.pid != nil && Int($0.pid) == app.pid)
                }) {
                    opened = match
                    break
                }
                Thread.sleep(forTimeInterval: 0.25)
            }
            let window = opened
            Task { @MainActor in
                if let window { self.openWindow(window, for: space) }
                completion(nil)
            }
        }
    }

    /// Recently fused apps for one Space, most recent first.
    ///
    /// Per Space on purpose: two accounts are two different jobs, and a shared
    /// list would reorder both by whichever was used last.
    func recentApps(for space: AgentAccount) -> [String] {
        UserDefaults.standard.stringArray(forKey: Self.recentKey(space)) ?? []
    }

    func rememberRecent(app: InstalledApplication, for space: AgentAccount) {
        var recent = recentApps(for: space).filter { $0 != app.path }
        recent.insert(app.path, at: 0)
        UserDefaults.standard.set(Array(recent.prefix(5)), forKey: Self.recentKey(space))
    }

    private static func recentKey(_ space: AgentAccount) -> String {
        "fusionRecentApps.\(space.id.uuidString)"
    }
}
