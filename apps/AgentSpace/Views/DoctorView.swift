import SwiftUI
import AgentSpaceCore

/// `agentspace doctor`, rendered — plan §38.
///
/// The checks themselves come from `AgentSpaceCore.Doctor`, the same type the CLI
/// uses. The GUI does not have its own diagnostics, so the two cannot disagree
/// about whether the machine is ready.
struct DoctorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// The exported bundle is the same redacted text the CLI's
    /// `agentspace diagnostics` produces — one collector, two surfaces (§49).
    @State private var exportedPath: String?

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "agentspace-diagnostics.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Diagnostics.collect().write(to: url, atomically: true, encoding: .utf8)
            exportedPath = url.path
        } catch {
            exportedPath = nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Diagnostics").font(.headline)
                Spacer()
                Button {
                    model.runDoctor()
                } label: {
                    Label("Re-run", systemImage: "arrow.clockwise")
                }
                Button {
                    exportDiagnostics()
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                .disabled(exportedPath != nil)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)

            Divider()

            if let report = model.doctorReport {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(report.checks.enumerated()), id: \.offset) { _, check in
                            CheckRow(check: check)
                            Divider()
                        }
                    }
                }
                Divider()
                HStack {
                    Text(summary(report))
                        .font(.callout)
                        .foregroundStyle(report.ok ? .secondary : .primary)
                    Spacer()
                    Button("Copy Report") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(report.render(), forType: .string)
                    }
                }
                .padding(14)
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Running checks…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 620, height: 520)
        .onAppear { model.runDoctor() }
    }

    private func summary(_ report: Doctor.Report) -> String {
        if report.ok && report.warned == 0 { return "All checks passed." }
        if report.ok { return "\(report.checks.count) checks, \(report.warned) warning(s). AgentSpace can run." }
        return "\(report.checks.count) checks, \(report.failed) failure(s), \(report.warned) warning(s)."
    }
}

private struct CheckRow: View {
    var check: Doctor.Check

    private var symbol: String {
        switch check.status {
        case .pass: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        case .skip: return "minus.circle"
        }
    }

    private var color: Color {
        switch check.status {
        case .pass: return .green
        case .warn: return .orange
        case .fail: return .red
        case .skip: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(check.name).font(.callout.weight(.medium))
                // A passing check's detail is noise; a failing one's is the point.
                if check.status != .pass {
                    Text(Redaction.scrubString(check.detail))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let fix = check.fix {
                        Label(fix, systemImage: "arrow.turn.down.right")
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// The create wizard's first two steps — plan §28.
///
/// It stops short of creating anything on purpose. Creating a Space makes a macOS
/// user and installs a LaunchAgent, which is the privileged helper's job (phase 3),
/// and the honest thing for this screen to do until then is explain that rather
/// than offer a button that cannot work.
struct NewSpaceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var workspaceKind = 0
    @State private var repositoryPath = ""
    @State private var branch = "agentspace/"

    /// The workspace the wizard will ask for. Computed here rather than in the
    /// model so the wizard can show the worktree path it is about to use — the
    /// user should see where the agent's checkout will live *before* committing.
    private var workspace: Workspace {
        switch workspaceKind {
        case 1, 2:
            let expanded = (repositoryPath as NSString).expandingTildeInPath
            if workspaceKind == 1, !expanded.isEmpty {
                // The path is filled in by SpaceProvisioner once the Space has an
                // id, so the preview below shows the parent it will live under
                // rather than pretending to know the final path.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Create Agent Space").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding(14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Card(title: "Name") {
                        TextField("Frontend Test", text: $name)
                            .textFieldStyle(.roundedBorder)
                        Text("A macOS user named _agentspace_<random> is created for this Space. The display name is only a label.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Card(title: "Workspace") {
                        Picker("", selection: $workspaceKind) {
                            Text("None").tag(0)
                            Text("Git Worktree").tag(1)
                            Text("Shared Folder").tag(2)
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
                                Field(label: "Repository", value: repo, monospaced: true)
                                Field(label: "Branch", value: branch, monospaced: true)
                                Field(label: "Worktree", value: AppModel.worktreesDirectory + "/<space-id>/…", monospaced: true)
                            }
                        } else if workspaceKind == 2 {
                            TextField("~/Documents/TestData", text: $repositoryPath)
                                .textFieldStyle(.roundedBorder)
                            Text("Shared folders are read-only unless you explicitly allow writing.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    HelperCard()
                }
                .padding(14)
            }

            Divider()

            HStack {
                Text("There is deliberately no way to create a Space from the CLI or from MCP. Those change the machine and require an administrator, so they stay here, behind a confirmation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Create") {
                    model.createSpace(
                        name: name.trimmingCharacters(in: .whitespaces),
                        workspace: workspace,
                        sharedFolders: sharedFolders)
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.helperState.isReachable
                              || name.trimmingCharacters(in: .whitespaces).isEmpty
                              || model.provisioning != nil)
                    .help(model.helperState.isReachable
                          ? "Create the Space's macOS user, runtime and worker."
                          : "The privileged helper must be installed and answering first.")
            }
            .padding(14)
        }
        .frame(width: 620, height: 620)
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
        Card(title: "Privileged helper") {
            HStack(spacing: 8) {
                StatusDot(state: model.helperState.isReachable ? .ready : .needsPermission)
                Text(model.helperState.summary)
                    .font(.callout.weight(.medium))
                Spacer()
            }

            if let version = model.helperState.helperVersionIfKnown {
                Field(label: "Version", value: version)
            }

            if model.helperState.isReachable {
                Text("The helper is installed and answering. Creating a Space will make a standard (never administrator) macOS account named _agentspace_<6 hex>, a runtime directory, and a LaunchAgent for its worker.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                RefusalBanner(
                    title: "Creating a Space needs the privileged helper",
                    code: "HELPER_UNAVAILABLE",
                    message: "A Space is a real macOS user, so creating one is an administrator operation. AgentSpace does it through a root helper that exposes a closed list of typed operations — it never runs a shell, and it will only ever create or delete accounts named _agentspace_<6 hex>.",
                    fix: model.helperState.fix ?? "Open the AgentSpace app and choose Install Helper.")

                HStack {
                    Button {
                        model.installHelper()
                    } label: {
                        if model.isInstallingHelper {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Installing…") }
                        } else {
                            Text("Install Helper…")
                        }
                    }
                    .disabled(model.isInstallingHelper)
                    .help("macOS will ask for your password: only an administrator can add a LaunchDaemon.")
                }
            }
        }
    }
}

/// What a create or delete is doing, step by step.
///
/// A spinner would be wrong here. Creating a Space makes a macOS account, a
/// runtime directory and a launchd job, and if one of those fails the user needs to
/// know *which* — and, when a cleanup also failed, that something was left behind
/// that they will have to remove themselves. The step list is the record of what
/// the machine actually did.
struct ProvisioningView: View {
    let provisioning: AppModel.Provisioning
    let dismiss: () -> Void

    private var hasFailure: Bool {
        provisioning.steps.contains { $0.hasPrefix("✗") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(provisioning.operation).font(.headline)
                Spacer()
                if provisioning.finished {
                    Button("Done") { dismiss() }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(provisioning.steps.enumerated()), id: \.offset) { _, step in
                        Text(step)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(step.hasPrefix("✗") ? .red : (step.hasPrefix("↩") ? .orange : .primary))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !provisioning.finished {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Working…").foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }

            if provisioning.finished && !hasFailure {
                Divider()
                LoginInstructions()
                    .padding(14)
            }
        }
        .frame(width: 560, height: 460)
    }
}

/// The one step that needs a human — plan §28.
///
/// AgentSpace cannot create an Aqua session for a user who has never logged in;
/// that is a macOS property, not a limitation to work around with a private API.
/// So the flow says so plainly, in order, and the app detects the result
/// afterwards rather than asking the user to report back.
struct LoginInstructions: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Next, once — this is the only step that needs you")
                .font(.callout.weight(.semibold))
            instruction(1, "Open Fast User Switching (Control Centre) and sign in as the new Space.")
            instruction(2, "Its password is in the Space's page: Show Login Password.")
            instruction(3, "In that session, grant Accessibility and Screen Recording when the setup window asks.")
            instruction(4, "Switch back to your own account. The agent keeps its desktop.")
            Text("The Space shows Needs Login until step 4 is done. AgentSpace will not start an agent in your account instead — if the background session is not there, every call fails with SESSION_NOT_READY.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Show the login password, briefly, for the one manual sign-in.
///
/// Deliberately not copy-on-appear and deliberately not stored anywhere by the
/// app: the password lives in the Keychain, is read on demand, and is discarded
/// when this sheet closes.
struct LoginPasswordView: View {
    let revealed: AppModel.RevealedPassword
    let dismiss: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Login password for \(revealed.spaceName)").font(.headline)

            Text(revealed.password)
                .font(.system(.title3, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Text("Use this once, at the fast-user-switching login window. It is stored in your login Keychain, not in a file, and nothing logs it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(revealed.password, forType: .string)
                    copied = true
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 460)
    }
}
