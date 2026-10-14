import SwiftUI
import AgentSpaceCore

/// The account page's sign-in dialog: the window chrome around
/// `AgentSignInPanel`, kept separate so the guide can show the same flow inline.
struct AccountLoginView: View {
    @Environment(\.dismiss) private var dismiss
    private let account: AgentAccount
    private let model: AppModel

    init(account: AgentAccount, model: AppModel) {
        self.account = account
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sign In or Unlock Agent").font(.title2.bold())
            AgentSignInPanel(account: account, model: model) { dismiss() }
        }
        .padding(24).frame(width: 480)
    }
}
