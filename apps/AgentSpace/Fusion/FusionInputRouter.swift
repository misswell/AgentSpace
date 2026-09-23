import AppKit
import Foundation
import AgentSpaceCore

/// Turns a gesture collected over a Fusion proxy into the `window.input` action
/// the worker already accepts.
///
/// The names here are the ones `InputAction.parse` already understands on the
/// desktop input path — the worker maps the window action onto it rather than
/// inventing a second vocabulary — so an option-drag or a shift-click from a
/// proxy means exactly what it means from a desktop viewer. Only the geometry
/// differs: a proxy sends fractions of the window, because it does not know the
/// window's global position and has no reason to.
enum FusionInputRouter {
    static func action(for gesture: RemotePointerGesture) -> JSONValue {
        switch gesture {
        case .hover(let u, let v):
            // Pointer travel carries no button and no modifiers: it is a
            // position, and claiming otherwise would post flags the remote has
            // no reason to honour.
            return .object(["type": .string("move"),
                            "xFraction": .double(u),
                            "yFraction": .double(v)])

        case .click(let u, let v, let button, let count, let modifiers):
            var object: [String: JSONValue] = ["type": .string(clickType(button: button, count: count)),
                                               "xFraction": .double(u),
                                               "yFraction": .double(v),
                                               "button": .string(button.rawValue)]
            if count > 1 { object["count"] = .int(count) }
            addModifiers(modifiers, to: &object)
            return .object(object)

        case .drag(let fromU, let fromV, let toU, let toV, let button, let modifiers):
            var object: [String: JSONValue] = ["type": .string("drag"),
                                               "xFraction": .double(fromU),
                                               "yFraction": .double(fromV),
                                               "toXFraction": .double(toU),
                                               "toYFraction": .double(toV),
                                               "button": .string(button.rawValue)]
            addModifiers(modifiers, to: &object)
            return .object(object)

        case .pointerDown(let u, let v, let button, let clickCount, let modifiers):
            return pointerPhase("pointerDown", u: u, v: v, button: button,
                                clickCount: clickCount, modifiers: modifiers)

        case .pointerUp(let u, let v, let button, let clickCount, let modifiers):
            return pointerPhase("pointerUp", u: u, v: v, button: button,
                                clickCount: clickCount, modifiers: modifiers)

        case .pointerDrag(let fromU, let fromV, let toU, let toV, let button, let modifiers):
            var object: [String: JSONValue] = [
                "type": .string("pointerDrag"),
                "xFraction": .double(fromU), "yFraction": .double(fromV),
                "toXFraction": .double(toU), "toYFraction": .double(toV),
                "button": .string(button.rawValue),
            ]
            addModifiers(modifiers, to: &object)
            return .object(object)

        case .scroll(let u, let v, let linesX, let linesY):
            return .object(["type": .string("scroll"),
                            "xFraction": .double(u),
                            "yFraction": .double(v),
                            "dx": .int(linesX),
                            "dy": .int(linesY)])
        }
    }

    /// `rightClick` and `doubleClick` are how the protocol spells a second button
    /// and a repeated press; a middle click has no such name, so it is a `click`
    /// with its button named.
    private static func clickType(button: MouseButton, count: Int) -> String {
        if button == .right { return "rightClick" }
        return count >= 2 ? "doubleClick" : "click"
    }

    private static func pointerPhase(_ type: String, u: Double, v: Double,
                                     button: MouseButton, clickCount: Int,
                                     modifiers: [Modifier]) -> JSONValue {
        var object: [String: JSONValue] = [
            "type": .string(type), "xFraction": .double(u), "yFraction": .double(v),
            "button": .string(button.rawValue),
        ]
        // Additive on the wire, and absent means one click — which is what every
        // existing proxy meant by sending a press with no count.
        if clickCount != 1 { object["count"] = .int(clickCount) }
        addModifiers(modifiers, to: &object)
        return .object(object)
    }

    private static func addModifiers(_ modifiers: [Modifier], to object: inout [String: JSONValue]) {
        guard !modifiers.isEmpty else { return }
        object["modifiers"] = .array(modifiers.map { .string($0.rawValue) })
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
