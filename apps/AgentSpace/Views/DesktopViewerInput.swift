import AppKit
import Combine
import AgentSpaceCore

/// Turns the desktop viewer's pointer gestures into packets on the fast channel.
///
/// This used to go through `SpaceService.input` — the same JSON RPC an agent
/// uses — and the reasoning was sound at the time: a person driving the agent's
/// desktop should be refused by exactly the rules an agent is refused by, and a
/// second transport is a second place for those rules to be wrong. What it cost
/// was the one thing a mouse is judged on. Every move opened a socket, encoded a
/// request and waited for a reply; measured on this machine that was p95 3.98 ms
/// per call (§327 row 894), which is invisible at 5 FPS and obvious at 60 — and
/// the pointer is what a hand compares against its own motion at a much finer
/// resolution than any frame rate.
///
/// So the pointer moved to `input.sock`, and the *rules did not move*: the
/// worker re-asks the session verdict, the desktop readiness, the Accessibility
/// grant and the human lease for every packet, from the same code the RPC path
/// uses. `SpaceService.input` remains the transport for keys and for everything
/// an agent does.
@MainActor
final class DesktopViewerInput: ObservableObject {
    /// A refusal worth interrupting the desktop for. A skipped hover is not one:
    /// pointer travel is refused by design while nobody holds the lease, and
    /// replacing a working desktop with a message about a hover would be the
    /// viewer manufacturing its own problem.
    @Published private(set) var refusal: AppModel.PresentedError?
    /// True once the channel is up and the worker has promised a cursor of its
    /// own, which is what lets the viewer hide the local one and stop drawing
    /// the cursor that is baked into the frames.
    @Published private(set) var cursorChannelActive = false

    private var space: AgentAccount?
    private var display: DisplayGeometry?
    private var client: InputClient?
    private var subscriptions: Set<AnyCancellable> = []
    private var legacyPointer = LegacyDesktopPointer()
    private let legacyQueue = DispatchQueue(label: BundleIdentifiers.app + ".desktop.legacy-input",
                                            qos: .userInteractive)
    /// One coalescer, at the display's own rate. Travel is state: at most one
    /// packet is being written while at most one newer position waits behind it,
    /// and a wave across the desktop cannot queue a hundred stale positions ahead
    /// of the click that ended it.
    ///
    /// Built in `configure` rather than lazily, because its sender needs the
    /// client that only exists once an account is known — and because a lazy
    /// initialiser that reaches back into `self` cannot both reference and
    /// release the coalescer it is building.
    ///
    /// The slot is released as soon as the packet is handed to the writer rather
    /// than when the worker answers: travel has no answer worth waiting for, and
    /// holding the slot for a round trip is the request/reply shape this channel
    /// exists to remove.
    private var travel: PointerTravelCoalescer<(x: Double, y: Double)>?
    private var pendingTravelPump: Task<Void, Never>?
    private var dragActive = false
    /// The display point of the last gesture's press, so a drag's phases all
    /// resolve against the frame the press named.
    private var lastPressPoint: (x: Double, y: Double)?

    func configure(space: AgentAccount, display: DisplayGeometry) {
        self.space = space
        self.display = display
        let rate = DisplayRefresh.defaultPointerRate
        if client == nil {
            let created = InputClient(space: space)
            client = created
            travel = PointerTravelCoalescer(minimumInterval: 1.0 / rate) { [weak self] point in
                guard let self else { return }
                if self.client?.state.isReady == true {
                    self.client?.move(to: point, target: .desktop)
                    self.travel?.finished()
                } else if let space = self.space {
                    // The old RPC has a reply. Hold the one in-flight slot until
                    // it arrives so a wave of hovers cannot queue ahead of a click.
                    self.legacyQueue.async { [weak self] in
                        let error = SpaceService().input(for: space,
                                                         actions: [.move(x: point.x, y: point.y)])
                        Task { @MainActor [weak self] in
                            self?.present(error, space: space)
                            self?.travel?.finished()
                            self?.schedulePendingTravel()
                        }
                    }
                } else {
                    self.travel?.finished()
                }
            }
            created.connect()
            observe(created)
        } else {
            travel?.setMinimumInterval(1.0 / rate)
        }
    }

    /// Follow the channel: its state decides whether this viewer may hide the
    /// local cursor, and its published position is what the overlay draws.
    ///
    /// Subscribed rather than polled, and the position is forwarded straight to
    /// the report closure instead of through a `@Published` property: it updates
    /// at display rate, and a SwiftUI invalidation per position would redraw the
    /// whole viewer at 120 Hz to move one AppKit layer.
    private func observe(_ client: InputClient) {
        subscriptions.removeAll()
        client.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                let next = state.isReady && client.capabilities.contains(.cursorShapes)
                guard next != self.cursorChannelActive else { return }
                self.cursorChannelActive = next
                self.onCursorChannelChange?(next)
                if !state.isReady { self.travel?.reset() }
            }
            .store(in: &subscriptions)
        client.$capabilities
            .receive(on: RunLoop.main)
            .sink { [weak self] capabilities in
                guard let self else { return }
                let next = (self.client?.state.isReady == true) && capabilities.contains(.cursorShapes)
                guard next != self.cursorChannelActive else { return }
                self.cursorChannelActive = next
                self.onCursorChannelChange?(next)
            }
            .store(in: &subscriptions)
        client.$remoteCursor
            .receive(on: RunLoop.main)
            .sink { [weak self] presentation in
                self?.onCursor?(presentation)
            }
            .store(in: &subscriptions)
        client.$lastRefusal
            .receive(on: RunLoop.main)
            .sink { [weak self] error in
                guard let self else { return }
                guard let error, let space = self.space else {
                    self.refusal = nil
                    return
                }
                self.refusal = AppModel.PresentedError(code: error.code.rawValue,
                    message: error.message, fix: error.code.remediation, spaceName: space.name)
            }
            .store(in: &subscriptions)
    }

    /// Called with every position the worker publishes, so the surface can draw
    /// it. Set by the viewer when it creates this object.
    var onCursor: ((InputClient.CursorPresentation?) -> Void)?
    /// Called when the channel comes up or goes away, so the host can act once
    /// per transition rather than once per packet.
    var onCursorChannelChange: ((Bool) -> Void)?

    var remoteCursor: InputClient.CursorPresentation? { client?.remoteCursor }

    /// Follow the display's pointer rate, which the viewer adjusts with the
    /// capture rate: a 60 FPS drag wants 60 Hz travel, and a still desktop does
    /// not need 120.
    func setPointerRate(_ rate: Double) {
        travel?.setMinimumInterval(1.0 / max(1, rate))
    }

    func send(_ gesture: RemotePointerGesture) {
        guard let client, let display, let space else { return }
        if case .hover(let u, let v) = gesture {
            travel?.offer(Self.point(u, v, display), now: Date())
            schedulePendingTravel()
            return
        }
        // Versions before the fast channel have no input.sock. Keep the
        // original RPC usable, including the raw phases emitted by Desktop Mode.
        // Once a press starts there, its release must finish on that path too.
        if !client.state.isReady || legacyPointer.hasPendingPress {
            if let action = legacyPointer.action(for: gesture, display: display) {
                legacyQueue.async { [weak self] in
                    let error = SpaceService().input(for: space, actions: [action])
                    Task { @MainActor [weak self] in self?.present(error, space: space) }
                }
            }
            return
        }
        switch gesture {
        case .hover:
            break // handled above, on either transport

        case .click(let u, let v, let button, let count, let modifiers):
            // A click is still expressible as down + up on the fast channel, and
            // that is what it becomes: the worker posts the same two events, and
            // the click state carries the count so a double-click stays one.
            let point = Self.point(u, v, display)
            client.pointerDown(at: point, target: .desktop, button: button,
                               clickCount: 1, modifiers: modifiers)
            client.pointerUp(at: point, target: .desktop, button: button,
                             clickCount: max(1, count), modifiers: modifiers)

        case .drag(let fromU, let fromV, let toU, let toV, let button, let modifiers):
            let press = Self.point(fromU, fromV, display)
            let release = Self.point(toU, toV, display)
            client.pointerDown(at: press, target: .desktop, button: button, clickCount: 1, modifiers: modifiers)
            client.pointerDrag(from: press, to: release, target: .desktop, button: button, modifiers: modifiers)
            client.pointerUp(at: release, target: .desktop, button: button, clickCount: 1, modifiers: modifiers)

        case .pointerDown(let u, let v, let button, let clickCount, let modifiers):
            dragActive = true
            travel?.reset()
            let point = Self.point(u, v, display)
            lastPressPoint = point
            client.pointerDown(at: point, target: .desktop, button: button,
                               clickCount: clickCount, modifiers: modifiers)

        case .pointerDrag(let fromU, let fromV, let toU, let toV, let button, let modifiers):
            let from = Self.point(fromU, fromV, display)
            let to = Self.point(toU, toV, display)
            // The gesture's own basis: the point the press named, not the point
            // this packet starts from, so a window that has already moved does
            // not make the drag chase itself.
            let origin = lastPressPoint ?? from
            client.pointerDrag(from: origin, to: to, target: .desktop, button: button, modifiers: modifiers)
            lastPressPoint = to

        case .pointerUp(let u, let v, let button, let clickCount, let modifiers):
            dragActive = false
            lastPressPoint = nil
            let point = Self.point(u, v, display)
            client.pointerUp(at: point, target: .desktop, button: button,
                             clickCount: clickCount, modifiers: modifiers)

        case .scroll(let u, let v, let linesX, let linesY):
            let point = Self.point(u, v, display)
            client.scroll(at: point, target: .desktop, dx: linesX, dy: linesY)
        }
    }

    /// A person has taken the desktop: automation pauses now rather than when
    /// the first press arrives, and resumes when they leave.
    func claimHuman() {
        client?.acquireHuman()
    }

    func releaseHuman() {
        client?.releaseHuman()
    }

    func sendKey(_ combo: String) {
        client?.key(combo)
    }

    func sendText(_ text: String) {
        client?.type(text)
    }

    /// Send a key or a typed string over the fast channel. Returns false when the
    /// channel is not up, which is the caller's signal to use the RPC path — the
    /// fallback a worker from before this channel needs.
    func sendKeyAction(_ action: InputAction) -> Bool {
        guard let client, client.state.isReady else { return false }
        switch action {
        case .key(let combo): client.key(combo); return true
        case .type(let text): client.type(text); return true
        default: return false
        }
    }

    /// Positions collected for a desktop nobody is watching any more must not be
    /// posted after it, and a person who has left must not leave automation
    /// paused.
    func reset() {
        pendingTravelPump?.cancel()
        pendingTravelPump = nil
        dragActive = false
        lastPressPoint = nil
        legacyPointer.reset()
        travel?.reset()
        client?.releaseHuman()
    }

    /// Closes the channel. The worker sees the socket end, which is also its
    /// fail-safe for a client that died mid-gesture.
    func shutdown() {
        reset()
        subscriptions.removeAll()
        client?.disconnect()
        client = nil
        cursorChannelActive = false
    }

    /// The gesture's fraction of the captured display, as the point on it that
    /// `input` accepts. `PreviewMapping` owns the rounding because the viewer's
    /// letterbox and a screenshot's downscale both resolve through it.
    private static func point(_ u: Double, _ v: Double, _ display: DisplayGeometry) -> (x: Double, y: Double) {
        PreviewMapping.displayPoint(u: u, v: v, displayWidth: display.width, displayHeight: display.height)
    }

    private func present(_ error: AgentSpaceError?, space: AgentAccount) {
        guard let error else {
            if refusal != nil { refusal = nil }
            return
        }
        refusal = AppModel.PresentedError(code: error.code.rawValue, message: error.message,
                                          fix: error.code.remediation, spaceName: space.name)
    }

    /// A last hover can arrive inside one display-refresh interval just after the
    /// previous packet's slot was released. No more mouse events are guaranteed,
    /// so it needs its own wakeup; otherwise the cursor can stop at an old
    /// position.
    private func schedulePendingTravel() {
        guard let delay = travel?.pendingDelay(), pendingTravelPump == nil else { return }
        pendingTravelPump = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(1, ceil(delay * 1_000_000_000))))
            guard let self else { return }
            self.pendingTravelPump = nil
            guard !Task.isCancelled else { return }
            self.travel?.pump()
            self.schedulePendingTravel()
        }
    }
}
