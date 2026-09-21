import Foundation

public enum CaptureTarget: Equatable, Sendable {
    case display(displayID: UInt32?)
    case window(WindowIdentity)

    public var jsonValue: JSONValue {
        switch self {
        case .display(let id):
            var value: [String: JSONValue] = ["kind": .string("display")]
            if let id { value["displayId"] = .int(Int(id)) }
            return .object(value)
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
