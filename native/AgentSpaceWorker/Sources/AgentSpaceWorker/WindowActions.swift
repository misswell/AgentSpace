import ApplicationServices
import Foundation
import AgentSpaceCore

enum WindowActions {
    enum Action { case close, minimize }

    /// Bring *this* window forward inside its own application.
    ///
    /// Activating the process only guarantees that the app is frontmost among
    /// apps; which of its windows is key is whatever the app last focused, so
    /// input posted at this window's coordinates can land on a sibling. When the
    /// window cannot be pinned to exactly one accessibility element this refuses
    /// rather than pretending: posting anyway is how a Fusion proxy silently
    /// drives a different window than the one the person is looking at.
    static func raise(window: RemoteWindow) throws {
        guard AccessibilityBridge.trusted() else {
            throw AgentSpaceError(code: .accessibilityDenied, message: "Accessibility is required to raise a window.")
        }
        let matches = matchingAXWindows(window)
        guard matches.count == 1, let element = matches.first else {
            throw AgentSpaceError(
                code: .badRequest,
                message: matches.isEmpty
                    ? "no accessibility window matches window \(window.id), so input could land on another window"
                    : "more than one accessibility window matches window \(window.id), so refusing to guess which one to raise")
        }
        let status = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        guard status == .success else {
            throw AgentSpaceError(
                code: .badRequest,
                message: "macOS refused to raise window \(window.id) (AX error \(status.rawValue)), so input could land on another window")
        }
    }

    static func perform(_ action: Action, window: RemoteWindow) throws {
        guard AccessibilityBridge.trusted() else {
            throw AgentSpaceError(code: .accessibilityDenied, message: "Accessibility is required for window actions.")
        }
        let matches = matchingAXWindows(window)
        guard matches.count == 1, let element = matches.first else {
            throw AgentSpaceError(
                code: .badRequest,
                message: matches.isEmpty
                    ? "no accessibility window matches window \(window.id)"
                    : "more than one accessibility window matches; refusing a destructive guess")
        }

        let status: AXError
        switch action {
        case .close:
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &value) == .success,
                  let button = value else {
                throw AgentSpaceError(code: .badRequest, message: "the remote window has no close action")
            }
            status = AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
        case .minimize:
            status = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        }
        guard status == .success else {
            throw AgentSpaceError(code: .badRequest, message: "macOS refused the requested window action (AX error \(status.rawValue))")
        }
    }

    static func setFrame(_ frame: CGRectValue, window: RemoteWindow) throws {
        guard AccessibilityBridge.trusted() else {
            throw AgentSpaceError(code: .accessibilityDenied, message: "Accessibility is required for window actions.")
        }
        let matches = matchingAXWindows(window)
        guard matches.count == 1, let element = matches.first else {
            throw AgentSpaceError(code: .badRequest, message: "could not map the remote window uniquely")
        }
        var point = CGPoint(x: frame.x, y: frame.y)
        var size = CGSize(width: frame.width, height: frame.height)
        guard let pointValue = AXValueCreate(.cgPoint, &point),
              let sizeValue = AXValueCreate(.cgSize, &size),
              AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, pointValue) == .success,
              AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue) == .success else {
            throw AgentSpaceError(code: .badRequest, message: "macOS refused the requested remote window frame")
        }
    }

    private static func matchingAXWindows(_ remote: RemoteWindow) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(remote.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows.filter { element in
            let title = stringAttribute(element, kAXTitleAttribute)
            guard remote.title == nil || title == remote.title else { return false }
            guard let position = pointAttribute(element, kAXPositionAttribute),
                  let size = sizeAttribute(element, kAXSizeAttribute) else { return false }
            return abs(position.x - remote.frame.x) <= 5
                && abs(position.y - remote.frame.y) <= 5
                && abs(size.width - remote.frame.width) <= 5
                && abs(size.height - remote.frame.height) <= 5
        }
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func pointAttribute(_ element: AXUIElement, _ name: String) -> CGPoint? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(raw as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func sizeAttribute(_ element: AXUIElement, _ name: String) -> CGSize? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(raw as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
}
