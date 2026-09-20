import AppKit
import Foundation
import AgentSpaceCore

enum WindowInputRouter {
    static func perform(params: JSONValue, window: RemoteWindow) throws -> Int {
        guard let value = params["action"] else {
            throw AgentSpaceError(code: .invalidAction, message: #"window.input requires an "action" object"#)
        }
        guard let object = value.objectValue, let type = object["type"]?.stringValue else {
            throw AgentSpaceError(code: .invalidAction, message: #"window action requires a "type""#)
        }

        let action: InputAction
        switch type {
        case "move", "click", "doubleClick", "rightClick", "scroll":
            guard let xFraction = object["xFraction"]?.doubleValue,
                  let yFraction = object["yFraction"]?.doubleValue else {
                throw AgentSpaceError(code: .invalidCoordinate, message: "window pointer input requires xFraction and yFraction")
            }
            let point = try WindowCoordinateMapper.point(
                xFraction: xFraction, yFraction: yFraction, in: window.frame)
            switch type {
            case "move":
                action = .move(x: point.x, y: point.y)
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

        guard let app = NSRunningApplication(processIdentifier: window.pid),
              app.activate(options: [.activateAllWindows]) else {
            throw AgentSpaceError(code: .appNotRunning, message: "could not activate pid \(window.pid) before Fusion input")
        }
        try InputSynthesizer.perform(action)
        return 1
    }
}
