import AppKit
import Combine
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
    /// The account's shared fast input channel, aimed at this window's identity.
    /// One connection per account serves every surface: a packet names its
    /// target, so a proxy's backlog can never sit in front of a desktop click.
    private var channel: InputChannel?
    private var channelClient: InputClient?
    private var stateSubscriptions: Set<AnyCancellable> = []
    /// The window frame a gesture resolves against, taken when the button goes
    /// down. A drag is usually what *moves* the window, so every later packet of
    /// the same gesture has to answer "which window, at which geometry" the way
    /// the press did — otherwise the pointer accelerates away from the hand.
    private var gestureFrame: CGRectValue?
    /// Pointer travel is state, not a gesture: one packet in flight and only the
    /// newest position behind it, so a wave across the proxy cannot put a hundred
    /// stale positions in front of the click that follows.
    ///
    /// Built in `init` rather than lazily: its sender reaches back into `self`,
    /// and a lazy initialiser that does so cannot also finish its own slot.
    private var travel: PointerTravelCoalescer<(x: Double, y: Double)>?
    /// The pointer's own drawn cursor, so the proxy's content area shows the
    /// agent's pointer rather than the picture's baked-in one.
    private let overlay = RemoteCursorOverlayProxy()

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
            send: { [weak self] gesture in self?.send(gesture) },
            claimHuman: { [weak self] in self?.claimHuman() },
            releaseHuman: { [weak self] in self?.releaseHuman() },
            overlay: overlay,
            sendKey: { [weak self] action in self?.sendKey(action) }))
        travel = PointerTravelCoalescer(minimumInterval: 1.0 / DisplayRefresh.defaultPointerRate) { [weak self] point in
            guard let self else { return }
            self.deliverTravel(point)
            // Released at once: the newest position replaces whatever is pending,
            // which is the whole contract of a travel coalescer.
            self.travel?.finished()
        }
        installTitlebarAction()
        openChannel()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The account's channel, taken once per window and released when it closes.
    private func openChannel() {
        guard channel == nil else { return }
        let shared = InputChannelRegistry.shared.channel(for: space)
        channel = shared
        let client = shared.use()
        channelClient = client
        // The channel's own state drives one thing here: whether the proxy may
        // draw the agent's cursor itself. Before it can, the picture's painted
        // cursor is what the person sees, and it must stay.
        client.$capabilities
            .receive(on: RunLoop.main)
            .sink { [weak self] capabilities in
                guard let self else { return }
                let live = self.channelClient?.state.isReady == true && capabilities.contains(.cursorShapes)
                self.overlay.isDrawingCursor = live
            }
            .store(in: &stateSubscriptions)
        client.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] newState in
                guard let self else { return }
                if !newState.isReady { self.overlay.detach(); self.travel?.reset() }
            }
            .store(in: &stateSubscriptions)
        client.$remoteCursor
            .receive(on: RunLoop.main)
            .sink { [weak self] presentation in self?.overlay.apply(presentation) }
            .store(in: &stateSubscriptions)
    }

    private func closeChannel() {
        stateSubscriptions.removeAll()
        overlay.detach()
        channel?.endUse()
        channel = nil
        channelClient = nil
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
        // not be posted to the agent afterwards, and a person who left must not
        // leave automation paused for five more seconds.
        travel?.reset()
        channelClient?.releaseHuman()
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
        travel?.reset()
        overlay.detach()
        channelClient?.releaseHuman()
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
        channelClient?.releaseHuman()
    }

    /// A background proxy does not need to move at the key window's rate, and a
    /// minimised one needs to move not at all.
    private func setCaptureRateForFocus() {
        guard UserDefaults.standard.integer(forKey: "fusionFPSPolicy") == 0 else { return }
        let target = window?.isKeyWindow == true ? Self.keyWindowFPS : Self.backgroundFPS
        frameClient?.setFPS(target)
    }

    /// The key window's rate. Was 15 while the cursor lived inside the frames;
    /// with a cursor channel the picture only has to keep up with its content,
    /// and 15 was where scroll and video visibly stepped.
    static let keyWindowFPS = 30
    /// A proxy behind another window costs almost nothing to keep current.
    static let backgroundFPS = 5
    /// A gesture is a picture that has to move with a hand.
    static let gestureFPS = 60

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
        let configuredFPS = UserDefaults.standard.integer(forKey: "fusionFPSPolicy")
        let fps = configuredFPS == 0
            ? (window?.isKeyWindow == true ? Self.keyWindowFPS : Self.backgroundFPS)
            : configuredFPS
        let client = FrameClient(space: space, target: .window(remoteWindow.identity), maxFPS: fps, targetWidth: Int(window?.contentView?.bounds.width ?? 0), targetHeight: Int(window?.contentView?.bounds.height ?? 0))
        frameClient = client; state.frameClient = client; startingCapture = false; client.start()
        // Once the cursor channel is up, the picture must stop painting a cursor
        // of its own: two cursors drawn from two sources is the trailing ghost
        // this path exists to remove, and zero is worse than both.
        client.setEmbeddedCursor(!overlay.isDrawingCursor)
    }

    private func restartCapture() {
        stop()
        startCapture()
    }

    /// One gesture from the proxy's surface.
    ///
    /// Travel goes through the coalescer first — it is the only input that is
    /// *state* — while a deliberate gesture goes straight out, in order.
    private func send(_ gesture: RemotePointerGesture) {
        guard let client = channelClient, client.state.isReady else {
            // No fast channel: a worker from before it, or one that is not up
            // yet. The RPC path is still correct, so this is a fallback.
            fallback(gesture)
            return
        }
        let target = InputTarget.window(remoteWindow.identity)
        switch gesture {
        case .hover(let u, let v):
            travel?.offer((x: u, y: v), now: Date())
            travel?.pump()

        case .pointerDown(let u, let v, let button, let clickCount, let modifiers):
            // The gesture's basis, taken once: every later phase resolves against
            // this frame until the button comes up.
            gestureFrame = remoteWindow.frame
            client.pointerDown(at: (x: u, y: v), target: target, button: button,
                               clickCount: clickCount, modifiers: modifiers)
            setGestureRate(true)

        case .pointerDrag(let fromU, let fromV, let toU, let toV, let button, let modifiers):
            // Deliberately the same frame the press named rather than the packet's
            // own `from`: the proxy's wire keeps a from/to pair for the atomic
            // `drag` action, while a live gesture is a chain of points.
            let origin = gestureFrame != nil ? lastDragPoint ?? (x: fromU, y: fromV) : (x: fromU, y: fromV)
            client.pointerDrag(from: origin, to: (x: toU, y: toV), target: target,
                               button: button, modifiers: modifiers)
            lastDragPoint = (x: toU, y: toV)

        case .pointerUp(let u, let v, let button, let clickCount, let modifiers):
            client.pointerUp(at: (x: u, y: v), target: target, button: button,
                             clickCount: clickCount, modifiers: modifiers)
            gestureFrame = nil
            lastDragPoint = nil
            setGestureRate(false)

        case .click(let u, let v, let button, let count, let modifiers):
            client.pointerDown(at: (x: u, y: v), target: target, button: button,
                               clickCount: 1, modifiers: modifiers)
            client.pointerUp(at: (x: u, y: v), target: target, button: button,
                             clickCount: max(1, count), modifiers: modifiers)

        case .drag(let fromU, let fromV, let toU, let toV, let button, let modifiers):
            client.pointerDown(at: (x: fromU, y: fromV), target: target, button: button,
                               clickCount: 1, modifiers: modifiers)
            client.pointerDrag(from: (x: fromU, y: fromV), to: (x: toU, y: toV), target: target,
                               button: button, modifiers: modifiers)
            client.pointerUp(at: (x: toU, y: toV), target: target, button: button,
                             clickCount: 1, modifiers: modifiers)

        case .scroll(let u, let v, let linesX, let linesY):
            client.scroll(at: (x: u, y: v), target: target, dx: linesX, dy: linesY)
        }
    }

    /// The last point a live drag reported, so the next packet starts where the
    /// hand actually is rather than where the gesture began.
    private var lastDragPoint: (x: Double, y: Double)?

    /// A gesture is in progress: the window has to move with the hand, which means
    /// the capture rate follows the gesture rather than the preference.
    private func setGestureRate(_ active: Bool) {
        guard UserDefaults.standard.integer(forKey: "fusionFPSPolicy") == 0 else { return }
        frameClient?.setFPS(active ? Self.gestureFPS : (window?.isKeyWindow == true ? Self.keyWindowFPS : Self.backgroundFPS))
        channelClient?.acquireHuman()
    }

    /// The pre-0.1.38 path: one `window.input` RPC per action, through the JSON
    /// transport. A worker that predates the fast channel answers it correctly,
    /// which is the whole reason it is kept.
    private func fallback(_ gesture: RemotePointerGesture) {
        let action = FusionInputRouter.action(for: gesture)
        if action["type"]?.stringValue == "move" {
            let point = (x: action["xFraction"]?.doubleValue ?? 0, y: action["yFraction"]?.doubleValue ?? 0)
            travel?.offer(point, now: Date())
            travel?.pump()
            return
        }
        perform(action)
    }

    private func deliverTravel(_ point: (x: Double, y: Double)) {
        if let client = channelClient, client.state.isReady {
            client.move(to: point, target: .window(remoteWindow.identity))
            return
        }
        perform(.obj(["type": .string("move"),
                      "xFraction": .double(point.x), "yFraction": .double(point.y)]))
    }

    /// Claim the human lease without performing input. The button is down, so
    /// the agent's pause starts now rather than when the gesture is posted.
    private func claimHuman() {
        if let client = channelClient, client.state.isReady {
            client.acquireHuman()
            return
        }
        let space = self.space, remote = remoteWindow
        queue.async { [weak self] in
            if case .failure(let error) = SpaceService().windowClaimHuman(for: space, window: remote) {
                Task { @MainActor in self?.state.error = error }
            }
        }
    }

    /// One keystroke, over the fast channel when it is up and the RPC path when
    /// it is not. Both end in the worker's own `KeyCombo` parser, so a combo that
    /// an agent could send is a combo a person can type.
    private func sendKey(_ action: JSONValue) {
        if let client = channelClient, client.state.isReady {
            if let combo = action["key"]?.stringValue { client.key(combo); return }
            if let text = action["text"]?.stringValue { client.type(text); return }
        }
        perform(action)
    }

    /// The person left this proxy. Automation resumes immediately rather than
    /// when the five-second fail-safe would have expired.
    private func releaseHuman() {
        channelClient?.releaseHuman()
    }

    private func perform(_ action: JSONValue) {
        let space = self.space, remote = remoteWindow
        queue.async { [weak self] in
            let result = SpaceService().windowInput(for: space, window: remote, action: action)
            Task { @MainActor in
                guard let self else { return }
                // The travel slot has to be released whether or not the worker
                // answered, or one failed hover silences the pointer forever.
                if action["type"]?.stringValue == "move" { self.travel?.finished() }
                if case .failure(let error) = result { self.state.error = error }
            }
        }
    }
}
