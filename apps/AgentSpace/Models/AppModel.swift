import Foundation
import SwiftUI
@preconcurrency import ServiceManagement
import AgentSpaceCore

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
/// does not decide whether a Space is usable; it asks, and it believes the answer.
@MainActor
final class AppModel: ObservableObject {

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
    /// A create or delete in flight, with its steps, so the UI can show exactly
    /// what is happening to the machine rather than a spinner.
    @Published var provisioning: Provisioning?
    /// The password for one Space, revealed on request and then dismissed. Held
    /// only while the sheet is open — never persisted by the app.
    @Published var revealedPassword: RevealedPassword?
    /// The Space whose disk is currently being measured, so the button can show
    /// progress instead of being pressed twice.
    @Published var measuringDisk: UUID?
    /// Set when something was copied, so the UI can confirm without an alert.
    @Published var copiedMessage: String?

    struct Provisioning: Equatable, Identifiable {
        var id = UUID()
        var operation: String
        var steps: [String] = []
        var finished = false
    }

    struct RevealedPassword: Identifiable, Equatable {
        var id: UUID { spaceID }
        var spaceID: UUID
        var spaceName: String
        var password: String
    }
    @Published private(set) var isLoading = false
    @Published var showingNewSpace = false
    @Published var showingDoctor = false
    @Published private(set) var doctorReport: Doctor.Report?
    /// AgentSpace-named accounts with no Space record, as last computed by
    /// `runDoctor`. Empty when the helper could not be reached, so the delete
    /// button never appears for a list this app could not verify.
    @Published private(set) var orphanedUsernames: [String] = []
    @Published private(set) var isDeletingOrphans = false

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

    // MARK: - Create / delete (plan §28, §41)

    /// Create a Space. The machine changes happen inside `SpaceProvisioner`, which
    /// is where the rollback lives; this only reports progress.
    ///
    /// Everything runs off the main actor: creating an account and installing a
    /// launchd job takes seconds, and blocking the main thread would freeze the
    /// window with no explanation.
    func createSpace(name: String, workspace: Workspace, sharedFolders: [SharedFolder]) {
        guard provisioning == nil else { return }
        // `root` is nil only when the service was built without one, which in this
        // app never happens; falling back to the computed default keeps create
        // working rather than silently doing nothing.
        let root = service.root ?? AgentSpaceEnvironment.rootOverride ?? RuntimePaths.root
        provisioning = Provisioning(operation: String(format: NSLocalizedString("Creating %@", comment: ""), name))
        let directory = Self.worktreesDirectory

        Task {
            let keychain = KeychainStore()
            let registry = SpaceRegistry.load(root: root)
            let outcome = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: SpaceProvisioner.create(
                        name: name, workspace: workspace, sharedFolders: sharedFolders,
                        options: SpaceProvisioner.Options(
                            root: root, workspaceDirectory: directory, mainUser: NSUserName()),
                        transport: { try HelperClient.call($0) },
                        registry: registry,
                        keychain: keychain))
                }
            }

            // Narrate the steps as they happened, not as they were planned: the
            // step list is the record of what the machine actually did, and it is
            // what the user needs if something went wrong.
            self.provisioning?.steps = outcome.steps.map(Self.describe)
            self.provisioning?.finished = true

            if let error = outcome.error {
                self.lastError = PresentedError(
                    code: error.code.rawValue,
                    message: error.message,
                    fix: error.code.remediation)
            }
            self.reload()
        }
    }

    /// §40's Stop Agent: stop the worker, keep the session. The effective
    /// state goes to offline/needsLogin on the next refresh — honestly.
    func stopWorker(_ space: AgentSpace) {
        guard case .success = service.stopWorker(for: space) else { return }
        if selected?.space.id == space.id { reload() }
    }

    /// §40's Logout Desktop: helper-typed; a missing helper surfaces as the
    /// typed error with its fix, which is the fail-closed behavior.
    func logoutDesktop(_ space: AgentSpace) {
        if case .failure(let error) = service.logoutDesktop(for: space) {
            lastError = PresentedError(code: error.code.rawValue, message: error.message, fix: error.code.remediation)
        }
        if selected?.space.id == space.id { reload() }
    }

    func deleteSpace(_ space: AgentSpace, removeHome: Bool) {
        guard provisioning == nil else { return }
        provisioning = Provisioning(operation: String(format: NSLocalizedString("Deleting %@", comment: ""), space.name))

        let root = service.root ?? AgentSpaceEnvironment.rootOverride ?? RuntimePaths.root
        let directory = Self.worktreesDirectory
        Task {
            let outcome = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: SpaceProvisioner.delete(
                        space: space, removeHome: removeHome,
                        options: SpaceProvisioner.Options(
                            root: root,
                            workspaceDirectory: directory,
                            mainUser: NSUserName()),
                        transport: { try HelperClient.call($0) },
                        registry: SpaceRegistry.load(root: root),
                        keychain: KeychainStore()))
                }
            }
            self.provisioning?.steps = outcome.steps.map(Self.describe)
            self.provisioning?.finished = true
            if let error = outcome.error {
                self.lastError = PresentedError(code: error.code.rawValue, message: error.message, fix: error.code.remediation)
            }
            self.reload()
        }
    }

    /// Measure one Space's home directory, on request.
    ///
    /// Kept out of `reload()` deliberately: it walks every file in the Space's
    /// home, which for a browser profile plus an IDE's caches is tens of thousands
    /// of them. Doing that on the 2–5 s status poll would pin the CPU, which §53
    /// forbids. The result is merged into the existing snapshot so the rest of the
    /// page does not flicker.
    func measureDiskUsage(for space: AgentSpace) {
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

    /// Reveal a Space's login password, for the one manual sign-in.
    ///
    /// Read from the Keychain on demand and held only in the sheet that shows it.
    /// The app never caches it, never logs it, and never puts it on the clipboard
    /// without the user asking.
    func revealPassword(for space: AgentSpace) {
        do {
            if let password = try KeychainStore().password(for: space.id) {
                revealedPassword = RevealedPassword(
                    spaceID: space.id, spaceName: space.name, password: password)
            } else {
                lastError = PresentedError(
                    code: "NO_STORED_PASSWORD",
                    message: String(format: NSLocalizedString("There is no stored password for %@", comment: ""), space.name),
                    fix: NSLocalizedString("This Space was created before the password was stored, or its Keychain item was removed. Re-creating the Space generates a new one; the current password cannot be recovered.", comment: ""))
            }
        } catch {
            lastError = PresentedError(
                code: "KEYCHAIN_DENIED",
                message: "\(error)",
                fix: NSLocalizedString("Unlock your login keychain (Keychain Access) and try again.", comment: ""))
        }
    }

    /// The parent directory for git worktrees. Deliberately independent of the
    /// Space's name: `SpaceProvisioner` adds the Space's id underneath, which is
    /// what makes the path unique. Two Spaces named `Test` and `test` are one
    /// directory on a case-insensitive filesystem, and two agents in one working
    /// tree is the bug the worktree exists to prevent (plan §24).
    static var worktreesDirectory: String {
        let root = AgentSpaceEnvironment.rootOverride ?? RuntimePaths.root
        return "\(root)/Worktrees"
    }

    private static func describe(_ step: SpaceProvisioner.Step) -> String {
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
    /// select that Space and raise its Desktop Viewer. A link for a Space that
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
                message: String(format: NSLocalizedString("the link points at a Space that no longer exists (%@). It was probably deleted after the link was made.", comment: ""), id.uuidString))
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

        // Resources are fetched only for the Space on screen: one `ps` fork per
        // Space per refresh would be exactly the overhead §53 forbids.
        snapshots = spaces.map { space in
            service.snapshot(for: space, includeResources: space.id == selection)
        }
        isLoading = false

        if let selected = snapshots.first(where: { $0.id == selection }), let problem = selected.problem {
            // A refusal is normal and is shown in the detail pane, not as an
            // alert. Only something the user did is worth interrupting for.
            _ = problem
        }
    }

    /// Refresh the resource numbers for whichever Space is selected.
    /// Measure the selected Space's home directory (plan §30).
    func measureDisk(for space: AgentSpace) { measureDiskUsage(for: space) }

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
                self.orphanedUsernames = orphans ?? []
                self.doctorReport = Doctor.run(root: root, orphanedAccounts: orphans)
            }
        }
    }

    /// Remove accounts an interrupted creation left behind. Each delete is a
    /// typed helper operation (`deleteUser`), and the names are re-checked
    /// against the §8 naming contract here as well as in the helper — an
    /// account this app cannot prove it created is never offered for removal.
    func deleteOrphanedAccounts() {
        guard !isDeletingOrphans else { return }
        let names = orphanedUsernames.filter { HelperValidation.isAgentSpaceAccount($0) }
        guard !names.isEmpty else { return }
        isDeletingOrphans = true
        Task {
            let failures: [(String, String)] = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    var failures: [(String, String)] = []
                    for name in names {
                        let request = HelperRequest(operation: .deleteUser, username: name, removeHome: true)
                        do {
                            let response = try HelperClient.call(request)
                            if let error = response.error {
                                failures.append((name, error.message))
                            }
                        } catch {
                            failures.append((name, error.localizedDescription))
                        }
                    }
                    continuation.resume(returning: failures)
                }
            }
            self.isDeletingOrphans = false
            if failures.isEmpty {
                self.lastError = PresentedError(
                    code: "ORPHANS_REMOVED",
                    message: String(
                        format: NSLocalizedString("Removed %d orphaned account(s).", comment: ""),
                        names.count))
            } else {
                self.lastError = PresentedError(
                    code: "HELPER_REJECTED",
                    message: failures.map { "\($0.0): \($0.1)" }.joined(separator: "\n"),
                    fix: NSLocalizedString("Some accounts could not be removed. The helper's log has the detail; Export Diagnostics collects it.", comment: ""))
            }
            self.runDoctor()
        }
    }

    // MARK: - Space actions

    func present(_ error: AgentSpaceError, space: AgentSpace?) {
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
        case nil:
            break
        }
        lastError = presented
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
                        message: NSLocalizedString("The Command Line Tools installer window is open. When it finishes, try creating the Space again.", comment: ""))
                } else if stderr.contains("already installed") {
                    self?.lastError = PresentedError(
                        code: "CLT_ALREADY_INSTALLED",
                        message: NSLocalizedString("The Xcode Command Line Tools are already installed. Try creating the Space again.", comment: ""))
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

    /// Write the Space's screenshot to a file the user asked for.
    ///
    /// Note this asks the *worker* for the capture; it never grabs this session's
    /// screen. If the Space is unavailable the user gets the refusal, not a
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

    /// Reveal the Space's runtime directory, the honest place to look when the
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
