import AppKit
import SwiftUI
import AgentSpaceCore

struct FusionWindowView: View {
    @ObservedObject var state: FusionWindowState
    let send: (JSONValue) -> Void
    let claimHuman: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let client = state.frameClient {
                FusionSurface(client: client, send: send, claimHuman: claimHuman)
                    .background(Color.black)
                VStack { HStack { FrameClientStatusOverlay(client: client); Spacer() }; Spacer() }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black)
            }
            if let error = state.error {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error.code.rawValue).font(.headline)
                    Text(error.message).font(.caption)
                }
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(12)
            }
        }
    }
}

private struct FusionSurface: NSViewRepresentable {
    let client: FrameClient
    let send: (JSONValue) -> Void
    let claimHuman: () -> Void

    func makeNSView(context: Context) -> RemoteWindowSurface {
        let view = RemoteWindowSurface(client: client)
        configure(view)
        return view
    }

    func updateNSView(_ view: RemoteWindowSurface, context: Context) { configure(view) }

    private func configure(_ view: RemoteWindowSurface) {
        view.send = send
        view.acceptsInput = true
        view.onGesture = { gesture in send(FusionInputRouter.action(for: gesture)) }
        view.onClaimHuman = claimHuman
    }
}

/// A proxy for one remote window.
///
/// What the pointer *did* is the shared surface's decision, made the same way here
/// as in the desktop viewer: a press that travelled is a drag rather than a click,
/// a trackpad fraction becomes a line once it adds up, and travel only counts
/// while a person is in control of this proxy. What is left in this subclass is
/// the keyboard, because a proxy is the window a person types into — the desktop
/// viewer gets its keys from a window-level monitor of its own.
private final class RemoteWindowSurface: RemoteSurfaceNSView {
    var send: ((JSONValue) -> Void)?

    override func keyDown(with event: NSEvent) {
        guard acceptsInput, let action = FusionInputRouter.keyboard(event) else { return }
        // Typing is a deliberate action, so the pointer travel that follows it
        // belongs to the same person.
        noteEngagement()
        send?(action)
    }
}
