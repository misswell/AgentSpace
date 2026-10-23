import AppKit
import AgentSpaceCore

/// Turns the person's own key-downs in an agent window into input for the
/// agent's session, and lets the host bridge ⌘V/⌘C.
///
/// The monitor deliberately does **not** read the pasteboard. Two reasons, and
/// both are about what would go wrong if it did: it runs for the Desktop Viewer
/// and for every Fusion proxy alike, so a pasteboard read here would be one
/// place for the two windows to drift apart; and "which keystroke am I?" is a
/// pure question (`ClipboardShortcut.intent`) that can be answered from the
/// event alone, while "what is on the person's clipboard?" is a question with a
/// side effect and belongs to the window that has a place to report it.
///
/// The bridge hook answers one of two things, and the difference is about
/// *when* the keystroke may be sent:
///
/// - `.forward` — send it now, exactly as it has always been sent.
/// - `.deferred` — the host will send this keystroke itself once it has done the
///   clipboard work it needs to do first. The monitor consumes the event so the
///   key cannot also be typed as text or delivered twice.
///
/// A `.deferred` host must send the keystroke on **every** path it takes —
/// success, failure, refusal. That is the whole contract: a bridged paste may
/// not swallow the person's ⌘V.
@MainActor
enum RemoteKeyboardMonitor {
    /// What the host wants done with a clipboard keystroke.
    enum ClipboardHandling {
        /// Send it immediately through the ordinary `send` closure.
        case forward
        /// The host owns the keystroke from here and will send it itself.
        case deferred
    }

    static func install(
        window: NSWindow,
        permitsInput: @escaping () -> Bool,
        clipboard: @escaping (ClipboardShortcut.Intent, InputAction) -> ClipboardHandling = { _, _ in .forward },
        send: @escaping (InputAction) -> Void
    ) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window] event in
            guard let window, event.window === window, permitsInput() else { return event }
            guard let action = KeyboardForwarding.action(
                characters: event.characters,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                command: event.modifierFlags.contains(.command),
                shift: event.modifierFlags.contains(.shift),
                option: event.modifierFlags.contains(.option),
                control: event.modifierFlags.contains(.control)) else { return event }
            // Only a keystroke that has a faithful translation can be bridged:
            // ⌘V and ⌘C are decided from the same fields `KeyboardForwarding` read,
            // so the two can never disagree about which key this is.
            if let intent = ClipboardShortcut.intent(
                characters: event.characters,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                command: event.modifierFlags.contains(.command),
                control: event.modifierFlags.contains(.control)) {
                switch clipboard(intent, action) {
                case .forward: break
                case .deferred: return nil
                }
            }
            send(action)
            return nil
        }
    }
}
