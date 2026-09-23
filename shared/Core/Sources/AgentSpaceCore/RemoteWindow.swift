import Foundation

public enum AgentPresentationMode: String, Codable, Sendable, CaseIterable {
    case desktop
    case fusion
}

public struct CGRectValue: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct WindowIdentity: Codable, Equatable, Hashable, Sendable {
    public var pid: Int32
    public var windowID: UInt32
    public var generation: UInt64

    public init(pid: Int32, windowID: UInt32, generation: UInt64) {
        self.pid = pid
        self.windowID = windowID
        self.generation = generation
    }
}

public struct RemoteWindow: Codable, Equatable, Identifiable, Sendable {
    public let id: UInt32
    public let pid: Int32
    public let appName: String
    public let bundleIdentifier: String?
    public let title: String?
    public let frame: CGRectValue
    public let layer: Int
    public let visible: Bool
    public let minimized: Bool
    public let generation: UInt64

    public init(
        id: UInt32,
        pid: Int32,
        appName: String,
        bundleIdentifier: String?,
        title: String?,
        frame: CGRectValue,
        layer: Int,
        visible: Bool,
        minimized: Bool,
        generation: UInt64
    ) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.frame = frame
        self.layer = layer
        self.visible = visible
        self.minimized = minimized
        self.generation = generation
    }

    public var identity: WindowIdentity {
        WindowIdentity(pid: pid, windowID: id, generation: generation)
    }

    public var jsonValue: JSONValue {
        var object: [String: JSONValue] = [
            "id": .int(Int(id)),
            "pid": .int(Int(pid)),
            "appName": .string(appName),
            "frame": .obj([
                "x": .double(frame.x), "y": .double(frame.y),
                "width": .double(frame.width), "height": .double(frame.height),
            ]),
            "layer": .int(layer),
            "visible": .bool(visible),
            "minimized": .bool(minimized),
            "generation": .int(Int(generation)),
        ]
        if let bundleIdentifier { object["bundleIdentifier"] = .string(bundleIdentifier) }
        if let title { object["title"] = .string(title) }
        return .object(object)
    }

    public init(jsonValue value: JSONValue) throws {
        guard let id = value["id"]?.intValue,
              let pid = value["pid"]?.intValue,
              let appName = value["appName"]?.stringValue,
              let frame = value["frame"],
              let x = frame["x"]?.doubleValue,
              let y = frame["y"]?.doubleValue,
              let width = frame["width"]?.doubleValue,
              let height = frame["height"]?.doubleValue,
              let layer = value["layer"]?.intValue,
              let generation = value["generation"]?.intValue,
              let windowID = UInt32(exactly: id),
              let processID = Int32(exactly: pid),
              let windowGeneration = UInt64(exactly: generation)
        else {
            throw AgentSpaceError(code: .badRequest, message: "malformed remote window")
        }
        self.init(
            id: windowID, pid: processID, appName: appName,
            bundleIdentifier: value["bundleIdentifier"]?.stringValue,
            title: value["title"]?.stringValue,
            frame: CGRectValue(x: x, y: y, width: width, height: height),
            layer: layer,
            visible: value["visible"]?.boolValue ?? true,
            minimized: value["minimized"]?.boolValue ?? false,
            generation: windowGeneration)
    }
}

public enum WindowCoordinateMapper {
    public static func point(
        xFraction: Double,
        yFraction: Double,
        in frame: CGRectValue
    ) throws -> (x: Double, y: Double) {
        guard xFraction.isFinite, yFraction.isFinite,
              (0...1).contains(xFraction), (0...1).contains(yFraction),
              frame.width > 0, frame.height > 0
        else {
            throw AgentSpaceError(
                code: .invalidCoordinate,
                message: "window coordinates must be finite fractions between 0 and 1")
        }
        return (
            x: frame.x + frame.width * xFraction,
            y: frame.y + frame.height * yFraction)
    }
}

/// One Fusion proxy action, resolved into the vocabulary the desktop input path
/// already speaks.
///
/// A proxy sends pointer geometry as fractions of its own window, because it
/// knows where that window sits on the agent's desktop and has no idea where
/// the human moved their copy of it. Everything past the geometry — which button,
/// how many clicks, which modifiers, how far the wheel turned — is the same
/// language `agentspace input` uses, so this resolves the geometry and hands the
/// result to `InputAction.parse` rather than keeping a second dialect alive.
public enum RemoteWindowInput {
    /// Pointer types whose coordinates arrive as fractions.
    private static let pointerTypes: Set<String> = [
        "move", "click", "doubleClick", "rightClick", "scroll", "drag",
        "pointerDown", "pointerDrag", "pointerUp",
    ]

    public static func action(from params: JSONValue, window: RemoteWindow,
                              gestureFrame: CGRectValue? = nil) throws -> InputAction {
        guard let value = params["action"] else {
            throw AgentSpaceError(code: .invalidAction, message: #"window.input requires an "action" object"#)
        }
        guard let object = value.objectValue, let type = object["type"]?.stringValue else {
            throw AgentSpaceError(code: .invalidAction, message: #"window action requires a "type""#)
        }
        if type == "type" || type == "key" {
            return try parsed(value)
        }
        guard pointerTypes.contains(type) else {
            throw AgentSpaceError(code: .invalidAction, message: "unsupported window action '\(type)'")
        }
        guard let xFraction = object["xFraction"]?.doubleValue,
              let yFraction = object["yFraction"]?.doubleValue else {
            throw AgentSpaceError(
                code: .invalidCoordinate,
                message: "window pointer input requires xFraction and yFraction")
        }
        let frame = gestureFrame ?? window.frame
        let press = try WindowCoordinateMapper.point(
            xFraction: xFraction, yFraction: yFraction, in: frame)
        // `drag` names its start `fromX`/`fromY`; every other pointer type uses
        // `x`/`y`. Sending a drag's press under the wrong key is a malformed
        // action to the parser, not a drag that starts somewhere else.
        var absolute: [String: JSONValue] = ["type": .string(type)]
        if type == "drag" || type == "pointerDrag" {
            absolute["fromX"] = .double(press.x)
            absolute["fromY"] = .double(press.y)
        } else {
            absolute["x"] = .double(press.x)
            absolute["y"] = .double(press.y)
        }
        if type == "drag" || type == "pointerDrag" {
            // A drag is two normalized points of the same window: the press and
            // the release. Text selection and slider knobs need the travelled
            // path, which a `click` followed by moves cannot express.
            guard let toXFraction = object["toXFraction"]?.doubleValue,
                  let toYFraction = object["toYFraction"]?.doubleValue else {
                throw AgentSpaceError(
                    code: .invalidCoordinate, message: "window drag requires toXFraction and toYFraction")
            }
            let release = try WindowCoordinateMapper.point(
                xFraction: toXFraction, yFraction: toYFraction, in: frame)
            absolute["toX"] = .double(release.x)
            absolute["toY"] = .double(release.y)
        }
        for key in ["button", "count", "modifiers", "dx", "dy"] {
            if let passed = object[key] { absolute[key] = passed }
        }
        return try parsed(.object(absolute))
    }

    private static func parsed(_ value: JSONValue) throws -> InputAction {
        switch InputAction.parse(value, index: 0) {
        case .success(let action): return action
        case .failure(let error): throw error
        }
    }
}
