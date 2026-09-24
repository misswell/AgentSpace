import Foundation
import AgentSpaceCore

@MainActor
final class FusionSession {
    let space: AgentAccount
    /// The link's state and the delay before the next window list. A session
    /// that is refused is not the same problem as a session that is restarting,
    /// and the difference is `FusionLinkPolicy`'s to make.
    private(set) var link: FusionLinkStatus
    private let policy = FusionLinkPolicy()
    private var nextPollAt = Date.distantPast
    private var controllers: [WindowIdentity: FusionWindowController] = [:]
    private var timer: Timer?
    private var refreshInFlight = false

    init(space: AgentAccount) {
        self.space = space
        link = FusionLinkPolicy().connected
    }

    func start() {
        refresh()
        // The timer is only a clock. When a tick is *not* allowed to poll, the
        // policy's delay decides it, so the ladder can be finer than a second
        // of drift in the timer without a second scheduling mechanism.
        timer = Timer.scheduledTimer(withTimeInterval: policy.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        controllers.values.forEach { $0.stop(); $0.close() }
        controllers.removeAll()
    }

    func open(_ remote: RemoteWindow) {
        if let controller = controllers[remote.identity] {
            controller.showAndResume()
            return
        }
        let controller = FusionWindowController(space: space, remoteWindow: remote)
        controllers[remote.identity] = controller
        controller.show()
    }

    private func tick() {
        guard Date() >= nextPollAt else { return }
        refresh()
    }

    private func refresh() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        let space = self.space
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = SpaceService().windows(for: space)
            Task { @MainActor in
                guard let self else { return }
                self.refreshInFlight = false
                switch result {
                case .success(let windows):
                    self.link = self.policy.connected
                    self.scheduleNextPoll()
                    self.reconcile(windows)
                case .failure(let error):
                    self.link = self.policy.status(after: error, failures: self.link.failures + 1)
                    self.scheduleNextPoll()
                    // A window that cannot be listed cannot be streamed either:
                    // without this the proxies keep pulling frames from a worker
                    // that already refused the session, one RPC per window.
                    self.controllers.values.forEach { $0.suspend(for: error) }
                }
            }
        }
    }

    private func scheduleNextPoll() {
        nextPollAt = Date().addingTimeInterval(link.nextPollInSeconds)
    }

    private func reconcile(_ windows: [RemoteWindow]) {
        let incoming = Set(windows.map(\.identity))
        for identity in Set(controllers.keys).subtracting(incoming) {
            // `close()` alone would leave the frame timer running against a
            // window nobody is watching, and never tell the worker to stop.
            if let gone = controllers.removeValue(forKey: identity) {
                gone.stop()
                gone.close()
            }
        }
        for identity in incoming {
            // Includes the identities `suspend(for:)` stopped: their timer is
            // gone, so this is what puts the stream back up after a worker
            // restart or a trip to the console.
            controllers[identity]?.resumeCapture()
        }
    }
}
