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
        var button: MouseButton
        var modifiers: [Modifier]
        var travelled = false
    }

    private var press: Press?
    private var engagedUntil: Date?
    private var lastRenewal = Date.distantPast
    /// Trackpad deltas arrive as fractions (0.1, 0.4 …). The wire carries whole
    /// lines, so rounding each event on its own turned slow scrolling to zero.
    private var scrollCarryX = 0.0
    private var scrollCarryY = 0.0

    public init() {}

    public func isEngaged(at now: Date) -> Bool {
        guard let engagedUntil else { return false }
        return now < engagedUntil
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
        scrollCarryX = 0
        scrollCarryY = 0
    }

    /// Pointer travel.
    ///
    /// Crossing a remote surface is the main user moving their own cursor over a
    /// *picture* of another session. Forwarding it would activate that app in the
    /// agent's session and move its pointer, so hovering there would interrupt
    /// whatever the agent is doing. Only a person who is already in control
    /// expects the remote pointer to follow their hand.
    public mutating func pointerMoved(to point: CGPoint, in surface: PreviewMapping,
                                      now: Date) -> RemotePointerGesture? {
        guard isEngaged(at: now) else { return nil }
        guard let f = surface.fraction(appKitX: Double(point.x), appKitY: Double(point.y)) else { return nil }
        return .hover(u: f.u, v: f.v)
    }

    /// The button came down. Returns whether this press should take the worker's
    /// human lease.
    ///
    /// The pause on automation starts here rather than when the gesture is finally
    /// posted, because the person has already committed to this surface.
    public mutating func beganPress(at point: CGPoint, button: MouseButton, modifiers: [Modifier],
                                    in surface: PreviewMapping, now: Date) -> Bool {
        guard let f = surface.fraction(appKitX: Double(point.x), appKitY: Double(point.y)) else {
            press = nil
            return false
        }
        press = Press(viewOrigin: point, u: f.u, v: f.v, button: button, modifiers: modifiers)
        engagedUntil = now.addingTimeInterval(Self.humanLeaseSeconds)
        lastRenewal = now
        return true
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
