import AppKit
import SwiftUI
import AgentSpaceCore

struct FusionWindowView: View {
    @ObservedObject var state: FusionWindowState
    let send: (JSONValue) -> Void
    let claimHuman: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            FusionSurface(image: state.image, send: send, claimHuman: claimHuman)
                .background(Color.black)
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
    var image: NSImage?
    let send: (JSONValue) -> Void
    let claimHuman: () -> Void

    func makeNSView(context: Context) -> RemoteWindowSurface {
        let view = RemoteWindowSurface()
        view.send = send
        view.claimHuman = claimHuman
        return view
    }

    func updateNSView(_ view: RemoteWindowSurface, context: Context) {
        view.image = image
        view.send = send
        view.claimHuman = claimHuman
    }
}

private final class RemoteWindowSurface: NSImageView {
    var send: ((JSONValue) -> Void)?
    /// Takes the worker's human lease without performing any input.
    var claimHuman: (() -> Void)?
    /// Where the current button press started, in both view and normalized
    /// coordinates: a click is only known once the button comes up, and a press
    /// that travelled further than this is a drag.
    private var pressOrigin: NSPoint?
    private var pressFraction: (x: Double, y: Double)?
    private var travelled = false
    /// The last moment a deliberate action was taken inside this proxy. Pointer
    /// travel outside that window is not forwarded at all.
    private var engagedUntil: Date?
    private var lastRenewal = Date.distantPast
    /// Trackpad deltas arrive as fractions (0.1, 0.4 …). The wire carries whole
    /// lines, so rounding each event on its own turned slow scrolling to zero.
    private var scrollCarryX = 0.0
    private var scrollCarryY = 0.0
    private static let dragThreshold: CGFloat = 3
    /// A held button renews the lease before the five seconds it bought runs
    /// out, so a long drag stays the agent's pause rather than its resume.
    private static let renewalInterval: TimeInterval = 2

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageScaling = .scaleProportionallyUpOrDown
        imageAlignment = .alignCenter
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { window?.acceptsMouseMovedEvents = true }
    override func mouseMoved(with event: NSEvent) {
        // Crossing a proxy is the main user moving their own cursor over a
        // *picture* of another session's window. Forwarding it would activate
        // that app in the agent's session and move its pointer, so hovering
        // here would interrupt whatever the agent is doing. Only a person who
        // is already in control of this proxy expects the remote pointer to
        // follow their hand.
        guard isEngaged else { return }
        guard let fraction = normalized(event) else { return }
        emit(FusionInputRouter.pointer(type: "move", x: fraction.x, y: fraction.y, event: event))
    }
    override func scrollWheel(with event: NSEvent) {
        guard let fraction = normalized(event) else { return }
        scrollCarryX += event.scrollingDeltaX
        scrollCarryY += event.scrollingDeltaY
        let dx = Int(scrollCarryX), dy = Int(scrollCarryY)
        guard dx != 0 || dy != 0 else { return }
        scrollCarryX -= Double(dx)
        scrollCarryY -= Double(dy)
        noteEngagement()
        emit(FusionInputRouter.pointer(type: "scroll", x: fraction.x, y: fraction.y,
                                      dx: dx, dy: dy, event: event))
    }
    override func mouseDown(with event: NSEvent) { beginPress(event) }
    override func rightMouseDown(with event: NSEvent) { beginPress(event) }
    override func otherMouseDown(with event: NSEvent) { beginPress(event) }
    override func mouseDragged(with event: NSEvent) { renew(); trackPress(event) }
    override func rightMouseDragged(with event: NSEvent) { renew(); trackPress(event) }
    override func otherMouseDragged(with event: NSEvent) { renew(); trackPress(event) }
    override func mouseUp(with event: NSEvent) { endPress(event, type: event.clickCount > 1 ? "doubleClick" : "click") }
    override func rightMouseUp(with event: NSEvent) { endPress(event, type: "rightClick") }
    override func otherMouseUp(with event: NSEvent) { endPress(event, type: "click") }
    override func keyDown(with event: NSEvent) {
        noteEngagement()
        if let action = FusionInputRouter.keyboard(event) { emit(action) }
    }

    /// The button is down, so a person has taken this window: the pause on
    /// automation starts here, not when the gesture is finally posted.
    private func beginPress(_ event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let fraction = normalized(event) else { return }
        pressOrigin = event.locationInWindow
        pressFraction = fraction
        travelled = false
        noteEngagement()
        lastRenewal = Date()
        claimHuman?()
    }

    private func trackPress(_ event: NSEvent) {
        guard pressOrigin != nil, !travelled else { return }
        let origin = event.locationInWindow
        travelled = hypot(origin.x - pressOrigin!.x, origin.y - pressOrigin!.y) > Self.dragThreshold
    }

    private func renew() {
        guard pressOrigin != nil else { return }
        noteEngagement()
        let now = Date()
        guard now.timeIntervalSince(lastRenewal) >= Self.renewalInterval else { return }
        lastRenewal = now
        claimHuman?()
    }

    /// The press becomes a click only when the button comes down and up in the
    /// same place; otherwise it was a drag and the travelled path is what the
    /// remote app needs to see.
    private func endPress(_ event: NSEvent, type: String) {
        defer { pressOrigin = nil; pressFraction = nil; travelled = false }
        guard let press = pressFraction else {
            // The press landed outside the remote image, so nothing here owns
            // the release either.
            return
        }
        window?.makeFirstResponder(self)
        guard let release = fractionClamped(toImage: event) else { return }
        noteEngagement()
        if travelled {
            emit(FusionInputRouter.drag(
                fromX: press.x, fromY: press.y, toX: release.x, toY: release.y, event: event))
        } else {
            emit(FusionInputRouter.pointer(type: type, x: press.x, y: press.y, event: event))
        }
    }

    private var isEngaged: Bool {
        guard let engagedUntil else { return false }
        return Date() < engagedUntil
    }

    /// A deliberate action keeps travel meaningful for one lease length — the
    /// same five seconds the worker grants, and the worker decides either way.
    private func noteEngagement() {
        engagedUntil = Date().addingTimeInterval(FusionInputRouter.humanLeaseSeconds)
    }

    private func emit(_ action: JSONValue) { send?(action) }

    /// Normalized position of the event, or nil when it is not over the remote
    /// image at all.
    private func normalized(_ event: NSEvent) -> (x: Double, y: Double)? {
        guard let point = position(event, strict: true) else { return nil }
        return point
    }

    /// As `normalized`, but a release that drifted past the image edges is
    /// pulled back onto it: the travelled path still started inside the window.
    private func fractionClamped(toImage event: NSEvent) -> (x: Double, y: Double)? {
        position(event, strict: false)
    }

    private func position(_ event: NSEvent, strict: Bool) -> (x: Double, y: Double)? {
        guard let image, bounds.width > 0, bounds.height > 0 else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let imageAspect = image.size.width / max(1, image.size.height)
        let viewAspect = bounds.width / max(1, bounds.height)
        let fitted: NSRect
        if imageAspect > viewAspect {
            let height = bounds.width / imageAspect
            fitted = NSRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
        } else {
            let width = bounds.height * imageAspect
            fitted = NSRect(x: (bounds.width - width) / 2, y: 0, width: width, height: bounds.height)
        }
        if strict, !fitted.contains(point) { return nil }
        let x = Double(point.x - fitted.minX) / Double(fitted.width)
        let y = 1 - (Double(point.y - fitted.minY) / Double(fitted.height))
        return (x, y)
    }
}
