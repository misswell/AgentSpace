import CoreGraphics
import Foundation

/// Whether a remote surface is under the hand, and what that means.
///
/// The desktop viewer used to require a *click* before pointer travel would
/// reach the agent: a cursor crossing a picture of somebody else's desktop must
/// not move that desktop's pointer, so `RemotePointerGestureTracker` forwarded
/// hover only inside a live lease. That rule is right for a proxy sitting among
/// a person's own windows, and wrong for Desktop Mode, where the whole point is
/// to operate the agent's desktop as if it were one's own — Parallels and
/// RustDesk both hand the pointer over the moment it enters the remote canvas.
///
/// The difference is not "which app" but "how much of the screen is the remote":
/// full Desktop Mode is an exclusive picture, so entering it is taking control;
/// a Fusion proxy is a *window*, and its title bar and its neighbours belong to
/// the human. So the policy is a value with two profiles, and the surface that
/// hosts it decides which one applies.
public struct PointerCapturePolicy: Equatable, Sendable {
    /// What entering the remote image does.
    public enum EntryBehavior: Equatable, Sendable {
        /// Entering is taking control: local cursor hides, travel forwards, the
        /// human lease is acquired explicitly. Desktop Mode.
        case captureOnEntry
        /// Entering does nothing; a press is what takes control. Fusion proxies,
        /// where the surface shares the screen with the person's own work.
        case captureOnPress
        /// Never capture. Used by a surface that is only being watched — the
        /// viewer of an account whose worker refuses input.
        case disabled
    }

    public var entry: EntryBehavior
    /// Whether the pointer must be inside the remote image for the local cursor
    /// to stay hidden. Always true in this product: hiding a cursor the person
    /// has moved off the picture would leave them with no pointer.
    public var requireImageContainment: Bool
    /// Whether leaving the image releases the lease immediately. True when the
    /// lease was taken by entry; a press-held gesture releases on mouse-up.
    public var releasesOnExit: Bool

    public init(entry: EntryBehavior, requireImageContainment: Bool = true, releasesOnExit: Bool = true) {
        self.entry = entry
        self.requireImageContainment = requireImageContainment
        self.releasesOnExit = releasesOnExit
    }

    /// Full Desktop Mode: entering the agent's desktop is taking the pointer.
    public static let desktop = PointerCapturePolicy(entry: .captureOnEntry)

    /// A Fusion proxy: the person's own windows surround this one, so only a
    /// deliberate press takes control — the §298 rule, kept.
    public static let fusionProxy = PointerCapturePolicy(entry: .captureOnPress, releasesOnExit: false)

    /// Watching, not driving.
    public static let watchOnly = PointerCapturePolicy(entry: .disabled)
}

/// The three states the pointer can be in over a remote surface.
///
/// Kept as a value with `contains` rather than a flag so a surface can ask the
/// one question that decides whether the local cursor hides, and the answer has
/// exactly one spelling.
public enum PointerCaptureState: Equatable, Sendable {
    /// The pointer is outside the remote image — letterbox bars included.
    case outside
    /// Inside the remote image, but not controlling it (a proxy without a
    /// press, or Desktop Mode with capture off).
    case hovering
    /// This surface owns the pointer: the local cursor is hidden and travel is
    /// being forwarded.
    case controlling

    /// Whether the *local* cursor must be invisible while state holds.
    public var hidesLocalCursor: Bool { self == .controlling }

    /// Whether pointer travel should be forwarded to the agent.
    public var forwardsTravel: Bool { self == .controlling }

    /// Whether a live gesture may continue past the image's edge. Once a press
    /// has been captured, dragging a slider to the edge of the picture must not
    /// drop the button.
    public var holdsGesture: Bool { self == .controlling }
}

/// The state machine a surface drives. Nothing here touches a window or an
/// event: geometry arrives as a `PreviewMapping` and time as a `Date`, so both
/// hosts of a remote surface are guaranteed the same behaviour by a test that
/// needs no screen — the same shape, and for the same reason, as
/// `RemotePointerGestureTracker`.
public struct PointerCaptureController {
    public private(set) var state: PointerCaptureState = .outside
    public private(set) var policy: PointerCapturePolicy = .watchOnly
    /// The button is held, so leaving the image must not release capture.
    private var pressHeld = false
    /// A capture taken by entry, so that leaving restores it and a press inside
    /// does not have to re-take something already held.
    private var capturedByEntry = false

    public init() {}

    /// Tell the controller which profile applies. A change of policy that ends
    /// capture reports the transition so the caller can restore the cursor.
    public mutating func apply(_ policy: PointerCapturePolicy) {
        guard policy != self.policy else { return }
        self.policy = policy
        if policy.entry == .disabled { releaseAll() }
    }

    /// The pointer arrived at or left the remote image. `inside` is the
    /// *image*-containment answer, not the view's bounds: the letterbox bars of
    /// a differently-shaped window are the person's own desktop, and moving
    /// through them must not drive the agent.
    ///
    /// Returns the new state so a caller can act on the transition exactly once.
    public mutating func pointer(inside: Bool) -> PointerCaptureState {
        guard policy.entry != .disabled else { return state }
        switch policy.entry {
        case .captureOnEntry:
            if inside {
                state = .controlling
                capturedByEntry = true
            } else if !pressHeld {
                // Leaving releases — unless a gesture is in progress, which is
                // exactly when a hand expects the button to stay down.
                state = .outside
                capturedByEntry = false
            }
        case .captureOnPress:
            if inside {
                if state != .controlling { state = .hovering }
            } else if !pressHeld {
                state = .outside
            }
        case .disabled:
            break
        }
        return state
    }

    /// The button came down inside the image. A press takes control in every
    /// non-disabled profile: it is the most deliberate thing a hand can do.
    public mutating func pressStarted() {
        guard policy.entry != .disabled else { return }
        pressHeld = true
        state = .controlling
    }

    /// The button came up. Capture survives it only if the pointer is still
    /// inside and the profile captured on entry.
    public mutating func pressEnded(pointerInside: Bool) -> PointerCaptureState {
        pressHeld = false
        switch policy.entry {
        case .captureOnEntry:
            state = pointerInside ? .controlling : .outside
            capturedByEntry = pointerInside
        case .captureOnPress, .disabled:
            state = pointerInside ? .hovering : .outside
        }
        return state
    }

    /// The surface stopped being an input target, or its window closed. Every
    /// way out of capture goes through this, so the local cursor cannot be left
    /// hidden by a path that forgot to restore it.
    public mutating func releaseAll() {
        state = .outside
        pressHeld = false
        capturedByEntry = false
    }

    /// An escape gesture — Control-Option, or Control-Command-G — released the
    /// capture while the pointer is still over the picture.
    public mutating func escapeToHovering() {
        state = policy.entry == .disabled ? .outside : .hovering
        capturedByEntry = false
    }

    public var isControlling: Bool { state == .controlling }
    public var isPressHeld: Bool { pressHeld }
}

// MARK: - Cursor rects

/// Which rectangles a surface may claim with a transparent cursor.
///
/// `NSCursor.hide()` is deliberately not used anywhere in this product: it is a
/// process-wide hide count, so any path that hides without un-hiding - a window
/// closing while the pointer is over the picture, a worker dying, a fast user
/// switch mid-gesture - leaves the person with no pointer at all anywhere on
/// their Mac. Cursor rects are scoped to a view and to the image inside it, and
/// are re-computed by AppKit whenever the pointer moves, which is what makes
/// them unable to leak. This type is the arithmetic that decides the rect; the
/// view applies it.
public enum CursorRectPolicy {
    /// The rectangle a transparent cursor covers: the remote image exactly,
    /// in view coordinates — never the letterbox bars, the header, the footer,
    /// or a Fusion title bar.
    ///
    /// A rect with no area is not a cursor rect, and AppKit would then show the
    /// view's ordinary cursor — which is the correct outcome for a picture that
    /// is not on screen at all, so `nil` is the honest answer rather than a
    /// zero-sized rect.
    public static func imageRect(state: PointerCaptureState, mapping: PreviewMapping) -> CGRect? {
        guard state.hidesLocalCursor, let rect = mapping.fittedRect else { return nil }
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        return CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}
