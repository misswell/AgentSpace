// What do the product's per-window accessibility paths actually answer?
//
// Two of them decide whether a Fusion proxy works at all:
//
//   * `WindowActions.raise` maps a catalog window to exactly one accessibility
//     element (title plus frame within 5 pt) and performs `kAXRaiseAction`, and a
//     refusal there aborts the click that follows it.
//   * `WindowActions.perform(.close)` presses that window's `kAXCloseButtonAttribute`,
//     and `FusionWindowController.windowShouldClose` only lets the proxy close if the
//     worker reports success — so a refusal there is a window that cannot be closed.
//
// This probe repeats those same calls, in the same order, and prints every status code
// — including for the calls that stand in for them (`AXMain`, `AXFocused`, the app's
// `AXFrontmost`), so a refusal can be read as "this app does not implement raise"
// rather than as "input is impossible".
//
//   swiftc -O tests/probes/WindowPathProbe.swift -o /tmp/windowpath \
//     -framework CoreGraphics -framework ApplicationServices -framework AppKit
//   /tmp/windowpath                 # read-only: what matches, which actions each window lists
//   /tmp/windowpath --mutate        # also performs the raise and the attribute writes
//   /tmp/windowpath raise <ID>      # only AXRaise on one window, with the front-to-back order
//   /tmp/windowpath pin <ID>        # only AXMain/AXFocused on one window, same order check
//   /tmp/windowpath close <ID>      # presses that window's close button
//
// Run it as the agent user in the agent session (`agentspace exec <space> …`): the
// accessibility calls are attributed to the trusted worker that spawns it, which is
// the same trust the worker's own paths run under. Both mutating modes really do act,
// so they change what is frontmost — or close — in that session.

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

let mutate = CommandLine.arguments.contains("--mutate")

struct CatalogWindow {
    var id: Int
    var pid: Int
    var owner: String
    var title: String
    var frame: CGRect
}

// `WindowCatalog.parse`, copied as literally as possible: the probe is only evidence
// about the product's failure if it offers the same windows the product offers.
func catalogWindows() -> [CatalogWindow] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let records = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    return records.compactMap { record in
        guard let layer = record[kCGWindowLayer as String] as? Int, layer == 0,
              let alpha = record[kCGWindowAlpha as String] as? Double, alpha > 0,
              let id = record[kCGWindowNumber as String] as? Int,
              let rawPID = record[kCGWindowOwnerPID as String] as? Int,
              let bounds = record[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              rect.width > 40, rect.height > 40
        else { return nil }
        let owner = record[kCGWindowOwnerName as String] as? String ?? "Application"
        let excluded = ["Dock", "Window Server", "WindowServer", "Control Center", "Wallpaper", "AgentSpace"]
        guard !excluded.contains(where: { owner.localizedCaseInsensitiveContains($0) }) else { return nil }
        guard let app = NSRunningApplication(processIdentifier: pid_t(rawPID)),
              app.activationPolicy == .regular else { return nil }
        return CatalogWindow(id: id, pid: rawPID, owner: app.localizedName ?? owner,
                             title: record[kCGWindowName as String] as? String ?? "", frame: rect)
    }
}

func axString(_ element: AXUIElement, _ name: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value as? String
}

func axFrame(_ element: AXUIElement) -> CGRect? {
    var position: CFTypeRef?
    var size: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
          let position, let size,
          CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
    else { return nil }
    var point = CGPoint.zero
    var dimensions = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
          AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
    return CGRect(origin: point, size: dimensions)
}

func actionNames(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
    return (names as? [String]) ?? []
}

/// `WindowActions.matchingAXWindows`, same rule: title equal and frame within 5 pt.
func matchingAXWindows(_ window: CatalogWindow, verbose: Bool) -> [AXUIElement] {
    let application = AXUIElementCreateApplication(pid_t(window.pid))
    var value: CFTypeRef?
    let copyStatus = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
    guard copyStatus == .success, let elements = value as? [AXUIElement] else {
        print("  kAXWindowsAttribute -> \(copyStatus.rawValue) — the product cannot map this window at all")
        return []
    }
    var matches: [AXUIElement] = []
    for element in elements {
        let title = axString(element, kAXTitleAttribute) ?? ""
        guard let frame = axFrame(element) else {
            if verbose { print("    element title=\(title) -> no AXPosition/AXSize") }
            continue
        }
        let matchesGeometry = abs(frame.origin.x - window.frame.origin.x) <= 5
            && abs(frame.origin.y - window.frame.origin.y) <= 5
            && abs(frame.size.width - window.frame.width) <= 5
            && abs(frame.size.height - window.frame.height) <= 5
        let matchesTitle = title == window.title
        if matchesGeometry, matchesTitle { matches.append(element) }
        if verbose {
            print("    element title=\(title.isEmpty ? "<no title>" : title) @ \(Int(frame.origin.x)),\(Int(frame.origin.y))"
                  + " \(Int(frame.width))x\(Int(frame.height))"
                  + " geometry=\(matchesGeometry ? "match" : "no") title=\(matchesTitle ? "match" : "no")"
                  + " actions=[\(actionNames(element).joined(separator: " "))]")
        }
    }
    return matches
}

func report(_ label: String, _ status: AXError) {
    print("  \(label) -> \(status.rawValue)")
}

// `WindowActions.perform(.close)`: read the window's close button and press it.
func closeWindow(_ window: CatalogWindow) {
    print("\n== close win \(window.id) (\(window.owner) — \(window.title)) ==")
    let matches = matchingAXWindows(window, verbose: true)
    print("  matchingAXWindows -> \(matches.count)")
    guard matches.count == 1, let element = matches.first else {
        print("  the product refuses here with \"no/More than one accessibility window matches\"")
        return
    }
    var button: CFTypeRef?
    let readStatus = AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &button)
    report("kAXCloseButtonAttribute", readStatus)
    guard readStatus == .success, let button = button else {
        print("  the product refuses here with \"the remote window has no close action\"")
        return
    }
    let pressed = AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
    report("AXPress on that button", pressed)
    for _ in 0..<10 {
        usleep(200_000)
        let stillThere = catalogWindows().contains { $0.id == window.id }
        if !stillThere {
            print("  CLOSED: win \(window.id) left the on-screen list")
            return
        }
    }
    print("  win \(window.id) is still on screen 2s after the press")
}

/// CG's own front-to-back order. This is the property `raise` exists to establish:
/// a click at a point belongs to the topmost window there, so "main and focused" only
/// counts as a substitute for `AXRaise` if it moves the window up this list.
func cgOrder() -> [Int] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let records = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    return records.compactMap { record in
        guard let layer = record[kCGWindowLayer as String] as? Int, layer == 0,
              let id = record[kCGWindowNumber as String] as? Int else { return nil }
        return id
    }
}

func axWindow(_ window: CatalogWindow) -> AXUIElement? {
    let matches = matchingAXWindows(window, verbose: true)
    print("  matchingAXWindows -> \(matches.count)")
    guard matches.count == 1 else { return nil }
    return matches.first
}

/// `pin`: only the attribute writes, no `AXRaise` — to see whether they move the
/// window up the front-to-back order on their own.
func pinWindow(_ window: CatalogWindow) {
    print("\n== pin win \(window.id) (\(window.owner) — \(window.title)) ==")
    print("  order before: \(cgOrder())")
    guard let element = axWindow(window) else {
        print("  cannot pin")
        return
    }
    report("set AXMain=true", AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue))
    report("set AXFocused=true",
           AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue))
    usleep(400_000)
    print("  order after:  \(cgOrder())  (this window is \(window.id))")
}

/// `raise`: only `AXRaise` — the same measurement for the call the product uses today.
func raiseWindow(_ window: CatalogWindow) {
    print("\n== raise win \(window.id) (\(window.owner) — \(window.title)) ==")
    print("  order before: \(cgOrder())")
    guard let element = axWindow(window) else {
        print("  cannot raise")
        return
    }
    report("AXUIElementPerformAction(kAXRaiseAction)",
           AXUIElementPerformAction(element, kAXRaiseAction as CFString))
    usleep(400_000)
    print("  order after:  \(cgOrder())  (this window is \(window.id))")
}

/// `fix`: the patched `WindowActions.raise`, transcribed literally — `AXRaise`,
/// and only when the app refuses it the main/focused writes, judged afterwards by
/// what the application reports. This measures the sequence the worker now runs on
/// the window that answered -25205, rather than inferring it from the parts.
func fixedRaise(_ window: CatalogWindow) {
    print("\n== shipped raise() sequence, win \(window.id) (\(window.owner) — \(window.title)) ==")
    print("  order before: \(cgOrder())")
    let matches = matchingAXWindows(window, verbose: false)
    guard matches.count == 1, let element = matches.first else {
        print("  VERDICT: REFUSED before AXRaise (\(matches.count) accessibility matches) — same as the product")
        return
    }
    let raiseStatus = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    report("AXUIElementPerformAction(kAXRaiseAction)", raiseStatus)
    if raiseStatus == .success {
        usleep(400_000)
        print("  order after:  \(cgOrder())  (this window is \(window.id))")
        print("  VERDICT: raised by AXRaise; the fallback never ran")
        return
    }
    report("set AXMain=true", AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue))
    report("set AXFocused=true",
           AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue))
    usleep(400_000)
    print("  order after:  \(cgOrder())  (this window is \(window.id))")
    var value: CFTypeRef?
    let readStatus = AXUIElementCopyAttributeValue(
        AXUIElementCreateApplication(pid_t(window.pid)), kAXMainWindowAttribute as CFString, &value)
    print("  copy AXMainWindow -> \(readStatus.rawValue)")
    let isMain = value.map { CFEqual($0, element) } ?? false
    print("  read-back: AXMainWindow is this window = \(isMain)")
    print(isMain
          ? "  VERDICT: the fallback raised it — the product performs the click"
          : "  VERDICT: REFUSED — neither raised nor main, so the product refuses and says so")
}

func resolveTarget(_ windows: [CatalogWindow], _ argument: String?) -> CatalogWindow? {
    guard let id = argument.flatMap(Int.init) else { return nil }
    return windows.first { $0.id == id }
}

let arguments = CommandLine.arguments.dropFirst()
let windows = catalogWindows()

if let mode = arguments.first, mode == "close" || mode == "pin" || mode == "raise" || mode == "fix" {
    let rest = Array(arguments.dropFirst())
    guard let target = resolveTarget(windows, rest.first) else {
        print("no such catalog window: \(rest.first ?? "<no id given>")")
        print("catalog: " + windows.map { "\($0.id)=\($0.owner) \($0.title)" }.joined(separator: " | "))
        exit(2)
    }
    switch mode {
    case "close": closeWindow(target)
    case "pin": pinWindow(target)
    case "fix": fixedRaise(target)
    default: raiseWindow(target)
    }
    exit(0)
}

print(mutate ? "== window paths probe (mutating) ==" : "== window paths probe (read-only) ==")
print("catalog windows (what the Fusion picker offers): \(windows.count)")
for window in windows {
    print("  win \(window.id) pid \(window.pid) \(window.owner) — \(window.title.isEmpty ? "<no title>" : window.title)"
          + " @ \(Int(window.frame.origin.x)),\(Int(window.frame.origin.y))"
          + " \(Int(window.frame.width))x\(Int(window.frame.height))")
}
print("NSWorkspace.frontmostApplication: "
      + (NSWorkspace.shared.frontmostApplication.map { "\($0.processIdentifier) \($0.localizedName ?? "?")" } ?? "nil"))

for window in windows {
    print("\nwin \(window.id) (\(window.owner) — \(window.title))")
    let matches = matchingAXWindows(window, verbose: true)
    print("  matchingAXWindows -> \(matches.count)")
    guard matches.count == 1, let element = matches.first else {
        print("  the product refuses here before reaching AXRaise")
        continue
    }
    guard mutate else {
        print("  (read-only: not performing AXRaise)")
        continue
    }
    report("AXUIElementPerformAction(kAXRaiseAction)",
           AXUIElementPerformAction(element, kAXRaiseAction as CFString))
    report("set AXMain=true", AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue))
    report("set AXFocused=true",
           AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue))
    let application = AXUIElementCreateApplication(pid_t(window.pid))
    var mainRef: CFTypeRef?
    _ = AXUIElementCopyAttributeValue(application, kAXMainWindowAttribute as CFString, &mainRef)
    var focusedRef: CFTypeRef?
    _ = AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focusedRef)
    print("  read-back: AXMainWindow is this window = \(mainRef.map { CFEqual($0, element) } ?? false),"
          + " AXFocusedWindow is this window = \(focusedRef.map { CFEqual($0, element) } ?? false)")
    report("set app AXFrontmost=true",
           AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue))
}
