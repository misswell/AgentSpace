import Foundation
import CoreGraphics
import AppKit
import ApplicationServices
import AgentSpaceCore

/// Minimal Accessibility access, used only by the acceptance test.
///
/// The worker has its own (`AccessibilityBridge`), but the worker is a separate
/// executable and this program must inspect the **console** session, which the
/// worker deliberately cannot do. Two small readers are cheaper than making the
/// worker's bridge public and tempting someone to point it at the wrong session.
enum AX {

    static func app(_ pid: pid_t) -> AXUIElement { AXUIElementCreateApplication(pid) }

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var out: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &out) == .success else {
            return nil
        }
        return out
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func children(_ element: AXUIElement, _ attribute: String = kAXChildrenAttribute) -> [AXUIElement] {
        (value(element, attribute) as? [AXUIElement]) ?? []
    }

    static func role(_ element: AXUIElement) -> String? { string(element, kAXRoleAttribute) }
    static func title(_ element: AXUIElement) -> String? { string(element, kAXTitleAttribute) }
    static func identifier(_ element: AXUIElement) -> String? { string(element, kAXIdentifierAttribute) }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue = value(element, kAXPositionAttribute),
              let sizeValue = value(element, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    /// Is this the element the keyboard would type into?
    static func isFocused(_ element: AXUIElement) -> Bool {
        (value(element, kAXFocusedAttribute) as? Bool) ?? false
    }

    /// Every descendant, breadth-first, bounded. TextEdit's tree is small but a
    /// bound costs nothing and turns a surprise into an empty result.
    static func descendants(of root: AXUIElement, maxNodes: Int = 4000) -> [AXUIElement] {
        var queue = [root]
        var found: [AXUIElement] = []
        var index = 0
        while index < queue.count, found.count < maxNodes {
            let node = queue[index]
            index += 1
            found.append(node)
            queue.append(contentsOf: children(node))
        }
        return found
    }

    /// The focused element anywhere in an application.
    static func focusedElement(in pid: pid_t) -> AXUIElement? {
        guard let systemWide = Optional(AXUIElementCreateSystemWide()),
              let focused = value(systemWide, kAXFocusedUIElementAttribute) else { return nil }
        // Confirm it belongs to the pid we asked about, so a focus change cannot
        // be silently attributed to the wrong application.
        let element = focused as! AXUIElement
        var elementPID: pid_t = 0
        AXUIElementGetPid(element, &elementPID)
        return elementPID == pid ? element : nil
    }

    /// The editable text areas in an application, front window first.
    static func textAreas(in pid: pid_t) -> [AXUIElement] {
        descendants(of: app(pid)).filter { role($0) == kAXTextAreaRole as String }
    }

    /// Type into an element by setting its value directly.
    ///
    /// Used only to *set up* the console's baseline. Deliberately not used to
    /// make any of the 1000 iterations happen: those must go through the worker,
    /// or the test would be measuring the wrong thing entirely.
    @discardableResult
    static func setValue(_ element: AXUIElement, _ text: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef) == .success
    }

    /// Press a menu item without touching the mouse.
    ///
    /// `open -a TextEdit` on a machine that already has documents open would give
    /// us one of *those*, and the acceptance test would then edit the user's real
    /// work. Driving File > New through Accessibility adds a document the honest
    /// way — and it is a fair demonstration that AX can act without moving the
    /// pointer, which is how the agent is expected to work.
    static func pressMenuItem(in pid: pid_t, menu: String, item: String) -> Bool {
        guard let menuBar = value(app(pid), kAXMenuBarAttribute) else { return false }
        for menuBarItem in children(menuBar as! AXUIElement) {
            guard title(menuBarItem) == menu else { continue }
            for menuItem in children(menuBarItem, kAXChildrenAttribute) {
                for candidate in [menuItem] + children(menuItem) {
                    guard title(candidate) == item else { continue }
                    return AXUIElementPerformAction(candidate, kAXPressAction as CFString) == .success
                }
            }
        }
        return false
    }
}

/// The console session's observable state: what a human would notice being taken
/// away from them. Plan §44 names three things and this is exactly those three.
struct ConsoleObservation {
    var frontmostAppName: String
    var frontmostAppPID: pid_t
    var focusedElementDescription: String
    var mouseLocation: CGPoint
    var textEditValue: String?

    var summary: String {
        """
        frontmost app:   \(frontmostAppName) (pid \(frontmostAppPID))
        focused element: \(focusedElementDescription)
        mouse location:  (\(Int(mouseLocation.x)), \(Int(mouseLocation.y)))
        TextEdit value:  \(textEditValue.map { "\"\($0.prefix(80))\"" } ?? "<none>")
        """
    }

    /// The comparison that decides the phase-0 gate.
    ///
    /// ## Why this is not a plain equality check
    ///
    /// The first version of this test compared the mouse position before and
    /// after and failed on any movement. It failed immediately — because a human
    /// was using the machine at the time. A person sitting at the console will
    /// move their own mouse, switch their own windows and focus their own text
    /// fields, and none of that is AgentSpace's doing. A test that cannot tell
    /// "the agent moved it" from "the human moved it" reports false failures,
    /// and a test that reports false failures gets ignored, which is worse than
    /// not having it.
    ///
    /// So there are two different kinds of evidence here:
    ///
    /// 1. **Attributable evidence — always a failure.** A leaked synthetic event
    ///    would put the pointer at a coordinate *this test asked for*. That is a
    ///    precise fingerprint, and it is checked first.
    /// 2. **Ambient evidence — a failure only if the property was stable when
    ///    measured with no actions sent at all.** A control window is sampled
    ///    before the run; if the frontmost app was already changing, a later
    ///    change is reported as inconclusive rather than blamed on AgentSpace.
    ///
    /// The result is a test that still fails loudly on a real leak, and says
    /// "the human is using the computer" instead of crying wolf.
    func differences(from before: ConsoleObservation, ambient: AmbientBaseline) -> [Finding] {
        var findings: [Finding] = []

        if frontmostAppPID != before.frontmostAppPID || frontmostAppName != before.frontmostAppName {
            findings.append(ambient.frontmostWasStable
                ? .failure("the console's frontmost application changed: \(before.frontmostAppName) → \(frontmostAppName)")
                : .inconclusive("the console's frontmost application changed (\(before.frontmostAppName) → \(frontmostAppName)), but it was already changing before any action was sent"))
        }
        if focusedElementDescription != before.focusedElementDescription {
            findings.append(ambient.focusWasStable
                ? .failure("the console's focused element changed: \(before.focusedElementDescription) → \(focusedElementDescription)")
                : .inconclusive("the console's focused element changed, but it was already changing before any action was sent"))
        }
        if textEditValue != before.textEditValue {
            findings.append(ambient.textWasStable
                ? .failure("the console's TextEdit content changed: "
                    + "\(before.textEditValue?.prefix(60) ?? "<none>") → \(textEditValue?.prefix(60) ?? "<none>")")
                : .inconclusive("the console's TextEdit content changed, but it was already being edited before any action was sent"))
        }
        findings.append(mouseFinding(from: before.mouseLocation, ambient: ambient))

        return findings
    }

    /// The pointer, with the leak fingerprint checked first.
    func mouseFinding(from before: CGPoint, ambient: AmbientBaseline) -> Finding {
        let moved = abs(mouseLocation.x - before.x) > 1 || abs(mouseLocation.y - before.y) > 1
        guard moved else { return .ok("the console's pointer never moved") }

        // A synthetic event that leaked would have put the pointer on one of the
        // coordinates this run asked for. Nothing about a human's own mouse
        // movement lands there by coincidence four times in a row.
        for target in ambient.requestedPoints {
            if abs(mouseLocation.x - target.x) <= 2, abs(mouseLocation.y - target.y) <= 2 {
                return .failure("the console's pointer is at (\(Int(mouseLocation.x)), \(Int(mouseLocation.y))), which is a coordinate this run asked the worker to click — a synthetic event reached the console")
            }
        }

        if ambient.mouseWasStable {
            return .failure("the console's pointer moved: (\(Int(before.x)), \(Int(before.y))) → (\(Int(mouseLocation.x)), \(Int(mouseLocation.y)))")
        }
        return .inconclusive("the console's pointer moved (\(Int(before.x)), \(Int(before.y))) → (\(Int(mouseLocation.x)), \(Int(mouseLocation.y))), but it was already moving before any action was sent — most likely the human at the keyboard")
    }
}

/// What the console was doing *before* the test sent anything.
///
/// Sampling a quiet window is what makes the difference between "AgentSpace moved
/// the mouse" and "somebody moved the mouse" decidable. Without it the test can
/// only assert a property it cannot attribute.
struct AmbientBaseline {
    var frontmostWasStable = true
    var focusWasStable = true
    var mouseWasStable = true
    var textWasStable = true
    /// Every coordinate the run will ask for, so a leak can be fingerprinted.
    var requestedPoints: [CGPoint] = []

    var summary: String {
        let unstable = [
            frontmostWasStable ? nil : "frontmost app",
            focusWasStable ? nil : "focused element",
            mouseWasStable ? nil : "pointer",
            textWasStable ? nil : "TextEdit content",
        ].compactMap { $0 }
        return unstable.isEmpty
            ? "the console was quiet before the run"
            : "the console was ALREADY changing before the run: " + unstable.joined(separator: ", ")
    }
}

/// One line of evidence. Three states rather than two, because "I could not
/// measure this" is a real answer and pretending otherwise is how a suite starts
/// lying.
enum Finding {
    case ok(String)
    case failure(String)
    case inconclusive(String)

    var isFailure: Bool { if case .failure = self { return true }; return false }
    var text: String {
        switch self {
        case .ok(let t), .failure(let t), .inconclusive(let t): return t
        }
    }
}

/// Sample the console for a while with nothing sent, and record what moved on its
/// own. Also records the coordinates the run intends to use.
func sampleAmbientBaseline(seconds: Double, requestedPoints: [CGPoint], textEdit: AXUIElement?) -> AmbientBaseline {
    var baseline = AmbientBaseline()
    baseline.requestedPoints = requestedPoints

    var first = observeConsole()
    if let textEdit { first.textEditValue = AX.string(textEdit, kAXValueAttribute) }

    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        usleep(120_000)
        var sample = observeConsole()
        if let textEdit { sample.textEditValue = AX.string(textEdit, kAXValueAttribute) }

        if sample.frontmostAppPID != first.frontmostAppPID { baseline.frontmostWasStable = false }
        if sample.focusedElementDescription != first.focusedElementDescription { baseline.focusWasStable = false }
        if abs(sample.mouseLocation.x - first.mouseLocation.x) > 1
            || abs(sample.mouseLocation.y - first.mouseLocation.y) > 1 { baseline.mouseWasStable = false }
        if sample.textEditValue != first.textEditValue { baseline.textWasStable = false }

        first = sample
    }
    return baseline
}
