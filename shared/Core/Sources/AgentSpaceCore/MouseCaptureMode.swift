import Foundation

/// How the host pointer controls a remote surface.
public enum MouseCaptureMode: String, CaseIterable, Sendable {
    /// Take over the moment the pointer enters the remote image: one cursor on
    /// both sides, and moves, clicks, drags and scrolls all follow while it
    /// moves — not after it pauses. The default, because this is the
    /// RustDesk/Parallels experience the owner asked for by name (§351): the
    /// mode has to be visible in the picker under its own name, not folded
    /// into another mode's steady state.
    case takeoverHidden
    /// Take over on entry exactly like takeoverHidden, but keep the person's
    /// own pointer visible: their cursor is the pointer, and the sprite is
    /// never drawn on top of it. Restored alongside (not instead of)
    /// takeoverHidden — the two are separate choices (§354).
    case takeover
    /// Synchronize hover only after the host pointer settles.
    case auto
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

    public func policy(for host: Host) -> PointerCapturePolicy {
        switch self {
        case .takeoverHidden, .takeover: return .desktop
        case .auto: return .automatic
        case .clickToCapture: return .fusionProxy
        }
    }

    /// Whether controlling hides the person's own pointer in favour of the
    /// worker's published sprite. Every mode but takeover does.
    public var hidesCursor: Bool { self != .takeover }

    public enum Host: Sendable {
        case desktop
        case fusion
    }
}
