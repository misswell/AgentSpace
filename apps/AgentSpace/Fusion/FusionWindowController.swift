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
        let space = self.space, remote = remoteWindow
        let configuredFPS = UserDefaults.standard.integer(forKey: "fusionFPSPolicy")
        let fps = configuredFPS == 0 ? (window?.isKeyWindow == true ? 15 : 5) : configuredFPS
        queue.async { [weak self] in
            switch SpaceService().windowStreamStart(for: space, window: remote, maxFPS: fps) {
            case .failure(let error):
                Task { @MainActor in self?.startingCapture = false; self?.state.error = error }
            case .success:
                self?.beginFrameTimer(fps: fps)
            }
        }
    }

    private func restartCapture() {
        stop()
        startCapture()
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
            guard let self else { return }
            let space = self.space, remote = self.remoteWindow
            self.queue.async { [weak self] in
                let result = SpaceService().windowFrame(for: space, window: remote)
                Task { @MainActor in
                    guard let self else { return }
                    switch result {
                    case .success(let image): self.state.image = image; self.state.error = nil
                    case .failure(let error):
                        if error.code != .previewNotRunning {
                            self.state.error = error
                            if error.code == .sessionIsConsole || error.code == .noWindowServer { self.stop() }
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
