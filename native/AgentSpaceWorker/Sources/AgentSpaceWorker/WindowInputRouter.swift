import AppKit
import Foundation
import AgentSpaceCore

enum WindowInputRouter {
    /// The proxy's action, with window-relative fractions resolved. The
    /// vocabulary past the geometry is Core's (`RemoteWindowInput`), so a
    /// shift-click from a proxy means what it means from `agentspace input`.
    static func prepare(params: JSONValue, window: RemoteWindow) throws -> InputAction {
        try RemoteWindowInput.action(from: params, window: window)
    }

    /// Make the Fusion window a provable input target before posting at its
    /// coordinates: frontmost app *and* frontmost window within it.
    static func activate(window: RemoteWindow) throws {
        guard let app = NSRunningApplication(processIdentifier: window.pid),
              app.activate(options: [.activateAllWindows]) else {
            throw AgentSpaceError(code: .appNotRunning, message: "could not activate pid \(window.pid) before Fusion input")
        }
        try WindowActions.raise(window: window)
    }

    static func perform(_ action: InputAction) throws -> Int {
        try InputSynthesizer.perform(action)
        return 1
    }
}
