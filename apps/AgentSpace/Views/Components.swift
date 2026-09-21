import SwiftUI
import AgentSpaceCore

/// Small, shared pieces. Kept plain on purpose: plan §27 asks for native macOS,
/// minimal, no gradients and no gamified dashboard, in the register of System
/// Settings and OrbStack.

/// The status dot from the plan's §27 sketch. Colour carries the meaning, and the
/// text label always accompanies it so colour is never the only signal.
struct StatusDot: View {
    var state: SpaceState

    private var color: Color {
        switch state {
        case .ready, .running: return .green
        case .console: return .orange
        case .needsLogin, .needsPermission: return .yellow
        case .offline, .error: return .red
        case .created: return .secondary
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
            .accessibilityLabel(state.displayName)
    }
}

/// A bordered group, matching the detail panes in System Settings.
struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

/// One key/value line inside a `Card`.
struct Field: View {
    var label: String
    var value: String
    var monospaced: Bool = false
    var tint: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 108, alignment: .leading)
            Text(value)
                .font(monospaced ? .callout.monospaced() : .callout)
                .foregroundStyle(tint ?? .primary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

/// A permission chip. Two states only — granted or not — because a "maybe" is
/// what the whole fail-closed design exists to avoid.
struct PermissionChip: View {
    var name: String
    var granted: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)
            Text(name)
                .font(.callout)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill((granted ? Color.green : Color.orange).opacity(0.10))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(
            format: NSLocalizedString("%@: %@", comment: ""),
            name, granted
                ? NSLocalizedString("granted", comment: "")
                : NSLocalizedString("not granted", comment: "")))
    }
}

/// Why an operation did not happen, and what to do about it.
///
/// Always shows the code as well as the sentence. A user reporting a problem, and
/// an agent reading a screenshot of this window, both need the stable name.
struct RefusalBanner: View {
    var title: String
    var code: String
    var message: String
    var fix: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.orange)
                Text(title).font(.callout.weight(.semibold))
                Spacer(minLength: 0)
                Text(code)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let fix {
                Text(fix)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }
}

/// What the last helper attempt said, rendered where it was pressed.
///
/// Both helper buttons live inside sheets, and §269 already settled that no alert
/// presents over an open sheet — so before this existed, a refused `register()`
/// produced a fully populated failure that nowhere on screen could show, and the
/// person who clicked watched a button do nothing.
struct HelperFailureBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let failure = model.helperFailure {
            RefusalBanner(
                title: NSLocalizedString("The helper was not changed", comment: ""),
                code: failure.code,
                message: failure.message,
                fix: failure.fix)
        }
    }
}

/// The empty state before any agent account exists. It has to explain the one
/// fact that makes AgentSpace different from every other tool with a "New"
/// button: making an agent account makes a real macOS user, which needs an
/// administrator.
struct EmptyStateView: View {
    @EnvironmentObject private var model: AppModel
    var onCreate: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.crop.square")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("No agent accounts", comment: ""))
                .font(.title3.weight(.semibold))
            Text(NSLocalizedString("An agent account is a dedicated macOS user with its own desktop, so the agent can browse, code and test without touching your keyboard, mouse or screen.", comment: ""))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Text("Build \(AppModel.displayVersion)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .accessibilityIdentifier("appBuildVersion")
            if let current = model.currentAccountAuthorization {
                CurrentAccountPermissionCard(current: current)
                    .environmentObject(model)
            } else if let root = AgentSpaceEnvironment.rootOverride {
                // An installation override reads a different registry, and that
                // looks exactly like an empty machine. Say which file was read
                // before offering any theory about why it is empty (§300).
                Text(String(format: NSLocalizedString("This window reads %@ because AGENTSPACE_ROOT was set when AgentSpace launched. Clear it to read the normal registry.", comment: ""), root))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("registryRootOverrideNotice")
            } else {
                Text(NSLocalizedString("If you are signed in as an attached account, this panel is intentionally empty. Switch back to the account that owns AgentSpace to manage the agent and its permissions.", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Text(NSLocalizedString("Permissions for this desktop belong to agentspace-worker, the background process in this account. If this account has already been attached, refresh this window to reveal its authorization card.", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Button(NSLocalizedString("New Agent…", comment: ""), action: onCreate)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

/// The attached account's local authorization surface. The controller's
/// registry remains private, but this account can authorize its own
/// `agentspace-worker` directly from the same AgentSpace window it opened.
private struct CurrentAccountPermissionCard: View {
    @EnvironmentObject private var model: AppModel

    let current: CurrentAccountAuthorization

    var body: some View {
        Card(title: NSLocalizedString("Authorize this account", comment: "")) {
            Text(String(format: NSLocalizedString("This AgentSpace window is running as %@. Authorize the background agentspace-worker for this desktop here.", comment: ""), current.account.username))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text(NSLocalizedString("You do not need a second AgentSpace app. The buttons below prepare the worker and open this account's own System Settings.", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                PermissionChip(
                    name: NSLocalizedString("Accessibility", comment: ""),
                    granted: current.accessibility)
                PermissionChip(
                    name: NSLocalizedString("Screen Recording", comment: ""),
                    granted: current.screenRecording)
                if let fileAccess = current.fileAccess {
                    PermissionChip(
                        name: NSLocalizedString("Full Disk Access", comment: ""),
                        granted: fileAccess)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    model.authorizeCurrentAccount(pane: .accessibility)
                } label: {
                    authorizationLabel(
                        title: NSLocalizedString("Authorize Accessibility", comment: ""),
                        icon: "person.crop.circle.badge.checkmark",
                        pane: .accessibility)
                }
                .accessibilityIdentifier("authorizeCurrentAccountAccessibility")

                Button {
                    model.authorizeCurrentAccount(pane: .screenRecording)
                } label: {
                    authorizationLabel(
                        title: NSLocalizedString("Authorize Screen Recording", comment: ""),
                        icon: "record.circle",
                        pane: .screenRecording)
                }
                .accessibilityIdentifier("authorizeCurrentAccountScreenRecording")
            }

            Button {
                model.authorizeCurrentAccount(pane: .fullDiskAccess)
            } label: {
                authorizationLabel(
                    title: NSLocalizedString("Authorize Full Disk Access", comment: ""),
                    icon: "lock.open.trianglebadge.exclamationmark",
                    pane: .fullDiskAccess)
            }
            .accessibilityIdentifier("authorizeCurrentAccountFullDiskAccess")

            Text(NSLocalizedString("Accessibility and Screen Recording are required. Full Disk Access is optional: without it this account's Desktop, Documents, Downloads and other apps' data stay closed to the worker, which is a working state, not a broken one.", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                model.discoverCurrentAccountAuthorization()
            } label: {
                Label(NSLocalizedString("Refresh authorization status", comment: ""), systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(model.authorizingCurrentPermission != nil)

            if !current.workerOnline {
                Label(NSLocalizedString("The worker is not running yet. The first authorization click installs and starts the current worker before opening System Settings.", comment: ""), systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 560)
    }

    @ViewBuilder
    private func authorizationLabel(
        title: String,
        icon: String,
        pane: SystemSettingsPane
    ) -> some View {
        if model.authorizingCurrentPermission == pane {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(NSLocalizedString("Preparing authorization…", comment: ""))
            }
        } else {
            Label(title, systemImage: icon)
        }
    }
}

/// The Finder-style home (plan(v2) §4/§14): every agent account as a card with
/// its status, its macOS user and the one action people actually want. Shown
/// in the detail column whenever no specific account is selected.
struct AgentCardGrid: View {
    var snapshots: [SpaceSnapshot]
    var onSelect: (UUID) -> Void
    var onOpenDesktop: (SpaceSnapshot) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 14)],
                spacing: 14) {
                ForEach(snapshots) { snapshot in
                    AgentCard(snapshot: snapshot, onSelect: onSelect, onOpenDesktop: onOpenDesktop)
                }
            }
            .padding(18)
        }
    }
}

private struct AgentCard: View {
    var snapshot: SpaceSnapshot
    var onSelect: (UUID) -> Void
    var onOpenDesktop: (SpaceSnapshot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusDot(state: snapshot.effectiveState)
                Text(snapshot.space.displayName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            if let purpose = snapshot.space.purpose {
                Text(purpose.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Field(label: NSLocalizedString("macOS User", comment: ""),
                  value: snapshot.space.macOSUsername, monospaced: true)
            Field(label: NSLocalizedString("Desktop", comment: ""),
                  value: snapshot.effectiveState.displayName)
            HStack(spacing: 8) {
                Button(NSLocalizedString("Open Desktop", comment: "")) {
                    onOpenDesktop(snapshot)
                }
                .controlSize(.small)
                .disabled(snapshot.display == nil)
                Button(NSLocalizedString("Details", comment: "")) {
                    onSelect(snapshot.space.id)
                }
                .controlSize(.small)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { onSelect(snapshot.space.id) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(snapshot.space.displayName)
    }
}
