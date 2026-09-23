import Foundation
import ApplicationServices
import AppKit
import AgentSpaceCore

/// Accessibility-tree access. Plan §18.
///
/// The point is to let an agent find a control by *name* instead of guessing at
/// pixels. Visual grounding stays available and is not replaced — the two are
/// complementary, and the plan keeps both.
///
/// Every call is depth- and count-bounded. An accessibility tree can be
/// enormous (a browser window is tens of thousands of nodes) and walking it
/// unbounded would wedge the worker.
enum AccessibilityBridge {

    static let maxDepth = 12
    static let maxNodes = 2000
    static let defaultTimeout: Float = 2.0

    static func trusted() -> Bool { AXIsProcessTrusted() }

    static func requireTrust() throws {
        guard trusted() else {
            throw AgentSpaceError(
                code: .accessibilityDenied,
                message: "Accessibility is not granted to agentspace-worker in this session, so no accessibility tree can be read.")
        }
    }

    // MARK: Attribute helpers

    static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value
    }

    static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        copyAttribute(element, attribute) as? String
    }

    static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        (copyAttribute(element, attribute) as? NSNumber)?.boolValue
    }

    static func intAttribute(_ element: AXUIElement, _ attribute: String) -> Int? {
        (copyAttribute(element, attribute) as? NSNumber)?.intValue
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        guard let raw = copyAttribute(element, kAXChildrenAttribute as String) else { return [] }
        guard let array = raw as? [AXUIElement] else { return [] }
        return array
    }

    static func appElement(pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    /// The deepest element under a global screen point (plan §18's
    /// `ax.elementAt`). Hit-testing runs on the system-wide element, whose
    /// coordinate space is the same top-left point space AgentSpace's input
    /// API uses — the coordinates an agent read off a screenshot are the
    /// coordinates this call takes, no conversion.
    static func elementAt(x: Float, y: Float) throws -> (element: AXUIElement, pid: pid_t) {
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(), x, y, &element)
        guard result == .success, let hit = element else {
            throw AgentSpaceError(
                code: .noInputTarget,
                message: "no accessibility element at (\(x), \(y)); the point may be outside any window, or on the desktop wallpaper.")
        }
        var pid: pid_t = 0
        AXUIElementGetPid(hit, &pid)
        return (hit, pid)
    }

    /// The element's frame in the AX coordinate space (origin top-left, which
    /// matches AgentSpace's point space, so no flip is needed).
    static func frame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        // Force-cast is safe after the type-id check above.
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    /// Is this element interesting enough to report? Without a filter, a
    /// snapshot of a browser is a wall of unlabelled groups.
    static func isInteresting(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(element, kAXRoleAttribute as String) ?? ""
        let interestingRoles: Set<String> = [
            "AXButton", "AXCheckBox", "AXRadioButton", "AXTextField", "AXTextArea",
            "AXStaticText", "AXMenuItem", "AXMenuBarItem", "AXPopUpButton",
            "AXComboBox", "AXSlider", "AXTab", "AXLink", "AXImage", "AXCell",
            "AXRow", "AXOutline", "AXTable", "AXWindow", "AXSheet", "AXDialog",
            "AXToolbar", "AXDisclosureTriangle", "AXSegmentedControl", "AXProgressIndicator",
            "AXScrollArea", "AXWebArea", "AXHeading", "AXList", "AXToggle",
        ]
        if interestingRoles.contains(role) { return true }
        // Anything the app gave a title, description or value to is meaningful.
        if stringAttribute(element, kAXTitleAttribute as String)?.isEmpty == false { return true }
        if stringAttribute(element, kAXDescriptionAttribute as String)?.isEmpty == false { return true }
        if stringAttribute(element, kAXValueAttribute as String)?.isEmpty == false { return true }
        return false
    }

    static func describe(_ element: AXUIElement, depth: Int) -> JSONValue {
        var object: [String: JSONValue] = [:]
        if let role = stringAttribute(element, kAXRoleAttribute as String) { object["role"] = .string(role) }
        if let subrole = stringAttribute(element, kAXSubroleAttribute as String) { object["subrole"] = .string(subrole) }
        if let title = stringAttribute(element, kAXTitleAttribute as String), !title.isEmpty {
            object["title"] = .string(title)
        }
        if let description = stringAttribute(element, kAXDescriptionAttribute as String), !description.isEmpty {
            object["description"] = .string(description)
        }
        if let value = stringAttribute(element, kAXValueAttribute as String), !value.isEmpty {
            // Values can hold typed text; cap and never log them (plan §37).
            object["value"] = .string(String(value.prefix(500)))
        }
        // Numeric values — a scroll bar's position, a slider's setting, a
        // progress indicator. They used to be dropped: `describe` kept a value
        // only when it was a String, which made "did that scroll move anything?"
        // unanswerable through the wire and left `AXMinValue`/`AXMaxValue`
        // invisible to every caller. Additive at protocol version 1: a client
        // that does not know the key ignores it.
        if let raw = copyAttribute(element, kAXValueAttribute as String),
           let number = raw as? NSNumber,
           CFGetTypeID(raw) != CFBooleanGetTypeID() {
            object["numberValue"] = .double(number.doubleValue)
        }
        if let identifier = stringAttribute(element, kAXIdentifierAttribute as String), !identifier.isEmpty {
            object["identifier"] = .string(identifier)
        }
        if let enabled = boolAttribute(element, kAXEnabledAttribute as String) { object["enabled"] = .bool(enabled) }
        if let focused = boolAttribute(element, kAXFocusedAttribute as String) { object["focused"] = .bool(focused) }
        if let frame = frame(element) {
            object["frame"] = .obj([
                "x": .double(Double(frame.origin.x)),
                "y": .double(Double(frame.origin.y)),
                "width": .double(Double(frame.size.width)),
                "height": .double(Double(frame.size.height)),
                "centerX": .double(Double(frame.midX)),
                "centerY": .double(Double(frame.midY)),
            ])
        }
        if let actions = actionNames(element), !actions.isEmpty {
            object["actions"] = .array(actions.map { .string($0) })
        }
        if depth > 0 { object["depth"] = .int(depth) }
        return .object(object)
    }

    static func actionNames(_ element: AXUIElement) -> [String]? {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return nil }
        return names as? [String]
    }

    // MARK: Snapshot

    /// Walk the tree, breadth-first, bounded on both depth and node count.
    static func snapshot(
        pid: pid_t,
        maxDepth limit: Int = AccessibilityBridge.maxDepth,
        maxNodes nodeLimit: Int = AccessibilityBridge.maxNodes,
        interestingOnly: Bool = true
    ) -> JSONValue {
        let root = appElement(pid: pid)
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var nodes: [JSONValue] = []
        var visited = 0

        while !queue.isEmpty && nodes.count < nodeLimit {
            let (element, depth) = queue.removeFirst()
            visited += 1
            if visited > nodeLimit * 4 { break }

            let include = !interestingOnly || isInteresting(element)
            if include {
                nodes.append(describe(element, depth: depth))
            }
            if depth < limit {
                for child in children(element) {
                    queue.append((child, depth + 1))
                }
            }
        }

        return .obj([
            "pid": .int(Int(pid)),
            "app": .string(NSRunningApplication(processIdentifier: pid)?.localizedName ?? "unknown"),
            "nodeCount": .int(nodes.count),
            "truncated": .bool(nodes.count >= nodeLimit),
            "nodes": .array(nodes),
        ])
    }

    /// Window list for a pid, straight from the accessibility API rather than
    /// the window server, so it carries titles.
    static func windows(pid: pid_t) -> JSONValue {
        let app = appElement(pid: pid)
        guard let raw = copyAttribute(app, kAXWindowsAttribute as String) as? [AXUIElement] else {
            return .obj(["pid": .int(Int(pid)), "windows": .array([])])
        }
        let described = raw.map { describe($0, depth: 0) }
        return .obj([
            "pid": .int(Int(pid)),
            "count": .int(described.count),
            "windows": .array(described),
        ])
    }

    /// Find an element by predicate: role and/or a title substring.
    ///
    /// This is the "look at the tree, find the Button, click it" path from the
    /// plan. Searching is bounded exactly like `snapshot`.
    static func find(
        pid: pid_t,
        role: String?,
        titleContains: String?,
        identifier: String?,
        maxNodes nodeLimit: Int = AccessibilityBridge.maxNodes
    ) -> AXUIElement? {
        let root = appElement(pid: pid)
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while !queue.isEmpty {
            let (element, depth) = queue.removeFirst()
            visited += 1
            if visited > nodeLimit * 4 { return nil }

            var matches = true
            if let role, stringAttribute(element, kAXRoleAttribute as String) != role { matches = false }
            if matches, let identifier,
               stringAttribute(element, kAXIdentifierAttribute as String) != identifier { matches = false }
            if matches, let titleContains {
                let title = stringAttribute(element, kAXTitleAttribute as String) ?? ""
                let description = stringAttribute(element, kAXDescriptionAttribute as String) ?? ""
                let value = stringAttribute(element, kAXValueAttribute as String) ?? ""
                let haystack = (title + "\u{1}" + description + "\u{1}" + value).lowercased()
                if !haystack.contains(titleContains.lowercased()) { matches = false }
            }
            if matches && (role != nil || titleContains != nil || identifier != nil) {
                return element
            }
            if depth < maxDepth {
                for child in children(element) { queue.append((child, depth + 1)) }
            }
        }
        return nil
    }

    /// Perform an accessibility action (e.g. `AXPress`) directly, bypassing
    /// synthetic mouse events entirely. More reliable than a click on a control
    /// that is off-screen or behind a sheet.
    static func perform(
        pid: pid_t,
        action: String,
        role: String?,
        titleContains: String?,
        identifier: String?
    ) throws -> JSONValue {
        try requireTrust()
        guard let element = find(pid: pid, role: role, titleContains: titleContains, identifier: identifier) else {
            throw AgentSpaceError(
                code: .appNotFound,
                message: "no accessibility element matched role=\(role ?? "*") title~=\(titleContains ?? "*") identifier=\(identifier ?? "*") in pid \(pid)")
        }
        var resolvedAction = action
        if !resolvedAction.hasPrefix("AX") { resolvedAction = "AX" + resolvedAction.capitalized }
        let status = AXUIElementPerformAction(element, resolvedAction as CFString)
        guard status == .success else {
            let available = actionNames(element)?.joined(separator: ", ") ?? "none"
            throw AgentSpaceError(
                code: .invalidAction,
                message: "AXUIElementPerformAction(\(resolvedAction)) failed with \(status.rawValue). Actions this element supports: \(available).")
        }
        return .obj([
            "performed": .string(resolvedAction),
            "element": describe(element, depth: 0),
        ])
    }

    /// Click an element via its accessibility frame center, using the same
    /// session event tap as everything else.
    static func clickElement(
        pid: pid_t,
        role: String?,
        titleContains: String?,
        identifier: String?
    ) throws -> JSONValue {
        try requireTrust()
        guard let element = find(pid: pid, role: role, titleContains: titleContains, identifier: identifier) else {
            throw AgentSpaceError(
                code: .appNotFound,
                message: "no accessibility element matched the given predicate in pid \(pid)")
        }
        guard let frame = frame(element) else {
            throw AgentSpaceError(
                code: .invalidCoordinate,
                message: "the matched element reports no frame, so it cannot be clicked by coordinate. Try ax.perform with AXPress.")
        }
        let point = (x: Double(frame.midX), y: Double(frame.midY))
        if let error = CoordinateRules.validate(x: point.x, y: point.y, geometry: nil) { throw error }
        try InputSynthesizer.perform(.click(x: point.x, y: point.y, button: .left, count: 1, modifiers: []))
        return .obj([
            "clicked": describe(element, depth: 0),
            "point": .obj(["x": .double(point.x), "y": .double(point.y)]),
        ])
    }

    // MARK: Scrolling

    /// Move the scroll bar of the scroll area under a point.
    ///
    /// A wheel event posted into a session that is not on the console does
    /// enter that session's event stream — a listen-only tap sees every field
    /// of it — but the window server never dispatches it to an app. Measured
    /// across eight event shapes, with `CGWarpMouseCursorPosition` confirming
    /// the cursor really was over the content: zero pixels moved, while a key
    /// press in the same window moved 59,576. The scroll bar is the channel
    /// that does work in a background session, so scroll drives it directly.
    ///
    /// `false` means "this place cannot be scrolled through accessibility" —
    /// the point is outside any scroll area, or the area reports nothing to
    /// scroll — and the caller still posts the wheel event, which is the path
    /// that works when the agent session *is* the console.
    static func scrollArea(atX x: Double, y: Double, linesX: Int, linesY: Int) -> Bool {
        guard AXIsProcessTrusted(),
              let area = scrollArea(under: x, y: y),
              let viewport = frame(area)?.size,
              let content = sizeAttribute(area, "AXContentSize")
        else { return false }
        var moved = false
        if linesY != 0 {
            moved = scroll(barOf: area, named: "AXVerticalScrollBar", lines: Double(linesY),
                           viewport: Double(viewport.height), content: Double(content.height)) || moved
        }
        if linesX != 0 {
            moved = scroll(barOf: area, named: "AXHorizontalScrollBar", lines: Double(linesX),
                           viewport: Double(viewport.width), content: Double(content.width)) || moved
        }
        return moved
    }

    /// The scroll area a point lands in — by hit-test if that works, by geometry
    /// if it does not.
    ///
    /// The hit-test route alone was not enough, and the way it fails is silent:
    /// in a background Aqua session `AXUIElementCopyElementAtPosition` returns
    /// the **AXApplication** element instead of the content under the point
    /// (measured on macOS 27.0 for both TextEdit and Finder), so walking up from
    /// it never reaches a scroll area, and every anchored `scroll` degraded to
    /// the wheel post that this same file documents as reaching nothing. The
    /// report a person sees is 「那个点什么都没滚动」 from `agentspace scroll`,
    /// which is honest but is not what they asked for.
    ///
    /// The fallback uses a hit-test that *does* work in that session: the window
    /// server says which window owns the point, and that window's own
    /// accessibility tree is then searched for the scroll area whose frame
    /// contains it. One more step, only when the cheap route fails, and it is
    /// what makes a Fusion/Desktop scroll work in an agent session at all.
    private static func scrollArea(under x: Double, y: Double) -> AXUIElement? {
        if let hit = try? elementAt(x: Float(x), y: Float(y)).element,
           let area = scrollArea(ancestorOf: hit) {
            return area
        }
        guard let pid = windowOwner(atX: x, y: y) else { return nil }
        for window in windows(of: pid) {
            for candidate in descendants(of: window, maxNodes: 600) {
                guard stringAttribute(candidate, kAXRoleAttribute as String) == "AXScrollArea",
                      let frame = frame(candidate),
                      frame.contains(CGPoint(x: x, y: y)) else { continue }
                return candidate
            }
        }
        return nil
    }

    /// The pid owning the topmost layer-0 window that contains this point — the
    /// same window-server hit-test the pointer input path relies on, which is
    /// why it works where the accessibility one does not.
    private static func windowOwner(atX x: Double, y: Double) -> pid_t? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let point = CGPoint(x: x, y: y)
        for entry in list {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { continue }
            if rect.contains(point) { return pid }
        }
        return nil
    }

    private static func windows(of pid: pid_t) -> [AXUIElement] {
        (copyAttribute(appElement(pid: pid), kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
    }

    /// Breadth-first, bounded. A browser's tree is tens of thousands of nodes and
    /// this walk exists to find one element.
    private static func descendants(of root: AXUIElement, maxNodes: Int) -> [AXUIElement] {
        var queue = [root]
        var found: [AXUIElement] = []
        var index = 0
        while index < queue.count && found.count < maxNodes {
            let node = queue[index]
            index += 1
            found.append(node)
            queue.append(contentsOf: children(node))
        }
        return found
    }

    private static func scroll(barOf area: AXUIElement, named attribute: String,
                               lines: Double, viewport: Double, content: Double) -> Bool {
        guard let bar = copyAttribute(area, attribute) as! AXUIElement?,
              let current = (copyAttribute(bar, kAXValueAttribute as String) as? NSNumber)?.doubleValue,
              let target = ScrollMechanics.value(current: current, lines: lines,
                                                 viewport: viewport, content: content),
              target != current
        else { return false }
        return AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString,
                                            NSNumber(value: target)) == .success
    }

    /// The nearest ancestor that actually scrolls, which is where the wheel
    /// event would have landed. Text views, browser lists and web content all
    /// sit inside one; a hit on the window frame or the wallpaper has none.
    private static func scrollArea(ancestorOf element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<12 {
            guard let candidate = current else { return nil }
            if stringAttribute(candidate, kAXRoleAttribute as String) == "AXScrollArea" { return candidate }
            current = copyAttribute(candidate, kAXParentAttribute as String) as! AXUIElement?
        }
        return nil
    }

    private static func sizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = copyAttribute(element, attribute),
              CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetType(value as! AXValue) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
}
