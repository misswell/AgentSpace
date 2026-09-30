import AppKit
import SwiftUI
import AgentSpaceCore

struct FusionWindowView: View {
    @ObservedObject var state: FusionWindowState
    @ObservedObject var input: RemoteViewerInput
    @AppStorage(MouseCaptureMode.storageKey) private var captureMode = MouseCaptureMode.default.rawValue
    let send: (RemotePointerGesture) -> Void
    let claimHuman: () -> Void
    let releaseHuman: () -> Void
    let overlay: RemoteCursorOverlayProxy
    /// A press started or ended, straight from the surface, so the stream rate
    /// follows the button rather than the gesture threshold.
    var onDragActivity: ((Bool) -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let client = state.frameClient {
                RemoteSurfaceView(client: client, captureFollowsLayout: false,
                    acceptsInput: true, remoteContentSize: state.contentSize,
                    capturePolicy: (MouseCaptureMode.parse(captureMode) ?? .default).policy(for: .fusion),
                    hidesLocalCursor: input.cursorChannelActive
                        && (MouseCaptureMode.parse(captureMode) ?? .default).hidesLocalCursor,
                    onGesture: send, onClaimHuman: claimHuman, onReleaseHuman: releaseHuman,
                    sendsRawPresses: true, cursorOverlay: overlay, onDragActivity: onDragActivity)
                    .background(Color.black)
                VStack { HStack { FrameClientStatusOverlay(client: client); Spacer() }; Spacer() }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black)
            }
            if let refusal = input.refusal {
                VStack(alignment: .leading, spacing: 6) {
                    Text(refusal.code).font(.headline)
                    Text(refusal.message).font(.caption)
                }
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(12)
            } else if let error = state.error {
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
