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
}
