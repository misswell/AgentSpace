import Foundation

/// One launchable application in an agent account's own session — a row of the
/// Fusion app picker, and what `agentspace apps --available` prints.
///
/// `path` is a path **inside that session**. The controller user often cannot
/// read it: an application in the agent account's own `~/Applications` sits
/// behind a 0700 home directory. That is why the icon travels in this record —
/// rendered by the process that can open the bundle — instead of being loaded
/// from the path by whoever displays the row.
public struct InstalledApplication: Equatable, Sendable {
    /// What a person reads: `CFBundleDisplayName`, else `CFBundleName`, else
    /// the file name without `.app`.
    public var name: String
    public var bundleIdentifier: String?
    /// Absolute path to the `.app` inside the session.
    public var path: String
    public var version: String?
    /// The pid it is already running under in that session, when it is. A picker
    /// can then bring up the windows it has instead of starting a second copy.
    public var pid: Int?
    /// A 32-point PNG, base64 — small on purpose: this record travels once per
    /// application, and a full-size icon is ~100 KB against ~1.5 KB.
    public var icon: String?

    public init(
        name: String,
        bundleIdentifier: String? = nil,
        path: String,
        version: String? = nil,
        pid: Int? = nil,
        icon: String? = nil
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.version = version
        self.pid = pid
        self.icon = icon
    }

    /// Is this app already up in that session?
    public var isRunning: Bool { pid != nil }
}

/// The rules that turn a session's directories into a list of applications:
/// which entries count, how duplicates collapse, and how a search matches.
///
/// Pure on purpose. The worker does the walking and the reading — it is the
/// process that can see those directories at all — and everything a mistake
/// would show up in is decided *here*, where a test can pin it without a
/// session, a filesystem or a signed bundle.
public enum ApplicationCatalog {

    /// Max applications in one reply unless the caller says otherwise. A Mac
    /// with a large `/Applications` answers in the low hundreds; the cap exists
    /// so a pathological directory cannot make one reply unbounded.
    public static let defaultLimit = 250

    /// The directories a session's applications are looked for in, **in the
    /// order that decides which copy of a duplicated bundle wins**.
    ///
    /// This is the same list `AppControl.resolve` searches when a caller names
    /// an app instead of a path, and that is the point of it being one
    /// function: a picker offering an app the launcher cannot find — or hiding
    /// one it could launch — would be the same bug in two places, and the two
    /// would drift apart the first time one of them gained a directory.
    public static func searchRoots(home: String) -> [String] {
        [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices",
            home + "/Applications",
        ]
    }

    /// What kind of process a bundle describes, as its own `Info.plist` states it.
    ///
    /// A picker is a list of things a person can open *and then look at*, and
    /// both of these flags mean "there is no window of mine to show": a
    /// background-only service never has one, and a menu-bar agent has one only
    /// when it decides to. Measured on this Mac before the rule existed: the six
    /// search roots answered **372** applications, most of them
    /// `/System/Library/CoreServices` daemons — `AddPrinter`,
    /// `AddressBookUrlForwarder`, `AccessibilityUIServer` — which is a list
    /// nobody can use, in a picker whose whole job is to be scanned by eye.
    public struct ActivationProfile: Equatable, Sendable {
        public var isBackgroundOnly: Bool
        public var isAgentApp: Bool

        public init(isBackgroundOnly: Bool = false, isAgentApp: Bool = false) {
            self.isBackgroundOnly = isBackgroundOnly
            self.isAgentApp = isAgentApp
        }

        public var isRegular: Bool { !isBackgroundOnly && !isAgentApp }
    }

    /// Is this directory entry an application worth offering?
    ///
    /// `.app` **and** a bundle that actually carries the executable its
    /// `CFBundleExecutable` promises. A folder named `Fake.app` with no binary
    /// inside launches nothing, and offering it turns a picker click into an
    /// error dialog — the list has to be a list of things that work.
    public static func isLaunchable(entryName: String, executableExists: Bool) -> Bool {
        entryName.hasSuffix(".app") && executableExists
    }

    /// Read a plist flag that macOS itself is loose about.
    ///
    /// `LSUIElement` and `LSBackgroundOnly` are booleans in some bundles and the
    /// **strings** `"1"`/`"0"` in others — measured on this Mac, where reading
    /// `as? Bool` alone left every `/System/Library/CoreServices` daemon in the
    /// picker's default list (372 entries, 240 of them after a filter that was
    /// supposed to remove exactly those). A missing key is false.
    public static func readsAsTrue(_ value: Any?) -> Bool {
        switch value {
        case let flag as Bool: return flag
        case let number as NSNumber: return number.intValue != 0
        case let text as String:
            let folded = text.trimmingCharacters(in: .whitespaces).lowercased()
            return folded == "1" || folded == "true" || folded == "yes"
        default: return false
        }
    }

    /// The picker's default filter: launchable, and a regular app.
    ///
    /// `includingAgents` is the caller saying it knows what it is doing — an
    /// agent that wants to start a menu-bar utility can, and the CLI exposes it
    /// as `--all`. There is no flag that makes a background-only service
    /// *regular*: it is listed when everything is listed, and never otherwise.
    public static func isOffered(
        entryName: String,
        executableExists: Bool,
        profile: ActivationProfile,
        includingAgents: Bool = false
    ) -> Bool {
        guard isLaunchable(entryName: entryName, executableExists: executableExists) else { return false }
        return includingAgents ? true : profile.isRegular
    }

    /// What a person reads as the app's name.
    ///
    /// The order is the system's own answer first — `FileManager.displayName`
    /// applies the bundle's localization, which is what Finder shows — then the
    /// plist values, then the file name. Two traps are measured into this:
    ///
    /// 1. every fallback is guarded against the **empty** string, not just
    ///    against nil: `/Applications/三局通.app` carries an empty
    ///    `CFBundleDisplayName`, and `??` does not catch it, so the picker grew a
    ///    row with no name on it at all;
    /// 2. `displayName(atPath:)` keeps the extension —
    ///    `/System/Applications/Utilities/Activity Monitor.app` answers
    ///    「活动监视器.app」, localized but not what Finder draws — so a trailing
    ///    `.app` is stripped from whichever name wins.
    ///
    /// (both measured 2026-09-23, in the agent account's session)
    public static func displayName(
        fileName: String,
        filesystemName: String?,
        infoDisplayName: String?,
        infoName: String?
    ) -> String {
        func withoutExtension(_ value: String) -> String {
            value.hasSuffix(".app") ? String(value.dropLast(4)) : value
        }
        func usable(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else { return nil }
            return withoutExtension(trimmed)
        }
        if let name = usable(filesystemName) { return name }
        if let name = usable(infoDisplayName) { return name }
        if let name = usable(infoName) { return name }
        return withoutExtension(fileName)
    }

    /// Collapse the per-root scans into one list: the first root wins a
    /// duplicate, then everything is sorted by name.
    ///
    /// Deduplicating by bundle identifier rather than by path is deliberate:
    /// `/Applications/Safari.app` and `/System/Applications/Safari.app` are one
    /// app to a person, and a list showing both is a list where half the clicks
    /// do nothing new. A bundle with no identifier falls back to its path, so
    /// two anonymous bundles are never collapsed into one.
    public static func merge(_ groups: [[InstalledApplication]]) -> [InstalledApplication] {
        var seen = Set<String>()
        var merged: [InstalledApplication] = []
        for group in groups {
            for app in group {
                let key = app.bundleIdentifier.map { $0.lowercased() } ?? app.path
                if seen.contains(key) { continue }
                seen.insert(key)
                merged.append(app)
            }
        }
        return merged.sorted { lhs, rhs in
            let left = lhs.name.lowercased()
            let right = rhs.name.lowercased()
            if left != right { return left < right }
            return lhs.path < rhs.path
        }
    }

    /// Does this app match what someone typed?
    ///
    /// Name, bundle identifier and file name all count: "safari",
    /// "com.apple.Safari" and "Safari.app" are three things a person may
    /// reasonably type for the same row, and a search that only understood the
    /// first would look broken to anyone who knew the other two. An empty query
    /// matches everything — the field starts empty and the list starts full.
    public static func matches(_ app: InstalledApplication, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let needle = trimmed.lowercased()
        if app.name.lowercased().contains(needle) { return true }
        if let identifier = app.bundleIdentifier?.lowercased(), identifier.contains(needle) {
            return true
        }
        return (app.path as NSString).lastPathComponent.lowercased().contains(needle)
    }

    /// The list a search field shows: everything, or everything that matches.
    public static func filtered(_ apps: [InstalledApplication], query: String?) -> [InstalledApplication] {
        guard let query else { return apps }
        return apps.filter { matches($0, query: query) }
    }
}
