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
              id >= 0, generation >= 0
        else {
            throw AgentSpaceError(code: .badRequest, message: "malformed remote window")
        }
        self.init(
            id: UInt32(id), pid: Int32(pid), appName: appName,
            bundleIdentifier: value["bundleIdentifier"]?.stringValue,
            title: value["title"]?.stringValue,
            frame: CGRectValue(x: x, y: y, width: width, height: height),
            layer: layer,
            visible: value["visible"]?.boolValue ?? true,
            minimized: value["minimized"]?.boolValue ?? false,
            generation: UInt64(generation))
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
