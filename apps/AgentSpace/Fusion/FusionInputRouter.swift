import AppKit
import Foundation
import AgentSpaceCore

enum FusionInputRouter {
    /// Normalized pointer geometry lives in the fitted image rect, so a value
    /// can land just outside it; the worker refuses out-of-window fractions, so
    /// clamp here rather than dropping the gesture.
    private static func clamp(_ fraction: Double) -> Double {
        max(0, min(1, fraction))
    }

    static func pointer(type: String, x: Double, y: Double, event: NSEvent? = nil) -> JSONValue {
        var object: [String: JSONValue] = [
            "type": .string(type),
            "xFraction": .double(clamp(x)),
            "yFraction": .double(clamp(y)),
        ]
        if let event, type == "scroll" {
            object["dx"] = .int(Int(event.scrollingDeltaX.rounded()))
            object["dy"] = .int(Int(event.scrollingDeltaY.rounded()))
        }
        return .object(object)
    }

    /// A press-and-travel gesture as one action: text selection, slider knobs
    /// and marquee rectangles need the button held between two points, which a
    /// `click` followed by `move` events cannot express.
    static func drag(fromX: Double, fromY: Double, toX: Double, toY: Double) -> JSONValue {
        .object([
            "type": .string("drag"),
            "xFraction": .double(clamp(fromX)),
            "yFraction": .double(clamp(fromY)),
            "toXFraction": .double(clamp(toX)),
            "toYFraction": .double(clamp(toY)),
        ])
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
