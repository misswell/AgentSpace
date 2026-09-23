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
    /// window cannot be pinned to a *unique* accessibility element this refuses
    /// rather than pretending: posting anyway is how a Fusion proxy silently
    /// drives a different window than the one the person is looking at.
    ///
    /// Raising is not destructive — a raise that lands on a sibling is a visible
    /// mis-click, not a lost document — so it accepts a clearly-best candidate
    /// rather than demanding an exact match. That distinction is what §328 row
    /// 901 left open: the old exact rule refused the windows a live test offered
    /// it, and refusing everything safe is not the same as being careful.
    static func raise(window: RemoteWindow) throws {
        guard AccessibilityBridge.trusted() else {
            throw AgentSpaceError(code: .accessibilityDenied, message: "Accessibility is required to raise a window.")
        }
        let element = try resolve(window, strict: false)
        // `AXRaise` is the action for this, but an app may advertise it and still
        // refuse it: measured on System Settings, whose own window lists `AXRaise` in
        // its action names and answers -25205 (AttributeUnsupported) when performed,
        // while Safari's answers 0. Making the window main and focused moves it up the
        // front-to-back order identically: on four Safari windows, raising the back
        // one and writing main+focused to it both took [2027,2022,2019,2013] to
        // [2019,2013,2027,2022] (§322 row 844), so the writes are tried before the
        // click that depends on this window being above its siblings is refused.
        if AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success { return }
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        // Judged by what the app now reports, not by the status of the write: an app
        // can accept the assignment and put the focus somewhere else, and then input
        // really would land on a sibling.
        guard isMainWindow(window, element: element) else {
            throw AgentSpaceError(
                code: .badRequest,
                message: "window \(window.id) would neither raise nor become the app's main window, so input could land on another window")
        }
    }

    /// Does the application say *this* window is its main one?
    private static func isMainWindow(_ window: RemoteWindow, element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            AXUIElementCreateApplication(window.pid), kAXMainWindowAttribute as CFString, &value) == .success,
              let value else { return false }
        return CFEqual(value, element)
    }

    /// Close or minimize the remote window.
    ///
    /// **Strict on purpose.** A pointer event that lands on the wrong window is a
    /// mis-click; closing a window has no undo. So this keeps the exact
    /// requirement — a unique match with an agreeing title and frame — while
    /// pointer input and raising accept a clearly-best candidate.
    static func perform(_ action: Action, window: RemoteWindow) throws {
        guard AccessibilityBridge.trusted() else {
            throw AgentSpaceError(code: .accessibilityDenied, message: "Accessibility is required for window actions.")
        }
        let element = try resolve(window, strict: true)

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
        // A resize is as consequential as a close for the app being driven, but
        // it is also the action a person reaches for while working, so it takes
        // the strict path: a resize that moved the wrong window is a window the
        // person has to repair by hand.
        let element = try resolve(window, strict: true)
        var point = CGPoint(x: frame.x, y: frame.y)
        var size = CGSize(width: frame.width, height: frame.height)
        guard let pointValue = AXValueCreate(.cgPoint, &point),
              let sizeValue = AXValueCreate(.cgSize, &size),
              AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, pointValue) == .success,
              AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue) == .success else {
            throw AgentSpaceError(code: .badRequest, message: "macOS refused the requested remote window frame")
        }
    }

    /// The one accessibility window a remote window maps onto.
    ///
    /// Every window of that pid is observed, Core's `WindowElementMatcher`
    /// scores them, and the verdict is either one index or a refusal with the
    /// reason attached. The *observation* is this file's job — it is the part
    /// that needs Accessibility — and the arithmetic is Core's, so the rule is
    /// testable with three rectangles and no WindowServer.
    private static func resolve(_ remote: RemoteWindow, strict: Bool) throws -> AXUIElement {
        let windows = accessibilityWindows(remote.pid)
        let observations = windows.enumerated().map { index, element in
            WindowElementMatcher.Observation(
                title: stringAttribute(element, kAXTitleAttribute),
                frame: frameAttribute(element),
                zIndex: index, totalCount: windows.count)
        }
        switch WindowElementMatcher.decide(observations, matches: remote, strict: strict) {
        case .matched(let index, _):
            return windows[index]
        case .refused(let reason):
            throw AgentSpaceError(code: .invalidTarget, message: describe(reason, window: remote, strict: strict))
        }
    }

    private static func describe(_ reason: WindowElementMatcher.Decision.Reason,
                                 window: RemoteWindow, strict: Bool) -> String {
        switch reason {
        case .noCandidates:
            return "no accessibility window belongs to pid \(window.pid), so window \(window.id) cannot be addressed. The app may not be responding to Accessibility."
        case .belowFloor(_, _, let reasons):
            let detail = reasons.isEmpty ? "no distinguishing evidence" : reasons.joined(separator: ", ")
            return "window \(window.id) could not be identified in pid \(window.pid) with enough confidence (\(detail))"
        case .ambiguous(let best, let runnerUp):
            return String(format: "two accessibility windows of pid %d are equally plausible for window %d (scores %.2f and %.2f); refusing to %@",
                          window.pid, Int(window.id), best, runnerUp,
                          strict ? "act destructively on a guess" : "guess which one the person is looking at")
        }
    }

    private static func accessibilityWindows(_ pid: Int32) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows
    }

    private static func frameAttribute(_ element: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(element, kAXPositionAttribute),
              let size = sizeAttribute(element, kAXSizeAttribute) else { return nil }
        return CGRect(origin: position, size: size)
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
