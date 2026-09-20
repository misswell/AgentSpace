import Foundation

/// Detects an app process whose bundle was replaced while it was still alive.
///
/// macOS keeps the old executable mapped, but later resource loads come from
/// the new bundle on disk. Continuing in that mixed state can leave SwiftUI
/// unresponsive. The old process should terminate when its session becomes
/// active; the next launch then uses one coherent version.
public enum AppBundleCompatibility {
    public static func installedVersion(bundleURL: URL) -> String? {
        let plistURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let object = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil),
              let dictionary = object as? [String: Any] else { return nil }
        return dictionary["CFBundleShortVersionString"] as? String
    }

    public static func requiresRelaunch(
        runningVersion: String,
        bundleURL: URL
    ) -> Bool {
        guard let installed = installedVersion(bundleURL: bundleURL) else { return false }
        return installed != runningVersion
    }
}
