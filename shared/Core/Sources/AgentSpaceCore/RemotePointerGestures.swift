import CoreGraphics
import Foundation

/// What a hand did over a picture of another session, expressed as a position
/// within that picture: `u` and `v` are 0…1 across the image, `v` from its top
/// edge.
///
/// Fractions are the unit because the two hosts need different ones and both can
/// be derived from them losslessly: a Fusion proxy puts them straight on the wire
/// (`xFraction`/`yFraction`), and the desktop viewer multiplies them out to the
/// display points `input` accepts through `PreviewMapping`.
public enum RemotePointerGesture: Equatable, Sendable {
    /// Pointer travel with no button held.
    case hover(u: Double, v: Double)
    case click(u: Double, v: Double, button: MouseButton, count: Int, modifiers: [Modifier])
    case drag(fromU: Double, fromV: Double, toU: Double, toV: Double,
              button: MouseButton, modifiers: [Modifier])
    /// Live drag phases. The first two are emitted while the local button is
    /// still down; the final phase is emitted on release.
    ///
    /// `clickCount` carries `NSEvent.clickCount` through to the remote press:
    /// the window server decides a double-click from the second press's own
    /// click state, so two presses sent as two unrelated single clicks are two
    /// single clicks however fast they arrive.
    case pointerDown(u: Double, v: Double, button: MouseButton, clickCount: Int, modifiers: [Modifier])
    case pointerDrag(fromU: Double, fromV: Double, toU: Double, toV: Double,
                     button: MouseButton, modifiers: [Modifier])
    case pointerUp(u: Double, v: Double, button: MouseButton, clickCount: Int, modifiers: [Modifier])
    /// Whole lines scrolled; the fractional remainder is kept by the tracker.
    ///
    /// The axes keep AppKit's own signs and order — `linesX` is
    /// `scrollingDeltaX` rounded into lines and `linesY` is `scrollingDeltaY`.
    /// Neither surface flips them, because the worker already knows which way a
    /// positive delta scrolls.
    case scroll(u: Double, v: Double, linesX: Int, linesY: Int)
}

/// The pointer state machine every remote surface shares.
///
/// It exists because the two surfaces answer the same three questions and were
/// answering them differently: a Fusion proxy knew that a press which travelled
/// is a drag, that a fractional trackpad delta still means a line eventually, and
/// that a cursor merely crossing a remote picture is not a person taking control.
/// The desktop viewer knew none of them, so it could not select text, could not
/// drag a slider, and could not hover at all.
///
/// Nothing here touches a window or an event: geometry arrives as a
/// `PreviewMapping` and time as a `Date`, so the whole machine is testable without
/// a screen, and both surfaces are guaranteed to mean the same thing by a press
/// that moved four pixels.
public struct RemotePointerGestureTracker {
    /// A press and a release this far apart, in view points, are a drag and not a
    /// click. Below it the hand was aiming at one place.
    public static let dragThreshold: CGFloat = 3
    /// The worker's human-lease length, mirrored here so a surface knows how long
    /// pointer travel stays meaningful after a deliberate action. The lease itself
    /// is the worker's to grant and to enforce; this only decides what is worth
    /// asking for.
    public static let humanLeaseSeconds: TimeInterval = 5
    /// A held button renews the lease before the five seconds it bought run out,
    /// so a long drag stays the agent's pause rather than its resume.
    public static let leaseRenewalSeconds: TimeInterval = 2

    private struct Press {
        var viewOrigin: CGPoint
        var u: Double
        var v: Double
        var lastU: Double
        var lastV: Double
        var button: MouseButton
        var clickCount: Int
        var modifiers: [Modifier]
        var travelled = false
        var streamStarted = false
        /// A travel phase went out, not just the down. A click that never moved
        /// must not gain a synthetic drag from its own release position.
        var travelStreamed = false
    }

    private var press: Press?
    private var engagedUntil: Date?
    private var lastRenewal = Date.distantPast
    /// Set while a surface has taken the pointer through capture rather than
    /// through a gesture — Desktop Mode, where entering the picture *is*
    /// taking control. `nil` means the old rule applies: travel reaches the
    /// agent only inside a live lease.
    ///
    /// The two are different questions and this is why the field is separate
    /// from `engagedUntil`: a lease expires on a clock, while control lasts
    /// exactly as long as the pointer is over the picture. Expressing the
    /// second as a far-future lease would leave a stale one behind after the
    /// pointer left, which is a five-second pause on automation nobody asked
    /// for — the opposite of what leaving is supposed to mean.
    private var controlling = false
    /// Raw pointer phases: every press goes to the agent as a press, as soon as
    /// it happens, instead of waiting to learn whether it was a click.
    private var rawPhases = false
    /// Trackpad deltas arrive as fractions (0.1, 0.4 …). The wire carries whole
    /// lines, so rounding each event on its own turned slow scrolling to zero.
    private var scrollCarryX = 0.0
    private var scrollCarryY = 0.0

    public init() {}

    public func isEngaged(at now: Date) -> Bool {
        if controlling { return true }
        guard let engagedUntil else { return false }
        return now < engagedUntil
    }

    public var isControlling: Bool { controlling }
    public var isRaw: Bool { rawPhases }

    /// The pointer entered a surface that captures on entry. Travel now reaches
    /// the agent, and every press is sent as a press.
    ///
    /// Deliberately does *not* take the human lease: that is the worker's to
    /// grant, and a surface asks for it over the fast channel where the answer
    /// is immediate. Calling this twice is harmless.
    public mutating func beginControl(rawPhases: Bool = true) {
        controlling = true
        self.rawPhases = rawPhases
    }

    /// The pointer left, or the surface stopped being an input target.
    public mutating func endControl() {
        controlling = false
        rawPhases = false
    }

    /// A deliberate action that is not a pointer gesture — typing into a proxy —
    /// keeps pointer travel meaningful for one lease length. It takes no lease: a
    /// keystroke is not a person holding the mouse.
    public mutating func noteEngagement(now: Date) {
        engagedUntil = now.addingTimeInterval(Self.humanLeaseSeconds)
    }

    /// Forget the gesture in progress and the engagement. Used when the surface
    /// stops being an input target, so a press or a position collected for it
    /// cannot be posted afterwards.
    public mutating func reset() {
        press = nil
        engagedUntil = nil
        lastRenewal = Date.distantPast
        controlling = false
        rawPhases = false
        scrollCarryX = 0
        scrollCarryY = 0
    }

    /// A disappearing surface must not leave the agent's button held down.
    public mutating func cancelPress() -> RemotePointerGesture? {
        defer { press = nil }
        guard let press, press.streamStarted || rawPhases else { return nil }
        return .pointerUp(u: press.lastU, v: press.lastV, button: press.button,
                          clickCount: press.clickCount, modifiers: press.modifiers)
    }

    /// Pointer travel.
    ///
    /// Crossing a remote surface is the main user moving their own cursor over a
    /// *picture* of another session. Forwarding it would activate that app in the
    /// agent's session and move its pointer, so hovering there would interrupt
    /// whatever the agent is doing. Only a person who is already in control
    /// expects the remote pointer to follow their hand — and "in control" is
    /// either a live lease (the proxy rule) or capture (Desktop Mode, where the
    /// picture *is* the screen being operated).
    public mutating func pointerMoved(to point: CGPoint, in surface: PreviewMapping,
                                      now: Date) -> RemotePointerGesture? {
        guard isEngaged(at: now) else { return nil }
        guard let f = surface.fraction(appKitX: Double(point.x), appKitY: Double(point.y)) else { return nil }
        return .hover(u: f.u, v: f.v)
    }

    /// A press arriving in raw mode is sent the moment it happens, whatever it
    /// turns out to be.
    public var sendsPressesImmediately: Bool { rawPhases }

    /// The button came down. Returns whether this press should take the worker's
    /// human lease.
    ///
    /// The pause on automation starts here rather than when the gesture is finally
    /// posted, because the person has already committed to this surface.
    public mutating func beganPress(at point: CGPoint, button: MouseButton, modifiers: [Modifier],
                                    in surface: PreviewMapping, now: Date,
                                    clickCount: Int = 1) -> Bool {
        guard let f = surface.fraction(appKitX: Double(point.x), appKitY: Double(point.y)) else {
            press = nil
            return false
        }
        press = Press(viewOrigin: point, u: f.u, v: f.v, lastU: f.u, lastV: f.v,
                      button: button, clickCount: max(1, clickCount), modifiers: modifiers)
        engagedUntil = now.addingTimeInterval(Self.humanLeaseSeconds)
        lastRenewal = now
        return true
    }

    /// The button came down, and every phase that follows it is reported as it
    /// happens.
    ///
    /// This is the model a remote desktop needs, and it is the one RustDesk uses:
    /// `MOUSE_DOWN` is sent when the local button goes down, not when the gesture
    /// has been classified. The old shape — record the press, wait for three
    /// points of travel, then decide between a click and a drag — is right for a
    /// proxy that has to keep a person's ordinary click working and wrong for a
    /// window the person is trying to *drag*, because it makes the title bar
    /// respond only after the hand has already moved.
    ///
    /// A press that never moves is therefore sent as down + up rather than as a
    /// click, which is exactly what the window server does with a real mouse:
    /// click-ness is decided remotely, by the app that receives both events.
    ///
    /// Returns the gesture to post, or `nil` when the press landed in the
    /// letterbox and belongs to nobody.
    public mutating func beganPressPhases(at point: CGPoint, button: MouseButton, clickCount: Int,
                                          modifiers: [Modifier], in surface: PreviewMapping,
                                          now: Date) -> RemotePointerGesture? {
        guard beganPress(at: point, button: button, modifiers: modifiers,
                         in: surface, now: now, clickCount: clickCount) else { return nil }
        guard rawPhases, var press else { return nil }
        // This press has already reached the remote session. Capture or cursor
        // availability can change before mouse-up; its release must remain an
        // up, never turn into a second complete click.
        press.streamStarted = true
        self.press = press
        return .pointerDown(u: press.u, v: press.v, button: press.button,
                            clickCount: press.clickCount, modifiers: press.modifiers)
    }

    /// Travel while the button is held. Remembers that the press went past the
    /// drag threshold, and reports whether the lease is due a renewal.
    public mutating func dragged(to point: CGPoint, now: Date) -> Bool {
        guard var press else { return false }
        if !press.travelled,
           hypot(point.x - press.viewOrigin.x, point.y - press.viewOrigin.y) > Self.dragThreshold {
            press.travelled = true
        }
        self.press = press
        engagedUntil = now.addingTimeInterval(Self.humanLeaseSeconds)
        guard now.timeIntervalSince(lastRenewal) >= Self.leaseRenewalSeconds else { return false }
        lastRenewal = now
        return true
    }

    /// Every phase of a live drag, in order.
    ///
    /// In raw mode the press was already sent, so this emits only the travel —
    /// including the first few points, which the threshold-based path deliberately
    /// swallowed. A drag that has to clear three points before the remote window
    /// hears anything is a title bar that starts moving late by exactly the
    /// distance the hand covered first.
    public mutating func draggedPhases(to point: CGPoint, in surface: PreviewMapping,
                                       now: Date) -> (renewLease: Bool, gestures: [RemotePointerGesture]) {
        let renewLease = dragged(to: point, now: now)
        guard var press,
              let fraction = surface.fractionClamped(appKitX: Double(point.x), appKitY: Double(point.y)) else {
            return (renewLease, [])
        }
        if rawPhases {
            // The NSView also calls this on mouse-up to capture a final position.
            // If the pointer did not move, a drag event here turns a click on a
            // macOS window button into a drag gesture: the button highlights on
            // down but does not close/minimise on up.
            guard fraction.u != press.lastU || fraction.v != press.lastV else {
                return (renewLease, [])
            }
            let move = RemotePointerGesture.pointerDrag(
                fromU: press.lastU, fromV: press.lastV, toU: fraction.u, toV: fraction.v,
                button: press.button, modifiers: press.modifiers)
            press.lastU = fraction.u
            press.lastV = fraction.v
            press.streamStarted = true
            press.travelStreamed = true
            self.press = press
            return (renewLease, [move])
        }
        guard press.travelled else { return (renewLease, []) }
        let move = RemotePointerGesture.pointerDrag(
            fromU: press.lastU, fromV: press.lastV, toU: fraction.u, toV: fraction.v,
            button: press.button, modifiers: press.modifiers)
        press.lastU = fraction.u
        press.lastV = fraction.v
        press.travelStreamed = true
        if press.streamStarted {
            self.press = press
            return (renewLease, [move])
        }
        press.streamStarted = true
        self.press = press
        return (renewLease, [
            .pointerDown(u: press.u, v: press.v, button: press.button,
                         clickCount: press.clickCount, modifiers: press.modifiers),
            move,
        ])
    }

    /// The release may be one point away from the press without any drag event
    /// having occurred. Keep that ordinary click as down+up; once an actual
    /// drag began, preserve its final position before sending the release.
    public mutating func releaseTravelPhases(to point: CGPoint, in surface: PreviewMapping,
                                             now: Date) -> (renewLease: Bool, gestures: [RemotePointerGesture]) {
        if rawPhases, let press, !press.travelStreamed,
           hypot(point.x - press.viewOrigin.x, point.y - press.viewOrigin.y) <= Self.dragThreshold {
            return (false, [])
        }
        return draggedPhases(to: point, in: surface, now: now)
    }

    /// Events to send before the local button comes up. Starting only after
    /// the click/drag threshold preserves ordinary clicks, while the first
    /// crossed point sends down + drag immediately instead of replaying the
    /// entire path after release.
    ///
    /// Kept beside `draggedPhases` because the two are different models rather
    /// than two spellings of one: this is the threshold model a proxy uses when
    /// it has not taken raw control, and the tests that pin it are the reason the
    /// old behaviour cannot come back by accident.
    public mutating func dragged(to point: CGPoint, in surface: PreviewMapping,
                                 now: Date) -> (renewLease: Bool, gestures: [RemotePointerGesture]) {
        draggedPhases(to: point, in: surface, now: now)
    }

    /// The button came up: the press resolves into a click or a drag here, because
    /// only now is it known whether it travelled.
    public mutating func endedPress(at point: CGPoint, clickCount: Int,
                                    in surface: PreviewMapping, now: Date) -> RemotePointerGesture? {
        defer { press = nil }
        guard let press else {
            // Nothing here owns the release: it belongs to a press that landed
            // outside the remote image.
            return nil
        }
        engagedUntil = now.addingTimeInterval(Self.humanLeaseSeconds)
        if rawPhases {
            // The press already went out; the release is its other half. Landing
            // outside the picture is pulled back onto it, because the travelled
            // path started inside and dropping the release would leave the remote
            // app's button held down.
            guard let to = surface.fractionClamped(appKitX: Double(point.x), appKitY: Double(point.y)) else { return nil }
            return .pointerUp(u: to.u, v: to.v, button: press.button,
                              clickCount: max(press.clickCount, clickCount), modifiers: press.modifiers)
        }
        if press.streamStarted {
            guard let to = surface.fractionClamped(appKitX: Double(point.x), appKitY: Double(point.y)) else { return nil }
            return .pointerUp(u: to.u, v: to.v, button: press.button,
                              clickCount: press.clickCount, modifiers: press.modifiers)
        }
        if press.travelled {
            // A release that drifted past the image edge is pulled back onto it:
            // the travelled path still started inside the window, and dropping the
            // release would leave the remote app's button held down.
            guard let to = surface.fractionClamped(appKitX: Double(point.x), appKitY: Double(point.y)) else { return nil }
            return .drag(fromU: press.u, fromV: press.v, toU: to.u, toV: to.v,
                         button: press.button, modifiers: press.modifiers)
        }
        return .click(u: press.u, v: press.v, button: press.button,
                      count: max(1, clickCount), modifiers: press.modifiers)
    }

    /// A scroll event, whole lines and all. `nil` while the accumulated motion is
    /// still less than one line, which is what makes a slow two-finger slide
    /// scroll one line rather than nothing.
    public mutating func scrolled(deltaX: Double, deltaY: Double, at point: CGPoint,
                                  in surface: PreviewMapping, now: Date) -> RemotePointerGesture? {
        guard let f = surface.fraction(appKitX: Double(point.x), appKitY: Double(point.y)) else { return nil }
        scrollCarryX += deltaX
        scrollCarryY += deltaY
        let linesX = Int(scrollCarryX)
        let linesY = Int(scrollCarryY)
        guard linesX != 0 || linesY != 0 else { return nil }
        scrollCarryX -= Double(linesX)
        scrollCarryY -= Double(linesY)
        engagedUntil = now.addingTimeInterval(Self.humanLeaseSeconds)
        return .scroll(u: f.u, v: f.v, linesX: linesX, linesY: linesY)
    }
}
