import CoreGraphics

/// Viewer keyboard forwarding — plan §17's "键盘输入也一样" and §52's
/// 看 · 点 · 输入.
///
/// The Desktop Viewer already turns clicks into translated InputActions;
/// this adds the keyboard half. The main app listens to its *own window's*
/// key events via an NSEvent local monitor — not a global HID tap, which
/// §13 forbids — and converts each key-down into the same action the CLI
/// and MCP would send, so the agent session receives one canonical shape.
///
/// The conversion is a pure function of the fields NSEvent exposes, so the
/// contract is testable without synthesising events.
public enum KeyboardForwarding {
    /// NSEvent encodes keys with no textual meaning (arrows, F-keys,
    /// navigation) as characters in the private-use area.
    static let privateUseBase: UInt32 = 0xF700
    static let privateUseTop: UInt32 = 0xF8FF

    /// Private-use character → the combo name in `KeyCombo.keycodes`.
    /// F1–F12 are the contiguous block starting at 0xF704.
    static let named: [UInt32: String] = [
        0xF700: "up", 0xF701: "down", 0xF702: "left", 0xF703: "right",
        0xF728: "forwarddelete", 0xF729: "home", 0xF72B: "end",
        0xF72C: "pageup", 0xF72D: "pagedown",
    ]

    /// Control characters that name a key rather than text.
    static let controlNamed: [UInt32: String] = [
        0x09: "tab", 0x0D: "return", 0x1B: "escape", 0x7F: "backspace",
    ]

    /// The action a viewer should send for one key-down, or nil when there
    /// is no faithful translation — ignored rather than guessed.
    ///
    /// Modifier precedence in the produced combo follows `Modifier`'s
    /// canonical order (cmd, ctrl, alt, shift), matching what the CLI
    /// documents.
    public static func action(
        characters: String?,
        charactersIgnoringModifiers: String?,
        command: Bool,
        shift: Bool,
        option: Bool,
        control: Bool
    ) -> InputAction? {
        guard let first = characters?.first,
              let scalar = first.unicodeScalars.first else { return nil }

        // 1. Function and navigation keys: always a combo, with whatever
        //    modifiers are held. An unknown private-use name is ignored.
        if (privateUseBase...privateUseTop).contains(scalar.value) {
            let name: String
            if let mapped = named[scalar.value] {
                name = mapped
            } else if (0xF704...0xF70F).contains(scalar.value) {
                name = "f\(scalar.value - 0xF704 + 1)"
            } else {
                return nil
            }
            return combo(name, command: command, shift: shift, option: option, control: control)
        }

        // 2. Control characters: tab/return/escape/backspace name keys, so a
        //    held modifier must survive (cmd+return, ctrl+tab). Anything
        //    else has no faithful rendering here.
        if let name = controlNamed[scalar.value] {
            return combo(name, command: command, shift: shift, option: option, control: control)
        }
        if scalar.value <= 0x1F || scalar.value == 0x7F { return nil }

        // 3. Command means a shortcut, never text: cmd+c must not type "c".
        //    Only bases the keycode table can synthesise are forwarded.
        if command {
            guard let base = charactersIgnoringModifiers?.lowercased(),
                  KeyCombo.keycodes[base] != nil else { return nil }
            return combo(base, command: command, shift: shift, option: option, control: control)
        }

        // 4. Control (without command) is a shortcut too. Option is not:
        //    option-composed characters (å, é) are how a Mac types them,
        //    so option alone stays text.
        if control, let base = charactersIgnoringModifiers?.lowercased(),
           KeyCombo.keycodes[base] != nil {
            return combo(base, command: false, shift: shift, option: option, control: true)
        }

        // 5. Everything printable is already final text — the character the
        //    user's layout produced, capital letters and å included.
        return .type(text: String(first))
    }

    /// Canonical modifier order, matching `Modifier`'s raw values.
    static func combo(_ name: String, command: Bool, shift: Bool, option: Bool, control: Bool) -> InputAction {
        var parts: [String] = []
        if command { parts.append(Modifier.cmd.rawValue) }
        if control { parts.append(Modifier.ctrl.rawValue) }
        if option { parts.append(Modifier.alt.rawValue) }
        if shift { parts.append(Modifier.shift.rawValue) }
        parts.append(name)
        return .key(combo: parts.joined(separator: "+"))
    }
}
