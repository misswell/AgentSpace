import Foundation

/// How the host pointer controls a remote surface.
public enum MouseCaptureMode: String, CaseIterable, Sendable {
    /// Synchronize hover only after the host pointer settles.
    case auto
    /// Continuously follow the host pointer inside the remote image.
    case capture
    /// Keep the existing press-to-control behavior.
    case clickToCapture

    public static let `default`: MouseCaptureMode = .auto
    public static let storageKey = "mouseCaptureMode"

    public static func parse(_ raw: String?) -> MouseCaptureMode? {
        guard let raw else { return nil }
        // The removed Off choice already allowed clicks and drags.
        if raw == "off" { return .clickToCapture }
        return MouseCaptureMode(rawValue: raw)
    }

    public func policy(for host: Host) -> PointerCapturePolicy {
        switch self {
        case .auto: return .automatic
        case .capture: return .desktop
        case .clickToCapture: return .fusionProxy
        }
    }

    public enum Host: Sendable {
        case desktop
        case fusion
    }
}
