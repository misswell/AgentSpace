import Foundation
import ApplicationServices
import AppKit

/// Minimal Accessibility reader and driver for the session-side GUI check.
///
/// Deliberately **not** the worker's `AccessibilityBridge` and deliberately not
/// System Events:
///
/// - not the bridge, because a bridge call is a wire call, and this program's
///   whole point is to run where the wire is not being asked (it is spawned by
///   the worker's own `exec`, inside the agent account's session);
/// - not System Events, because that does not work there. Measured on
///   2026-09-23 inside the agent session: `osascript` asking System Events for
///   anything answers `-1712 AppleEvent timed out`, while a process spawned the
///   same way reads the tree directly with `AXIsProcessTrusted() == true` —
///   the worker's Accessibility grant is inherited by what it spawns
///   (validation §324 rows 865–866).
///
/// Everything here is bounded: an accessibility tree can be enormous, and a
/// check that hangs is worse than a check that fails.
enum AXUI {

    static let maxDepth = 12
    static let maxNodes = 4000

    // MARK: Reading

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    static func bool(_ element: AXUIElement, _ name: String) -> Bool? {
        (attribute(element, name) as? NSNumber)?.boolValue
    }

    static func double(_ element: AXUIElement, _ name: String) -> Double? {
        (attribute(element, name) as? NSNumber)?.doubleValue
    }

    static func role(_ element: AXUIElement) -> String {
        string(element, kAXRoleAttribute as String) ?? "?"
    }

    static func identifier(_ element: AXUIElement) -> String? {
        string(element, kAXIdentifierAttribute as String)
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    }

    static func app(_ pid: pid_t) -> AXUIElement { AXUIElementCreateApplication(pid) }

    static func windows(_ pid: pid_t) -> [AXUIElement] {
        (attribute(app(pid), kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
    }

    /// The window the app considers front — what a person would call "the
    /// Settings window I just opened". Preferred over guessing by shape, and
    /// checked rather than assumed: the caller falls back to a content test
    /// when an app reports no main window.
    static func mainWindow(_ pid: pid_t) -> AXUIElement? {
        guard let raw = attribute(app(pid), kAXMainWindowAttribute as String) else { return nil }
        return (raw as! AXUIElement)
    }

    /// Every descendant, breadth-first, bounded on depth and count.
    static func descendants(of root: AXUIElement) -> [AXUIElement] {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var found: [AXUIElement] = []
        var visited = 0
        while !queue.isEmpty && found.count < maxNodes {
            let (element, depth) = queue.removeFirst()
            visited += 1
            if visited > maxNodes * 4 { break }
            found.append(element)
            if depth < maxDepth {
                for child in children(element) { queue.append((child, depth + 1)) }
            }
        }
        return found
    }

    /// The element carrying this AXIdentifier, or nil.
    ///
    /// Identifier-only on purpose: it is the one attribute no localization,
    /// no re-layout and no theme touches. The console twin of this check
    /// learned that the hard way twice (§299 rows 639–640, §307 rows 721–722).
    static func find(_ root: AXUIElement, identifier wanted: String) -> AXUIElement? {
        descendants(of: root).first { identifier($0) == wanted }
    }

    static func findAll(_ root: AXUIElement, role wanted: String) -> [AXUIElement] {
        descendants(of: root).filter { role($0) == wanted }
    }

    /// Where the settings tabs live: the window's toolbar buttons, in order.
    ///
    /// The order is a contract this check depends on — Accounts, Permissions,
    /// Performance, Advanced, Update — and it is read rather than hard-coded,
    /// so a sixth tab moves the "last button" checks with it.
    static func toolbarButtons(_ window: AXUIElement) -> [AXUIElement] {
        guard let toolbar = descendants(of: window).first(where: { role($0) == "AXToolbar" }) else {
            return []
        }
        return children(toolbar).filter { role($0) == "AXButton" }
    }

    static func toolbarButtonTitles(_ window: AXUIElement) -> [String] {
        toolbarButtons(window).map { string($0, kAXTitleAttribute as String) ?? "" }
    }

    // MARK: Driving

    @discardableResult
    static func press(_ element: AXUIElement) -> AXError {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    @discardableResult
    static func setValue(_ element: AXUIElement, _ value: String) -> AXError {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFString)
    }

    /// The app's menu item carrying this key equivalent, pressed directly.
    ///
    /// Two measured traps live here. The comparison is case-**insensitive**:
    /// `AXMenuItemCmdChar` reports `N` for 「新建 Agent…」 on this build, and
    /// the console twin only ever matched `n` because AppleScript's `is` folds
    /// case (§324 row 866). And the item is found by its key equivalent rather
    /// than its title, because this machine's menus are Chinese and a title
    /// match would fail in exactly the language it is written for.
    static func menuItem(_ pid: pid_t, cmdChar: String) -> AXUIElement? {
        guard let rawBar = attribute(app(pid), kAXMenuBarAttribute as String) else { return nil }
        let bar = rawBar as! AXUIElement
        for top in children(bar) {
            guard let menu = children(top).first else { continue }
            for item in children(menu) where
                (string(item, "AXMenuItemCmdChar") ?? "").caseInsensitiveCompare(cmdChar) == .orderedSame {
                return item
            }
        }
        return nil
    }

    /// Wait for a menu bar to exist and carry this key equivalent, then press
    /// it. Returns a sentence either way, because "the menu never appeared" and
    /// "the item is not there" want different fixes.
    @discardableResult
    static func pressMenuItem(_ pid: pid_t, cmdChar: String, deadline: TimeInterval = 8) -> String {
        let until = Date().addingTimeInterval(deadline)
        var sawMenuBar = false
        while Date() < until {
            if let rawBar = attribute(app(pid), kAXMenuBarAttribute as String) {
                sawMenuBar = true
                let bar = rawBar as! AXUIElement
                for top in children(bar) {
                    guard let menu = children(top).first else { continue }
                    for item in children(menu) where
                        (string(item, "AXMenuItemCmdChar") ?? "").caseInsensitiveCompare(cmdChar) == .orderedSame {
                        let status = press(item)
                        let title = string(item, kAXTitleAttribute as String) ?? "?"
                        return status == .success ? "pressed ⌘\(cmdChar.uppercased()) (\(title))"
                                                  : "press failed \(status.rawValue) for \(title)"
                    }
                }
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        return sawMenuBar ? "no menu item carries ⌘\(cmdChar.uppercased())"
                          : "the app vended no menu bar within \(Int(deadline))s"
    }

    // MARK: Waiting

    /// Poll until `body` answers something, or the deadline passes. The single
    /// rule this encodes: an accessibility read taken too early is a verifier
    /// defect, not a build defect — a lesson this repository paid for four
    /// times (§307 rows 721–722, §318 rows 816–818).
    static func wait<T>(_ seconds: TimeInterval, _ body: () -> T?) -> T? {
        let until = Date().addingTimeInterval(seconds)
        while Date() < until {
            if let value = body() { return value }
            Thread.sleep(forTimeInterval: 0.4)
        }
        return body()
    }
}

/// Pass/fail counting in the console gate's own shape, so the two gates read
/// alike in a transcript.
final class Report {
    private(set) var passed = 0
    private(set) var failed = 0

    func note(_ text: String) { print("  \(text)") }

    func check(_ name: String, _ expected: String, _ actual: String) {
        if expected == actual {
            passed += 1
            note("ok   \(name)")
        } else {
            failed += 1
            note("FAIL \(name): expected [\(expected)] got [\(actual)]")
        }
    }

    func check(_ name: String, contains needle: String, in haystack: String) {
        if haystack.contains(needle) {
            passed += 1
            note("ok   \(name)")
        } else {
            failed += 1
            note("FAIL \(name): expected to contain [\(needle)] got [\(haystack)]")
        }
    }

    var summary: String { "\(passed) passed, \(failed) failed" }
}
