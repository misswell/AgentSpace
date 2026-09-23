import AppKit
import SwiftUI
import AgentSpaceCore

struct FusionWindowView: View {
    @ObservedObject var state: FusionWindowState
    let send: (RemotePointerGesture) -> Void
    let claimHuman: () -> Void
    let releaseHuman: () -> Void
    let overlay: RemoteCursorOverlayProxy
    let sendKey: ((JSONValue) -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let client = state.frameClient {
                FusionSurface(client: client, send: send, claimHuman: claimHuman,
                              releaseHuman: releaseHuman, overlay: overlay,
                              sendKey: sendKey)
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

/// The proxy's title-bar action.
///
/// The proxy's own close button only ever dismissed this mirror; closing the
/// window being mirrored is deliberate and says so in words.
struct FusionWindowActions: View {
    let closeRemote: () -> Void

    var body: some View {
        Button(action: closeRemote) {
            Text("Close Agent Window")
        }
        .help(Text("Closes the agent's own window, not just this mirror of it."))
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("closeFusionAgentWindow")
        .padding(.horizontal, 8)
        .fixedSize()
    }
}

private struct FusionSurface: NSViewRepresentable {
    let client: FrameClient
    let send: (RemotePointerGesture) -> Void
    let claimHuman: () -> Void
    let releaseHuman: () -> Void
    let overlay: RemoteCursorOverlayProxy
    /// Keys take the RPC path on purpose: one keystroke is one event, a person
    /// types at tens per second at most, and the RPC route is the one an agent's
    /// `key` call uses — so a combo typed into a proxy is validated by exactly
    /// the same parser an agent's is.
    var sendKey: ((JSONValue) -> Void)?

    func makeNSView(context: Context) -> RemoteWindowSurface {
        let view = RemoteWindowSurface(client: client)
        configure(view)
        return view
    }

    func updateNSView(_ view: RemoteWindowSurface, context: Context) { configure(view) }

    private func configure(_ view: RemoteWindowSurface) {
        view.acceptsInput = true
        view.keySend = sendKey
        view.onGesture = send
        view.onClaimHuman = claimHuman
        view.onReleaseHuman = releaseHuman
        // A proxy captures on the press, not on entry: the person's own windows
        // surround this one, and a cursor crossing it is not a person working in
        // it. The local cursor is only hidden once the channel can draw the
        // agent's own — the picture's painted cursor is what the person sees until
        // then, and hiding the local one early would leave no pointer at all.
        let mode = MouseCaptureMode.parse(UserDefaults.standard.string(forKey: MouseCaptureMode.storageKey)) ?? .default
        view.capture.configure(mode.policy(for: .fusion))
        view.allowsLocalCursorHiding = overlay.isDrawingCursor
        overlay.attach(view.cursorOverlay)
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
    /// The keyboard, translated by the same vocabulary `agentspace input` uses.
    ///
    /// Keys still travel over the JSON RPC rather than the fast channel, and that
    /// is deliberate: a keystroke is one event, a person types at tens per
    /// second at most, and the RPC path is the one an agent's `key` call uses —
    /// so a combo typed into a proxy is validated by exactly the same parser.
    var keySend: ((JSONValue) -> Void)?

    override func keyDown(with event: NSEvent) {
        guard acceptsInput, let action = FusionInputRouter.keyboard(event) else { return }
        // Typing is a deliberate action, so the pointer travel that follows it
        // belongs to the same person.
        noteEngagement()
        keySend?(action)
    }
}
