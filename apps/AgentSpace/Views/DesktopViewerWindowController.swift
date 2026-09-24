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
    /// Header, footer and dividers are outside the captured desktop. The
    /// viewport reports their combined height after SwiftUI lays them out.
    private var controlsHeight: CGFloat?
    private var conforming = false

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
            rootView: DesktopViewerView(spaceID: space.id, onViewportSize: { [weak self] size in
                self?.viewportDidLayout(size)
            })
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

    func windowDidChangeScreen(_ notification: Notification) {
        guard let window, controlsHeight != nil else { return }
        let frame = windowWillResize(window, to: window.frame.size)
        if abs(frame.width - window.frame.width) > 1 || abs(frame.height - window.frame.height) > 1 {
            window.setFrame(NSRect(origin: window.frame.origin, size: frame), display: true)
        }
    }

    /// Keep the *desktop viewport*, not the entire decorated window, at the
    /// agent display's aspect ratio. This preserves every desktop pixel while
    /// leaving no unused strips above or below it.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let controlsHeight, let display = currentDisplay else { return frameSize }
        let content = sender.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize))
        let screen = sender.screen ?? NSScreen.main
        let titlebar = frameSize.height - content.height
        let maximumHeight = screen?.visibleFrame.height ?? .greatestFiniteMagnitude
        let fitted = DesktopViewportSizing.contentSize(
            proposedWidth: min(content.width, screen?.visibleFrame.width ?? .greatestFiniteMagnitude),
            controlsHeight: controlsHeight,
            titlebarHeight: titlebar, maximumFrameHeight: maximumHeight,
            displayWidth: Double(display.width), displayHeight: Double(display.height))
        let adjusted = NSRect(origin: .zero,
                              size: NSSize(width: fitted.width, height: fitted.height))
        return sender.frameRect(forContentRect: adjusted).size
    }

    private var currentDisplay: DisplayGeometry? {
        model?.snapshots.first(where: { $0.space.id == space.id })?.display
    }

    private var displayAspectRatio: CGFloat? {
        guard let display = currentDisplay,
              display.width > 0, display.height > 0 else { return nil }
        return CGFloat(display.width) / CGFloat(display.height)
    }

    private func viewportDidLayout(_ viewport: CGSize) {
        guard let window, let ratio = displayAspectRatio, !conforming else { return }
        let controls = max(0, window.contentView!.bounds.height - viewport.height)
        controlsHeight = controls
        guard !window.inLiveResize else { return }
        let expectedHeight = viewport.width / ratio
        guard abs(viewport.height - expectedHeight) > 1 else { return }
        conforming = true
        let frame = windowWillResize(window, to: window.frame.size)
        window.setFrame(NSRect(origin: window.frame.origin, size: frame), display: true)
        conforming = false
    }
}
