import AppKit
import CoreGraphics
import Foundation
import AgentSpaceCore

/// Public-API view of the normal application windows in this Aqua session.
final class WindowCatalog {
    private struct RawIdentity: Hashable {
        var pid: Int32
        var windowID: UInt32
    }

    private let lock = NSLock()
    private var generations: [RawIdentity: UInt64] = [:]
    private var previouslyVisible: Set<RawIdentity> = []
    private var nextGeneration: UInt64 = 1

    func windows() -> [RemoteWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let records = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]] else { return [] }

        let raw = records.compactMap(parse)
        let seen = Set(raw.map { RawIdentity(pid: $0.pid, windowID: $0.id) })

        lock.lock()
        for key in seen where !previouslyVisible.contains(key) {
            generations[key] = nextGeneration
            nextGeneration &+= 1
        }
        previouslyVisible = seen
        let snapshot = generations
        lock.unlock()

        return raw.map { window in
            let key = RawIdentity(pid: window.pid, windowID: window.id)
            return RemoteWindow(
                id: window.id, pid: window.pid, appName: window.appName,
                bundleIdentifier: window.bundleIdentifier, title: window.title,
                frame: window.frame, layer: window.layer, visible: window.visible,
                minimized: window.minimized, generation: snapshot[key] ?? 0)
        }
    }

    func window(matching identity: WindowIdentity) throws -> RemoteWindow {
        guard let window = windows().first(where: { $0.identity == identity }) else {
            throw AgentSpaceError(
                code: .badRequest,
                message: "window \(identity.windowID) no longer exists or its generation changed")
        }
        return window
    }

    private func parse(_ record: [String: Any]) -> RemoteWindow? {
        guard let layer = number(record[kCGWindowLayer as String])?.intValue, layer == 0,
              let alpha = number(record[kCGWindowAlpha as String])?.doubleValue, alpha > 0,
              let rawID = number(record[kCGWindowNumber as String])?.uint32Value,
              let rawPID = number(record[kCGWindowOwnerPID as String])?.int32Value,
              rawPID != getpid(),
              let bounds = record[kCGWindowBounds as String] as? [String: Any],
              let x = number(bounds["X"])?.doubleValue,
              let y = number(bounds["Y"])?.doubleValue,
              let width = number(bounds["Width"])?.doubleValue, width > 40,
              let height = number(bounds["Height"])?.doubleValue, height > 40
        else { return nil }

        let owner = (record[kCGWindowOwnerName as String] as? String) ?? "Application"
        let excluded = ["Dock", "Window Server", "WindowServer", "Control Center", "Wallpaper", "AgentSpace"]
        guard !excluded.contains(where: { owner.localizedCaseInsensitiveContains($0) }) else { return nil }

        let app = NSRunningApplication(processIdentifier: rawPID)
        guard app?.activationPolicy == .regular else { return nil }
        return RemoteWindow(
            id: rawID,
            pid: rawPID,
            appName: app?.localizedName ?? owner,
            bundleIdentifier: app?.bundleIdentifier,
            title: record[kCGWindowName as String] as? String,
            frame: CGRectValue(x: x, y: y, width: width, height: height),
            layer: layer,
            visible: (record[kCGWindowIsOnscreen as String] as? Bool) ?? true,
            minimized: false,
            generation: 0)
    }

    private func number(_ value: Any?) -> NSNumber? { value as? NSNumber }
}
