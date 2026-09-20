import AppKit
import Foundation
import AgentSpaceCore

enum FusionInputRouter {
    static func pointer(type: String, x: Double, y: Double, event: NSEvent? = nil) -> JSONValue {
        var object: [String: JSONValue] = [
            "type": .string(type),
            "xFraction": .double(max(0, min(1, x))),
            "yFraction": .double(max(0, min(1, y))),
        ]
        if let event, type == "scroll" {
            object["dx"] = .int(Int(event.scrollingDeltaX.rounded()))
            object["dy"] = .int(Int(event.scrollingDeltaY.rounded()))
        }
        return .object(object)
    }

    static func keyboard(_ event: NSEvent) -> JSONValue? {
        let modifiers: [(NSEvent.ModifierFlags, String)] = [
            (.command, "cmd"), (.control, "ctrl"), (.option, "alt"), (.shift, "shift"),
        ]
        let special: [UInt16: String] = [
            36: "return", 48: "tab", 49: "space", 51: "backspace", 53: "escape",
            123: "left", 124: "right", 125: "down", 126: "up",
        ]
        if let key = special[event.keyCode] {
            let prefix = modifiers.compactMap { event.modifierFlags.contains($0.0) ? $0.1 : nil }
            return .obj(["type": .string("key"), "key": .string((prefix + [key]).joined(separator: "+"))])
        }
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           let text = event.characters, !text.isEmpty {
            return .obj(["type": .string("type"), "text": .string(text)])
        }
        guard let key = event.charactersIgnoringModifiers?.lowercased(), key.count == 1 else { return nil }
        let prefix = modifiers.compactMap { event.modifierFlags.contains($0.0) ? $0.1 : nil }
        return .obj(["type": .string("key"), "key": .string((prefix + [key]).joined(separator: "+"))])
    }
}
