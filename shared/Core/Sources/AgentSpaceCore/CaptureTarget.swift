import Foundation

public enum CaptureTarget: Equatable, Sendable {
    case display(displayID: UInt32?)
    /// One logical Retina desktop. The worker makes a real 2× display the main
    /// display for this background session while the stream is open.
    case retinaDesktop
    case window(WindowIdentity)

    /// What this target is, for a log line a person reads. Never a wire field.
    public var kindDescription: String {
        switch self {
        case .display: return "display"
        case .retinaDesktop: return "retina desktop"
        case .window: return "window"
        }
    }

    public var jsonValue: JSONValue {
        switch self {
        case .display(let id):
            var value: [String: JSONValue] = ["kind": .string("display")]
            if let id { value["displayId"] = .int(Int(id)) }
            return .object(value)
        case .retinaDesktop:
            return .obj(["kind": .string("retinaDesktop")])
        case .window(let identity):
            return .obj([
                "kind": .string("window"),
                "windowId": .int(Int(identity.windowID)),
                "pid": .int(Int(identity.pid)),
                "generation": .int(Int(identity.generation)),
            ])
        }
    }

    public init(jsonValue: JSONValue) throws {
        switch jsonValue["kind"]?.stringValue {
        case "display":
            self = .display(displayID: jsonValue["displayId"]?.intValue.map(UInt32.init))
        case "retinaDesktop":
            self = .retinaDesktop
        case "window":
            guard let windowID = jsonValue["windowId"]?.intValue,
                  let pid = jsonValue["pid"]?.intValue,
                  let generation = jsonValue["generation"]?.intValue else {
                throw AgentSpaceError(code: .badRequest, message: "window frame target is missing its identity")
            }
            self = .window(.init(pid: Int32(pid), windowID: UInt32(windowID), generation: UInt64(generation)))
        default:
            throw AgentSpaceError(code: .badRequest, message: "frame target kind must be display or window")
        }
    }
}
