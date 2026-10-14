import SwiftUI
import AgentSpaceCore

/// A focused first-login guide for the one confusing part of V3: the privacy
/// grants belong to the attached account's Aqua session, while the AgentSpace
/// GUI stays in the controller account. The buttons deliberately remain in
/// this sheet so the user never has to hunt for a second copy of the app.
///
/// The sign-in door lives here too, inline rather than as a second sheet: a
/// window presents one sheet at a time (§269), and the temporary Screen Sharing
/// path stays live only while the view that opened it is on screen. Approving
/// three grants therefore needs one visit to that session, not one switch per
/// permission.
struct PermissionGuideView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let spaceID: UUID

    @State private var showingSignIn = false

    private var snapshot: SpaceSnapshot? {
        model.snapshots.first { $0.id == spaceID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let snapshot {
                        guide(snapshot)
                    } else {
                        Text(NSLocalizedString("This agent is no longer attached. Close this guide and refresh the account list.", comment: ""))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Spacer()
                Button(NSLocalizedString("Done", comment: "")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 620)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Authorize this agent", comment: ""))
                    .font(.title2.weight(.semibold))
                Text(NSLocalizedString("The worker needs two macOS privacy permissions before it can control the attached desktop. A third, optional grant opens this account's own files.", comment: ""))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func guide(_ snapshot: SpaceSnapshot) -> some View {
        Text(String(format: NSLocalizedString("You do not need to find AgentSpace in %@. The permission entry is agentspace-worker, a background process rather than a separate app. You also do not have to switch users: sign in below, keep that window on screen, and each pane opened from this guide appears inside it.", comment: ""), snapshot.space.username))
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        Text(NSLocalizedString("If no entry appears in the list, the worker has not asked yet. Pressing Open settings below asks on the worker's behalf and opens the pane in one step; the prompt then waits in the account's own session.", comment: ""))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        VStack(alignment: .leading, spacing: 10) {
            permissionRow(
                space: snapshot.space,
                title: NSLocalizedString("Accessibility", comment: ""),
                detail: NSLocalizedString("Lets agentspace-worker operate the attached desktop.", comment: ""),
                granted: snapshot.accessibility,
                pane: .accessibility,
                identifier: "permissionGuideAccessibility")
            permissionRow(
                space: snapshot.space,
                title: NSLocalizedString("Screen & System Audio Recording", comment: ""),
                detail: NSLocalizedString("Lets the worker capture the attached desktop for previews.", comment: ""),
                granted: snapshot.screenRecording,
                pane: .screenRecording,
                identifier: "permissionGuideScreenRecording")
            if let fileAccess = snapshot.fileAccess {
                permissionRow(
                    space: snapshot.space,
                    title: NSLocalizedString("Full Disk Access", comment: ""),
                    detail: NSLocalizedString("Optional. Lets agentspace-worker read this account's Desktop, Documents, Downloads and other apps' data. Without it those folders stay closed and the agent works normally everywhere else.", comment: ""),
                    granted: fileAccess,
                    pane: .fullDiskAccess,
                    identifier: "permissionGuideFullDiskAccess",
                    optional: true)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )

        if !snapshot.workerOnline {
            Label(NSLocalizedString("Sign in to the attached account first — the entry below does it without switching users. The worker must be running before macOS can show its permission entry.", comment: ""), systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        if snapshot.offersSignInDoor {
            signInDoor(snapshot.space)
        }

        HStack(spacing: 8) {
            Button {
                model.reload()
            } label: {
                Label(NSLocalizedString("Refresh authorization status", comment: ""), systemImage: "arrow.clockwise")
            }
            .accessibilityIdentifier("refreshPermissionGuide")
            .disabled(model.isLoading)
            Spacer()
            if !snapshot.workerOnline {
                Button(NSLocalizedString("Finish setup", comment: "")) {
                    model.finishPendingSetup(snapshot.space)
                }
                .disabled(model.finishingSetup != nil || model.updatingWorker != nil)
            }
        }

        Text(NSLocalizedString("AgentSpace never writes the TCC database. You approve each grant yourself in the attached account's System Settings.", comment: ""))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Always available, because the reason to open that session changes
    /// mid-approval: the window is the only way to see a pane while the
    /// permission that governs the built-in viewer — Screen Recording — is
    /// still missing.
    private func signInDoor(_ space: AgentAccount) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString("Approve without switching users", comment: ""))
                        .font(.callout.weight(.semibold))
                    Text(NSLocalizedString("The window this opens is also how you see the panes above: it stays live only while this guide is open.", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if !showingSignIn {
                    Button(NSLocalizedString("Sign in without switching users…", comment: "")) {
                        showingSignIn = true
                    }
                    .accessibilityIdentifier("permissionGuideSignIn")
                    .disabled(model.finishingSetup != nil || model.updatingWorker != nil)
                }
            }
            if showingSignIn {
                AgentSignInPanel(account: space, model: model, context: .authorization) {
                    showingSignIn = false
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(0.30), lineWidth: 1)
        )
    }

    private func permissionRow(
        space: AgentAccount,
        title: String,
        detail: String,
        granted: Bool,
        pane: SystemSettingsPane,
        identifier: String,
        optional: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(stateColor(granted: granted, optional: optional))
                Text(title).font(.callout.weight(.semibold))
                Spacer()
                Text(statusLabel(granted: granted, optional: optional))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(stateColor(granted: granted, optional: optional))
            }
            HStack(alignment: .top, spacing: 8) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(NSLocalizedString("Open settings", comment: "")) {
                    model.authorizeAgent(space, pane: pane)
                }
                .accessibilityIdentifier(identifier)
                .disabled(model.authorizingPermission != nil || model.openingSystemSettings != nil || model.updatingWorker != nil || model.finishingSetup != nil)
            }
        }
    }

    /// A missing optional grant is a choice, not a fault, so it does not earn
    /// the warning orange that "this desktop cannot be operated" earns.
    private func stateColor(granted: Bool, optional: Bool) -> Color {
        if granted { return .green }
        return optional ? .secondary : .orange
    }

    private func statusLabel(granted: Bool, optional: Bool) -> String {
        if granted { return NSLocalizedString("Granted", comment: "") }
        if optional { return NSLocalizedString("Not granted (optional)", comment: "") }
        return NSLocalizedString("Needs approval", comment: "")
    }
}
