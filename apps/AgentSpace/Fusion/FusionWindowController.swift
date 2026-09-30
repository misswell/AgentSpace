import AppKit
import Combine
import SwiftUI
import AgentSpaceCore

@MainActor
final class FusionWindowController: NSWindowController, NSWindowDelegate {
    private(set) var remoteWindow: RemoteWindow
    private let space: AgentAccount
    private let service = SpaceService()
    private let state = FusionWindowState()
    private let queue: DispatchQueue
    private var startingCapture = false
    private var frameClient: FrameClient?
    private var activityTracker = FrameActivityTracker()
    private var captureRateTimer: Timer?
    private var liveCaptureFPS: Int?
    private var resizeWork: DispatchWorkItem?
    private var resizingFromAgent = false
    private var hasShown = false
    private var lastRequestedSize: NSSize?
    private let input = RemoteViewerInput()
    private var keyboardMonitor: Any?
    private var stateSubscriptions: Set<AnyCancellable> = []
    private var captureQuality = DisplayQuality.default
    /// The pointer's own drawn cursor, so the proxy's content area shows the
    /// agent's pointer rather than the picture's baked-in one.
    private let overlay = RemoteCursorOverlayProxy()

    init(space: AgentAccount, remoteWindow: RemoteWindow) {
        self.space = space
        self.remoteWindow = remoteWindow
        self.queue = DispatchQueue(label: BundleIdentifiers.app + ".fusion.\(remoteWindow.pid).\(remoteWindow.id)")
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1200, height: 900)
        let size = NSSize(
            width: min(remoteWindow.frame.width, visible.width),
            height: min(remoteWindow.frame.height, visible.height))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        // The title bar occupies part of the visible screen too.
        let titlebarHeight = window.frame.height - size.height
        if window.frame.height > visible.height {
            window.setContentSize(NSSize(width: size.width,
                                         height: max(80, visible.height - titlebarHeight)))
        }
        window.title = "\(space.displayName) — \(remoteWindow.appName)"
        window.isReleasedWhenClosed = false
        window.isMovable = true
        window.collectionBehavior = [.managed, .participatesInCycle]
        window.contentMinSize = NSSize(width: 80, height: 80)
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: FusionWindowView(
            state: state, input: input,
            send: { [weak self] gesture in self?.send(gesture) },
            claimHuman: { [weak self] in self?.claimHuman() },
            releaseHuman: { [weak self] in self?.releaseHuman() },
            overlay: overlay,
            onDragActivity: { [weak self] active in self?.setGestureRate(active) }))
        installTitlebarAction()
        openChannel()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func openChannel() {
        guard stateSubscriptions.isEmpty else { return }
        state.contentSize = NSSize(width: remoteWindow.frame.width, height: remoteWindow.frame.height)
        input.configure(space: space, surface: .window(remoteWindow.identity, remoteWindow.frame))
        input.onCursor = { [weak self] presentation in self?.overlay.apply(presentation) }
        input.onCursorChannelChange = { [weak self] _ in self?.refreshCursorPresentation() }
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshCursorPresentation()
                let quality = DisplayQuality.parse(UserDefaults.standard.string(forKey: DisplayQuality.storageKey)) ?? .default
                if quality != self.captureQuality {
                    self.captureQuality = quality
                    self.restartCapture()
                } else {
                    self.updateCaptureRate()
                }
            }
            .store(in: &stateSubscriptions)
        if let window {
            keyboardMonitor = RemoteKeyboardMonitor.install(window: window,
                permitsInput: { [weak self] in self?.frameClient != nil }) { [weak self] action in
                    self?.sendKey(action)
                }
        }
    }

    func update(remote: RemoteWindow) {
        remoteWindow = remote
        state.contentSize = NSSize(width: remote.frame.width, height: remote.frame.height)
        input.configure(space: space, surface: .window(remote.identity, remote.frame))
    }

    private func refreshCursorPresentation() {
        let mode = MouseCaptureMode.parse(UserDefaults.standard.string(forKey: MouseCaptureMode.storageKey)) ?? .default
        let live = input.cursorChannelActive
        overlay.hidesCursor = !mode.hidesInternalCursor
        overlay.isDrawingCursor = live && !mode.hidesInternalCursor
        frameClient?.setEmbeddedCursor(mode.embedsCursor(cursorChannelActive: live))
    }

    private func closeChannel() {
        stateSubscriptions.removeAll()
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        keyboardMonitor = nil
        overlay.detach()
        input.shutdown()
    }

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

    func show() {
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        hasShown = true
        // The host screen may be smaller than the agent's existing window.
        // Bring the actual app to the size the person can see here.
        requestResize()
        startCapture()
    }

    func showAndResume() {
        openChannel()
        window?.makeKeyAndOrderFront(nil)
        resumeCapture()
    }

    override func close() {
        stop()
        closeChannel()
        super.close()
    }

    func resumeCapture() { startCapture() }

    func stop() {
        resizeWork?.cancel(); resizeWork = nil
        captureRateTimer?.invalidate(); captureRateTimer = nil
        frameClient?.onFrameArrived = nil
        frameClient?.stop(); frameClient = nil; state.frameClient = nil
        liveCaptureFPS = nil
        startingCapture = false
        // A position collected for a window that is no longer being watched must
        // not be posted to the agent afterwards, and a person who left must not
        // leave automation paused for five more seconds.
        input.reset()
        input.releaseHuman()
    }

    /// The session-level link was refused or went away, so this proxy stops
    /// polling for as long as the link says the worker will not answer.
    ///
    /// Deliberately not `stop()`: the `window.stream.stop` RPC would go to the
    /// same worker that just refused, and the stream is reaped server-side by
    /// the idle watchdog the moment this proxy stops pulling.
    func suspend(for error: AgentSpaceError) {
        startingCapture = false
        captureRateTimer?.invalidate(); captureRateTimer = nil
        frameClient?.onFrameArrived = nil
        frameClient?.stop(); frameClient = nil; state.frameClient = nil
        liveCaptureFPS = nil
        input.reset()
        overlay.detach()
        input.releaseHuman()
        state.error = error
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // Activating the window is an RPC, not input: it asks the worker to raise
        // the window it mirrors, which is a deliberate cross-process action rather
        // than a hand movement.
        let space = self.space, remote = remoteWindow
        queue.async { _ = SpaceService().windowActivate(for: space, window: remote) }
        setCaptureRateForFocus()
    }

    func windowDidResignKey(_ notification: Notification) {
        setCaptureRateForFocus()
        // Focus left, so this proxy is no longer under the person's hand: the
        // lease goes back and automation may resume.
        input.releaseHuman()
    }

    /// A background proxy does not need to move at the key window's rate, and a
    /// minimised one needs to move not at all.
    private func setCaptureRateForFocus() {
        updateCaptureRate()
    }

    func windowDidMiniaturize(_ notification: Notification) { stop() }
    func windowDidDeminiaturize(_ notification: Notification) { startCapture() }

    func windowDidResize(_ notification: Notification) {
        guard hasShown, !resizingFromAgent, window?.isMiniaturized != true else { return }
        requestResize()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        input.setPointerRate(HostDisplayRefresh.pointerRate(for: window))
    }

    func windowDidEndLiveResize(_ notification: Notification) { requestResize(immediate: true) }

    /// Size is expressed in points on both desktops. The frame client separately
    /// requests enough device pixels for the local display's backing scale.
    private func requestResize(immediate: Bool = false) {
        guard let size = window?.contentView?.bounds.size, size.width > 40, size.height > 40 else { return }
        resizeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.lastRequestedSize != size || immediate else { return }
            self.lastRequestedSize = size
            let space = self.space, remote = self.remoteWindow
            self.queue.async { [weak self] in
                let result = SpaceService().windowSetSize(for: space, window: remote,
                                                          width: size.width, height: size.height)
                Task { @MainActor in
                    guard let self else { return }
                    switch result {
                    case .success(let actual):
                        self.state.error = nil
                        // Apps can impose a minimum or maximum. Match what the
                        // app actually accepted once the person releases the edge.
                        guard self.window?.isVisible == true else { return }
                        guard self.window?.contentView?.inLiveResize != true else { return }
                        let current = self.window?.contentView?.bounds.size ?? .zero
                        guard abs(current.width - size.width) <= 1,
                              abs(current.height - size.height) <= 1 else { return }
                        let accepted = NSSize(width: actual.width, height: actual.height)
                        if abs(accepted.width - size.width) > 1 || abs(accepted.height - size.height) > 1 {
                            self.resizingFromAgent = true
                            self.window?.setContentSize(accepted)
                            self.resizingFromAgent = false
                            self.lastRequestedSize = accepted
                        }
                    case .failure(let error):
                        self.lastRequestedSize = nil
                        self.state.error = error
                    }
                }
            }
        }
        resizeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0 : 0.08), execute: work)
    }

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
        closeChannel()
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
                    self.closeChannel()
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
        let fps = ViewerFrameRate.ceiling()
        let scale = window?.backingScaleFactor ?? 1
        captureQuality = DisplayQuality.parse(UserDefaults.standard.string(forKey: DisplayQuality.storageKey)) ?? .default
        let size = captureQuality.captureSize(sourceWidth: Int(remoteWindow.frame.width * scale),
                                             sourceHeight: Int(remoteWindow.frame.height * scale))
        let client = FrameClient(space: space, target: .window(remoteWindow.identity),
            maxFPS: fps, targetWidth: size.width, targetHeight: size.height)
        activityTracker = FrameActivityTracker()
        liveCaptureFPS = fps
        client.onFrameArrived = { [weak self, weak client] in
            guard let self, self.frameClient === client else { return }
            self.activityTracker.noteChange(at: Date())
            self.updateCaptureRate()
        }
        frameClient = client; state.frameClient = client; startingCapture = false; client.start()
        captureRateTimer?.invalidate()
        captureRateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateCaptureRate() }
        }
        refreshCursorPresentation()
    }

    private func restartCapture() {
        stop()
        startCapture()
    }

    private func send(_ gesture: RemotePointerGesture) {
        if case .scroll = gesture { activityTracker.noteScroll(at: Date()) }
        else { activityTracker.noteChange(at: Date()) }
        updateCaptureRate()
        input.send(gesture)
    }

    private func setGestureRate(_ active: Bool) {
        activityTracker.notePress(active, at: Date())
        updateCaptureRate()
    }

    private func updateCaptureRate() {
        guard let frameClient else { return }
        let policy = InputRatePolicy(ceiling: ViewerFrameRate.ceiling(),
                                     pointerRate: HostDisplayRefresh.pointerRate(for: window))
        input.setPointerRate(policy.pointerRate)
        let fps = policy.frames(for: activityTracker.activity(at: Date()))
        guard liveCaptureFPS != fps else { return }
        liveCaptureFPS = fps
        frameClient.setFPS(fps)
    }

    private func claimHuman() { input.claimHuman() }
    private func releaseHuman() { input.releaseHuman() }

    private func sendKey(_ action: InputAction) {
        activityTracker.noteChange(at: Date())
        updateCaptureRate()
        if input.sendKeyAction(action) { return }
        let json: JSONValue
        switch action {
        case .key(let combo): json = .obj(["type": .string("key"), "key": .string(combo)])
        case .type(let text): json = .obj(["type": .string("type"), "text": .string(text)])
        default: return
        }
        let space = self.space, remote = remoteWindow
        queue.async { [weak self] in
            let result = SpaceService().windowInput(for: space, window: remote, action: json)
            Task { @MainActor in
                if case .failure(let error) = result { self?.state.error = error }
            }
        }
    }
}
