import Foundation
import SwiftUI
import Darwin
@preconcurrency import ServiceManagement
import AgentSpaceCore

/// A runtime record discovered from the attached account's own session.
///
/// The controller keeps the registry private to the main account (the target
/// account cannot traverse `Spaces/` by design), but the target account can
/// still see its own 0700 runtime directory. This small hand-off lets the
/// AgentSpace UI running there offer the same authorization action without
/// exposing the controller's registry or creating a second management view.
struct CurrentAccountAuthorization: Equatable, Sendable {
    var account: AgentAccount
    var mainUser: String
    var workerOnline: Bool
    var accessibility: Bool
    var screenRecording: Bool
}

/// The GUI's state.
///
/// Two deliberate choices are visible here.
///
/// **Refresh is slow and on demand.** Plan §53 sets a 2–5 s floor on status
/// polling, prefers event notifications outright, and forbids the 100 ms loop
/// that makes a management app cost more than the thing it manages. Nothing
/// polls on a timer at all: refreshes happen on foreground, selection and
/// explicit request, and the only repeating timer in the app is the desktop
/// preview — the §52 stream at 5 FPS while the viewer is open, falling back to
/// 1 FPS screenshots when the stream is refused. Idle, measured in
/// docs/validation.md §27: 0.0% CPU.
///
/// **Input is gated on `acceptsInput`.** The buttons that drive the agent's
/// desktop are disabled unless the worker itself said input is permitted. The GUI
/// does not decide whether an agent is usable; it asks, and it believes the answer.
@MainActor
final class AppModel: ObservableObject {

    /// "0.1.10 (413)" — marketing version plus the build number that
    /// `scripts/bundle-app.sh` stamps from git at bundle time. Shown in the
    /// sidebar so "am I looking at the copy I just built?" is answered on
    /// screen; the About panel reads the same plist keys.
    static let displayVersion: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }()

    @Published private(set) var snapshots: [SpaceSnapshot] = []
    @Published var selection: UUID?
    /// Settable because SwiftUI's `alert(item:)` needs a two-way binding.
    @Published var lastError: PresentedError?
    /// Whether the selected Space's Desktop Viewer sheet is up. Owned by the
    /// model, not the detail view, so a deep link can raise it: the CLI's
    /// `desktop` command lands here (§31's `agentspace desktop <space>`).
    @Published var showingDesktopViewer = false
    /// What is known about the privileged helper. Refreshed with everything else
    /// so the UI never offers a button that cannot work.
    @Published var helperState: HelperInstallation.State = HelperInstallation.inspect(ping: false)
    @Published var isInstallingHelper = false
    /// An attach or detach in flight, with its steps, so the UI can show exactly
    /// what is happening to the machine rather than a spinner.
    @Published var provisioning: Provisioning?
    /// The Agent whose disk is currently being measured, so the button can show
    /// progress instead of being pressed twice.
    @Published var measuringDisk: UUID?
    /// Set when something was copied, so the UI can confirm without an alert.
    @Published var copiedMessage: String?
    @Published private(set) var availableAccounts: [LocalAccount] = []
    /// The attached account represented by this login session, when this
    /// process is running inside that account. It is intentionally separate
    /// from `snapshots`: the controller's registry is not readable by the
    /// attached account, but its own runtime is.
    @Published private(set) var currentAccountAuthorization: CurrentAccountAuthorization?

    struct Provisioning: Equatable, Identifiable {
        var id = UUID()
        var operation: String
        var steps: [String] = []
        var finished = false
        /// An attach that ended with a usable account. The sign-in instructions
        /// are shown only for this — never for a failed attach or a detach.
        var offersLoginInstructions = false
        /// The failure, phrased for a human, rendered inside the overlay itself:
        /// while the wizard sheet is open no alert can present over it (§269),
        /// so an error routed only to `lastError` was swallowed.
        var error: PresentedError?
    }
    @Published private(set) var isLoading = false
    @Published var showingNewSpace = false
    @Published var showingDoctor = false
    @Published private(set) var doctorReport: Doctor.Report?
    /// AgentSpace-named accounts with no agent record, as last computed by
    /// `runDoctor`. Empty when the helper could not be reached, so the delete
    /// button never appears for a list this app could not verify.

    /// A failure phrased for a human, with the code kept for the detail line.
    /// When the core marks a one-button recovery (`actionTitle` non-nil), the
    /// alert grows that button and `action` runs it — the user fixes the
    /// problem from the dialog, never from a terminal.
    struct PresentedError: Identifiable, Equatable {
        var id = UUID()
        var code: String
        var message: String
        var fix: String?
        var spaceName: String?
        var actionTitle: String?
        var action: (() -> Void)?

        static func == (lhs: PresentedError, rhs: PresentedError) -> Bool {
            // id and action are identity/behaviour, not state; comparing them
            // would make otherwise identical presentations unequal.
            lhs.code == rhs.code && lhs.message == rhs.message
                && lhs.fix == rhs.fix && lhs.spaceName == rhs.spaceName
                && lhs.actionTitle == rhs.actionTitle
        }
    }

    private let service: SpaceService
    private var refreshTask: Task<Void, Never>?
    private var accountDiscoveryGeneration = 0
    private var currentAccountDiscoveryGeneration = 0
    @Published private(set) var finishingSetup: UUID?
    @Published private(set) var openingSystemSettings: UUID?
    @Published private(set) var updatingWorker: UUID?
    @Published private(set) var authorizingPermission: UUID?
    @Published private(set) var authorizingCurrentPermission: SystemSettingsPane?

    init(service: SpaceService = SpaceService()) {
        self.service = service
    }

    // MARK: - Loading

    /// Register the LaunchDaemon with launchd.
    ///
    /// `SMAppService` is the supported replacement for `SMJobBless` (plan §7).
    /// Registering a LaunchDaemon requires administrator approval, so macOS shows
    /// its own prompt — this call blocks on that, which is why it runs off the main
    /// actor and the UI shows progress rather than appearing to hang.
    ///
    /// On success the helper is *registered*, not necessarily *answering*: launchd
    /// starts it on demand, so the state is re-read rather than assumed.
    func installHelper() {
        guard !isInstallingHelper else { return }
        isInstallingHelper = true
        Task {
            let result: Result<Void, Error> = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let service = SMAppService.daemon(plistName: BundleIdentifiers.helperPlist)
                        try service.register()
                        continuation.resume(returning: .success(()))
                    } catch {
                        continuation.resume(returning: .failure(error))
                    }
                }
            }
            // Give launchd a moment, then ask the helper directly rather than
            // trusting that registration implies a working daemon.
            if case .success = result { try? await Task.sleep(nanoseconds: 500_000_000) }
            self.helperState = HelperInstallation.inspect()
            self.isInstallingHelper = false
            if case .failure(let error) = result {
                self.lastError = PresentedError(
                    code: "HELPER_UNAVAILABLE",
                    message: error.localizedDescription,
                    fix: HelperInstallation.inspect(ping: false).fix)
            } else if !self.helperState.isReachable {
                // Registered but silent is a real state (approval pending, or a
                // signature mismatch) and silently reporting success would send the
                // user to a Create button that then fails.
                self.lastError = PresentedError(
                    code: "HELPER_UNAVAILABLE",
                    message: NSLocalizedString("The helper was registered with launchd but is not answering yet.", comment: ""),
                    fix: self.helperState.fix ?? NSLocalizedString("Try again in a moment, or look for com.agentspace.app in Console.", comment: ""))
            }
        }
    }

    /// Ask the helper directly, once, off the main thread, and publish what it
    /// said. `reload()` deliberately does not ping — it runs on every refresh,
    /// and a missing helper would cost a connection timeout each time — so
    /// without this the wizard's helper card reads "registered but not
    /// answering" forever even while the helper answers create calls.
    func refreshHelperState() {
        Task.detached(priority: .userInitiated) {
            let state = HelperInstallation.inspect()
            await MainActor.run { self.helperState = state }
        }
    }

    func uninstallHelper() {
        isInstallingHelper = true
        Task {
            let service = SMAppService.daemon(plistName: BundleIdentifiers.helperPlist)
            let error: Error? = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { try service.unregister(); continuation.resume(returning: nil) }
                    catch { continuation.resume(returning: error) }
                }
            }
            self.helperState = HelperInstallation.inspect()
            self.isInstallingHelper = false
            if let error {
                self.lastError = PresentedError(
                    code: "HELPER_REJECTED",
                    message: String(format: NSLocalizedString("Could not remove the helper: %@", comment: ""), error.localizedDescription))
            }
        }
    }

    /// Swap the running helper for the one in this app bundle.
    ///
    /// launchd keeps a registered daemon running across an app rebuild, so a
    /// passing Doctor check can still be an old binary answering. Unregister
    /// stops the process; register loads the current one (with macOS's own
    /// admin prompt, because that is what a LaunchDaemon costs). This is the
    /// in-app path — the alternative was a terminal, and the terminal is not
    /// offered.
    func reinstallHelper() {
        guard !isInstallingHelper else { return }
        isInstallingHelper = true
        Task {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    _ = try? SMAppService.daemon(plistName: BundleIdentifiers.helperPlist).unregister()
                    continuation.resume()
                }
            }
            self.isInstallingHelper = false
            self.installHelper()
            self.runDoctor()
        }
    }

    /// Bring an attached account's worker up to the version in this app, then
    /// retry its first-login setup. A LaunchAgent can keep an older worker
    /// alive after an app update; in that state the new GUI receives
    /// METHOD_NOT_FOUND for `systemSettings.open`. If the helper is old too,
    /// swap it first so the install operation copies the current worker.
    func updateWorker(_ space: AgentAccount) {
        guard updatingWorker == nil, finishingSetup == nil, authorizingPermission == nil else { return }
        updatingWorker = space.id
        Task {
            let state = await Task.detached(priority: .userInitiated) {
                HelperInstallation.inspect()
            }.value
            let helperReady: Bool
            if state.isReachable && !state.isStaleBinary {
                helperReady = true
            } else {
                helperReady = await reinstallHelperForWorker()
            }
            self.updatingWorker = nil
            guard helperReady else { return }
            self.finishPendingSetup(space)
        }
    }

    /// The completion-aware helper swap used by the worker-update fix-it. The
    /// Doctor button intentionally keeps its older fire-and-forget behaviour;
    /// this path must wait until the current helper can answer before copying a
    /// worker from it.
    private func reinstallHelperForWorker() async -> Bool {
        isInstallingHelper = true
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let service = SMAppService.daemon(plistName: BundleIdentifiers.helperPlist)
                    _ = try? service.unregister()
                    try service.register()
                    continuation.resume(returning: .success(()))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
        if case .success = result { try? await Task.sleep(nanoseconds: 500_000_000) }
        let state = await Task.detached(priority: .userInitiated) {
            HelperInstallation.inspect()
        }.value
        helperState = state
        isInstallingHelper = false
        if case .failure(let error) = result {
            lastError = PresentedError(
                code: "HELPER_UNAVAILABLE",
                message: error.localizedDescription,
                fix: HelperInstallation.inspect(ping: false).fix)
            return false
        }
        guard state.isReachable && !state.isStaleBinary else {
            lastError = PresentedError(
                code: "HELPER_UNAVAILABLE",
                message: NSLocalizedString("The helper was reinstalled but is not answering with the current build yet.", comment: ""),
                fix: state.fix ?? NSLocalizedString("Try Update worker again after a moment.", comment: ""))
            return false
        }
        return true
    }

    // MARK: - Attach / detach (V3)

    /// Connect an existing standard macOS account and install its runtime.
    ///
    /// Everything runs off the main actor: creating an account and installing a
    /// launchd job takes seconds, and blocking the main thread would freeze the
    /// window with no explanation.
    func attachAccount(_ account: LocalAccount, displayName: String, workspace: Workspace, sharedFolders: [SharedFolder]) {
        guard provisioning == nil else { return }
        let root = service.root ?? AgentSpaceEnvironment.rootOverride ?? RuntimePaths.root
        provisioning = Provisioning(operation: String(format: NSLocalizedString("Connecting %@", comment: ""), displayName))
        let directory = Self.worktreesDirectory

        Task {
            let registry = SpaceRegistry.load(root: root)
            let outcome = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: AccountAttachService.attach(
                        account: account,
                        displayName: displayName,
                        workspace: workspace,
                        sharedFolders: sharedFolders,
                        options: AccountAttachService.Options(
                            root: root, workspaceDirectory: directory, mainUser: NSUserName()),
                        transport: { try HelperClient.call($0) },
                        registry: registry))
                }
            }

            // Narrate the steps as they happened, not as they were planned: the
            // step list is the record of what the machine actually did, and it is
            // what the user needs if something went wrong.
            self.provisioning?.steps = outcome.steps.map(Self.describe)
            self.provisioning?.finished = true
            self.provisioning?.offersLoginInstructions = outcome.ok

            // The error goes into the overlay, not `lastError`: the wizard sheet
            // absorbs alerts (§269), and a create that failed while the overlay
            // said "sign in now" was the lie §272 records.
            if let error = outcome.error {
                self.provisioning?.error = self.presented(for: error, space: nil)
            }
            self.reload()
            self.discoverAccounts()
            // Ask the helper again: if it refused mid-run, the card behind the
            // overlay should say so when the overlay closes.
            self.refreshHelperState()
        }
    }

    func discoverAccounts() {
        accountDiscoveryGeneration += 1
        let generation = accountDiscoveryGeneration
        let attached = Set(service.loadRegistry().spaces.map { $0.username })
        Task {
            let accounts = await Task.detached(priority: .userInitiated) {
                AccountDiscovery.discover().filter { !attached.contains($0.username) }
            }.value
            guard generation == self.accountDiscoveryGeneration else { return }
            self.availableAccounts = accounts
        }
    }

    /// Find the runtime owned by the account running this GUI, without reading
    /// the controller's private `Spaces/index.json`. Runtime directories are
    /// named by UUID; only the matching account can read its `space.json`, so a
    /// target-account AgentSpace window gets a narrow, local authorization
    /// hand-off rather than a copy of the controller's registry.
    func discoverCurrentAccountAuthorization() {
        currentAccountDiscoveryGeneration += 1
        let generation = currentAccountDiscoveryGeneration
        Task {
            let discovered = await Task.detached(priority: .userInitiated) {
                Self.discoverCurrentAccountAuthorizationFromRuntime()
            }.value
            guard generation == self.currentAccountDiscoveryGeneration else { return }
            self.currentAccountAuthorization = discovered
        }
    }

    nonisolated private static func discoverCurrentAccountAuthorizationFromRuntime() -> CurrentAccountAuthorization? {
        let username = NSUserName()
        guard !username.isEmpty else { return nil }
        let resolvedRoot = AgentSpaceEnvironment.rootOverride ?? RuntimePaths.root
        let runtimeRoot = resolvedRoot + "/Runtime"
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(atPath: runtimeRoot) else {
            return nil
        }

        for entry in entries {
            guard let id = UUID(uuidString: entry) else { continue }
            let recordPath = "\(runtimeRoot)/\(entry)/space.json"
            guard let data = fileManager.contents(atPath: recordPath),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let record = object as? [String: Any],
                  let home = record["home"] as? String,
                  (home as NSString).lastPathComponent == username,
                  let mainUser = record["mainUser"] as? String,
                  !mainUser.isEmpty else { continue }

            let name = (record["spaceName"] as? String).flatMap {
                $0.isEmpty ? nil : $0
            } ?? username
            let account = AgentAccount(
                id: id,
                name: name,
                username: username,
                uid: getuid(),
                homeDirectory: home,
                runtimeRoot: resolvedRoot,
                state: .offline)
            let snapshot = SpaceService().snapshot(for: account)
            return CurrentAccountAuthorization(
                account: account,
                mainUser: mainUser,
                workerOnline: snapshot.workerOnline,
                accessibility: snapshot.accessibility,
                screenRecording: snapshot.screenRecording)
        }
        return nil
    }

    /// Finish the one deferred step for an account whose home directory was
    /// created by its first GUI login. The helper remains the only component
    /// allowed to write the LaunchAgent; this method merely retries the typed
    /// operation after the user has completed that macOS login.
    func finishPendingSetup(_ space: AgentAccount) {
        guard finishingSetup == nil, authorizingPermission == nil else { return }
        finishingSetup = space.id
        Task {
            let outcome = await finishPendingSetupOutcome(for: space)
            self.finishingSetup = nil
            if let error = outcome.error {
                self.lastError = self.presented(for: error, space: space)
            }
            self.reload()
        }
    }

    /// Install/start the worker when a user presses a permission button before
    /// the worker exists, then open the requested pane in that account's Aqua
    /// session. This is intentionally one action from the main page: users do
    /// not need to find a second AgentSpace app or guess which account owns the
    /// System Settings window.
    func authorizeAgent(_ space: AgentAccount, pane: SystemSettingsPane) {
        guard authorizingPermission == nil,
              updatingWorker == nil,
              finishingSetup == nil,
              openingSystemSettings == nil else { return }

        authorizingPermission = space.id
        Task {
            // Do this for both online and offline workers. `launchd` can keep
            // an old binary alive after an app update, and the old worker is
            // exactly what makes the button look like it did nothing.
            let preparationError = await self.prepareWorkerForAuthorization(
                space, mainUser: NSUserName())
            if let preparationError {
                self.authorizingPermission = nil
                self.lastError = self.presented(for: preparationError, space: space)
                self.reload()
                return
            }
            self.openingSystemSettings = space.id
            var error = await Task.detached(priority: .userInitiated) {
                SpaceService().openSystemSettings(for: space, pane: pane)
            }.value
            // A helper/worker race can leave launchd serving the old image for
            // one request. Repair once and retry automatically instead of
            // surfacing METHOD_NOT_FOUND as if the button were broken.
            if error?.recoveryHint == .reinstallWorker {
                if await self.prepareWorkerForAuthorization(space, mainUser: NSUserName()) == nil {
                    error = await Task.detached(priority: .userInitiated) {
                        SpaceService().openSystemSettings(for: space, pane: pane)
                    }.value
                }
            }
            self.openingSystemSettings = nil
            self.authorizingPermission = nil
            if let error {
                self.lastError = self.presented(for: error, space: space)
            }
            self.reload()
        }
    }

    /// Authorize the worker from the AgentSpace window running *inside* the
    /// attached account. The target account cannot read the controller's
    /// registry, so it uses the current-session runtime hand-off discovered by
    /// `discoverCurrentAccountAuthorization()` instead.
    func authorizeCurrentAccount(pane: SystemSettingsPane) {
        guard let currentAccountAuthorization,
              authorizingCurrentPermission == nil,
              authorizingPermission == nil,
              openingSystemSettings == nil else { return }

        authorizingCurrentPermission = pane
        Task {
            let preparationError = await self.prepareWorkerForAuthorization(
                currentAccountAuthorization.account,
                mainUser: currentAccountAuthorization.mainUser)
            if let preparationError {
                self.authorizingCurrentPermission = nil
                self.lastError = self.presented(
                    for: preparationError,
                    space: currentAccountAuthorization.account)
                self.discoverCurrentAccountAuthorization()
                return
            }

            var error = await Task.detached(priority: .userInitiated) {
                SpaceService().openSystemSettings(
                    for: currentAccountAuthorization.account,
                    pane: pane)
            }.value
            if error?.recoveryHint == .reinstallWorker {
                if await self.prepareWorkerForAuthorization(
                    currentAccountAuthorization.account,
                    mainUser: currentAccountAuthorization.mainUser) == nil {
                    error = await Task.detached(priority: .userInitiated) {
                        SpaceService().openSystemSettings(
                            for: currentAccountAuthorization.account,
                            pane: pane)
                    }.value
                }
            }
            self.authorizingCurrentPermission = nil
            if let error {
                self.lastError = self.presented(
                    for: error,
                    space: currentAccountAuthorization.account)
            }
            self.discoverCurrentAccountAuthorization()
        }
    }

    /// Install and kick the current worker through the typed helper surface.
    /// This deliberately does not call `AccountAttachService.finishPendingSetup`:
    /// the target account must not write the controller-owned registry just to
    /// grant its own permissions.
    private func prepareWorkerForAuthorization(
        _ space: AgentAccount,
        mainUser: String
    ) async -> AgentSpaceError? {
        let currentVersion = await Task.detached(priority: .userInitiated) {
            WorkerCompatibility.version(from: Self.workerHello(space))
        }.value
        if currentVersion == helperVersion {
            return nil
        }

        let helperState = await Task.detached(priority: .userInitiated) {
            HelperInstallation.inspect()
        }.value
        if !helperState.isReachable || helperState.isStaleBinary {
            guard await reinstallHelperForWorker() else {
                return AgentSpaceError(
                    code: .helperUnavailable,
                    message: NSLocalizedString(
                        "The AgentSpace helper is not ready, so the worker cannot be updated yet.",
                        comment: ""),
                    recoverable: true)
            }
        }

        let error = await Task.detached(priority: .userInitiated) {
            Self.installAndStartWorker(space, mainUser: mainUser)
        }.value
        return error
    }

    nonisolated private static func workerHello(_ space: AgentAccount) -> RPCResponse? {
        let connection = SpaceConnection(space: space)
        return try? connection.client.call(
            method: Method.hello, token: nil, timeout: 1)
    }

    nonisolated private static func installAndStartWorker(
        _ space: AgentAccount,
        mainUser: String
    ) -> AgentSpaceError? {
        let install = HelperRequest(
            operation: .installWorker,
            spaceID: space.id,
            username: space.username,
            mainUser: mainUser,
            runtimeRoot: space.runtimeRoot ?? RuntimePaths.root,
            uid: space.uid)
        do {
            let installed = try HelperClient.call(install)
            guard installed.ok else {
                return installed.error ?? AgentSpaceError(
                    code: .helperRejected,
                    message: NSLocalizedString(
                        "The helper did not install the current worker.", comment: ""))
            }
            if installed.result?["deferred"]?.boolValue == true {
                return AgentSpaceError(
                    code: .sessionNotReady,
                    message: NSLocalizedString(
                        "Sign in to the attached account's desktop once before requesting permissions.",
                        comment: ""),
                    recoverable: true)
            }

            let start = try HelperClient.call(HelperRequest(
                operation: .startWorker,
                spaceID: space.id,
                username: space.username,
                mainUser: mainUser,
                runtimeRoot: space.runtimeRoot ?? RuntimePaths.root,
                uid: space.uid))
            guard start.ok else {
                return start.error ?? AgentSpaceError(
                    code: .workerOffline,
                    message: NSLocalizedString(
                        "The worker could not be started in the attached account's desktop.",
                        comment: ""),
                    recoverable: true)
            }
            let readiness = WorkerCompatibility.waitForVersion(
                expected: helperVersion,
                attempts: 40,
                pause: { Thread.sleep(forTimeInterval: 0.15) },
                probe: { workerHello(space) })
            switch readiness {
            case .ready:
                return nil
            case .unavailable:
                return AgentSpaceError(
                    code: .workerOffline,
                    message: NSLocalizedString(
                        "The updated worker was started but did not become ready.", comment: ""),
                    recoverable: true,
                    recoveryHint: .reinstallWorker)
            case .mismatched(let actual):
                return AgentSpaceError(
                    code: .workerOffline,
                    message: String(format: NSLocalizedString(
                        "The worker is still running version %@ instead of %@.", comment: ""),
                        actual, helperVersion),
                    recoverable: true,
                    recoveryHint: .reinstallWorker)
            }
        } catch let error as HelperClientError {
            return error.agentSpaceError
        } catch {
            return AgentSpaceError(
                code: .helperRejected,
                message: String(format: NSLocalizedString(
                    "The helper could not prepare the worker: %@", comment: ""),
                    error.localizedDescription))
        }
    }

    private func finishPendingSetupOutcome(
        for space: AgentAccount,
        registryRoot: String? = nil
    ) async -> AccountAttachService.Outcome {
        let root = registryRoot ?? service.root ?? AgentSpaceEnvironment.rootOverride ?? RuntimePaths.root
        let accountRoot = space.runtimeRoot ?? root
        let directory = Self.worktreesDirectory
        let registry = service.loadRegistry()
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: AccountAttachService.finishPendingSetup(
                    account: space,
                    options: AccountAttachService.Options(
                        root: accountRoot,
                        registryRoot: root,
                        workspaceDirectory: directory,
                        mainUser: NSUserName()),
                    transport: { try HelperClient.call($0) },
                    registry: registry))
            }
        }
    }

    /// Ask the worker to open a privacy pane in the connected account's own
    /// session. The app's `NSWorkspace` would target the controller account,
    /// which is exactly the confusion this button is meant to remove.
    func openSystemSettings(_ space: AgentAccount, pane: SystemSettingsPane) {
        guard openingSystemSettings == nil else { return }
        openingSystemSettings = space.id
        Task {
            let error = await Task.detached(priority: .userInitiated) {
                SpaceService().openSystemSettings(for: space, pane: pane)
            }.value
            self.openingSystemSettings = nil
            if self.authorizingPermission == space.id {
                self.authorizingPermission = nil
            }
            if let error {
                self.lastError = self.presented(for: error, space: space)
            }
        }
    }

    /// §40's Stop Agent: stop the worker, keep the session. The effective
    /// state goes to offline/needsLogin on the next refresh — honestly.
    func stopWorker(_ space: AgentAccount) {
        guard case .success = service.stopWorker(for: space) else { return }
        if selected?.space.id == space.id { reload() }
    }

    func deleteSpace(_ space: AgentAccount, removeHome: Bool = false) {
        guard provisioning == nil else { return }
        _ = removeHome
        provisioning = Provisioning(operation: String(format: NSLocalizedString("Disconnecting %@", comment: ""), space.name))

        let root = service.root ?? AgentSpaceEnvironment.rootOverride ?? RuntimePaths.root
        let accountRoot = space.runtimeRoot ?? root
        let directory = Self.worktreesDirectory
        Task {
            let outcome = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: AccountAttachService.detach(
                        account: space,
                        options: AccountAttachService.Options(
                            root: accountRoot,
                            registryRoot: root,
                            workspaceDirectory: directory,
                            mainUser: NSUserName()),
                        transport: { try HelperClient.call($0) },
                        registry: SpaceRegistry.load(root: root)))
                }
            }
            self.provisioning?.steps = outcome.steps.map(Self.describe)
            self.provisioning?.finished = true
            if let error = outcome.error {
                self.provisioning?.error = self.presented(for: error, space: space)
            }
            self.reload()
            self.discoverAccounts()
        }
    }

    /// Measure one Space's home directory, on request.
    ///
    /// Kept out of `reload()` deliberately: it walks every file in the agent's
    /// home, which for a browser profile plus an IDE's caches is tens of thousands
    /// of them. Doing that on the 2–5 s status poll would pin the CPU, which §53
    /// forbids. The result is merged into the existing snapshot so the rest of the
    /// page does not flicker.
    func measureDiskUsage(for space: AgentAccount) {
        guard measuringDisk != space.id else { return }
        measuringDisk = space.id

        Task {
            let outcome = await Task.detached(priority: .utility) {
                SpaceService().measureDisk(for: space)
            }.value
            self.measuringDisk = nil

            switch outcome {
            case .success(let usage):
                // Merge into the array rather than replacing the whole snapshot:
                // the disk walk takes a moment, and rebuilding everything would
                // discard the session verdict that was current when it started.
                if let index = self.snapshots.firstIndex(where: { $0.space.id == space.id }) {
                    self.snapshots[index].resources = usage
                }
            case .failure(let error):
                self.lastError = PresentedError(
                    code: error.code.rawValue, message: error.message, fix: error.code.remediation)
            }
        }
    }

    func dismissProvisioning() {
        provisioning = nil
    }

    /// The parent directory for git worktrees. Deliberately independent of the
    /// account's display name: the attach service adds the id underneath, which is
    /// what makes the path unique. Two Spaces named `Test` and `test` are one
    /// directory on a case-insensitive filesystem, and two agents in one working
    /// tree is the bug the worktree exists to prevent (plan §24).
    static var worktreesDirectory: String {
        let root = AgentSpaceEnvironment.rootOverride ?? RuntimePaths.root
        return "\(root)/Worktrees"
    }

    private static func describe(_ step: AccountAttachService.Step) -> String {
        let mark: String
        switch step.outcome {
        case .done: mark = "✓"
        case .skipped: mark = "~"
        case .failed, .rollbackFailed: mark = "✗"
        case .rolledBack: mark = "↩"
        }
        var text = "\(mark) \(step.name)"
        if !step.detail.isEmpty { text += " — \(step.detail)" }
        switch step.outcome {
        case .skipped(let reason), .failed(let reason), .rolledBack(let reason), .rollbackFailed(let reason):
            if !reason.isEmpty { text += "\n     \(reason)" }
        default: break
        }
        return text
    }

    /// `agentspace://space/<uuid>` from the CLI's `desktop` command (§31):
    /// select that agent and raise its Desktop Viewer. A link for an agent that
    /// does not exist is reported here — the poster may be long gone, so this
    /// is the only place the failure can be seen.
    func handleDeepLink(_ url: URL) {
        guard let id = AppDeepLink.spaceID(in: url) else {
            lastError = PresentedError(
                code: "BAD_REQUEST",
                message: String(format: NSLocalizedString("not an AgentSpace deep link: %@", comment: ""), url.absoluteString))
            return
        }
        reload()
        guard snapshots.contains(where: { $0.space.id == id }) else {
            lastError = PresentedError(
                code: "SPACE_NOT_FOUND",
                message: String(format: NSLocalizedString("the link points at an agent that no longer exists (%@). It was probably deleted after the link was made.", comment: ""), id.uuidString))
            return
        }
        selection = id
        showingDesktopViewer = true
    }

    func reload() {
        isLoading = true
        // No ping: this runs on every refresh, and a helper that is not installed
        // would cost a connection timeout each time.
        helperState = HelperInstallation.inspect(ping: false)
        let registry = service.loadRegistry()
        let spaces = registry.spaces

        if selection == nil || !spaces.contains(where: { $0.id == selection }) {
            selection = spaces.first?.id
        }

        // Resources are fetched only for the agent on screen: one `ps` fork per
        // Agent per refresh would be exactly the overhead §53 forbids.
        snapshots = spaces.map { space in
            service.snapshot(for: space, includeResources: space.id == selection)
        }
        isLoading = false
        discoverCurrentAccountAuthorization()

        if let selected = snapshots.first(where: { $0.id == selection }), let problem = selected.problem {
            // A refusal is normal and is shown in the detail pane, not as an
            // alert. Only something the user did is worth interrupting for.
            _ = problem
        }
    }

    /// Refresh the resource numbers for whichever agent is selected.
    /// Measure the selected Space's home directory (plan §30).
    func measureDisk(for space: AgentAccount) { measureDiskUsage(for: space) }

    func refreshSelectedResources() {
        guard let index = snapshots.firstIndex(where: { $0.id == selection }) else { return }
        let space = snapshots[index].space
        snapshots[index] = service.snapshot(for: space, includeResources: true)
    }

    var selected: SpaceSnapshot? {
        snapshots.first { $0.id == selection }
    }

    // MARK: - Doctor

    /// Run the checks, including the orphan-account check.
    ///
    /// The helper is the only thing that can enumerate AgentSpace-named macOS
    /// accounts, so the app asks it, subtracts the registry's usernames, and
    /// hands Doctor the remainder. A helper that cannot be reached yields
    /// `nil`, and Doctor omits the check rather than claiming a pass it did
    /// not verify.
    func runDoctor() {
        let root = service.root ?? AgentSpaceEnvironment.rootOverride ?? RuntimePaths.root
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let accounts = HelperClient.agentSpaceAccounts()
            let registered = Set(SpaceRegistry.load(root: root).spaces.map(\.username))
            let orphans = accounts.map { names in
                names.filter { !registered.contains($0) }.sorted()
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.doctorReport = Doctor.run(root: root, orphanedAccounts: orphans)
            }
        }
    }

    // MARK: - Agent actions

    func present(_ error: AgentSpaceError, space: AgentAccount?) {
        lastError = presented(for: error, space: space)
    }

    /// Phrase a core error for a human, including the one-button recovery the
    /// core asked for. Split out of `present` because the provisioning overlay
    /// shows errors inline — an alert cannot present over the wizard sheet
    /// (§269) — and the inline version needs the same button.
    private func presented(for error: AgentSpaceError, space: AgentAccount?) -> PresentedError {
        var presented = PresentedError(
            code: error.code.rawValue,
            message: error.message,
            fix: error.code.remediation,
            spaceName: space?.name)
        // The core names the one-button recovery; the app supplies the actual
        // behaviour, so the core stays free of AppKit concerns.
        switch error.recoveryHint {
        case .installCommandLineTools:
            presented.actionTitle = NSLocalizedString("Install Command Line Tools…", comment: "")
            presented.action = { [weak self] in self?.installCommandLineTools() }
        case .removeOrphanedAccounts:
            // The failing operation already named the account; Doctor is where
            // it becomes visible and removable, so the button opens Doctor and
            // re-runs the checks rather than guessing at a name from the text.
            presented.actionTitle = NSLocalizedString("Open Doctor…", comment: "")
            presented.action = { [weak self] in
                self?.showingDoctor = true
                self?.runDoctor()
            }
        case .reinstallWorker:
            guard let space else { break }
            presented.code = "WORKER_OUTDATED"
            presented.message = NSLocalizedString(
                "The connected account is running an older worker that does not support this permission button.",
                comment: "")
            presented.fix = NSLocalizedString(
                "Click Update worker to install the current worker in the connected account, then try the permission button again.",
                comment: "")
            presented.actionTitle = NSLocalizedString("Update worker…", comment: "")
            presented.action = { [weak self] in self?.updateWorker(space) }
        case nil:
            break
        }
        return presented
    }

    /// Run `xcode-select --install`, which opens macOS's own GUI installer —
    /// this is the sanctioned in-app path for a missing git (plan §51): the
    /// user clicks a button, a system window appears, no terminal is involved.
    func installCommandLineTools() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
            process.arguments = ["--install"]
            let stderrPipe = Pipe()
            process.standardError = stderrPipe
            process.standardOutput = Pipe()
            do {
                try process.run()
            } catch {
                DispatchQueue.main.async {
                    self?.lastError = PresentedError(
                        code: "WORKSPACE_INVALID",
                        message: NSLocalizedString("Could not start the Command Line Tools installer.", comment: ""),
                        fix: NSLocalizedString("Install the Xcode Command Line Tools from Software Update settings, or choose a different workspace kind.", comment: ""))
                }
                return
            }
            process.waitUntilExit()
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                if process.terminationStatus == 0 {
                    self?.lastError = PresentedError(
                        code: "CLT_INSTALLER_OPEN",
                        message: NSLocalizedString("The Command Line Tools installer window is open. When it finishes, try creating the agent again.", comment: ""))
                } else if stderr.contains("already installed") {
                    self?.lastError = PresentedError(
                        code: "CLT_ALREADY_INSTALLED",
                        message: NSLocalizedString("The Xcode Command Line Tools are already installed. Try creating the agent again.", comment: ""))
                } else {
                    self?.lastError = PresentedError(
                        code: "WORKSPACE_INVALID",
                        message: NSLocalizedString("Could not start the Command Line Tools installer.", comment: ""),
                        fix: NSLocalizedString("Install the Xcode Command Line Tools from Software Update settings, or choose a different workspace kind.", comment: ""))
                }
            }
        }
    }

    func dismissError() { lastError = nil }

    /// Write the agent's screenshot to a file the user asked for.
    ///
    /// Note this asks the *worker* for the capture; it never grabs this session's
    /// screen. If the agent is unavailable the user gets the refusal, not a
    /// picture of their own desktop labelled as the agent's.
    func captureScreenshot(maxWidth: Int = 1600) -> ScreenshotResult? {
        guard let snapshot = selected else { return nil }
        switch service.screenshot(for: snapshot.space, maxWidth: maxWidth, inline: false) {
        case .failure(let error):
            present(error, space: snapshot.space)
            return nil
        case .success(let result):
            return result
        }
    }

    /// Reveal the agent's runtime directory, the honest place to look when the
    /// worker is not answering.
    func revealRuntimeDirectory() {
        guard let snapshot = selected else { return }
        let path = service.paths(for: snapshot.space).directory
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        } else {
            present(AgentSpaceError(
                code: .workerOffline,
                message: String(format: NSLocalizedString("there is no runtime directory for '%@' yet, so the worker has never started", comment: ""), snapshot.space.name)),
                space: snapshot.space)
        }
    }

    /// Copy the install instructions for the MCP server (plan §34).
    /// Install the MCP configuration into one client, exactly as
    /// `agentspace integrate <target> --install` does — same merge, same backup —
    /// so the two cannot disagree about what ends up in the user's config file.
    ///
    /// The confirmation dialog lives in the view; by the time this runs, the user
    /// has already said yes.
    func installIntegration(_ target: Integrations.Target) {
        guard let binary = Integrations.defaultBinaryPath() else { return }
        let path = (target.configPath as NSString).expandingTildeInPath
        let existing = FileManager.default.contents(atPath: path)
        do {
            let merged: Data
            switch target {
            case .codex:
                merged = try Integrations.mergeTOMLConfig(existing: existing, binaryPath: binary)
            case .claudeCode:
                merged = try Integrations.mergeJSONConfig(existing: existing, rootKey: "mcpServers", binaryPath: binary)
            case .openCode:
                merged = try Integrations.mergeJSONConfig(existing: existing, rootKey: "mcp", binaryPath: binary)
            case .generic:
                // No single file to write; copying is the whole feature.
                copyMCPConfiguration()
                return
            }
            try FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            if let existing, !FileManager.default.fileExists(atPath: path + ".agentspace.bak") {
                try existing.write(to: URL(fileURLWithPath: path + ".agentspace.bak"))
            }
            try merged.write(to: URL(fileURLWithPath: path))
            var message = String(format: NSLocalizedString("Configured %1$@: %2$@. Restart %3$@ to pick it up.", comment: ""), target.displayName, path, target.displayName)
            if existing != nil { message += String(format: NSLocalizedString(" Previous contents are at %@.agentspace.bak.", comment: ""), path) }
            copiedMessage = message
        } catch {
            lastError = PresentedError(
                code: "INTEGRATION_FAILED",
                message: String(format: NSLocalizedString("could not configure %1$@: %2$@", comment: ""), target.displayName, "\(error)"),
                fix: String(format: NSLocalizedString("Edit %1$@ by hand, or use `agentspace integrate %2$@ --install` which reports the same refusal with more detail.", comment: ""), path, target.rawValue))
        }
    }

    /// Copy the §35 agent safety rules, ready to paste into AGENTS.md/CLAUDE.md.
    ///
    /// Copy rather than write: an instructions file is the user's voice to their
    /// agents, and §35 requires their explicit consent before AgentSpace's rules
    /// appear in it. The CLI's `integrate rules --install` exists for those who
    /// prefer that, with a backup and marker-scoped idempotence.
    func copyAgentRules() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Integrations.agentRulesSection(), forType: .string)
        copiedMessage = NSLocalizedString("Agent safety rules copied. Paste them into AGENTS.md or CLAUDE.md.", comment: "")
    }

    func copyMCPConfiguration() {
        // Resolved through Integrations so the path is the CLI that actually
        // ships in this bundle. The previous version hardcoded
        // Contents/MacOS/agentspace — a file this bundle has never contained —
        // so the copied configuration pointed the MCP server at nothing.
        guard let binary = Integrations.defaultBinaryPath() else { return }
        let snippet = Integrations.config(for: .generic, binaryPath: binary)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet, forType: .string)
        copiedMessage = NSLocalizedString("MCP configuration copied. Paste it into your client's mcpServers object.", comment: "")
    }
}
