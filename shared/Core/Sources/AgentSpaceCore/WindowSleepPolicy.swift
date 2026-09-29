import Foundation

/// How long a viewer window stays awake with nobody using it.
///
/// The Desktop Viewer is a window a person leaves open while an agent works
/// for hours. The idle frame ladder already drops a still desktop to 5 FPS,
/// but the stream, its shared region and the worker's capture of the whole
/// Retina layout stay alive for a window nobody is looking at. So a window
/// that has seen no interaction for the chosen interval puts its stream to
/// sleep — the capture, the shared region and the socket all end, the window
/// says so, and a click wakes it. What counts as activity is the person's
/// hand (a gesture, a drag, a key), deliberately **not** the desktop
/// changing: an agent working all day is exactly the case worth sleeping
/// through, and the person who comes back clicks once and is live again.
public enum WindowSleepPolicy {
    /// The idle lengths a person can choose from, in minutes; `0` is never.
    public static let options: [Int] = [5, 15, 30, 60, 0]

    /// What nobody chose: half an hour.
    public static let `default` = 30

    /// The preference this choice is stored under.
    public static let storageKey = "desktopViewerSleepMinutes"

    /// Only the offered lengths are honored: a stale or hand-edited stored
    /// value falls back to the default rather than becoming a surprise
    /// interval no picker ever offered.
    public static func parse(_ raw: Int?) -> Int {
        guard let raw, options.contains(raw) else { return Self.default }
        return raw
    }

    /// Whether the window should sleep now. `0` (never) never does; the
    /// boundary is inclusive, so 「30 分钟」 means asleep at 30:00 of silence.
    public static func shouldSleep(now: TimeInterval, lastActivity: TimeInterval,
                                   minutes: Int) -> Bool {
        guard minutes > 0 else { return false }
        return now - lastActivity >= Double(minutes) * 60
    }
}
