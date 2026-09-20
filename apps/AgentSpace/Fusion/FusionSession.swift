import Foundation
import AgentSpaceCore

@MainActor
final class FusionSession {
    let space: AgentAccount
    private var controllers: [WindowIdentity: FusionWindowController] = [:]
    private var timer: Timer?
    private var refreshInFlight = false

    init(space: AgentAccount) { self.space = space }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        controllers.values.forEach { $0.stop(); $0.close() }
        controllers.removeAll()
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
                if case .success(let windows) = result { self.reconcile(windows) }
            }
        }
    }

    private func reconcile(_ windows: [RemoteWindow]) {
        let incoming = Set(windows.map(\.identity))
        for identity in Set(controllers.keys).subtracting(incoming) {
            controllers.removeValue(forKey: identity)?.close()
        }
        for remote in windows where controllers[remote.identity] == nil {
            let controller = FusionWindowController(space: space, remoteWindow: remote)
            controllers[remote.identity] = controller
            controller.show()
        }
    }
}
