import CoreGraphics
import Foundation
import AgentSpaceCore

/// One logical, real 2× desktop for the lifetime of Desktop Viewer streams.
/// This changes only the worker's background Aqua session: the real 2× display
/// becomes the session's single main display and every other display mirrors
/// it. The original arrangement returns when the last stream closes — and a
/// display's own mode returns with it when it leaves the mirror set, which is
/// why only the arrangement is saved here and no mode is ever re-applied.
final class RetinaDesktopLayout {
    private struct DisplayState {
        let id: CGDirectDisplayID
        let origin: CGPoint
    }
    private struct SavedDisplay: Codable {
        let id: UInt32
        let x: Int32
        let y: Int32
        // Informational: they name what the session looked like when the
        // layout was taken, and are read back by nobody.
        let width: Int
        let height: Int
        let pixelWidth: Int
        let pixelHeight: Int
    }
    private struct SavedLayout: Codable {
        let main: UInt32
        let displays: [SavedDisplay]
    }

    private let lock = NSLock()
    private let markerURL: URL
    private var users = 0
    private var original: [DisplayState]?
    private var originalMain: CGDirectDisplayID = 0

    init(runtimeDirectory: String) {
        markerURL = URL(fileURLWithPath: runtimeDirectory).appendingPathComponent("retina-desktop-layout.json")
    }

    /// A killed worker cannot run `stopAll`. launchd's replacement restores the
    /// saved session arrangement before accepting another viewer.
    func recoverIfNeeded() {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: markerURL) else { return }
        guard let saved = try? JSONDecoder().decode(SavedLayout.self, from: data),
              let online = try? onlineDisplays(),
              Set(saved.displays.map(\.id)) == Set(online) else {
            Log.capture.error("Retina desktop: previous layout marker could not be resolved")
            return
        }
        // A display that still mirrors another reports the mirror's
        // arrangement, so leave the mirror set first; the saved arrangement is
        // an un-mirrored one, and each display's own mode returns with it.
        unmirrorAll(online)
        guard let states = states(from: saved) else {
            Log.capture.error("Retina desktop: previous layout marker could not be resolved")
            return
        }
        if restore(states, main: saved.main) {
            try? FileManager.default.removeItem(at: markerURL)
            Log.capture.info("Retina desktop: recovered the layout left by an interrupted worker")
        } else {
            Log.capture.error("Retina desktop: could not recover the interrupted worker's layout")
        }
    }

    func acquire() throws {
        lock.lock(); defer { lock.unlock() }
        if users > 0 { users += 1; return }
        if let original {
            guard restore(original, main: originalMain) else {
                throw AgentSpaceError(code: .internalError, message: "could not restore the agent desktop's previous display layout")
            }
            self.original = nil
        }

        let active = try activeDisplays()
        let online = try onlineDisplays()
        guard active.count == online.count,
              online.allSatisfy({ CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }) else {
            throw AgentSpaceError(code: .invalidTarget,
                message: "the agent session already has mirrored or sleeping displays; AgentSpace cannot safely prepare one Retina desktop")
        }
        let main = CGMainDisplayID()
        guard let retina = ScreenCapture.retinaViewerDisplay(), active.contains(retina.id) else {
            throw AgentSpaceError(code: .invalidTarget, message: "the agent session has no real 2× display")
        }
        if main == retina.id && active.count == 1 { users = 1; return }

        let before = online.map { DisplayState(id: $0, origin: CGDisplayBounds($0).origin) }
        let saved = SavedLayout(main: main, displays: online.map { id in
            let mode = CGDisplayCopyDisplayMode(id)
            let bounds = CGDisplayBounds(id)
            return SavedDisplay(id: id,
                x: Int32(bounds.origin.x.rounded()), y: Int32(bounds.origin.y.rounded()),
                width: mode?.width ?? 0, height: mode?.height ?? 0,
                pixelWidth: mode?.pixelWidth ?? 0, pixelHeight: mode?.pixelHeight ?? 0)
        })
        do { try JSONEncoder().encode(saved).write(to: markerURL, options: .atomic) }
        catch { throw AgentSpaceError(code: .internalError, message: "could not save the agent desktop layout before changing it") }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else {
            try? FileManager.default.removeItem(at: markerURL)
            throw AgentSpaceError(code: .internalError, message: "could not begin the Retina desktop configuration")
        }
        let origin = CGConfigureDisplayOrigin(config, retina.id, 0, 0)
        let mirrors = online.filter { $0 != retina.id }.map {
            CGConfigureDisplayMirrorOfDisplay(config, $0, retina.id)
        }
        guard origin == .success, mirrors.allSatisfy({ $0 == .success }) else {
            CGCancelDisplayConfiguration(config)
            try? FileManager.default.removeItem(at: markerURL)
            throw AgentSpaceError(code: .internalError, message: "could not make the Retina display the agent session's single main desktop")
        }
        guard CGCompleteDisplayConfiguration(config, .forSession) == .success else {
            throw AgentSpaceError(code: .internalError, message: "macOS refused the agent session's Retina desktop layout")
        }
        guard waitForMain(retina.id),
              let mode = CGDisplayCopyDisplayMode(retina.id),
              mode.pixelWidth >= mode.width * 2,
              online.filter({ $0 != retina.id }).allSatisfy({ CGDisplayMirrorsDisplay($0) == retina.id }) else {
            if restore(before, main: main) { try? FileManager.default.removeItem(at: markerURL) }
            throw AgentSpaceError(code: .invalidTarget, message: "the agent session did not become one real 2× desktop")
        }
        original = before
        originalMain = main
        users = 1
        Log.capture.info("Retina desktop: one logical 2× main display \(retina.id) in the agent session")
    }

    func release() {
        lock.lock(); defer { lock.unlock() }
        guard users > 0 else { return }
        users -= 1
        guard users == 0, let original else { return }
        if restore(original, main: originalMain) {
            self.original = nil
            try? FileManager.default.removeItem(at: markerURL)
            Log.capture.info("Retina desktop: restored the agent session's previous layout")
        } else {
            Log.capture.error("Retina desktop: could not restore the agent session's previous layout")
        }
    }

    /// Best-effort; a display that cannot leave its mirror keeps reporting the
    /// mirror's arrangement and the restore below names the mismatch.
    private func unmirrorAll(_ displays: [CGDirectDisplayID]) {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        for display in displays {
            CGConfigureDisplayMirrorOfDisplay(config, display, kCGNullDirectDisplay)
        }
        CGCompleteDisplayConfiguration(config, .forSession)
    }

    private func restore(_ displays: [DisplayState], main: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        for display in displays where display.id != main {
            guard CGConfigureDisplayMirrorOfDisplay(config, display.id, kCGNullDirectDisplay) == .success else {
                CGCancelDisplayConfiguration(config); return false
            }
        }
        guard CGConfigureDisplayOrigin(config, main, 0, 0) == .success else {
            CGCancelDisplayConfiguration(config); return false
        }
        for display in displays where display.id != main {
            guard CGConfigureDisplayOrigin(config, display.id,
                    Int32(display.origin.x.rounded()), Int32(display.origin.y.rounded())) == .success else {
                CGCancelDisplayConfiguration(config); return false
            }
        }
        guard CGCompleteDisplayConfiguration(config, .forSession) == .success else { return false }
        return waitForMain(main)
    }

    /// The main-display reassignment is not always settled by the time a
    /// configuration call returns — measured: the arrangement was already
    /// correct on screen while an immediate `CGMainDisplayID()` still named
    /// the mirror source, which read as a failure and left the marker behind.
    private func waitForMain(_ id: CGDirectDisplayID) -> Bool {
        let deadline = Date().addingTimeInterval(6)
        while CGMainDisplayID() != id {
            guard Date() < deadline else { return false }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return true
    }

    /// The saved arrangement needs no mode lookup, and cannot use one:
    /// measured on this Mac, `CGDisplayCopyAllDisplayModes` answers an empty
    /// list for the built-in 2× display both while it is a mirror source and
    /// after it leaves the mirror set, and a single entry for the other
    /// display. No mode is re-applied because no mode was changed: a display
    /// that was mirroring reverts to its own mode as it un-mirrors.
    private func states(from saved: SavedLayout) -> [DisplayState]? {
        guard saved.displays.count >= 1, saved.displays.count <= 32,
              saved.displays.contains(where: { $0.id == saved.main }) else { return nil }
        return saved.displays.map { DisplayState(id: $0.id, origin: CGPoint(x: Int($0.x), y: Int($0.y))) }
    }

    private func activeDisplays() throws -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else {
            throw AgentSpaceError(code: .noWindowServer, message: "could not enumerate the agent session's active displays")
        }
        return Array(ids.prefix(Int(count)))
    }

    private func onlineDisplays() throws -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else {
            throw AgentSpaceError(code: .noWindowServer, message: "could not enumerate the agent session's online displays")
        }
        return Array(ids.prefix(Int(count)))
    }
}
