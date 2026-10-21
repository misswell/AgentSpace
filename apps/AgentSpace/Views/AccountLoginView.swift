import SwiftUI
import AgentSpaceCore

/// The account page's sign-in dialog: the window chrome around
/// `AgentSignInPanel`, kept separate so the guide can show the same flow inline.
struct AccountLoginView: View {
    @Environment(\.dismiss) private var dismiss
    private let account: AgentAccount
    private let model: AppModel
    /// True for the sign-in door: the window exists to carry the password and
    /// goes away once the desktop is up. The 「用屏幕共享打开该桌面」 door is a
    /// place to watch and approve, so the window stays until the person is
    /// done with it.
    private let closesWindowWhenConnected: Bool

    init(account: AgentAccount, model: AppModel, closesWindowWhenConnected: Bool = true) {
        self.account = account
        self.model = model
        self.closesWindowWhenConnected = closesWindowWhenConnected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sign In or Unlock Agent").font(.title2.bold())
            AgentSignInPanel(account: account, model: model,
                             closesTemporaryWindow: closesWindowWhenConnected) { dismiss() }
        }
        .padding(24).frame(width: 480)
    }
}
