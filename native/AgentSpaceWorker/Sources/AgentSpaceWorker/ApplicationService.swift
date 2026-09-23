import Foundation
import AppKit
import AgentSpaceCore

/// Every application installed in this session, for the Fusion app picker.
///
/// The walking and the reading happen here because this is the process that can
/// do them: the bundle may sit in the agent account's own home, behind a
/// directory the controller user cannot enter, and its icon can only be rendered
/// where the bundle can be opened. Every *decision* about the resulting list
/// (which entries count, how duplicates collapse, what a search matches) is in
/// Core's `ApplicationCatalog`, where it is unit-tested without any of this.
enum ApplicationService {

    /// Applications a picker can offer.
    ///
    /// A `.app` directory that launches nothing is not an application, and a
    /// background-only service has no window to fuse — see
    /// `ApplicationCatalog.ActivationProfile` for the measurement that put the
    /// second rule here. The price is one `stat` and two plist reads per entry.
    static func entries(
        in root: String,
        running: [AppControl.AppInfo],
        icons: Bool,
        includingAgents: Bool
    ) -> [InstalledApplication] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else { return [] }
        var out: [InstalledApplication] = []
        for name in names.sorted() {
            let path = root + "/" + name
            guard let bundle = Bundle(path: path) else { continue }
            let executable = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
            let executablePath = executable.map { path + "/Contents/MacOS/" + $0 }
            let hasExecutable = executablePath.map { FileManager.default.isExecutableFile(atPath: $0) } ?? false
            let profile = ApplicationCatalog.ActivationProfile(
                isBackgroundOnly: ApplicationCatalog.readsAsTrue(
                    bundle.object(forInfoDictionaryKey: "LSBackgroundOnly")),
                isAgentApp: ApplicationCatalog.readsAsTrue(
                    bundle.object(forInfoDictionaryKey: "LSUIElement")))
            guard ApplicationCatalog.isOffered(
                entryName: name, executableExists: hasExecutable,
                profile: profile, includingAgents: includingAgents)
            else { continue }
            let identifier = bundle.bundleIdentifier
            // The system's own answer first: `displayName(atPath:)` applies the
            // bundle's localization and hides the extension, which is what
            // Finder shows. The plist values are the fallbacks, and the empty
            // string is guarded there too — `三局通.app` carries an empty
            // `CFBundleDisplayName`, and a `??` chain does not catch that.
            let displayName = ApplicationCatalog.displayName(
                fileName: name,
                filesystemName: FileManager.default.displayName(atPath: path),
                infoDisplayName: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                infoName: bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            // Matching on the path as well catches the app *this* session
            // launched from a directory `resolve` would not have searched.
            let live = running.first { info in
                (identifier != nil && info.bundleID == identifier) || info.path == path
            }
            out.append(InstalledApplication(
                name: displayName,
                bundleIdentifier: identifier,
                path: path,
                version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                pid: live.map { Int($0.pid) },
                icon: icons ? iconPNG(path) : nil))
        }
        return out
    }

    /// The whole reply: the union of the search roots, deduplicated, filtered by
    /// the query and capped.
    ///
    /// `total` is the size of the list *before* the query, so a caller can say
    /// "12 of 240" rather than leaving a person wondering whether their search
    /// worked or the scan did.
    static func available(query: String?, limit: Int, icons: Bool, includingAgents: Bool) -> JSONValue {
        let roots = ApplicationCatalog.searchRoots(home: NSHomeDirectory())
        let running = AppControl.runningApps()
        let merged = ApplicationCatalog.merge(roots.map {
            entries(in: $0, running: running, icons: icons, includingAgents: includingAgents)
        })
        let matched = ApplicationCatalog.filtered(merged, query: query)
        let capped = Array(matched.prefix(max(1, limit)))
        return .obj([
            "count": .int(capped.count),
            "total": .int(merged.count),
            "truncated": .bool(capped.count < matched.count),
            "roots": .array(roots.map { .string($0) }),
            "apps": .array(capped.map(json)),
        ])
    }

    static func json(_ app: InstalledApplication) -> JSONValue {
        var object: [String: JSONValue] = [
            "name": .string(app.name),
            "path": .string(app.path),
        ]
        if let identifier = app.bundleIdentifier { object["bundleId"] = .string(identifier) }
        if let version = app.version { object["version"] = .string(version) }
        if let pid = app.pid { object["pid"] = .int(pid) }
        if let icon = app.icon { object["icon"] = .string(icon) }
        return .object(object)
    }

    /// A 32-point PNG of the app's icon, base64.
    ///
    /// Drawn into an explicit bitmap rather than by setting `NSImage.size`: the
    /// latter changes what the image *reports* and not what `tiffRepresentation`
    /// returns, which for an application icon is the 512-point original — about
    /// 100 KB per app against ~1.5 KB for this one, and the whole list travels in
    /// a single reply.
    ///
    /// Returns nil rather than a placeholder when there is no icon: a row
    /// without one is honest, and inventing an image here would hide the fact
    /// that the bundle could not be read.
    static func iconPNG(_ path: String, pixelSize: Int = 32) -> String? {
        let image = NSWorkspace.shared.icon(forFile: path)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = NSSize(width: pixelSize, height: pixelSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
                   from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])?.base64EncodedString()
    }
}
