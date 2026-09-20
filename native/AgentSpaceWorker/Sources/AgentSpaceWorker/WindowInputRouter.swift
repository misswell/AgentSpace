import AppKit
import Foundation
import AgentSpaceCore

enum WindowInputRouter {
    static func prepare(params: JSONValue, window: RemoteWindow) throws -> InputAction {
        guard let value = params["action"] else {
            throw AgentSpaceError(code: .invalidAction, message: #"window.input requires an "action" object"#)
        }
        guard let object = value.objectValue, let type = object["type"]?.stringValue else {
            throw AgentSpaceError(code: .invalidAction, message: #"window action requires a "type""#)
        }

        let action: InputAction
        switch type {
        case "move", "click", "doubleClick", "rightClick", "scroll", "drag":
            guard let xFraction = object["xFraction"]?.doubleValue,
                  let yFraction = object["yFraction"]?.doubleValue else {
                throw AgentSpaceError(code: .invalidCoordinate, message: "window pointer input requires xFraction and yFraction")
            }
            let point = try WindowCoordinateMapper.point(
                xFraction: xFraction, yFraction: yFraction, in: window.frame)
            switch type {
            case "move":
                action = .move(x: point.x, y: point.y)
            case "drag":
                // A drag is two normalized points of the same window: the press
                // and the release. Text selection and sliders need the travelled
                // path, which `click` + `move` cannot express.
                guard let toXFraction = object["toXFraction"]?.doubleValue,
                      let toYFraction = object["toYFraction"]?.doubleValue else {
                    throw AgentSpaceError(code: .invalidCoordinate, message: "window drag requires toXFraction and toYFraction")
                }
                let destination = try WindowCoordinateMapper.point(
                    xFraction: toXFraction, yFraction: toYFraction, in: window.frame)
                action = .drag(
                    fromX: point.x, fromY: point.y, toX: destination.x, toY: destination.y,
                    button: .left, modifiers: [])
            case "scroll":
                action = .scroll(
                    x: point.x, y: point.y,
                    dx: object["dx"]?.intValue ?? 0,
                    dy: object["dy"]?.intValue ?? 0)
            default:
                let button: MouseButton = type == "rightClick" ? .right : .left
                action = .click(
                    x: point.x, y: point.y, button: button,
                    count: type == "doubleClick" ? 2 : 1,
                    modifiers: [])
            }
        case "type", "key":
            switch InputAction.parse(value, index: 0) {
            case .success(let parsed): action = parsed
            case .failure(let error): throw error
            }
        default:
            throw AgentSpaceError(code: .invalidAction, message: "unsupported window action '\(type)'")
        }

        return action
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
