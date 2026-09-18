// Prints the on-screen windows, with the CGWindowID that `screencapture -l` wants.
//
// `screencapture -R x,y,w,h` captures a *screen region*, so it picks up whatever
// happens to be on top — useless for verifying that one app rendered when the
// desktop has other windows on it. `screencapture -l <id>` captures the window's
// own contents regardless of stacking, and the window id is only reachable
// through CGWindowListCopyWindowInfo.
//
//   swiftc -O tests/probes/WindowListProbe.swift -o /tmp/windowlist \
//     -framework CoreGraphics -framework Foundation
//   /tmp/windowlist                 # every window
//   /tmp/windowlist AgentSpace      # only windows whose owner name matches
//
// This is also the API the worker uses to find the frontmost pid (layer 0),
// which is why it lives next to the other probes: it is the same question.

import Foundation
import CoreGraphics

let filter = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil

guard let raw = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
    FileHandle.standardError.write(Data("CGWindowListCopyWindowInfo returned nothing\n".utf8))
    exit(1)
}

// Padding is done by hand rather than with `%s` in a format string: `%s` expects
// a C string, and passing a Swift `String` to it crashes rather than misformatting.
func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

print(pad("WINDOWID", 9) + pad("PID", 8) + pad("LAYER", 7) + pad("BOUNDS", 18) + "OWNER / TITLE")

for window in raw {
    let owner = window[kCGWindowOwnerName as String] as? String ?? "?"
    guard filter == nil || owner.localizedCaseInsensitiveContains(filter!) else { continue }

    let id = window[kCGWindowNumber as String] as? Int ?? 0
    let pid = window[kCGWindowOwnerPID as String] as? pid_t ?? 0
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    let title = window[kCGWindowName as String] as? String ?? ""

    var boundsText = "?"
    if let bounds = window[kCGWindowBounds as String] as? [String: Any],
       let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) {
        boundsText = String(format: "%.0fx%.0f@%.0f,%.0f",
                            rect.width, rect.height, rect.origin.x, rect.origin.y)
    }

    print(pad(String(id), 9) + pad(String(pid), 8) + pad(String(layer), 7)
          + pad(boundsText, 18) + owner + (title.isEmpty ? "" : " — \(title)"))
}
