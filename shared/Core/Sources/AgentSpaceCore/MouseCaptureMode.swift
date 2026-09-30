import Foundation

/// How the host pointer controls a remote surface.
public enum MouseCaptureMode: String, CaseIterable, Sendable {
    /// Auto: take control on entry, hide the internal cursor, keep the host one.
    /// The stored spelling remains compatible with earlier hidden-takeover choices.
    case takeoverHidden
    /// Take control on entry and retain the internal cursor as well.
    case takeover
    /// Keep the existing press-to-control behavior.
    case clickToCapture

    public static let `default`: MouseCaptureMode = .takeoverHidden
    public static let storageKey = "mouseCaptureMode"

    public static func parse(_ raw: String?) -> MouseCaptureMode? {
        guard let raw else { return nil }
        // The removed Off choice already allowed clicks and drags.
        if raw == "off" { return .clickToCapture }
        // 0.1.49–0.1.57 stored 「Capture」 for the same entry-takes-control
        // behavior this mode now names; an old stored value keeps its feel.
        if raw == "capture" { return .takeoverHidden }
        return MouseCaptureMode(rawValue: raw)
    }

    /// Delete the removed pause-to-sync Auto setting without migrating it.
    public static func discardRemovedPreference(in defaults: UserDefaults = .standard) {
        if defaults.string(forKey: storageKey) == "auto" {
            defaults.removeObject(forKey: storageKey)
        }
    }

    public func policy(for host: Host) -> PointerCapturePolicy {
        switch self {
        case .takeoverHidden, .takeover: return .desktop
        case .clickToCapture: return .fusionProxy
        }
    }

    /// Whether controlling hides the person's **own** pointer. The two
    /// takeover modes never do: a hand's own cursor is the only zero-latency
    /// pointer there is, and hiding it is what makes a remote desktop feel
    /// slow — the owner's correction of §351's semantics (§364).
    public var hidesLocalCursor: Bool { self == .clickToCapture }

    /// Whether the **internal** cursor — the one drawn inside the remote
    /// picture, from the worker's published sprite — is suppressed.
    /// 「自动」 hides the internal one, never the person's own (§368).
    public var hidesInternalCursor: Bool { self == .takeoverHidden }

    /// Hidden mode uses the person's own pointer even when the channel is offline.
    public func embedsCursor(cursorChannelActive: Bool) -> Bool {
        !hidesInternalCursor && !cursorChannelActive
    }

    public enum Host: Sendable {
        case desktop
        case fusion
    }
}
