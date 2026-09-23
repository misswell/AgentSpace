import Foundation

/// How the pointer behaves when it enters an agent desktop.
///
/// The default is `auto`, and the reason it is the default is the whole point of
/// Desktop Mode: a person who opened the agent's desktop to work in it should not
/// have to click first to make their own pointer reach it. Parallels and RustDesk
/// both hand the pointer over on entry, and both offer the alternative for the
/// person who does not want that — so this is a preference with three positions
/// rather than a decision made for everybody.
public enum MouseCaptureMode: String, CaseIterable, Sendable {
    /// Entering the remote picture takes the pointer.
    case auto
    /// Only a press takes it, so a cursor crossing the picture changes nothing.
    case clickToCapture
    /// Never take it. The desktop stays visible and can be driven, but the local
    /// cursor is never hidden and travel is forwarded only inside a gesture.
    case off

    /// The default, stored nowhere until a person chooses otherwise.
    public static let `default`: MouseCaptureMode = .auto
    /// The `UserDefaults` key the GUI and both surfaces read.
    public static let storageKey = "mouseCaptureMode"

    public static func parse(_ raw: String?) -> MouseCaptureMode? {
        guard let raw else { return nil }
        return MouseCaptureMode(rawValue: raw)
    }

    /// The policy this mode means for a surface.
    public func policy(for host: Host) -> PointerCapturePolicy {
        switch (self, host) {
        case (.off, _):
            return .watchOnly
        case (.auto, .desktop):
            return .desktop
        case (.auto, .fusion):
            return .fusionProxy
        case (.clickToCapture, _):
            // Every host behaves like a proxy in this mode: the person's own
            // windows surround an agent desktop too, from their point of view,
            // when they have asked not to have the pointer taken.
            return .fusionProxy
        }
    }

    /// Which surface is asking. The desktop viewer is a whole screen; a Fusion
    /// proxy is one window among the person's own.
    public enum Host: Sendable {
        case desktop
        case fusion
    }
}
