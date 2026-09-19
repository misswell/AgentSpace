import SwiftUI
import AgentSpaceCore

/// The create flow restated in V2 vocabulary — plan(v2) §5.
///
/// Three steps a human can follow without ever learning what a "Space" was:
/// 1. name the agent,
/// 2. say what it will do (stored on the record; per-purpose templates come
///    with the runtime manager, plan(v2) §10/§11),
/// 3. see exactly what will be created — and what will NOT change — before
///    anything touches the machine.
///
/// The workspace controls from the old single-page wizard live inside step 3:
/// they are an advanced answer, not the first question. Step 5 of the plan's
/// flow — the one manual first login — is not part of this sheet; it is
/// `LoginInstructions`, shown by `ProvisioningView` once the machine work is
/// done.
struct NewAgentWizard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var step = 1
    @State private var name = ""
    @State private var purpose: AgentPurpose?
    @State private var workspaceKind = 0
    @State private var repositoryPath = ""
    @State private var branch = "agentspace/"

    private let steps = 3

    /// The workspace the wizard will ask for. Computed here rather than in the
    /// model so the wizard can show the worktree path it is about to use — the
    /// user should see where the agent's checkout will live *before* committing.
    private var workspace: Workspace {
        switch workspaceKind {
        case 1, 2:
            let expanded = (repositoryPath as NSString).expandingTildeInPath
            if workspaceKind == 1, !expanded.isEmpty {
                // The path is filled in by SpaceProvisioner once the account has
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
                    if step == 2 { purposeStep }
                    if step == 3 { reviewStep }
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
                    Button(NSLocalizedString("Continue", comment: "")) {
                        step += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedName.isEmpty)
                } else {
                    Button(NSLocalizedString("Create Agent", comment: "")) {
                        model.createSpace(
                            name: trimmedName,
                            purpose: purpose,
                            workspace: workspace,
                            sharedFolders: sharedFolders)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.helperState.isReachable
                              || trimmedName.isEmpty
                              || model.provisioning != nil)
                    .help(Text(model.helperState.isReachable
                          ? NSLocalizedString("Create the agent's macOS user, runtime and worker.", comment: "")
                          : NSLocalizedString("The privileged helper must be installed and answering first.", comment: "")))
                }
            }
            .padding(14)
        }
        .frame(width: 620, height: 620)
    }

    // MARK: - Step 1: name

    private var nameStep: some View {
        Card(title: NSLocalizedString("Agent Name", comment: "")) {
            TextField("Coding Agent", text: $name)
                .textFieldStyle(.roundedBorder)
            Text("A macOS user named _agentspace_<random> is created for this agent. The display name is only a label.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 2: purpose

    private var purposeStep: some View {
        Card(title: NSLocalizedString("What will this agent do?", comment: "")) {
            Picker("", selection: $purpose) {
                Text(NSLocalizedString("Choose a purpose…", comment: "")).tag(AgentPurpose?.none)
                ForEach(AgentPurpose.allCases, id: \.self) { purpose in
                    Text(purpose.displayName).tag(AgentPurpose?.some(purpose))
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if let purpose {
                Text(purpose.summary)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("The purpose is saved with the account. Per-purpose startup templates arrive with the runtime manager.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 3: what will be created

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card(title: NSLocalizedString("AgentSpace will create a dedicated macOS user for this agent.", comment: "")) {
                VStack(alignment: .leading, spacing: 5) {
                    checkmark(NSLocalizedString("Separate files", comment: ""))
                    checkmark(NSLocalizedString("Separate browser data", comment: ""))
                    checkmark(NSLocalizedString("Separate desktop", comment: ""))
                    checkmark(NSLocalizedString("Separate applications", comment: ""))
                    checkmark(NSLocalizedString("Your current account will not be affected", comment: ""))
                }
                if let purpose {
                    Field(label: NSLocalizedString("Purpose", comment: ""), value: purpose.displayName)
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

            Text("There is deliberately no way to create an account from the CLI or from MCP. Those change the machine and require an administrator, so they stay here, behind a confirmation.")
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
                StatusDot(state: model.helperState.isReachable ? .ready : .needsPermission)
                Text(model.helperState.summary)
                    .font(.callout.weight(.medium))
                Spacer()
            }

            if let version = model.helperState.helperVersionIfKnown {
                Field(label: NSLocalizedString("Version", comment: ""), value: version)
            }

            if model.helperState.isReachable {
                Text("The helper is installed and answering. Creating an agent account will make a standard (never administrator) macOS user named _agentspace_<6 hex>, a runtime directory, and a LaunchAgent for its worker.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                RefusalBanner(
                    title: NSLocalizedString("Creating an agent account needs the privileged helper", comment: ""),
                    code: "HELPER_UNAVAILABLE",
                    message: "An agent account is a real macOS user, so creating one is an administrator operation. AgentSpace does it through a root helper that exposes a closed list of typed operations — it never runs a shell, and it will only ever create or delete users named _agentspace_<6 hex>.",
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
