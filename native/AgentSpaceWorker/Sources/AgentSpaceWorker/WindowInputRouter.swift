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

    /// What the action did, and which channel it took. The channel travels out
    /// to the caller for the same reason it does on `input` (see
    /// `InputSynthesizer.Outcome`): a proxy scroll that reaches no scroll area is
    /// posted as a wheel event, and in a session that is not on the console that
    /// event reaches no app — so a proxy whose document does not move should not
    /// have been told that it scrolled.
    static func perform(_ action: InputAction) throws -> InputSynthesizer.Outcome {
        try InputSynthesizer.perform(action)
    }
}
