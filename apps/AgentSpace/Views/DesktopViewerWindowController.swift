import AppKit
import SwiftUI
import os
import AgentSpaceCore

/// One line per aspect re-fit of a Desktop Viewer window, with the numbers that
/// describe it. One or two per resize is the working state; a stream of them is
/// the trade that used to end in AppKit's per-display-cycle budget asserting
/// (§381).
private let conformLog = Logger(subsystem: BundleIdentifiers.logSubsystem, category: "viewer-conform")

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
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = "\(space.displayName) Desktop"
        // The status strip IS the title bar (§361): the traffic lights sit on
        // the strip's left, the window title stays for Mission Control but is
        // not drawn, and the strip's controls live in what used to be two
        // rows. The reclaimed row goes to the desktop viewport.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
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
            hasShown = true
            window?.center()
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        bringOnScreenIfOutOfReach()
    }

    /// A saved frame can name a position the window can no longer be reached
    /// from — with the title strip off the screen there is nothing left to drag
    /// it by. macOS constrains a *drag* for exactly that reason; a frame that
    /// came back from preferences has to be constrained here. Frames like that
    /// exist in the wild: the ping-pong this round fixes saved one on this Mac.
    ///
    /// It runs *after* the window has been ordered on screen, because that is
    /// when the saved frame is applied — a repair attempted before that would be
    /// overwritten by the restore it exists to correct.
    private func bringOnScreenIfOutOfReach() {
        guard let window, let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let clamped = DesktopViewportSizing.onScreenFrame(window.frame, visibleArea: visible)
        guard clamped != window.frame else { return }
        window.setFrame(clamped, display: true)
        conformLog.log("saved frame was out of reach: window \(Int(clamped.width))x\(Int(clamped.height)) moved to (\(Int(clamped.minX)), \(Int(clamped.minY)))")
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
        let maximumWidth = screen?.visibleFrame.width ?? .greatestFiniteMagnitude
        guard let fitted = DesktopViewportSizing.contentSize(
            proposedWidth: min(content.width, maximumWidth),
            controlsHeight: controlsHeight,
            titlebarHeight: titlebar, maximumFrameHeight: maximumHeight,
            displayWidth: Double(display.width), displayHeight: Double(display.height),
            minimumViewportWidth: DesktopViewerView.minimumViewportWidth,
            minimumViewportHeight: DesktopViewerView.minimumViewportHeight,
            maximumWidth: maximumWidth) else {
            // The display's aspect cannot hold at the viewer's own minimum on
            // this screen. Leave the size alone; a resized window that cannot
            // show the whole desktop undistorted is still better than a window
            // that argues with the size SwiftUI enforces (§381).
            return frameSize
        }
        let adjusted = NSRect(origin: .zero,
                              size: NSSize(width: fitted.width, height: fitted.height))
        return sender.frameRect(forContentRect: adjusted).size
    }

    private var currentDisplay: DisplayGeometry? {
        model?.snapshots.first(where: { $0.space.id == space.id })?.retinaDisplay?.geometry
    }

    private var displayAspectRatio: CGFloat? {
        guard let display = currentDisplay,
              display.width > 0, display.height > 0 else { return nil }
        return CGFloat(display.width) / CGFloat(display.height)
    }

    private func viewportDidLayout(_ viewport: CGSize) {
        lastViewport = viewport
        guard let window else { return }
        controlsHeight = max(0, window.contentView!.bounds.height - viewport.height)
        guard !window.inLiveResize, let ratio = displayAspectRatio else { return }
        guard abs(viewport.height - viewport.width / ratio) > 1 else { return }
        scheduleConform()
    }

    /// Queues one aspect re-fit, run out of the layout pass that asked for it.
    ///
    /// A window's frame must not be changed from *inside* the layout pass that
    /// measured it. AppKit answers that by redoing the window's placement, the
    /// placement re-applies the saved frame, and the two trade the window back
    /// and forth inside a single display cycle — walking it off the screen
    /// while AppKit's per-cycle budget (47 constraint updates) runs out and it
    /// asserts. That is §381: five crashes in one afternoon, every one of them a
    /// Desktop Viewer window whose saved frame was narrower than the display's
    /// aspect and the viewer's own minimum can both satisfy.
    private func scheduleConform() {
        guard !conformScheduled else { return }
        conformScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.conformScheduled = false
            self.conformIfAspectIsOff()
        }
    }

    private func conformIfAspectIsOff() {
        guard let window, !conforming, !window.inLiveResize, let ratio = displayAspectRatio else { return }
        let viewport = lastViewport
        guard viewport.width > 0, abs(viewport.height - viewport.width / ratio) > 1 else { return }
        conforming = true
        defer { conforming = false }
        let before = window.frame
        let target = windowWillResize(window, to: before.size)
        guard abs(target.width - before.width) > 1 || abs(target.height - before.height) > 1 else {
            // No size holds the aspect and the viewer's own minimum at once, or
            // the size is already the answer: either way there is nothing to
            // change, and retrying is the trade that used to end in AppKit's
            // budget asserting (§381).
            conformLog.log("aspect is off (viewport \(Int(viewport.width))x\(Int(viewport.height)) of a \(Int(before.width))x\(Int(before.height)) window) and no re-fit is available — leaving it")
            return
        }
        window.setFrame(NSRect(origin: before.origin, size: target), display: true)
        conformCount += 1
        let after = window.frame
        conformLog.log("conform #\(self.conformCount) viewport \(Int(viewport.width))x\(Int(viewport.height)), expected height \(Int(viewport.width / ratio)): window \(Int(before.width))x\(Int(before.height)) → asked \(Int(target.width))x\(Int(target.height)) → \(Int(after.width))x\(Int(after.height))")
    }

    /// How many times this window has re-fitted itself, reported with each
    /// conform line so a runaway is visible as a count rather than inferred.
    private var conformCount = 0
    private var conformScheduled = false
    /// The newest viewport size SwiftUI reported, re-checked when the queued
    /// re-fit runs so a stale measurement cannot drive a frame change.
    private var lastViewport: CGSize = .zero
}
