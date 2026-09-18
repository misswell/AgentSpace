import Foundation
import CoreGraphics

/// A mouse button, named the way the protocol names it.
public enum MouseButton: String, Codable, Sendable, CaseIterable {
    case left
    case right
    case middle

    public var cgButton: CGMouseButton {
        switch self {
        case .left: return .left
        case .right: return .right
        case .middle: return .center
        }
    }
}

/// A modifier key.
public enum Modifier: String, Codable, Sendable, CaseIterable {
    case cmd
    case ctrl
    case alt
    case shift
    case fn

    public var cgFlag: CGEventFlags {
        switch self {
        case .cmd: return .maskCommand
        case .ctrl: return .maskControl
        case .alt: return .maskAlternate
        case .shift: return .maskShift
        case .fn: return .maskSecondaryFn
        }
    }

    /// Accept the spellings a human or a model is likely to produce.
    public static func parse(_ raw: String) -> Modifier? {
        switch raw.lowercased() {
        case "cmd", "command", "meta", "super", "⌘": return .cmd
        case "ctrl", "control", "⌃": return .ctrl
        case "alt", "opt", "option", "⌥": return .alt
        case "shift", "⇧": return .shift
        case "fn", "function": return .fn
        default: return nil
        }
    }
}

/// One synthetic input step. Plan §14.
///
/// The whole list is parsed and validated *before* any event is posted. This is
/// a deliberate refinement of "fail on the first bad action": half-executing a
/// synthetic gesture leaves a mouse button down or a modifier stuck, and the
/// caller has no way to reason about the session afterwards. A rejected batch
/// performs nothing and says so.
public enum InputAction: Equatable, Sendable {
    case move(x: Double, y: Double)
    case click(x: Double, y: Double, button: MouseButton, count: Int, modifiers: [Modifier])
    case drag(fromX: Double, fromY: Double, toX: Double, toY: Double, button: MouseButton, modifiers: [Modifier])
    case scroll(x: Double?, y: Double?, dx: Int, dy: Int)
    case type(text: String)
    case key(combo: String)
    /// Let the target settle. Bounded; see `InputLimits`.
    case sleep(ms: Int)

    /// The `type` discriminator used on the wire.
    public var typeName: String {
        switch self {
        case .move: return "move"
        case .click(_, _, _, let count, _): return count >= 2 ? "doubleClick" : "click"
        case .drag: return "drag"
        case .scroll: return "scroll"
        case .type: return "type"
        case .key: return "key"
        case .sleep: return "sleep"
        }
    }
}

/// Hard bounds. Plan §14 asks for batching; unbounded batching is a
/// denial-of-service against the human's own machine, so every list is capped.
public enum InputLimits {
    /// Maximum actions in one `input` call. Agents are told to batch, so this is
    /// generous while still bounding a single request.
    public static let maxActions = 512
    /// Maximum characters in one `type` action.
    public static let maxTypeLength = 10_000
    /// Maximum `sleep` in one action, and in total across a batch.
    public static let maxSleepMsPerAction = 30_000
    public static let maxSleepMsPerBatch = 120_000
    /// Click repeat bound.
    public static let maxClickCount = 5
    /// Cap on total time a single input call may occupy the worker.
    public static let maxTotalMs = 180_000
}

// MARK: - Parsing

extension InputAction {

    /// Parse one action from a JSON object. Errors are `INVALID_ACTION` with a
    /// message naming the offending index — a model that sends a malformed
    /// action must be able to fix it from the error alone.
    public static func parse(_ value: JSONValue, index: Int) -> Result<InputAction, AgentSpaceError> {
        func bad(_ why: String) -> Result<InputAction, AgentSpaceError> {
            .failure(AgentSpaceError(code: .invalidAction, message: "action \(index): \(why)"))
        }
        guard let object = value.objectValue else {
            return bad("must be an object")
        }
        guard let type = object["type"]?.stringValue else {
            return bad(#"missing "type""#)
        }

        switch type {
        case "move":
            guard let x = object["x"]?.doubleValue, let y = object["y"]?.doubleValue else {
                return bad("move requires numeric x and y")
            }
            return .success(.move(x: x, y: y))

        case "click", "doubleClick", "rightClick":
            guard let x = object["x"]?.doubleValue, let y = object["y"]?.doubleValue else {
                return bad("\(type) requires numeric x and y")
            }
            var button: MouseButton = .left
            if type == "rightClick" {
                button = .right
            } else if let raw = object["button"]?.stringValue {
                guard let parsed = MouseButton(rawValue: raw.lowercased()) else {
                    return bad("unknown button '\(raw)' (expected left, right or middle)")
                }
                button = parsed
            }
            var count = 1
            if type == "doubleClick" {
                count = 2
            } else if let raw = object["count"]?.intValue {
                guard raw >= 1 && raw <= InputLimits.maxClickCount else {
                    return bad("count must be between 1 and \(InputLimits.maxClickCount)")
                }
                count = raw
            }
            guard let modifiers = parseModifiers(object["modifiers"], index: index) else {
                return bad("modifiers must be an array of known modifier names")
            }
            return .success(.click(x: x, y: y, button: button, count: count, modifiers: modifiers))

        case "drag":
            guard let fx = object["fromX"]?.doubleValue, let fy = object["fromY"]?.doubleValue,
                  let tx = object["toX"]?.doubleValue, let ty = object["toY"]?.doubleValue else {
                return bad("drag requires numeric fromX, fromY, toX and toY")
            }
            var button: MouseButton = .left
            if let raw = object["button"]?.stringValue {
                guard let parsed = MouseButton(rawValue: raw.lowercased()) else {
                    return bad("unknown button '\(raw)'")
                }
                button = parsed
            }
            guard let modifiers = parseModifiers(object["modifiers"], index: index) else {
                return bad("modifiers must be an array of known modifier names")
            }
            return .success(.drag(fromX: fx, fromY: fy, toX: tx, toY: ty, button: button, modifiers: modifiers))

        case "scroll":
            let dx = object["dx"]?.intValue ?? 0
            let dy = object["dy"]?.intValue ?? 0
            return .success(.scroll(x: object["x"]?.doubleValue, y: object["y"]?.doubleValue, dx: dx, dy: dy))

        case "type":
            guard let text = object["text"]?.stringValue else {
                return bad(#"type requires a "text" string"#)
            }
            guard text.count <= InputLimits.maxTypeLength else {
                return bad("text longer than \(InputLimits.maxTypeLength) characters")
            }
            return .success(.type(text: text))

        case "key":
            // Accept both `keys: ["cmd","enter"]` (plan §14) and
            // `key: "cmd+enter"` (the CLI's spelling). Same thing, two shapes.
            if let combo = object["key"]?.stringValue {
                guard !combo.isEmpty else { return bad("key must not be empty") }
                if let err = KeyCombo.parse(combo).errorMessage {
                    return bad(err)
                }
                return .success(.key(combo: combo))
            }
            if let keys = object["keys"]?.arrayValue {
                let names = keys.compactMap { $0.stringValue }
                guard names.count == keys.count, !names.isEmpty else {
                    return bad("keys must be a non-empty array of strings")
                }
                // Last non-modifier entry is the key; the rest must be modifiers.
                var mods: [String] = []
                var keyName: String?
                for name in names {
                    if Modifier.parse(name) != nil {
                        mods.append(name.lowercased())
                    } else {
                        if keyName != nil {
                            return bad("keys contains more than one non-modifier key: \(names)")
                        }
                        keyName = name
                    }
                }
                guard let keyName else {
                    return bad("keys must contain a non-modifier key, e.g. [\"cmd\",\"enter\"]")
                }
                let combo = (mods + [keyName]).joined(separator: "+")
                if let err = KeyCombo.parse(combo).errorMessage {
                    return bad(err)
                }
                return .success(.key(combo: combo))
            }
            return bad(#"key requires either "key" (a combo string) or "keys" (an array)"#)

        case "sleep", "wait":
            guard let ms = object["ms"]?.intValue else {
                return bad("sleep requires numeric ms")
            }
            guard ms >= 0 && ms <= InputLimits.maxSleepMsPerAction else {
                return bad("sleep ms must be between 0 and \(InputLimits.maxSleepMsPerAction)")
            }
            return .success(.sleep(ms: ms))

        default:
            return bad("unknown action type '\(type)'")
        }
    }

    private static func parseModifiers(_ value: JSONValue?, index: Int) -> [Modifier]? {
        guard let value, value != .null else { return [] }
        guard let list = value.arrayValue else { return nil }
        var out: [Modifier] = []
        for item in list {
            guard let raw = item.stringValue, let mod = Modifier.parse(raw) else { return nil }
            out.append(mod)
        }
        return out
    }

    /// Parse and validate a whole batch.
    ///
    /// Returns `.failure` with the *first* problem, having validated everything
    /// — so a caller learns about a bad action 40 before it performs action 1.
    public static func parseBatch(_ value: JSONValue) -> Result<[InputAction], AgentSpaceError> {
        guard let raw = value.arrayValue else {
            return .failure(AgentSpaceError(
                code: .invalidAction,
                message: #"input requires an "actions" array"#))
        }
        guard raw.count <= InputLimits.maxActions else {
            return .failure(AgentSpaceError(
                code: .invalidAction,
                message: "\(raw.count) actions in one call exceeds the limit of \(InputLimits.maxActions)"))
        }
        var actions: [InputAction] = []
        actions.reserveCapacity(raw.count)
        for (i, item) in raw.enumerated() {
            switch parse(item, index: i) {
            case .success(let a): actions.append(a)
            case .failure(let e): return .failure(e)
            }
        }
        let totalSleep = actions.reduce(0) { partial, action in
            if case .sleep(let ms) = action { return partial + ms }
            return partial
        }
        guard totalSleep <= InputLimits.maxSleepMsPerBatch else {
            return .failure(AgentSpaceError(
                code: .invalidAction,
                message: "total sleep \(totalSleep)ms exceeds the per-call limit of \(InputLimits.maxSleepMsPerBatch)ms"))
        }
        return .success(actions)
    }
}

// MARK: - Key combinations

/// US-layout virtual keycodes and `[modifier+]*key` parsing.
///
/// The table is deliberately finite: an unknown key name is `INVALID_ACTION`,
/// never a guess. Silently typing the wrong key into someone's session is worse
/// than refusing.
public enum KeyCombo {
    public static let keycodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50,
        "return": 36, "enter": 36,
        "tab": 48, "space": 49,
        "backspace": 51, "delete": 51,
        "escape": 53, "esc": 53,
        "forwarddelete": 117,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "home": 115, "pageup": 116, "end": 119, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]

    public struct Parsed: Equatable, Sendable {
        public var keyCode: CGKeyCode
        public var flags: CGEventFlags
        public var canonical: String
    }

    /// Parse `[modifier+]*key`, e.g. `cmd+shift+t`, `cmd+l`, `enter`.
    ///
    /// A trailing `+` means the key itself is `+` (shift+`=` on a US layout),
    /// which is the only way to name that key unambiguously.
    public static func parse(_ combo: String) -> Result<Parsed, AgentSpaceError> {
        var flags: CGEventFlags = []
        var canonicalMods: [String] = []
        var name: String

        // A trailing "+" means the key itself is "+" (shift+"=" on a US
        // layout). Splitting the remainder on "+" and dropping empty pieces is
        // what makes "cmd++" mean command-plus rather than command followed by
        // two empty modifiers.
        if combo.hasSuffix("+") {
            flags.insert(.maskShift)
            canonicalMods.append("shift")
            name = "="
        } else {
            guard !combo.isEmpty else {
                return .failure(AgentSpaceError(code: .invalidAction, message: "empty key combo"))
            }
            name = combo.lowercased()
        }

        // Everything before the final "+" (or the whole string when there is no
        // trailing "+") is a modifier list.
        let modifierPart = combo.hasSuffix("+") ? String(combo.dropLast()) : ""
        var parts = modifierPart
            .split(separator: "+", omittingEmptySubsequences: true)
            .map(String.init)

        if !combo.hasSuffix("+") {
            parts = name.split(separator: "+", omittingEmptySubsequences: true).map(String.init)
            guard let last = parts.popLast() else {
                return .failure(AgentSpaceError(code: .invalidAction, message: "empty key combo"))
            }
            name = last
        }

        for raw in parts {
            guard let mod = Modifier.parse(raw) else {
                return .failure(AgentSpaceError(
                    code: .invalidAction,
                    message: "unknown modifier '\(raw)' in key combo '\(combo)'"))
            }
            flags.insert(mod.cgFlag)
            canonicalMods.append(mod.rawValue)
        }
        guard let code = keycodes[name] else {
            return .failure(AgentSpaceError(
                code: .invalidAction,
                message: "unknown key '\(name)' in key combo '\(combo)'. Known keys: \(keycodes.keys.sorted().joined(separator: " "))"))
        }
        return .success(Parsed(
            keyCode: code,
            flags: flags,
            canonical: (canonicalMods + [name]).joined(separator: "+")))
    }
}

extension Result where Success == KeyCombo.Parsed, Failure == AgentSpaceError {
    var errorMessage: String? {
        if case .failure(let e) = self { return e.message }
        return nil
    }
}
