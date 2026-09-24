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

    /// Bring one application up in the Space. Its windows are opened separately
    /// through the window picker when the person asks for one.
    ///
    /// An app that is already running is *activated* rather than launched: the
    /// picker labels that row 「已在运行」, and starting a second copy would give
    /// the person two of everything.
    func fuse(app: InstalledApplication, in space: AgentAccount, completion: @escaping (AgentSpaceError?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Built inside the closure: `SpaceService` is not Sendable, and
            // capturing one here is exactly what the compiler warns about.
            let service = SpaceService()
            let error = app.isRunning
                ? service.activate(space, app: app.path)
                : service.launch(space, app: app.path)
            Task { @MainActor in
                guard error == nil else {
                    completion(error)
                    return
                }
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
