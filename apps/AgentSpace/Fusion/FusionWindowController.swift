import AppKit
import SwiftUI
import AgentSpaceCore

@MainActor
final class FusionWindowController: NSWindowController, NSWindowDelegate {
    let remoteWindow: RemoteWindow
    private let space: AgentAccount
    private let service = SpaceService()
    private let state = FusionWindowState()
    private let queue: DispatchQueue
    private var startingCapture = false
    private var frameClient: FrameClient?
    /// Pointer travel is state, not a gesture: one request in flight and only
    /// the newest position behind it, so a wave across the proxy cannot put a
    /// hundred stale positions in front of the click that follows. Lazy because
    /// its sender needs `self`, which the window controller cannot hand out
    /// before `super.init`.
    private lazy var travel = PointerTravelCoalescer<JSONValue> { [weak self] action in
        Task { @MainActor in self?.perform(action) }
    }
    /// Gaps between rebuild attempts, so a worker that is restarting — or a
    /// window that vanished — costs a decaying trickle of RPCs, not one per
    /// frame pull.

    init(space: AgentAccount, remoteWindow: RemoteWindow) {
        self.space = space
        self.remoteWindow = remoteWindow
        self.queue = DispatchQueue(label: BundleIdentifiers.app + ".fusion.\(remoteWindow.pid).\(remoteWindow.id)")
        let size = NSSize(
            width: max(420, min(1200, remoteWindow.frame.width)),
            height: max(300, min(900, remoteWindow.frame.height)))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "\(space.displayName) — \(remoteWindow.appName)"
        window.isReleasedWhenClosed = false
        window.isMovable = true
        window.collectionBehavior = [.managed, .participatesInCycle]
        window.minSize = NSSize(width: 420, height: 300)
        window.setFrameAutosaveName(
            "AgentSpace.Fusion.\(space.id.uuidString).\(remoteWindow.pid).\(remoteWindow.id)")
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: FusionWindowView(
            state: state,
            send: { [weak self] action in self?.send(action) },
            claimHuman: { [weak self] in self?.claimHuman() }))
        installTitlebarAction()
    }

    /// The one action this window takes against the agent, in the title bar.
    ///
    /// Not over the picture: that is the agent's window, and its corners are where
    /// its own controls live.
    private func installTitlebarAction() {
        guard let window else { return }
        let hosting = NSHostingView(rootView: FusionWindowActions(closeRemote: { [weak self] in
            self?.closeRemoteWindow()
        }))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = hosting
        accessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(accessory)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        startCapture()
    }

    func showAndResume() {
        window?.orderFrontRegardless()
        resumeCapture()
    }

    func resumeCapture() { startCapture() }

    func stop() {
        frameClient?.stop(); frameClient = nil; state.frameClient = nil
        startingCapture = false
        // A position collected for a window that is no longer being watched must
        // not be posted to the agent afterwards.
        travel.reset()
    }

    /// The session-level link was refused or went away, so this proxy stops
    /// polling for as long as the link says the worker will not answer.
    ///
    /// Deliberately not `stop()`: the `window.stream.stop` RPC would go to the
    /// same worker that just refused, and the stream is reaped server-side by
    /// the idle watchdog the moment this proxy stops pulling.
    func suspend(for error: AgentSpaceError) {
        startingCapture = false
        frameClient?.stop(); frameClient = nil; state.frameClient = nil
        travel.reset()
        state.error = error
    }

    func windowDidBecomeKey(_ notification: Notification) {
        let space = self.space, remote = remoteWindow
        queue.async { _ = SpaceService().windowActivate(for: space, window: remote) }
        if UserDefaults.standard.integer(forKey: "fusionFPSPolicy") == 0 { restartCapture() }
    }

    func windowDidResignKey(_ notification: Notification) {
        if UserDefaults.standard.integer(forKey: "fusionFPSPolicy") == 0 { restartCapture() }
    }

    func windowDidMiniaturize(_ notification: Notification) { stop() }
    func windowDidDeminiaturize(_ notification: Notification) { startCapture() }

    /// The mirror always closes, and closing it never touches the agent's window.
    ///
    /// This button used to *mean* "close the remote window": it asked the worker and
    /// only closed the mirror once that came back, so a proxy whose remote window was
    /// already gone, or whose app refuses the close, could not be dismissed at all —
    /// the one thing a mirror must always allow. Closing the agent's window is now the
    /// labelled action in the corner of the proxy, where its consequence is visible.
    ///
    /// `stop()` has to happen here: the session keeps this controller so the next
    /// poll does not hand the same window a fresh mirror, and a kept controller is
    /// offered `resumeCapture` again on every poll.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        stop()
        return true
    }

    /// Close the *agent's* window, then this mirror of it.
    func closeRemoteWindow() {
        let space = self.space, remote = remoteWindow
        queue.async { [weak self] in
            let result = SpaceService().windowClose(for: space, window: remote)
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    self.stop()
                    self.window?.close()
                case .failure(let error):
                    self.state.error = error
                }
            }
        }
    }

    private func startCapture() {
        // A dismissed mirror stays in the session's dictionary so the poll does not
        // hand that window a fresh mirror a second after the person closed it. That
        // record must not also keep a frame stream alive for a window nobody is
        // looking at, so an invisible proxy is simply not started.
        guard frameClient == nil, !startingCapture,
              window?.isMiniaturized != true, window?.isVisible != false else { return }
        startingCapture = true
        let configuredFPS = UserDefaults.standard.integer(forKey: "fusionFPSPolicy")
        let fps = configuredFPS == 0 ? (window?.isKeyWindow == true ? 15 : 5) : configuredFPS
        let client = FrameClient(space: space, target: .window(remoteWindow.identity), maxFPS: fps, targetWidth: Int(window?.contentView?.bounds.width ?? 0), targetHeight: Int(window?.contentView?.bounds.height ?? 0))
        frameClient = client; state.frameClient = client; startingCapture = false; client.start()
    }

    private func restartCapture() {
        stop()
        startCapture()
    }

    /// One action toward the agent.
    ///
    /// Deliberate gestures go straight onto the proxy's queue, in order. Pointer
    /// travel goes through the coalescer first: it is the only input that is
    /// *state*, and a wave across the window would otherwise put a hundred
    /// stale positions in front of the click that ended it.
    private func send(_ action: JSONValue) {
        if action["type"]?.stringValue == "move" {
            travel.offer(action, now: Date())
            travel.pump()
            return
        }
        perform(action)
    }

    /// Claim the human lease without performing input. The button is down, so
    /// the agent's pause starts now rather than when the gesture is posted.
    private func claimHuman() {
        let space = self.space, remote = remoteWindow
        queue.async { [weak self] in
            if case .failure(let error) = SpaceService().windowClaimHuman(for: space, window: remote) {
                Task { @MainActor in self?.state.error = error }
            }
        }
    }

    private func perform(_ action: JSONValue) {
        let space = self.space, remote = remoteWindow
        queue.async { [weak self] in
            let result = SpaceService().windowInput(for: space, window: remote, action: action)
            Task { @MainActor in
                guard let self else { return }
                // The travel slot has to be released whether or not the worker
                // answered, or one failed hover silences the pointer forever.
                if action["type"]?.stringValue == "move" { self.travel.finished() }
                if case .failure(let error) = result { self.state.error = error }
            }
        }
    }
}
