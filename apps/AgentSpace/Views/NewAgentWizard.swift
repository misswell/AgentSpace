import SwiftUI
import AgentSpaceCore

/// V3 attach flow: select an existing standard macOS user, choose a label and
/// workspace, then install only AgentSpace's runtime and worker.
struct NewAgentWizard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var step = 1
    @State private var name = ""
    @State private var selectedUsername: String?
    @State private var workspaceKind = 0
    @State private var repositoryPath = ""
    @State private var branch = "agentspace/"

    private let steps = 2

    /// The workspace the wizard will ask for. Computed here rather than in the
    /// model so the wizard can show the worktree path it is about to use — the
    /// user should see where the agent's checkout will live *before* committing.
    private var workspace: Workspace {
        switch workspaceKind {
        case 1, 2:
            let expanded = (repositoryPath as NSString).expandingTildeInPath
            if workspaceKind == 1, !expanded.isEmpty {
                // The path is filled in by the attach service once the account has
                // an id, so the preview below shows the parent it will live
                // under rather than pretending to know the final path.
                return .gitWorktree(
                    repository: expanded,
                    branch: branch.hasPrefix("agentspace/") ? branch : "agentspace/\(branch)",
                    path: "")
            }
            return .sharedFolders
        default:
            return .none
        }
    }

    private var sharedFolders: [SharedFolder] {
        guard workspaceKind == 2, !repositoryPath.isEmpty else { return [] }
        return [SharedFolder(
            path: (repositoryPath as NSString).expandingTildeInPath,
            access: .readOnly)]
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var selectedAccount: LocalAccount? {
        model.availableAccounts.first { $0.username == selectedUsername }
    }

    private var continueButtonHint: String? {
        if selectedAccount == nil {
            return NSLocalizedString("Select an existing macOS account before continuing.", comment: "")
        }
        if trimmedName.isEmpty {
            return NSLocalizedString("Enter an Agent display name before continuing.", comment: "")
        }
        return nil
    }

    /// Why the Create button is or is not armed — the stale-helper case needs
    /// its own sentence because "installed and answering" would be a lie: the
    /// answering process is the pre-update binary launchd kept alive.
    private var createButtonHelp: String {
        if !model.helperState.isReachable {
            return NSLocalizedString("The privileged helper must be installed and answering first.", comment: "")
        }
        if model.helperState.isStaleBinary {
            return NSLocalizedString("The running helper is an older build; reinstall it in the card below before creating.", comment: "")
        }
        return NSLocalizedString("Connect the existing macOS account and install its AgentSpace worker.", comment: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(NSLocalizedString("New Agent", comment: "")).font(.headline)
                Text(String(format: NSLocalizedString("Step %ld of %ld", comment: ""), step, steps))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(NSLocalizedString("Cancel", comment: "")) { dismiss() }
            }
            .padding(14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if step == 1 { nameStep }
                    if step == 2 { reviewStep }
                }
                .padding(14)
            }

            Divider()

            HStack {
                if step > 1 {
                    Button(NSLocalizedString("Back", comment: "")) {
                        step -= 1
                    }
                }
                Spacer()
                if step < steps {
                    if let continueButtonHint {
                        Text(continueButtonHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                    Button(NSLocalizedString("Continue", comment: "")) {
                        step += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedName.isEmpty || selectedAccount == nil)
                    .help(Text(continueButtonHint ?? NSLocalizedString("Continue to review the connection.", comment: "")))
                    .accessibilityIdentifier("wizardContinue")
                } else {
                    Button(NSLocalizedString("Connect Account", comment: "")) {
                        guard let selectedAccount else { return }
                        model.attachAccount(
                            selectedAccount,
                            displayName: trimmedName,
                            workspace: workspace,
                            sharedFolders: sharedFolders)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.helperState.isReachable
                              || model.helperState.isStaleBinary
                              || trimmedName.isEmpty
                              || selectedAccount == nil
                              || model.provisioning != nil)
                    .help(Text(createButtonHelp))
                    // The one button in the app that makes a macOS user. Its
                    // enabled state *is* the staleness verdict, so
                    // `scripts/gui-verify.sh` reads it against the banner's
                    // HELPER_OUTDATED code — neither of which is a translated
                    // string, so the check works in any system language.
                    .accessibilityIdentifier("createAgentButton")
                }
            }
            .padding(14)
        }
        .frame(width: 620, height: 620)
        // The card below has to describe the helper as it is *now*: the periodic
        // refresh never pings it (a timeout per refresh with no helper installed),
        // so without this the wizard could refuse Create against a helper that
        // answers, or green-light one launchd has since evicted.
        .onAppear {
            model.refreshHelperState()
            model.discoverAccounts()
        }
        // Provisioning lives *inside* the wizard, not in a second sheet. A
        // window presents one sheet at a time: while the wizard held it, the
        // RootView-level provisioning sheet never appeared, so a failed create
        // left `provisioning` set with no visible way to dismiss it — and the
        // Create button, disabled on `provisioning != nil`, was dead on every
        // later attempt with no explanation. As an overlay the step list, the
        // failure and the Done button are all on screen.
        .overlay {
            if let provisioning = model.provisioning {
                ProvisioningView(provisioning: provisioning) { model.dismissProvisioning() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
            }
        }
    }

    // MARK: - Step 1: account

    private var nameStep: some View {
        Card(title: NSLocalizedString("Available macOS Accounts", comment: "")) {
            if model.availableAccounts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("No unattached standard users were found. Add one in System Settings → Users & Groups, then return here.", comment: ""))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Picker(NSLocalizedString("macOS User", comment: ""), selection: $selectedUsername) {
                    Text(NSLocalizedString("Choose an account", comment: "")).tag(String?.none)
                    ForEach(model.availableAccounts) { account in
                        Text("\(account.displayName) — \(account.username) (uid \(account.uid))")
                            .tag(Optional(account.username))
                    }
                }
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("macOSUserPicker")
            }

            HStack(spacing: 8) {
                if model.availableAccounts.isEmpty {
                    Button(NSLocalizedString("Open Users & Groups", comment: "")) {
                        openUsersAndGroups()
                    }
                    .accessibilityIdentifier("openUsersGroupsButton")
                }
                Button(NSLocalizedString("Refresh accounts", comment: "")) {
                    model.discoverAccounts()
                }
                .accessibilityIdentifier("refreshAccountsButton")
            }
            .controlSize(.small)

            Text(NSLocalizedString("Agent display name", comment: ""))
                .font(.callout.weight(.medium))
            TextField(NSLocalizedString("Agent name", comment: ""), text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("agentNameField")
            Text(NSLocalizedString("The name below is a label only; it does not create a macOS account.", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func openUsersAndGroups() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Step 2: what will be created

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card(title: NSLocalizedString("AgentSpace will connect to this existing macOS account.", comment: "")) {
                VStack(alignment: .leading, spacing: 5) {
                    checkmark(NSLocalizedString("Separate files", comment: ""))
                    checkmark(NSLocalizedString("Separate browser data", comment: ""))
                    checkmark(NSLocalizedString("Separate desktop", comment: ""))
                    checkmark(NSLocalizedString("Separate applications", comment: ""))
                    checkmark(NSLocalizedString("Your current account will not be affected", comment: ""))
                }
                if trimmedName.isEmpty {
                    Text(NSLocalizedString("Go back and give the agent a name.", comment: ""))
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Card(title: NSLocalizedString("Workspace (advanced)", comment: "")) {
                Picker("", selection: $workspaceKind) {
                    Text(NSLocalizedString("None", comment: "")).tag(0)
                    Text(NSLocalizedString("Git Worktree", comment: "")).tag(1)
                    Text(NSLocalizedString("Shared Folder", comment: "")).tag(2)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                if workspaceKind == 1 {
                    TextField("~/Code/MyApp", text: $repositoryPath)
                        .textFieldStyle(.roundedBorder)
                    TextField("agentspace/", text: $branch)
                        .textFieldStyle(.roundedBorder)
                    Text("The agent works in its own worktree on its own branch, so it never edits the tree you have open.")
                        .font(.caption).foregroundStyle(.secondary)
                    if case .gitWorktree(let repo, let branch, _) = workspace {
                        Field(label: NSLocalizedString("Repository", comment: ""), value: repo, monospaced: true)
                        Field(label: NSLocalizedString("Branch", comment: ""), value: branch, monospaced: true)
                        Field(label: NSLocalizedString("Worktree", comment: ""), value: AppModel.worktreesDirectory + "/<account-id>/…", monospaced: true)
                    }
                } else if workspaceKind == 2 {
                    TextField("~/Documents/TestData", text: $repositoryPath)
                        .textFieldStyle(.roundedBorder)
                    Text("Shared folders are read-only unless you explicitly allow writing.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            HelperCard()

            Text("Disconnecting later removes only the AgentSpace worker and runtime. The macOS account and its home directory are always kept.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func checkmark(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text).font(.callout)
        }
    }
}

/// The privileged helper's state, with the one button that can change it.
///
/// Shown inside the create flow rather than buried in Settings, because this is
/// where it blocks the user: a Create button that cannot work needs to say why,
/// on the same screen, with the fix next to it.
struct HelperCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Card(title: NSLocalizedString("Privileged helper", comment: "")) {
            HStack(spacing: 8) {
                StatusDot(state: model.helperState.isReachable && !model.helperState.isStaleBinary
                    ? .ready : .needsPermission)
                Text(model.helperState.summary)
                    .font(.callout.weight(.medium))
                Spacer()
            }

            if let version = model.helperState.helperVersionIfKnown {
                Field(label: NSLocalizedString("Version", comment: ""), value: version)
            }

            if model.helperState.isReachable, model.helperState.isStaleBinary {
                // The trap this removes: the card used to read "installed and
                // answering" in green while launchd served the pre-update
                // binary, so every create failed identically and the Install
                // button — a no-op on a registered daemon — looked like it had
                // been ignored. Say what is running, and offer the one swap.
                RefusalBanner(
                    title: NSLocalizedString("The helper that answers is an older build than this app", comment: ""),
                    code: "HELPER_OUTDATED",
                    message: NSLocalizedString("launchd keeps a registered daemon's process running across app updates, so the version inside this app has never started. Connecting an account would run the old code.", comment: ""),
                    fix: NSLocalizedString("Reinstall the helper below. macOS will ask for your password once: it stops the old daemon and registers the current one.", comment: ""))

                Button {
                    model.reinstallHelper()
                } label: {
                    if model.isInstallingHelper {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text(NSLocalizedString("Reinstalling…", comment: "")) }
                    } else {
                        Text(NSLocalizedString("Reinstall Helper…", comment: ""))
                    }
                }
                .disabled(model.isInstallingHelper)
                .accessibilityIdentifier("reinstallHelperButton")
            } else if model.helperState.isReachable {
                Text("The helper is installed and answering. It installs a root-owned worker and an account-specific runtime; it never creates or deletes macOS users.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                RefusalBanner(
                    title: NSLocalizedString("Connecting an account needs the privileged helper", comment: ""),
                    code: "HELPER_UNAVAILABLE",
                    message: NSLocalizedString("AgentSpace uses a root helper only to install its worker and prepare the shared runtime. The helper exposes a closed list of typed operations and never runs a shell or changes macOS user accounts.", comment: ""),
                    fix: model.helperState.fix ?? NSLocalizedString("Open the AgentSpace app and choose Install Helper.", comment: ""))

                HStack {
                    Button {
                        model.installHelper()
                    } label: {
                        if model.isInstallingHelper {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(NSLocalizedString("Installing…", comment: "")) }
                        } else {
                            Text(NSLocalizedString("Install Helper…", comment: ""))
                        }
                    }
                    .disabled(model.isInstallingHelper)
                    .help(Text("macOS will ask for your password: only an administrator can add a LaunchDaemon."))
                }
            }
        }
    }
}
