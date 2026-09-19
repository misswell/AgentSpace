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
                        }                    }
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
        if report.ok && report.warned == 0 { return NSLocalizedString("All checks passed.", comment: "") }
        if report.ok {
            return String(format: NSLocalizedString("%ld checks, %ld warning(s). AgentSpace can run.", comment: ""),
                          report.checks.count, report.warned)
        }
        return String(format: NSLocalizedString("%ld checks, %ld failure(s), %ld warning(s).", comment: ""),
                      report.checks.count, report.failed, report.warned)
    }
}

private struct CheckRow: View {
    var check: Doctor.Check
    @EnvironmentObject private var model: AppModel

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
                    // A check can name the one in-app action that fixes it, so
                    // the fix is a button here rather than advice to run
                    // something in a terminal.
                    if check.actionHint == "deleteOrphans" {
                        HStack(spacing: 8) {
                            Button {
                                model.deleteOrphanedAccounts()
                            } label: {
                                if model.isDeletingOrphans {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text(NSLocalizedString("Removing…", comment: ""))
                                    }
                                } else {
                                    Text(NSLocalizedString("Delete Orphaned Accounts…", comment: ""))
                                }
                            }
                            .disabled(model.isDeletingOrphans)
                            .help(Text("The helper deletes only accounts named _agentspace_<6 hex>. Your own accounts are never candidates."))
                        }
                        .padding(.top, 2)
                    }
                    if check.actionHint == "reinstallHelper" {
                        HStack(spacing: 8) {
                            Button {
                                model.reinstallHelper()
                            } label: {
                                if model.isInstallingHelper {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text(NSLocalizedString("Reinstalling…", comment: ""))
                                    }
                                } else {
                                    Text(NSLocalizedString("Reinstall Helper…", comment: ""))
                                }
                            }
                            .disabled(model.isInstallingHelper)
                            .help(Text("macOS keeps the old helper running after an app update; this swaps it for the one in this app. macOS will ask for your password."))
                        }
                        .padding(.top, 2)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
                    if provisioning.finished, let error = provisioning.error {
                        // The failure is rendered here, in the sheet the user is
                        // already looking at, because nothing can alert over an
                        // open sheet (§269) — and "Finished" with a silent error
                        // underneath the sign-in steps is the lie §272 records.
                        RefusalBanner(
                            title: NSLocalizedString("This did not finish", comment: ""),
                            code: error.code,
                            message: error.message,
                            fix: error.fix)
                        if let actionTitle = error.actionTitle, let action = error.action {
                            Button(actionTitle) { action() }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }

            if provisioning.finished && provisioning.offersLoginInstructions {
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
            instruction(1, NSLocalizedString("Open Fast User Switching (Control Centre) and sign in as the new agent.", comment: ""))
            instruction(2, NSLocalizedString("Its password is on the agent's page: Show Login Password.", comment: ""))
            instruction(3, NSLocalizedString("In that session, grant Accessibility and Screen Recording when the setup window asks.", comment: ""))
            instruction(4, NSLocalizedString("Switch back to your own account. The agent keeps its desktop.", comment: ""))
            Text("The agent shows Needs Login until step 4 is done. AgentSpace will not start an agent in your account instead — if the background session is not there, every call fails with SESSION_NOT_READY.")
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
            Text(String(format: NSLocalizedString("Login password for %@", comment: ""), revealed.spaceName)).font(.headline)

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
                Button(copied ? NSLocalizedString("Copied", comment: "") : NSLocalizedString("Copy", comment: "")) {
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
