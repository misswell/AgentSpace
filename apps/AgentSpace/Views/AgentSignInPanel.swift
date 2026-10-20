import SwiftUI
import AgentSpaceCore

/// The explicit-login flow, as a panel that can live inside another view.
///
/// This was the body of `AccountLoginView`'s sheet, and the sheet was the only
/// place it existed. That made the two things the flow does in practice fight
/// each other: the Screen Sharing path stays usable only while the sheet is up
/// (`AccountLoginController.stop()` closes our transport), and while the sheet
/// is up the window behind it answers to nothing — including the permission
/// buttons this panel exists to make approvable. A second copy cannot be a
/// sheet over a sheet, because a window presents one sheet at a time (§269).
/// So the sheet is chrome now, and the authorization guide embeds this.
struct AgentSignInPanel: View {
    enum Context {
        /// The account page's sign-in dialog: nothing else is on screen.
        case login
        /// Inside the authorization guide, where the point is to *watch* the
        /// other session while that guide opens panes in it.
        case authorization
    }

    @StateObject private var controller: AccountLoginController
    @ObservedObject private var model: AppModel
    @State private var repairAttempted = false
    private let account: AgentAccount
    private let context: Context
    private let onClose: () -> Void

    init(account: AgentAccount, model: AppModel,
         context: Context = .login, onClose: @escaping () -> Void) {
        self.account = account
        self.context = context
        self.onClose = onClose
        _model = ObservedObject(wrappedValue: model)
        _controller = StateObject(wrappedValue: AccountLoginController(account: account, model: model))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(format: NSLocalizedString("Sign in as %@ without switching your main desktop.", comment: ""), account.username))
                .font(.callout)
            Text("macOS Screen Sharing handles the password. AgentSpace does not read or save it.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            switch controller.phase {
            case .idle:
                instructions
            case .starting:
                ProgressView("Opening macOS sign-in…")
            case .sharingDisabled:
                Text("Enable Screen Sharing in System Settings → General → Sharing. Choose Only these users and add the agent account, then try again.")
                    .fixedSize(horizontal: false, vertical: true)
            case .waiting:
                instructions
                ProgressView(waitingLabel)
                    .fixedSize(horizontal: false, vertical: true)
            case .finishing:
                ProgressView("Preparing the agent worker…")
            case .connected:
                Label("The agent desktop is connected.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(connectedHint)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed(let message):
                if controller.isRepairingHelper {
                    ProgressView("Reinstalling…")
                } else {
                    Text(message).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
            if repairAttempted, controller.needsHelperRepair {
                HelperFailureBanner().environmentObject(model)
            }
            Text(footnote)
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if showsClose {
                    Button(closeLabel, action: onClose)
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                if controller.needsHelperRepair {
                    Button {
                        repairAttempted = true
                        controller.repairHelper()
                    } label: {
                        if controller.isRepairingHelper {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Reinstalling…") }
                        } else {
                            Text("Reinstall Helper…")
                        }
                    }
                    .disabled(controller.isRepairingHelper || model.isInstallingHelper)
                    .accessibilityIdentifier("signInReinstallHelperButton")
                }
                if canStart {
                    Button("Open macOS Sign-In") { controller.start() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("openAgentSystemSignIn")
                }
            }
        }
        .onDisappear { controller.stop() }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: NSLocalizedString("In the system window, enter %@ and that account's password.", comment: ""), account.username))
            Text("If asked, choose Log In to your own desktop. Choose Standard screen sharing. Finish any first-login setup in that window.")
            Text("If the agent desktop is locked, unlock that account in the system window. Unlocking your main account does not unlock the agent desktop.")
            Text("AgentSpace will detect the desktop and start the worker automatically.")
        }
        .font(.callout).fixedSize(horizontal: false, vertical: true)
    }

    /// One spinner used to mean four different waits, and the person at the
    /// keyboard could not tell "macOS has not finished" from "you still have to
    /// unlock it". The label now says which, from the same poll that decides it.
    private var waitingLabel: String {
        switch controller.wait {
        case .some(.probeFailed):
            return NSLocalizedString("AgentSpace could not confirm the agent account's desktop session. Retrying…", comment: "")
        case .some(.noSession):
            return NSLocalizedString("Waiting for macOS to sign in to the agent account…", comment: "")
        case .some(.workerOffline):
            return NSLocalizedString("Signed in. Starting the agent Worker…", comment: "")
        case .some(.desktopLocked):
            return NSLocalizedString("Signed in. The agent desktop is still locked — unlock it in the system window.", comment: "")
        case .some(.desktopNotReady):
            return NSLocalizedString("Signed in. Waiting for the agent desktop to finish starting…", comment: "")
        case nil:
            return NSLocalizedString("Waiting for the agent desktop…", comment: "")
        }
    }

    /// The sheet's connected step ends the visit; the guide's is the middle of
    /// it, and closing the window there would close the transport with it.
    private var connectedHint: String {
        context == .login
            ? NSLocalizedString("Close the temporary Screen Sharing window, then click Done. You can use Open Desktop and the permission buttons in AgentSpace.", comment: "")
            : NSLocalizedString("Keep that window on screen and this guide open. Every pane this guide opens appears inside it — approve there and the tick lands here.", comment: "")
    }

    private var footnote: String {
        context == .login
            ? NSLocalizedString("Closing this dialog ends only the temporary login connection. It does not log out the agent account.", comment: "")
            : NSLocalizedString("Closing this guide ends only the temporary view of that session. The agent account stays signed in.", comment: "")
    }

    /// Once the desktop is connected inside the guide, the panel has done its
    /// job and staying up is the point: the Screen Sharing path lives as long
    /// as this view does. The sheet keeps its Done button in that state.
    private var showsClose: Bool {
        if context == .login { return true }
        return controller.phase != .connected
    }

    private var closeLabel: String {
        if context == .login {
            return controller.phase == .connected
                ? NSLocalizedString("Done", comment: "")
                : NSLocalizedString("Cancel", comment: "")
        }
        return NSLocalizedString("Hide sign-in", comment: "")
    }

    private var canStart: Bool {
        switch controller.phase {
        case .idle, .sharingDisabled: return true
        case .failed: return !controller.needsHelperRepair
        default: return false
        }
    }
}
