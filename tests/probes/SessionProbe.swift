// Minimal probe: verify by execution, not by documentation, what the session
// and permission APIs actually report on this machine. Run it in the console
// session and once more inside a background AgentSpace session; the diff
// between the two runs is the evidence docs/validation.md cites.
//
//   swiftc -O -o /tmp/agentspace-probe tests/probes/SessionProbe.swift \
//     -framework CoreGraphics -framework AppKit -framework ApplicationServices -framework Security
//   /tmp/agentspace-probe

import Foundation
import CoreGraphics
import AppKit
import ApplicationServices
import Security

func section(_ title: String) {
    print("\n== \(title) ==")
}

// MARK: 1. CGSessionCopyCurrentDictionary

section("CGSessionCopyCurrentDictionary")
if let dict = CGSessionCopyCurrentDictionary() as? [String: Any] {
    for key in dict.keys.sorted() {
        print("  \(key) = \(dict[key]!)")
    }
    let dblS = dict["kCGSSessionOnConsoleKey"]
    let singleS = dict["kCGSessionOnConsoleKey"]
    print("  --> kCGSSessionOnConsoleKey (double-S) present: \(dblS != nil) value: \(String(describing: dblS))")
    print("  --> kCGSessionOnConsoleKey  (single-S) present: \(singleS != nil) value: \(String(describing: singleS))")
    print("  --> managerName key present: \(dict["kCGSSessionManagerNameKey"] != nil)")
} else {
    print("  <nil> — no session dictionary at all")
}

// MARK: 2. SessionGetInfo / sessionHasGraphicAccess

section("SessionGetInfo (Security framework)")
var sid: SecuritySessionId = 0
var bits = SessionAttributeBits(rawValue: 0)
let st = SessionGetInfo(callerSecuritySession, &sid, &bits)
print("  OSStatus = \(st)")
if st == errSecSuccess {
    print("  sessionId = \(sid)")
    print("  raw bits = 0x\(String(bits.rawValue, radix: 16))")
    print("  sessionIsRoot            = \(bits.contains(.sessionIsRoot))")
    print("  sessionHasGraphicAccess  = \(bits.contains(.sessionHasGraphicAccess))")
    print("  sessionHasTTY            = \(bits.contains(.sessionHasTTY))")
    print("  sessionIsRemote          = \(bits.contains(.sessionIsRemote))")
} else {
    print("  SessionGetInfo failed — cannot use graphic-access bit as the WindowServer signal")
}

// MARK: 3. Guard name

section("Guard process name")
var buf = [CChar](repeating: 0, count: 512)
if let r = getenv("XPC_SERVICE_NAME") { print("  XPC_SERVICE_NAME = \(String(cString: r))") }
if let r = getenv("SECURITYSESSIONID") { print("  SECURITYSESSIONID = \(String(cString: r))") }
_ = buf

// MARK: 4. TCC preflight (never prompts)

section("TCC preflight (prompts nothing)")
let ax = AXIsProcessTrusted()
let sr = CGPreflightScreenCaptureAccess()
print("  AXIsProcessTrusted()             = \(ax)")
print("  CGPreflightScreenCaptureAccess() = \(sr)")

// MARK: 5. Display geometry — the scale trap

section("Display geometry")
let did = CGMainDisplayID()
let bounds = CGDisplayBounds(did)
print("  CGDisplayBounds       = \(bounds)")
print("  CGDisplayPixelsWide   = \(CGDisplayPixelsWide(did))  (documented as pixels)")
print("  CGDisplayPixelsHigh   = \(CGDisplayPixelsHigh(did))")
if let mode = CGDisplayCopyDisplayMode(did) {
    print("  mode.width            = \(mode.width)  (points)")
    print("  mode.pixelWidth       = \(mode.pixelWidth)  (pixels)")
    let scale = mode.width > 0 ? Double(mode.pixelWidth) / Double(mode.width) : 0
    print("  derived scale         = \(scale)")
    if CGDisplayPixelsWide(did) == mode.width && mode.pixelWidth != mode.width {
        print("  !! CONFIRMED: CGDisplayPixelsWide() returns POINTS, not pixels —")
        print("     deriving scale from it yields 1 on a Retina display. Use mode.pixelWidth/mode.width.")
    }
} else {
    print("  CGDisplayCopyDisplayMode returned nil")
}

// MARK: 6. Frontmost window pid from the window server

section("Window server frontmost")
let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
if let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] {
    print("  on-screen windows: \(list.count)")
    var shown = 0
    for w in list {
        guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
        let pid = w[kCGWindowOwnerPID as String] as? pid_t ?? -1
        let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
        print("  layer-0: pid=\(pid) owner=\(owner)")
        shown += 1
        if shown >= 3 { break }
    }
    if shown == 0 { print("  no layer-0 window on screen") }
} else {
    print("  CGWindowListCopyWindowInfo returned nil — no window server?")
}
print("  NSWorkspace.frontmost = \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil") (cache; may be stale)")
print("  getuid() = \(getuid())  getpid() = \(getpid())")

// MARK: 7. Console user

section("Console")
print("  /dev/console owner uid follows")
var st2 = stat()
if stat("/dev/console", &st2) == 0 {
    print("  st_uid = \(st2.st_uid)  (compare to getuid() above)")
}
print("\nPROBE COMPLETE")
