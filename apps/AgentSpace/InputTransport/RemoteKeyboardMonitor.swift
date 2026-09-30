import AppKit
import AgentSpaceCore

@MainActor
enum RemoteKeyboardMonitor {
    static func install(window: NSWindow, permitsInput: @escaping () -> Bool,
                        send: @escaping (InputAction) -> Void) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window] event in
            guard let window, event.window === window, permitsInput() else { return event }
            guard let action = KeyboardForwarding.action(
                characters: event.characters,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                command: event.modifierFlags.contains(.command),
                shift: event.modifierFlags.contains(.shift),
                option: event.modifierFlags.contains(.option),
                control: event.modifierFlags.contains(.control)) else { return event }
            send(action)
            return nil
        }
    }
}
