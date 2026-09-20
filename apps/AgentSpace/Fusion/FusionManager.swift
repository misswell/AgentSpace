import AppKit
import Foundation
import AgentSpaceCore

@MainActor
final class FusionManager {
    static let shared = FusionManager()
    private var sessions: [UUID: FusionSession] = [:]

    func openApps(for space: AgentAccount) {
        if sessions[space.id] == nil {
            let session = FusionSession(space: space)
            sessions[space.id] = session
            session.start()
        } else {
            sessions[space.id]?.showAll()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeApps(for spaceID: UUID) {
        sessions.removeValue(forKey: spaceID)?.stop()
    }
}
