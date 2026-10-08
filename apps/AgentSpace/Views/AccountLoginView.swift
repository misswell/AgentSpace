import SwiftUI
import AgentSpaceCore

struct AccountLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller: AccountLoginController
    private let account: AgentAccount

    init(account: AgentAccount, model: AppModel) {
        self.account = account
        _controller = StateObject(wrappedValue: AccountLoginController(account: account, model: model))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sign In Agent").font(.title2.bold())
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
                ProgressView("Waiting for the agent desktop…")
            case .finishing:
                ProgressView("Preparing the agent worker…")
            case .connected:
                Label("The agent desktop is connected.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Close the temporary Screen Sharing window, then click Done. You can use Open Desktop and the permission buttons in AgentSpace.")
                    .fixedSize(horizontal: false, vertical: true)
            case .failed(let message):
                Text(message).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Text("Closing this dialog ends only the temporary login connection. It does not log out the agent account.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(controller.phase == .connected ? "Done" : "Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if canStart {
                    Button("Open macOS Sign-In") { controller.start() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("openAgentSystemSignIn")
                }
            }
        }
        .padding(24).frame(width: 480)
        .onDisappear { controller.stop() }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: NSLocalizedString("In the system window, enter %@ and that account's password.", comment: ""), account.username))
            Text("If asked, choose Log In to your own desktop. Choose Standard screen sharing. Finish any first-login setup in that window.")
            Text("AgentSpace will detect the desktop and start the worker automatically.")
        }
        .font(.callout).fixedSize(horizontal: false, vertical: true)
    }

    private var canStart: Bool {
        switch controller.phase {
        case .idle, .sharingDisabled, .failed: return true
        default: return false
        }
    }
}
