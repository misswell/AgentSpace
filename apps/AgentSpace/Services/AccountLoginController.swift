import AppKit
import AgentSpaceCore
import CoreGraphics
import os

/// The sheet's own log line. Measured on 2026-10-09: a sign-in that had actually
/// succeeded sat on 「正在等待 Agent 桌面…」 for minutes it could not explain, and nothing outside
/// this process could say which of four conditions it was waiting on.
private let loginLog = Logger(subsystem: BundleIdentifiers.logSubsystem, category: "login")

/// What the sign-in sheet may do to the system window that carried the sign-in.
///
/// The window belongs to Apple's Screen Sharing app, and quitting that app ends
/// every window it owns. So the sheet ends it only when the app owes this sheet
/// its existence and holds no other window; a person's own Screen Sharing
/// session is not AgentSpace's to close.
enum SignInWindowPolicy {
    static func closesTemporaryWindow(launchedByAgentSpace: Bool, windowCount: Int) -> Bool {
        launchedByAgentSpace && windowCount <= 1
    }
}

@MainActor
final class AccountLoginController: ObservableObject {
    enum Phase: Equatable {
        case idle, starting, sharingDisabled, waiting, finishing, connected, failed(String)
    }
    @Published private(set) var phase: Phase = .idle
    /// Why `phase == .waiting`. Set by the same poll that decides it, and only
    /// logged when it changes.
    @Published private(set) var wait: AccountLogin.Wait?
    /// True while the sheet is showing one of the failures whose fix is the
    /// helper swap. The sheet draws 「重新安装助手…」 for exactly this state, so a
    /// message that used to send the person to another window ends in the
    /// button that does the work.
    @Published private(set) var needsHelperRepair = false
    @Published private(set) var isRepairingHelper = false
    /// Whether the temporary Screen Sharing window was asked to quit once the
    /// desktop came up. The sheet's connected sentence depends on it, because a
    /// window that is still there has to be closed by the person.
    @Published private(set) var closedTemporaryWindow = false
    private var task: Task<Void, Never>?
    private var relay: ScreenSharingRelay?
    private weak var model: AppModel?
    private let account: AgentAccount
    /// The guide context needs the window on screen to approve panes in; only
    /// the account page's sign-in dialog ends it.
    private let closesTemporaryWindow: Bool
    private var screenSharingWasRunning = false

    private static let screenSharingBundleID = "com.apple.ScreenSharing"

    init(account: AgentAccount, model: AppModel, closesTemporaryWindow: Bool = false) {
        self.account = account
        self.model = model
        self.closesTemporaryWindow = closesTemporaryWindow
    }

    /// One edge per reason, so a wait that lasts ten minutes is one log line
    /// rather than two hundred. `.log` and not `.info`, because the line a reader
    /// is sent to look for must arrive: on the owner's Mac the `sign-in gave up
    /// after 10 minutes …` error from this very sheet is in the log (08:43:11 on
    /// 2026-10-10) while the info-level reason line from the same process, same
    /// subsystem and same category is not there at all — not even with
    /// `log show --info`, which does show this subsystem's info lines from the
    /// root helper. Default level is the one both the Worker and the helper prove
    /// reaches the log here.
    private func setWait(_ next: AccountLogin.Wait?, detail: String? = nil) {
        guard wait != next else { return }
        wait = next
        if let next {
            let suffix = detail.map { " — \($0)" } ?? ""
            loginLog.log("sign-in is still waiting: \(next.logLabel, privacy: .public)\(suffix, privacy: .public)")
        } else {
            loginLog.log("sign-in is complete: the agent desktop is ready")
        }
    }

    /// The wait's own clock: how long it has sat in *one* state, rather than how
    /// long it is since the click. Timed from the click, 600 seconds can expire
    /// while a person is still at the macOS window — the measured case stayed
    /// locked for 5 m 12 s after its Worker came online — and a login that was
    /// succeeding gets reported as one that failed. Timed per state, ten minutes
    /// of the same unanswered condition is a real failure and says so.
    ///
    /// One state is exempt, because only a person can end it: the lock screen.
    /// How long they take is not this product's to time out. Every other state is
    /// AgentSpace's own work, and a wait on it must end rather than spin forever.
    private var watched: AccountLogin.Wait?
    private var sinceChange = Date()

    private func note(_ next: AccountLogin.Wait?, detail: String? = nil) {
        if next != watched { watched = next; sinceChange = Date() }
        setWait(next, detail: detail)
    }

    private func stalled() -> Bool {
        guard let watched, !watched.waitsOnAPerson else { return false }
        return Date().timeIntervalSince(sinceChange) > 600
    }

    /// Giving up on AgentSpace's own work is rare enough to be worth a line: the
    /// person sees the same timeout either way, but only the log says which
    /// condition never cleared.
    private func fail(_ message: String, stalledOn wait: AccountLogin.Wait) {
        loginLog.error("sign-in gave up after 10 minutes in one state: \(wait.logLabel, privacy: .public)")
        self.fail(message)
    }

    func start() {
        guard task == nil, !isRepairingHelper else { return }
        watched = nil
        sinceChange = Date()
        needsHelperRepair = false
        closedTemporaryWindow = false
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
                self.needsHelperRepair = true
                self.fail(NSLocalizedString("The privileged helper could not inspect this account. Reinstall it below, then try again.", comment: "")); return
            }
            // An in-app update replaces only /Applications/AgentSpace.app, so the
            // daemon that answers this question can still be the one the previous
            // release installed — and a fix that lives in the helper is not in the
            // running one. Say that before the sheet spends ten minutes blaming the
            // macOS window for AgentSpace's own stale binary.
            if let model = self.model {
                await model.recheckHelper()
                guard !Task.isCancelled else { return }
                if model.helperState.isStaleBinary {
                    self.needsHelperRepair = true
                    self.fail(NSLocalizedString("The installed helper is from an earlier version of AgentSpace. Reinstall it below and allow the administrator approval, then try again.", comment: ""))
                    return
                }
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
                      let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.screenSharingBundleID) else {
                    self.fail(NSLocalizedString("The macOS Screen Sharing app could not be found.", comment: "")); return
                }
                self.screenSharingWasRunning = !NSRunningApplication
                    .runningApplications(withBundleIdentifier: Self.screenSharingBundleID).isEmpty
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
                while !Task.isCancelled {
                    let account = self.account
                    // A GUI domain, not 'any process with this uid'. SSH and a
                    // stopped worker cannot masquerade as a successful desktop login.
                    // The answer is kept as three outcomes rather than collapsed
                    // to a boolean: `try?` here is what let a broken probe report
                    // a granted login as one that never happened.
                    let probe: AccountLogin.SessionProbe = await Task.detached(priority: .utility) {
                        let request = HelperRequest(operation: .sessionInfo, spaceID: account.id,
                            username: account.username, mainUser: NSUserName(),
                            runtimeRoot: account.runtimeRoot ?? RuntimePaths.root,
                            uid: account.uid)
                        do {
                            return AccountLogin.probe(try HelperClient.call(request, timeout: 5), for: account)
                        } catch {
                            return .unusable(detail: "\(error)")
                        }
                    }.value
                    guard !Task.isCancelled else { return }
                    switch probe {
                    case .unusable(let detail):
                        note(.probeFailed, detail: detail)
                        guard !stalled() else {
                            self.needsHelperRepair = true
                            self.fail(NSLocalizedString("AgentSpace could not confirm the agent account's desktop session. Reinstall the helper below, then try again.", comment: ""), stalledOn: .probeFailed)
                            return
                        }
                    case .noSession:
                        note(.noSession)
                        guard !stalled() else {
                            self.fail(NSLocalizedString("Sign-in timed out. Close the temporary Screen Sharing window and try again.", comment: ""), stalledOn: .noSession)
                            return
                        }
                    case .graphicalSession:
                        if let model = self.model {
                            self.phase = .finishing
                            let outcome = await model.prepareAccountAfterLogin(account)
                            guard !Task.isCancelled else { return }
                            switch outcome {
                            case .failed(let error): self.fail(error); return
                            case .waiting(let reason):
                                self.phase = .waiting
                                note(reason)
                                guard !stalled() else {
                                    self.fail(NSLocalizedString("Sign-in timed out. Close the temporary Screen Sharing window and try again.", comment: ""), stalledOn: reason)
                                    return
                                }
                            case .connected:
                                self.phase = .connected
                                note(nil)
                                self.closeTemporarySystemWindow()
                                // Keep the authenticated connection until the person
                                // closes this sheet. stop() closes only our transport.
                                self.task = nil
                                return
                            }
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

    /// Repair the helper from inside the sheet.
    ///
    /// This is the same awaited swap 「重新安装助手…」 runs elsewhere, including
    /// macOS's single administrator approval. When it returns ready, the sign-in
    /// that was blocked resumes by itself; when it does not, `helperFailure`
    /// carries the refusal where this sheet can show it (§269: no alert presents
    /// over a sheet).
    func repairHelper() {
        guard let model, !isRepairingHelper, !model.isInstallingHelper else { return }
        isRepairingHelper = true
        Task { [weak self] in
            let repaired = await model.reinstallHelperNow(alertOnFailure: false)
            guard let self else { return }
            self.isRepairingHelper = false
            guard repaired else { return }
            self.needsHelperRepair = false
            self.start()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        relay?.stop()
        relay = nil
    }

    /// Ends the temporary window the sign-in ran in.
    ///
    /// Closing it is safe only because a running Worker has pinned this
    /// account's own `askForPasswordDelay` (AGENTS.md §8): measured 2026-10-10,
    /// the last viewer going away no longer locks that desktop. The quit is
    /// scoped to the app this sheet launched and to a single window, so a
    /// Screen Sharing session of the person's own is never ended by a sign-in.
    private func closeTemporarySystemWindow() {
        guard closesTemporaryWindow, !screenSharingWasRunning else { return }
        guard let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.screenSharingBundleID).first else {
            // The person closed it while the worker was starting; there is
            // nothing left to end, and the connected sentence must not ask for
            // a window that is already gone.
            closedTemporaryWindow = true
            return
        }
        let windows = Self.windowsOwned(by: application.processIdentifier)
        guard SignInWindowPolicy.closesTemporaryWindow(
            launchedByAgentSpace: !screenSharingWasRunning, windowCount: windows) else {
            loginLog.log("sign-in left the Screen Sharing app open: it owns \(windows, privacy: .public) windows")
            return
        }
        let requested = application.terminate()
        closedTemporaryWindow = requested
        loginLog.log("sign-in ended the temporary Screen Sharing window: \(requested ? "quit requested" : "quit refused", privacy: .public)")
        guard requested else { return }
        // Quit is asynchronous, and the sheet's sentence may only claim what
        // happened: if the app is still there after a breath, the person is
        // told to close the window after all.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self, !application.isTerminated else { return }
            self.closedTemporaryWindow = false
            loginLog.log("the Screen Sharing app is still running after the sign-in asked it to quit")
        }
    }

    private static func windowsOwned(by pid: pid_t) -> Int {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return 0 }
        return windows.reduce(into: 0) { count, window in
            guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value == pid,
                  let layer = window[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue == 0 else { return }
            count += 1
        }
    }

    private func fail(_ message: String) {
        stop()
        phase = .failed(message)
    }
}
