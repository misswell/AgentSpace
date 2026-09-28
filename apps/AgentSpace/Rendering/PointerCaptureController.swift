import AppKit
import AgentSpaceCore

/// The pointer half of a remote surface's state.
///
/// A thin instrument on top of Core's `PointerCaptureController`, because the
/// only things that differ per host are which events count and what happens when
/// capture starts or stops. All the state logic lives in Core so the desktop
/// viewer and a Fusion proxy cannot drift apart, and so the transitions are
/// testable without a window.
@MainActor
final class PointerCaptureCoordinator {
    private(set) var state: PointerCaptureState = .outside
    /// The frame the remote image occupies in the view, in view coordinates.
    /// Updated on layout and on every event, because that is the only thing that
    /// decides whether the hand is over the picture or over the letterbox.
    var imageRect: CGRect = .zero

    /// Called when capture begins: the surface should hide the local cursor and
    /// tell the worker a person has taken control.
    var onCaptureBegan: (() -> Void)?
    /// Called when capture ends: restore the cursor and release the lease.
    var onCaptureEnded: (() -> Void)?
    /// Whether the local cursor is currently hidden by this surface.
    private(set) var isHidingLocalCursor = false

    private var controller = PointerCaptureController()
    private var idleTimer: Timer?
    var canSettlePointer: (() -> Bool)?
    var onPointerSettled: ((CGPoint) -> Void)?

    /// Which profile applies to this surface.
    func configure(_ policy: PointerCapturePolicy) {
        if controller.policy != policy { cancelIdle() }
        controller.apply(policy)
        state = controller.state
        sync()
    }

    /// The pointer entered or left the *image*. `point` is in the view's own
    /// coordinate space.
    func pointer(movedTo point: CGPoint) {
        cancelIdle()
        let inside = imageRect.width >= 1 && imageRect.height >= 1 && imageRect.contains(point)
        let previous = state
        state = controller.pointer(inside: inside)
        if previous != state { sync() }
        if inside, controller.policy.entry == .captureOnIdle, !controller.isPressHeld {
            idleTimer = Timer.scheduledTimer(withTimeInterval: PointerCapturePolicy.idleDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.idleTimer = nil
                    guard self.imageRect.contains(point), self.canSettlePointer?() == true else { return }
                    self.controller.pointerSettled()
                    self.state = self.controller.state
                    self.sync()
                    if self.isControlling { self.onPointerSettled?(point) }
                }
            }
        }
    }

    private func cancelIdle() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    func pressStarted() {
        cancelIdle()
        let previous = state
        controller.pressStarted()
        state = controller.state
        if previous != state { sync() }
    }

    func pressEnded(pointerInside: Bool) {
        cancelIdle()
        let previous = state
        state = controller.pressEnded(pointerInside: pointerInside)
        if previous != state { sync() }
    }

    /// The pointer left the *view* entirely: capture is over whatever the image
    /// rect says, and a held button does not keep a window the person's hand has
    /// left.
    func pointerLeftView() {
        cancelIdle()
        guard state != .outside else { return }
        state = controller.pointer(inside: false)
        sync()
    }

    /// Escape released the capture without the pointer moving anywhere.
    func escape() {
        cancelIdle()
        controller.escapeToHovering()
        state = controller.state
        sync()
    }

    /// Every path out of capture — window closed, worker offline, session became
    /// the console, input revoked — comes through here, so the local cursor
    /// cannot be left hidden by a route that forgot to restore it.
    func release() {
        cancelIdle()
        controller.releaseAll()
        state = .outside
        sync()
    }

    var waitsForIdle: Bool { controller.policy.entry == .captureOnIdle }

    var isControlling: Bool { state == .controlling }

    private func sync() {
        let shouldHide = state.hidesLocalCursor
        guard shouldHide != isHidingLocalCursor else { return }
        isHidingLocalCursor = shouldHide
        if shouldHide { onCaptureBegan?() } else { onCaptureEnded?() }
    }

    /// The rect to claim with a transparent cursor, in the view's coordinate
    /// space, or nil when the pointer must stay visible.
    var cursorRect: CGRect? {
        guard isHidingLocalCursor, imageRect.width >= 1, imageRect.height >= 1 else { return nil }
        return imageRect
    }
}
