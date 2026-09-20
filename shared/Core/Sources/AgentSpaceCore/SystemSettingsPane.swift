import Foundation

/// The only System Settings destinations AgentSpace may open on behalf of an
/// attached account. Keeping this as a closed enum prevents a caller from
/// turning the convenience button into an arbitrary URL launcher.
public enum SystemSettingsPane: String, Codable, CaseIterable, Hashable, Sendable {
    case accessibility
    case screenRecording
    case fullDiskAccess

    /// Anchors read from this macOS's own Settings privacy extension
    /// (`SecurityPrivacyExtension.appex`), verified to navigate on macOS 27.
    public var urlString: String {
        switch self {
        case .accessibility:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenRecording:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .fullDiskAccess:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        }
    }
}
