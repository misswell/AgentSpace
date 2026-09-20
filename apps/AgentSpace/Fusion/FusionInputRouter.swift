import AppKit
import Foundation
import AgentSpaceCore

enum FusionInputRouter {
    /// The worker's human-lease duration, mirrored here so the proxy knows how
    /// long a deliberate interaction keeps pointer travel meaningful. The lease
    /// itself is the worker's to grant and to enforce; this is only a local
    /// guess about whether a remote move is worth asking for.
    static let humanLeaseSeconds: TimeInterval = 5

    /// Normalized pointer geometry lives in the fitted image rect, so a value
    /// can land just outside it; the worker refuses out-of-window fractions, so
    /// clamp here rather than dropping the gesture.
    private static func clamp(_ fraction: Double) -> Double {
        max(0, min(1, fraction))
    }

    static func pointer(
        type: String, x: Double, y: Double, dx: Int = 0, dy: Int = 0, event: NSEvent? = nil
    ) -> JSONValue {
        var object: [String: JSONValue] = [
            "type": .string(type),
            "xFraction": .double(clamp(x)),
            "yFraction": .double(clamp(y)),
        ]
        if type == "scroll", dx != 0 || dy != 0 {
            object["dx"] = .int(dx)
            object["dy"] = .int(dy)
        }
        addPointerAttributes(to: &object, event: event)
        return .object(object)
    }

    /// A press-and-travel gesture as one action: text selection, slider knobs
    /// and marquee rectangles need the button held between two points, which a
    /// `click` followed by `move` events cannot express.
    static func drag(
        fromX: Double, fromY: Double, toX: Double, toY: Double, event: NSEvent? = nil
    ) -> JSONValue {
        var object: [String: JSONValue] = [
            "type": .string("drag"),
            "xFraction": .double(clamp(fromX)),
            "yFraction": .double(clamp(fromY)),
            "toXFraction": .double(clamp(toX)),
            "toYFraction": .double(clamp(toY)),
        ]
        addPointerAttributes(to: &object, event: event)
        return .object(object)
    }

    /// Which button and which modifiers were held.
    ///
    /// These are the names `InputAction.parse` already accepts on the desktop
    /// input path — the worker maps the window action onto it rather than
    /// inventing a second vocabulary — so an option-drag or a shift-click from a
    /// proxy means exactly what it means from a desktop viewer.
    private static func addPointerAttributes(
        to object: inout [String: JSONValue], event: NSEvent?
    ) {
        guard let event else { return }
        let type = object["type"]?.stringValue ?? ""
        if type != "move", type != "scroll", let button = buttonName(event.buttonNumber) {
            object["button"] = .string(button)
        }
        let held = modifiers(event.modifierFlags)
        if !held.isEmpty { object["modifiers"] = .array(held.map { .string($0) }) }
    }

    private static func buttonName(_ number: Int) -> String? {
        switch number {
        case 0: return MouseButton.left.rawValue
        case 1: return MouseButton.right.rawValue
        case 2: return MouseButton.middle.rawValue
        default: return nil
        }
    }

    /// The four command modifiers, in the protocol's spelling. `fn` is left out
    /// deliberately: on a Mac keyboard it is not held as a modifier for mouse
    /// gestures, and reporting it would send a flag the remote cannot honour.
    private static func modifiers(_ flags: NSEvent.ModifierFlags) -> [String] {
        var names: [String] = []
        if flags.contains(.command) { names.append(Modifier.cmd.rawValue) }
        if flags.contains(.control) { names.append(Modifier.ctrl.rawValue) }
        if flags.contains(.option) { names.append(Modifier.alt.rawValue) }
        if flags.contains(.shift) { names.append(Modifier.shift.rawValue) }
        return names
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
