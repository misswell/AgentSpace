import AppKit
import AgentSpaceCore
import os

/// The sheet's own log line. Measured on 2026-10-09: a sign-in that had actually
/// succeeded sat on 「正在等待 Agent 桌面…」 for minutes it could not explain, and nothing outside
/// this process could say which of four conditions it was waiting on.
private let loginLog = Logger(subsystem: BundleIdentifiers.logSubsystem, category: "login")

@MainActor
final class AccountLoginController: ObservableObject {
    enum Phase: Equatable {
        case idle, starting, sharingDisabled, waiting, finishing, connected, failed(String)
    }
    @Published private(set) var phase: Phase = .idle
    /// Why `phase == .waiting`. Set by the same poll that decides it, and only
    /// logged when it changes.
    @Published private(set) var wait: AccountLogin.Wait?
    private var task: Task<Void, Never>?
    private var relay: ScreenSharingRelay?
    private weak var model: AppModel?
    private let account: AgentAccount

    init(account: AgentAccount, model: AppModel) {
        self.account = account
        self.model = model
    }

    /// One edge per reason, so a wait that lasts ten minutes is one log line
    /// rather than two hundred.
    private func setWait(_ next: AccountLogin.Wait?) {
        guard wait != next else { return }
        wait = next
        if let next {
            loginLog.info("sign-in is still waiting: \(next.logLabel, privacy: .public)")
        } else {
            loginLog.info("sign-in is complete: the agent desktop is ready")
        }
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
                //
                // The deadline covers *only* "no session ever appeared", which
                // means the system window was abandoned and waiting further is
                // waiting for nothing. Once macOS has handed over a session the
                // wait is open-ended: what remains is the Worker coming up and
                // the person unlocking at the lock screen, and the measured case
                // stayed locked for 5 m 12 s after its Worker came online. A wall
                // clock timed from the click can expire inside that, and would
                // have reported a login that was still succeeding as a failure.
                let noSessionDeadline = Date().addingTimeInterval(600)
                while !Task.isCancelled {
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
                    if !hasSession {
                        setWait(.noSession)
                        guard Date() < noSessionDeadline else {
                            self.fail(NSLocalizedString("Sign-in timed out. Close the temporary Screen Sharing window and try again.", comment: ""))
                            return
                        }
                        try await Task.sleep(nanoseconds: 3_000_000_000)
                        continue
                    }
                    if let model = self.model {
                        self.phase = .finishing
                        let outcome = await model.prepareAccountAfterLogin(account)
                        guard !Task.isCancelled else { return }
                        switch outcome {
                        case .failed(let error): self.fail(error); return
                        case .waiting(let reason):
                            self.phase = .waiting
                            setWait(reason)
                        case .connected:
                            self.phase = .connected
                            setWait(nil)
                            // Keep the authenticated connection until the person
                            // closes this sheet. stop() closes only our transport.
                            self.task = nil
                            return
                        }
                    }
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                }
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
