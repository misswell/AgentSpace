import AppKit
import AgentSpaceCore
import SwiftUI

/// The bridge between SwiftUI's view state and the AppKit layer that draws the
/// agent's cursor.
///
/// A `RemoteSurfaceView` is an `NSViewRepresentable`: SwiftUI may build a new
/// host view at any time, while the cursor position arrives on the observer that
/// lives with the *view*. Something has to hold the two ends together without
/// either of them owning the other, and this is that holder — the surface hands
/// it the layer it built, and the view hands it the positions the worker
/// published.
///
/// It also owns the one decision that must not be made in two places: whether the
/// drawn cursor is *live* enough to be the only one on screen. While the worker
/// is publishing positions the overlay is the cursor and the capture's own
/// painted cursor is redundant; if the channel drops, the overlay is cleared and
/// the picture's cursor becomes the only one again. Neither state ever shows two.
@MainActor
final class RemoteCursorOverlayProxy: ObservableObject {
    /// The layer the surface built, or nil while no surface is on screen.
    private weak var layer: RemoteCursorOverlayLayer?
    /// Whether this proxy is currently the source of the drawn pointer.
    ///
    /// Settable by the host as well as by `apply`, because the host is what
    /// decides whether the *channel* is live — and the overlay must not draw a
    /// frozen position for a channel that has gone away.
    var isDrawingCursor = false
    
    func attach(_ layer: RemoteCursorOverlayLayer?) {
        self.layer = layer
        if layer == nil { isDrawingCursor = false }
    }

    func apply(_ presentation: InputClient.CursorPresentation?) {
        guard let layer else { return }
        guard let presentation else {
            layer.clear()
            isDrawingCursor = false
            return
        }
        layer.apply(presentation)
        isDrawingCursor = true
    }

    /// The channel went away. The overlay must stop drawing rather than freeze
    /// on a last known position: a pointer that does not move while the desktop
    /// does is worse than the frame-baked one it replaced.
    func detach() {
        layer?.clear()
        isDrawingCursor = false
    }
}
