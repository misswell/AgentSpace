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
                Button("Create") { }
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
                    .help(model.helperState.isReachable
                          ? "The helper is ready. Wiring this button to it is the next piece of work."
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
                // Still not a working Create button: Space creation is the next
                // phase. Saying so is better than a button that fails.
                RefusalBanner(
                    title: "The helper is ready; Space creation is not wired up yet",
                    code: "NOT_IMPLEMENTED",
                    message: "The helper — a root LaunchDaemon with a closed list of typed operations and no shell — is installed and answering. The final step, calling it from this wizard to create the macOS user, is the next piece of work.",
                    fix: "Everything that drives an *existing* Space works today: the Desktop Viewer, input, screenshots, apps, exec and the accessibility tree.")
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
