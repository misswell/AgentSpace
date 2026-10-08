import AppKit
import AgentSpaceCore

@MainActor
final class AccountLoginController: ObservableObject {
    enum Phase: Equatable {
        case idle, starting, sharingDisabled, waiting, finishing, connected, failed(String)
    }
    @Published private(set) var phase: Phase = .idle
    private var task: Task<Void, Never>?
    private var relay: ScreenSharingRelay?
    private weak var model: AppModel?
    private let account: AgentAccount

    init(account: AgentAccount, model: AppModel) {
        self.account = account
        self.model = model
    }

    func start() {
        guard task == nil else { return }
        phase = .starting
        task = Task { [weak self] in
            guard let self else { return }
            // Re-read both the registry and Directory Service at the action,
            // rather than trusting a stale selected row or a hand-crafted URL.
            let eligible = await Task.detached(priority: .userInitiated) {
                let registry = SpaceService().loadRegistry()
                return registry.spaces.contains { $0.id == self.account.id && $0.uid == self.account.uid && $0.username == self.account.username }
                    && AccountLogin.permits(self.account, candidates: AccountDiscovery.discover())
            }.value
            guard !Task.isCancelled else { return }
            guard eligible else {
                self.fail(NSLocalizedString("This account is no longer an attached standard user. Refresh the account list.", comment: "")); return
            }
            let helperAvailable = await Task.detached(priority: .utility) {
                (try? HelperClient.call(HelperRequest(operation: .sessionInfo,
                    spaceID: self.account.id, username: self.account.username,
                    mainUser: NSUserName(), runtimeRoot: self.account.runtimeRoot ?? RuntimePaths.root,
                    uid: self.account.uid), timeout: 5).ok) == true
            }.value
            guard !Task.isCancelled else { return }
            guard helperAvailable else {
                self.fail(NSLocalizedString("The privileged helper could not inspect this account. Install or repair the helper in AgentSpace, then try again.", comment: "")); return
            }
            guard await ScreenSharingRelay.isAvailable() else {
                if !Task.isCancelled { self.phase = .sharingDisabled; self.task = nil }
                return
            }
            guard !Task.isCancelled else { return }
            let relay = ScreenSharingRelay()
            self.relay = relay
            do {
                let port = try await relay.start()
                guard !Task.isCancelled else { relay.stop(); return }
                guard let url = AccountLogin.url(username: self.account.username, port: port),
                      let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ScreenSharing") else {
                    self.fail(NSLocalizedString("The macOS Screen Sharing app could not be found.", comment: "")); return
                }
                let opened: Bool = await withCheckedContinuation { continuation in
                    let configuration = NSWorkspace.OpenConfiguration()
                    NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration) { application, error in
                        continuation.resume(returning: application != nil && error == nil)
                    }
                }
                guard !Task.isCancelled else { relay.stop(); return }
                guard opened else {
                    self.fail(NSLocalizedString("The macOS sign-in window could not be opened. Try again.", comment: "")); return
                }
                self.phase = .waiting
                // A GUI domain, not 'any process with this uid'. SSH and a
                // stopped worker cannot masquerade as a successful desktop login.
                let deadline = Date().addingTimeInterval(600)
                while Date() < deadline {
                    guard !Task.isCancelled else { return }
                    let account = self.account
                    let hasSession = await Task.detached(priority: .utility) {
                        guard let response = try? HelperClient.call(HelperRequest(
                            operation: .sessionInfo, spaceID: account.id,
                            username: account.username, mainUser: NSUserName(),
                            runtimeRoot: account.runtimeRoot ?? RuntimePaths.root,
                            uid: account.uid), timeout: 5) else { return false }
                        return AccountLogin.hasSession(response, for: account)
                    }.value
                    guard !Task.isCancelled else { return }
                    if hasSession, let model = self.model {
                        self.phase = .finishing
                        let error = await model.prepareAccountAfterLogin(account)
                        guard !Task.isCancelled else { return }
                        if let error { self.fail(error); return }
                        self.phase = .connected
                        // Keep the authenticated connection until the person
                        // closes this sheet: they may still be granting TCC in
                        // the system viewer. stop() closes only our transport.
                        self.task = nil
                        return
                    }
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                }
                self.fail(NSLocalizedString("Sign-in timed out. Close the temporary Screen Sharing window and try again.", comment: ""))
            } catch {
                if !Task.isCancelled {
                    self.fail(NSLocalizedString("The local sign-in connection could not be started. Try again.", comment: ""))
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        relay?.stop()
        relay = nil
    }

    private func fail(_ message: String) {
        stop()
        phase = .failed(message)
    }
}
