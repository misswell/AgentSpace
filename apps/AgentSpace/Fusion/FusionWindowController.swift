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
    private var timer: DispatchSourceTimer?
    private var startingCapture = false
    private var closingRemote = false
    private var frameInFlight = false
    private var streamFPS = 5
    private var pullsWithoutFrame = 0
    private var rebuildWork: DispatchWorkItem?
    private var rebuildAttempt = 0
    /// Gaps between rebuild attempts, so a worker that is restarting — or a
    /// window that vanished — costs a decaying trickle of RPCs, not one per
    /// frame pull.
    private static let rebuildDelays: [TimeInterval] = [0.5, 1, 2, 4, 8]

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
        window.contentView = NSHostingView(rootView: FusionWindowView(state: state) { [weak self] action in
            self?.send(action)
        })
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
        timer?.cancel(); timer = nil
        startingCapture = false
        rebuildWork?.cancel()
        rebuildWork = nil
        pullsWithoutFrame = 0
        let space = self.space, remote = remoteWindow
        queue.async { SpaceService().windowStreamStop(for: space, window: remote) }
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

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closingRemote { stop(); return true }
        let space = self.space, remote = remoteWindow
        queue.async { [weak self] in
            let result = SpaceService().windowClose(for: space, window: remote)
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    self.closingRemote = true
                    self.window?.performClose(nil)
                case .failure(let error): self.state.error = error
                }
            }
        }
        return false
    }

    private func startCapture() {
        guard timer == nil, !startingCapture, window?.isMiniaturized != true else { return }
        startingCapture = true
        pullsWithoutFrame = 0
        let space = self.space, remote = remoteWindow
        let configuredFPS = UserDefaults.standard.integer(forKey: "fusionFPSPolicy")
        let fps = configuredFPS == 0 ? (window?.isKeyWindow == true ? 15 : 5) : configuredFPS
        streamFPS = fps
        queue.async { [weak self] in
            switch SpaceService().windowStreamStart(for: space, window: remote, maxFPS: fps) {
            case .failure(let error):
                Task { @MainActor in
                    guard let self else { return }
                    self.startingCapture = false
                    self.scheduleRebuild(after: error)
                }
            case .success:
                self?.beginFrameTimer(fps: fps)
            }
        }
    }

    private func restartCapture() {
        stop()
        startCapture()
    }

    /// Put the stream back up after it stopped producing frames.
    ///
    /// This is the only path out of a worker restart. The new worker has no
    /// stream for this window, `window.stream.frame` answers PREVIEW_NOT_RUNNING
    /// to every pull, and a `startCapture()` blocked by the live timer would
    /// never re-issue `window.stream.start` — the proxy would keep showing the
    /// last frame of the old worker indefinitely.
    private func scheduleRebuild(after error: AgentSpaceError? = nil) {
        if let error { state.error = error }
        // A session that can no longer be captured is not retried here: the
        // refusal is the outcome, and the window list refresh drops the proxy.
        guard error?.code != .sessionIsConsole, error?.code != .noWindowServer else {
            stop()
            return
        }
        guard rebuildWork == nil else { return }
        let delay = Self.rebuildDelays[min(rebuildAttempt, Self.rebuildDelays.count - 1)]
        rebuildAttempt += 1
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.rebuildWork != nil else { return }
                self.rebuildWork = nil
                self.restartCapture()
            }
        }
        rebuildWork = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private nonisolated func beginFrameTimer(fps: Int) {
        Task { @MainActor [weak self] in
            guard let self, self.timer == nil else { return }
            self.startingCapture = false
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 1.0 / Double(max(1, fps)), leeway: .milliseconds(12))
            timer.setEventHandler { [weak self] in self?.pullFrame() }
            self.timer = timer
            timer.resume()
        }
    }

    private nonisolated func pullFrame() {
        Task { @MainActor [weak self] in
            // One outstanding pull at a time: a slow worker must not turn a
            // 15 FPS timer into an unbounded queue of blocking RPCs.
            guard let self, !self.frameInFlight else { return }
            self.frameInFlight = true
            let space = self.space, remote = self.remoteWindow
            self.queue.async { [weak self] in
                let result = SpaceService().windowFrame(for: space, window: remote)
                Task { @MainActor in
                    guard let self else { return }
                    self.frameInFlight = false
                    switch result {
                    case .success(let image):
                        self.state.image = image
                        self.state.error = nil
                        self.pullsWithoutFrame = 0
                        self.rebuildAttempt = 0
                    case .failure(let error):
                        if error.code == .previewNotRunning {
                            // The same code covers "no frame yet" and "there is
                            // no stream", so a fresh stream gets about a second
                            // of pulls before it counts as dead.
                            self.pullsWithoutFrame += 1
                            if self.pullsWithoutFrame > max(2, self.streamFPS) {
                                self.scheduleRebuild()
                            }
                        } else {
                            self.scheduleRebuild(after: error)
                        }
                    }
                }
            }
        }
    }

    private func send(_ action: JSONValue) {
        let space = self.space, remote = remoteWindow
        queue.async { [weak self] in
            if case .failure(let error) = SpaceService().windowInput(for: space, window: remote, action: action) {
                Task { @MainActor in self?.state.error = error }
            }
        }
    }
}
