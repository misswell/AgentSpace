import AppKit

/// The panel that actually shows this viewer, rather than the agent's display.
/// `NSScreen.maximumRefreshRate` does not exist in AppKit; the public rate is
/// `maximumFramesPerSecond`. A window moved between panels can change this rate
/// without changing the remote desktop or reconnecting its input channel.
enum HostDisplayRefresh {
    /// A remembered answer, because `maximumFramesPerSecond` is not a field read:
    /// it asks the window server about the panel. The pointer path wants it for
    /// every mouse-moved event — a trackpad at 125 Hz is 125 questions a second —
    /// and the display's refresh rate is not a thing that changes while a hand is
    /// moving. A panel switch is answered by `windowDidChangeScreen` recomputing
    /// through a fresh window, and by this cache's own expiry.
    private static var cached: (window: ObjectIdentifier, rate: Double, at: TimeInterval)?
    private static let ttl: TimeInterval = 1

    static func pointerRate(for window: NSWindow?, now: TimeInterval = Date().timeIntervalSinceReferenceDate) -> Double {
        if let key = window.map(ObjectIdentifier.init), let cached, cached.window == key,
           now - cached.at < ttl {
            return cached.rate
        }
        let reported = window?.screen?.maximumFramesPerSecond
            ?? NSScreen.main?.maximumFramesPerSecond ?? 60
        let rate = min(120, max(30, Double(reported)))
        if let key = window.map(ObjectIdentifier.init) { cached = (key, rate, now) }
        return rate
    }

    /// For tests: the cache is process-wide state, and a test that asserts the
    /// arithmetic must not inherit a previous test's answer.
    static func resetCache() { cached = nil }
}
