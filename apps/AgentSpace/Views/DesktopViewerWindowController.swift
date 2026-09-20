import AppKit
import SwiftUI
import AgentSpaceCore

/// Owns the detached Desktop Viewer windows.
///
/// The dashboard is a navigation surface, not the agent's desktop.  Keeping
/// the viewer in a separate `NSWindow` means it can be moved to another
/// display, resized independently, and left open while the user continues to
/// work in AgentSpace.
@MainActor
final class DesktopViewerWindowManager {
    static let shared = DesktopViewerWindowManager()

    private var controllers: [UUID: DesktopViewerWindowController] = [:]

    func open(for space: AgentAccount, model: AppModel) {
        if let controller = controllers[space.id] {
            controller.show()
            return
        }

        let controller = DesktopViewerWindowController(space: space, model: model)
        controllers[space.id] = controller
        controller.show()
    }

    func close(for spaceID: UUID) {
        controllers[spaceID]?.close()
    }

    func remove(spaceID: UUID) {
        controllers.removeValue(forKey: spaceID)
    }
}

@MainActor
final class DesktopViewerWindowController: NSWindowController, NSWindowDelegate {
    let space: AgentAccount
    private weak var model: AppModel?
    private var hasShown = false

    init(space: AgentAccount, model: AppModel) {
        self.space = space
        self.model = model

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "\(space.displayName) Desktop"
        window.isReleasedWhenClosed = false
        window.isMovable = true
        window.collectionBehavior = [.managed, .participatesInCycle]
        window.minSize = NSSize(width: 720, height: 520)
        window.setFrameAutosaveName("AgentSpace.DesktopViewer.\(space.id.uuidString)")

        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: DesktopViewerView(spaceID: space.id)
                .environmentObject(model))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if !hasShown {
            // A first-run window should be visible and independent of the
            // dashboard. Subsequent calls preserve the user's position.
            window?.center()
            hasShown = true
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model?.showingDesktopViewer = false
        DesktopViewerWindowManager.shared.remove(spaceID: space.id)
    }
}
