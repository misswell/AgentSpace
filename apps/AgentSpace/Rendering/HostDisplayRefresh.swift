import AppKit

/// The panel that actually shows this viewer, rather than the agent's display.
/// `NSScreen.maximumRefreshRate` does not exist in AppKit; the public rate is
/// `maximumFramesPerSecond`. A window moved between panels can change this rate
/// without changing the remote desktop or reconnecting its input channel.
enum HostDisplayRefresh {
    static func pointerRate(for window: NSWindow?) -> Double {
        let reported = window?.screen?.maximumFramesPerSecond
            ?? NSScreen.main?.maximumFramesPerSecond ?? 60
        return min(120, max(30, Double(reported)))
    }
}
