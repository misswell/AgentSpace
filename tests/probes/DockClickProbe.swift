// Does a click posted into a session with no frontmost app reach anything?
//
// `Operations.input` refuses every non-`sleep` action when `AppControl.frontmostPID()`
// is nil, on the stated grounds that such an event "would be delivered to nothing".
// On a bare desktop that premise is the whole product: the only way to open an app is
// to click its Dock tile, and the guard refuses that click, so the refusal cannot be
// escaped from the viewer. §315 already proved that a *scroll* event enters a
// background session's stream yet is never dispatched to an app, so "it entered the
// stream" is not evidence here. This probe therefore measures dispatch by consequence:
// click a Dock tile for an app that is not running and look for a new layer-0 window.
//
//   swiftc -O tests/probes/DockClickProbe.swift -o /tmp/dockclick \
//     -framework CoreGraphics -framework ApplicationServices -framework AppKit
//   /tmp/dockclick state                    # read-only: what is frontmost, what is under a point
//   /tmp/dockclick click X Y                # post a real click, then report the window delta
//   /tmp/dockclick launch NAME              # click the Dock tile named NAME, report the delta
//
// Run it *as the agent user, in the agent session* (`agentspace exec <space> …`), the
// same way the worker itself runs — that is what makes the events land in session 503
// rather than on the physical console.
//
// Deliberately does not use `screencapture`: window titles here need Screen Recording,
// which the probe inherits from the worker it was exec'd by, and a probe that quietly
// lost that permission would report an empty Dock rather than an untrusted session.

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

func layerZeroWindows() -> [(id: Int, pid: Int, owner: String, title: String, frame: CGRect)] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let records = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    return records.compactMap { record in
        guard let layer = record[kCGWindowLayer as String] as? Int, layer == 0,
              let id = record[kCGWindowNumber as String] as? Int,
              let pid = record[kCGWindowOwnerPID as String] as? Int,
              let bounds = record[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
        else { return nil }
        return (id, pid,
                record[kCGWindowOwnerName as String] as? String ?? "?",
                record[kCGWindowName as String] as? String ?? "",
                rect)
    }
}

func allWindows() -> [(owner: String, pid: Int, layer: Int, frame: CGRect)] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let records = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    return records.compactMap { record in
        guard let bounds = record[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        return (record[kCGWindowOwnerName as String] as? String ?? "?",
                record[kCGWindowOwnerPID as String] as? Int ?? -1,
                record[kCGWindowLayer as String] as? Int ?? -9999,
                rect)
    }
}

/// The worker's own answer to "is there somewhere for this to land?".
func frontmostPIDWorkerStyle() -> pid_t? {
    for window in layerZeroWindows() where window.owner != "AgentSpace" {
        return pid_t(window.pid)
    }
    return nil
}

func axAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func describe(_ element: AXUIElement?) -> String {
    guard let element else { return "<none>" }
    func string(_ name: String) -> String { (axAttribute(element, name) as? String) ?? "<none>" }
    var position = "<?>", size = "<?>", pid = 0
    if let raw = axAttribute(element, kAXPositionAttribute), CFGetTypeID(raw) == AXValueGetTypeID() {
        var point = CGPoint.zero
        if AXValueGetValue(raw as! AXValue, .cgPoint, &point) { position = "\(Int(point.x)),\(Int(point.y))" }
    }
    if let raw = axAttribute(element, kAXSizeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() {
        var dimensions = CGSize.zero
        if AXValueGetValue(raw as! AXValue, .cgSize, &dimensions) {
            size = "\(Int(dimensions.width))x\(Int(dimensions.height))"
        }
    }
    var rawPid: pid_t = 0
    if AXUIElementGetPid(element, &rawPid) == .success { pid = Int(rawPid) }
    return "\(string(kAXRoleAttribute))/\(string(kAXSubroleAttribute)) title=\(string(kAXTitleAttribute)) "
        + "at \(position) \(size) pid=\(pid) "
        + "app=\(NSRunningApplication(processIdentifier: pid_t(pid))?.localizedName ?? "?")"
}

// The Dock's own tiles, read through accessibility: the position of a tile is the
// point that has to be clicked, and guessing it from the Dock's window bounds is how
// a probe ends up clicking the wallpaper.
func dockTiles() -> [(label: String, center: CGPoint, running: Bool)] {
    guard let dock = NSWorkspace.shared.runningApplications.first(where: {
        $0.localizedName == "Dock" || $0.bundleIdentifier == "com.apple.dock"
    }) else { return [] }
    let application = AXUIElementCreateApplication(dock.processIdentifier)
    var lists: CFTypeRef?
    guard AXUIElementCopyAttributeValue(application, kAXChildrenAttribute as CFString, &lists) == .success,
          let lists = lists as? [AXUIElement] else { return [] }
    var tiles: [(String, CGPoint, Bool)] = []
    for list in lists {
        var items: CFTypeRef?
        guard AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &items) == .success,
              let items = items as? [AXUIElement] else { continue }
        for item in items {
            var label = ""
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &value) == .success,
               let text = value as? String { label = text }
            var position: CFTypeRef?
            var size: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &position) == .success,
                  AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &size) == .success,
                  let position, let size,
                  CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
            else { continue }
            var point = CGPoint.zero
            var dimensions = CGSize.zero
            guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
                  AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { continue }
            tiles.append((label, CGPoint(x: point.x + dimensions.width / 2,
                                         y: point.y + dimensions.height / 2), false))
        }
    }
    let names = Set(NSWorkspace.shared.runningApplications.compactMap { $0.localizedName })
    return tiles.map { ($0.0, $0.1, names.contains($0.0)) }
}

// Mirror `InputSynthesizer`: a move to the point, then down and up with the click
// state set, posted to the session tap.
func postClick(at point: CGPoint) {
    func event(_ type: CGEventType, _ state: Int) {
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type,
                              mouseCursorPosition: point, mouseButton: .left) else {
            print("  ! could not build \(type.rawValue)")
            return
        }
        e.setIntegerValueField(.mouseEventClickState, value: Int64(state))
        e.post(tap: .cgSessionEventTap)
    }
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cgSessionEventTap)
    usleep(80_000)
    event(.leftMouseDown, 1)
    usleep(60_000)
    event(.leftMouseUp, 0)
}

let arguments = CommandLine.arguments
let mode = arguments.count > 1 ? arguments[1] : "state"

switch mode {
case "state":
    print("this pid \(getpid()), session uid \(geteuid())")
    print("NSWorkspace.frontmostApplication: "
          + (NSWorkspace.shared.frontmostApplication.map {
               "\($0.processIdentifier) \($0.localizedName ?? "?")"
             } ?? "nil"))
    print("worker-style frontmostPID(): \(frontmostPIDWorkerStyle().map(String.init) ?? "nil")")
    let zero = layerZeroWindows()
    print("layer-0 windows: \(zero.count)")
    for window in zero {
        print("  win \(window.id) pid \(window.pid) \(window.owner) — \(window.title) @ "
              + "\(Int(window.frame.origin.x)),\(Int(window.frame.origin.y)) "
              + "\(Int(window.frame.width))x\(Int(window.frame.height))")
    }
    let tiles = dockTiles()
    print("Dock tiles read through accessibility: \(tiles.count)")
    for tile in tiles.prefix(40) {
        print("  \(tile.running ? "running" : "stopped") "
              + "\(tile.label.isEmpty ? "<no title>" : tile.label) "
              + "@ \(Int(tile.center.x)),\(Int(tile.center.y))")
    }
    let stoppable = tiles.first { !$0.running && !$0.label.isEmpty }
    if let stoppable {
        var hit: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(), Float(stoppable.center.x), Float(stoppable.center.y), &hit)
        print("hit-test at the stopped tile \u{201C}\(stoppable.label)\u{201D} "
              + "\(Int(stoppable.center.x)),\(Int(stoppable.center.y)) -> \(status.rawValue) "
              + describe(hit))
    }
    for window in allWindows() where window.layer != 0 {
        print(String(format: "  (not a target) layer %d %@ pid %d %.0fx%.0f@%.0f,%.0f",
                     window.layer, window.owner as NSString, window.pid,
                     window.frame.width, window.frame.height,
                     window.frame.origin.x, window.frame.origin.y))
    }

case "launch":
    // By label rather than by coordinate: the Dock is centred, so every tile moves
    // whenever a window is minimized or restored, and a stale x,y clicks a neighbour.
    let label = arguments.dropFirst(2).joined(separator: " ")
    guard let tile = dockTiles().first(where: { $0.label == label }) else {
        print("no Dock tile named \u{201C}\(label)\u{201D}; tiles are: "
              + dockTiles().map(\.label).joined(separator: " | "))
        exit(2)
    }
    print("Dock tile \u{201C}\(label)\u{201D} at \(Int(tile.center.x)),\(Int(tile.center.y)) "
          + (tile.running ? "(already running)" : "(stopped)"))
    let before = Set(layerZeroWindows().map { "\($0.pid):\($0.id)" })
    postClick(at: tile.center)
    for _ in 0..<25 {
        usleep(200_000)
        let appeared = layerZeroWindows().filter { !before.contains("\($0.pid):\($0.id)") }
        if !appeared.isEmpty {
            print("DISPATCHED: " + appeared.map { "win \($0.id) \($0.owner) — \($0.title)" }
                  .joined(separator: "; "))
            exit(0)
        }
    }
    print("NOT DISPATCHED: no new layer-0 window 5s after the click")
    exit(1)

case "click":
    guard arguments.count >= 4, let x = Double(arguments[2]), let y = Double(arguments[3]) else {
        print("usage: dockclick click X Y"); exit(2)
    }
    let point = CGPoint(x: x, y: y)
    print("before: frontmost=\(frontmostPIDWorkerStyle().map(String.init) ?? "nil") "
          + "layer0=\(layerZeroWindows().count)")
    var hit: AXUIElement?
    let hitStatus = AXUIElementCopyElementAtPosition(
        AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit)
    print("hit-test at \(Int(point.x)),\(Int(point.y)) -> \(hitStatus.rawValue) \(describe(hit))")
    let before = Set(layerZeroWindows().map { "\($0.pid):\($0.id)" })
    postClick(at: point)
    print("posted move + down + up at \(Int(point.x)),\(Int(point.y))")
    for _ in 0..<30 {
        usleep(200_000)
        let appeared = layerZeroWindows().filter { !before.contains("\($0.pid):\($0.id)") }
        if !appeared.isEmpty {
            print("DISPATCHED: \(appeared.count) new layer-0 window(s) in 6s")
            for window in appeared {
                print("  win \(window.id) pid \(window.pid) \(window.owner) — \(window.title) "
                      + "\(Int(window.frame.width))x\(Int(window.frame.height))")
            }
            exit(0)
        }
    }
    print("NOT DISPATCHED: no new layer-0 window 6s after the click")
    exit(1)

default:
    print("usage: dockclick [state|click X Y]")
    exit(2)
}
