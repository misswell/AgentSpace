import Foundation

public enum ViewerFrameRate {
    public static let storageKey = "previewFPS"
    public static let defaultValue = 30
    public static let options = [1, 5, 10, 15, 30, 60]

    public static func ceiling(in defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: storageKey)
        return options.contains(stored) ? stored : defaultValue
    }
}
