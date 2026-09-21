import AppKit
import SwiftUI
import AgentSpaceUpdaterSupport

/// The Update tab. Declared last on purpose: `scripts/gui-verify.sh` reaches the
/// Advanced tab by clicking the fourth toolbar button of the Settings window, so
/// the settings tabs are a gate contract as well as an ordering.
struct SoftwareUpdateView: View {
    @EnvironmentObject private var updater: SoftwareUpdater
    @AppStorage("automaticallyChecksForUpdates") private var checksAutomatically = true

    private var release: SoftwareRelease? { updater.state.availableRelease }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version") {
                    Text(String(
                        format: NSLocalizedString("Running %@ from %@", comment: ""),
                        AppModel.displayVersion,
                        updater.applicationDirectory))
                        .textSelection(.enabled)
                }
                if let obstruction = updater.installObstruction {
                    Text(obstructionNotice(obstruction))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("updateBlockedNotice")
                }
            } header: {
                Text("This copy")
            }

            Section {
                switch updater.state {
                case .idle:
                    checkButton(title: "Check for Updates", disabled: false)
                case .checking:
                    busyRow(NSLocalizedString("Checking for updates…", comment: ""))
                case .upToDate:
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.green)
                        Text(String(format: NSLocalizedString("%@ is the latest version.", comment: ""),
                                    updater.currentVersion))
                        Spacer()
                        checkButton(title: "Check Again", disabled: false)
                    }
                case .available:
                    availableRow
                case .downloading:
                    busyRow(NSLocalizedString("Downloading the update…", comment: ""))
                case .installing:
                    busyRow(NSLocalizedString("Preparing the update…", comment: ""))
                case .failed(let failure):
                    failedRow(failure)
                }
            } header: {
                Text("Software Update")
            } footer: {
                Text(NSLocalizedString(
                    "Updates come from AgentSpace's GitHub releases. The download is checked against the SHA-256 GitHub stores for it, then the unpacked app is checked for its signature, its developer team, its identity against this running copy, and Gatekeeper's approval. AgentSpace then quits, installs itself and relaunches.",
                    comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Check for updates when AgentSpace opens", isOn: $checksAutomatically)
                    .accessibilityIdentifier("automaticUpdateCheckToggle")
                Button("Open Release Page") {
                    NSWorkspace.shared.open(SoftwareUpdater.latestReleasePageURL)
                }
            }
        }
        .formStyle(.grouped)
        .tabItem { Label("Update", systemImage: "arrow.triangle.2.circlepath") }
        .accessibilityIdentifier("softwareUpdatePane")
    }
    private var availableRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.up.circle")
                    .foregroundStyle(.blue)
                Text(String(format: NSLocalizedString("AgentSpace %@ is available.", comment: ""),
                            release?.version.description ?? ""))
                    .font(.headline)
                Spacer()
                installButton
            }
            if let notes = release?.releaseNotes, !notes.isEmpty {
                Text("Release notes")
                    .font(.caption.bold())
                Text(notes)
                    .font(.caption)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func failedRow(_ failure: SoftwareUpdateFailure) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(messageText(failure.message))
                    .accessibilityIdentifier("updateStateText")
                Spacer()
                checkButton(title: "Try Again", disabled: false)
            }
            if let detail = failure.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func busyRow(_ label: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(label)
                .accessibilityIdentifier("updateStateText")
        }
    }

    private func checkButton(title: String, disabled: Bool) -> some View {
        Button(LocalizedStringKey(title)) {
            Task { await updater.checkForUpdates() }
        }
        .disabled(disabled || updater.state.isBusy)
        .accessibilityIdentifier("updateCheckButton")
    }

    private var installButton: some View {
        Button("Download and Update") {
            Task { await updater.downloadAndInstall() }
        }
        .disabled(!updater.canInstallUpdates)
        .accessibilityIdentifier("updateInstallButton")
    }

    private func obstructionNotice(_ obstruction: String) -> String {
        String(format: NSLocalizedString(
            "This window is %@, which is not where an installed AgentSpace lives, so it cannot replace itself. Install the release DMG to update.",
            comment: ""), obstruction)
    }

    private func messageText(_ message: SoftwareUpdateFailure.Message) -> String {
        switch message {
        case .release: return NSLocalizedString(
            "The published release could not be read, or it carries no verified archive.", comment: "")
        case .integrity: return NSLocalizedString(
            "The download did not match the checksum GitHub published for it.", comment: "")
        case .verification: return NSLocalizedString(
            "The update failed signature or identity verification, so it was not installed.", comment: "")
        case .location: return NSLocalizedString(
            "This copy of AgentSpace cannot be replaced from here.", comment: "")
        case .helper: return NSLocalizedString(
            "This copy of AgentSpace ships no updater, so it cannot install one.", comment: "")
        case .network: return NSLocalizedString(
            "The network refused the update request.", comment: "")
        case .command: return NSLocalizedString(
            "A step of the installation failed.", comment: "")
        }
    }
}
