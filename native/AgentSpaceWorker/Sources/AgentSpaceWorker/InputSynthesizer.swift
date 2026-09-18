import Foundation
import CoreGraphics
import ApplicationServices
import AppKit
import AgentSpaceCore

/// Posts synthetic input into **this session only**. Plan §13.
///
/// There are three ways to inject a CGEvent and only one of them is correct
/// from a background session. This was measured (see `docs/validation.md` and
/// the reference implementation's notes, which agree):
///
/// - `.cghidEventTap` — the global hardware entry point. The window server
///   routes it to whichever session is **on the console**, i.e. the human's
///   screen. Never correct here, and actively harmful: it types on the desktop
///   we promised not to touch. It is unreachable from this file by
///   construction — `post` takes no tap parameter.
/// - `postToPid` — bypasses the window server and delivers into a process
///   queue. Measured to deliver nothing at all.
/// - `.cgSessionEventTap` — the per-session entry point. Posted from a process
///   inside session N, the event enters session N's stream and reaches that
///   session's key window.
///
/// So every event goes to `.cgSessionEventTap`, and the console check in
/// `Operations.input` runs before any of this is reached.
enum InputSynthesizer {

    /// Post one event into this session's stream.
    ///
    /// `flags` is **always** assigned, including the empty set. A freshly
    /// created `CGEvent` inherits the session's current modifier state, so an
    /// ambient or stuck modifier silently rewrites every event: a plain "3"
    /// arrives as ⌘3 and typed text arrives as a string of shortcuts. Assigning
    /// only when the caller asked for modifiers leaves that state in place and
    /// was observed live to switch Calculator into Programmer mode instead of
    /// entering a digit.
    private static func post(_ event: CGEvent?, flags: CGEventFlags = []) {
        guard let event else { return }
        event.flags = flags
        event.post(tap: .cgSessionEventTap)
    }

    private static func mouseEvent(
        _ type: CGEventType, _ x: Double, _ y: Double, _ button: CGMouseButton
    ) -> CGEvent? {
        CGEvent(mouseEventSource: nil, mouseType: type,
                mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: button)
    }

    private static func downUpTypes(_ button: CGMouseButton) -> (CGEventType, CGEventType, CGEventType) {
        switch button {
        case .right: return (.rightMouseDown, .rightMouseUp, .rightMouseDragged)
        case .center: return (.otherMouseDown, .otherMouseUp, .otherMouseDragged)
        default: return (.leftMouseDown, .leftMouseUp, .leftMouseDragged)
        }
    }

    private static func sleepMs(_ ms: Int) {
        if ms > 0 { usleep(UInt32(ms) * 1000) }
    }

    /// Execute one validated action. Throws only the errors that are genuinely
    /// per-action (`INVALID_ACTION` for a key combo that fails to parse).
    static func perform(_ action: InputAction) throws {
        switch action {
        case .sleep(let ms):
            // A sleep moves no cursor and presses no key, so it needs no target.
            sleepMs(ms)

        case .move(let x, let y):
            post(mouseEvent(.mouseMoved, x, y, .left))

        case .click(let x, let y, let button, let count, let modifiers):
            let flags = flags(from: modifiers)
            let (down, up, _) = downUpTypes(button.cgButton)
            post(mouseEvent(.mouseMoved, x, y, button.cgButton))
            for n in 1...max(1, count) {
                if let e = mouseEvent(down, x, y, button.cgButton) {
                    e.setIntegerValueField(.mouseEventClickState, value: Int64(n))
                    post(e, flags: flags)
                }
                if let e = mouseEvent(up, x, y, button.cgButton) {
                    e.setIntegerValueField(.mouseEventClickState, value: Int64(n))
                    post(e, flags: flags)
                }
                if n < count { sleepMs(60) }
            }

        case .drag(let fx, let fy, let tx, let ty, let button, let modifiers):
            // A drag is a *stream*, not "down, jump, up". AppKit only starts
            // tracking once it has entered its own mouse-tracking loop and
            // decides what is happening from the events that follow, so this
            // pauses after the press, sends enough intermediate points to look
            // like a real gesture at roughly one step per frame, and pauses
            // before the release. Views that read deltas rather than
            // differencing positions need those fields set too.
            //
            // Honest status: this shape follows how AppKit documents drag
            // tracking. It is **unverified end to end** — see
            // docs/validation.md's "not verified" list. `drag` should be
            // treated as best-effort until a background session exists to
            // verify it in.
            let flags = flags(from: modifiers)
            let (down, up, dragged) = downUpTypes(button.cgButton)
            post(mouseEvent(.mouseMoved, fx, fy, button.cgButton))
            sleepMs(30)
            post(mouseEvent(down, fx, fy, button.cgButton), flags: flags)
            sleepMs(80)
            let steps = 24
            var lastX = fx
            var lastY = fy
            for step in 1...steps {
                let t = Double(step) / Double(steps)
                let x = fx + (tx - fx) * t
                let y = fy + (ty - fy) * t
                if let e = mouseEvent(dragged, x, y, button.cgButton) {
                    e.setDoubleValueField(.mouseEventDeltaX, value: x - lastX)
                    e.setDoubleValueField(.mouseEventDeltaY, value: y - lastY)
                    post(e, flags: flags)
                }
                lastX = x
                lastY = y
                sleepMs(16)
            }
            sleepMs(80)
            post(mouseEvent(up, tx, ty, button.cgButton), flags: flags)

        case .scroll(let x, let y, let dx, let dy):
            if let x, let y { post(mouseEvent(.mouseMoved, x, y, .left)) }
            // wheel1 = vertical, wheel2 = horizontal. `dy` is passed straight
            // through, so positive dy is what a natural trackpad swipe down does.
            post(CGEvent(scrollWheelEvent2Source: nil, units: .line,
                         wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0))

        case .type(let text):
            // One event per **grapheme cluster**, 2 ms apart.
            //
            // Packing several characters into a single
            // `keyboardSetUnicodeString` event is faster and works in an
            // NSTextView, but it is not portable: an app that reads only the
            // first character of the event silently swallows the rest —
            // observed live as "8675309" entering a lone "8". One character per
            // event is what every app handles the same way. Iterating `text`
            // (not `utf16`) keeps an emoji or a combining sequence whole rather
            // than splitting it into surrogate halves.
            for character in text {
                var units = Array(String(character).utf16)
                if let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                    down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
                    post(down)
                }
                if let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                    up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
                    post(up)
                }
                sleepMs(2)
            }

        case .key(let combo):
            switch KeyCombo.parse(combo) {
            case .success(let parsed):
                if let down = CGEvent(keyboardEventSource: nil, virtualKey: parsed.keyCode, keyDown: true) {
                    post(down, flags: parsed.flags)
                }
                if let up = CGEvent(keyboardEventSource: nil, virtualKey: parsed.keyCode, keyDown: false) {
                    post(up, flags: parsed.flags)
                }
            case .failure(let error):
                throw error
            }
        }
    }

    private static func flags(from modifiers: [Modifier]) -> CGEventFlags {
        modifiers.reduce(CGEventFlags()) { $0.union($1.cgFlag) }
    }
}
