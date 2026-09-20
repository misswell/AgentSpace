import AppKit
import SwiftUI
import AgentSpaceCore

struct FusionWindowView: View {
    @ObservedObject var state: FusionWindowState
    let send: (JSONValue) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            FusionSurface(image: state.image, send: send)
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

    func makeNSView(context: Context) -> RemoteWindowSurface {
        let view = RemoteWindowSurface()
        view.send = send
        return view
    }

    func updateNSView(_ view: RemoteWindowSurface, context: Context) {
        view.image = image
        view.send = send
    }
}

private final class RemoteWindowSurface: NSImageView {
    var send: ((JSONValue) -> Void)?
    /// Where the current button press started, in both view and normalized
    /// coordinates: a click is only known once the button comes up, and a press
    /// that travelled further than this is a drag.
    private var pressOrigin: NSPoint?
    private var pressFraction: (x: Double, y: Double)?
    private var travelled = false
    private static let dragThreshold: CGFloat = 3

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageScaling = .scaleProportionallyUpOrDown
        imageAlignment = .alignCenter
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { window?.acceptsMouseMovedEvents = true }
    override func mouseMoved(with event: NSEvent) {
        guard let fraction = normalized(event) else { return }
        emit(FusionInputRouter.pointer(type: "move", x: fraction.x, y: fraction.y, event: event))
    }
    override func scrollWheel(with event: NSEvent) {
        guard let fraction = normalized(event) else { return }
        emit(FusionInputRouter.pointer(type: "scroll", x: fraction.x, y: fraction.y, event: event))
    }
    override func mouseDown(with event: NSEvent) { beginPress(event) }
    override func rightMouseDown(with event: NSEvent) { beginPress(event) }
    override func mouseDragged(with event: NSEvent) { trackPress(event) }
    override func rightMouseDragged(with event: NSEvent) { trackPress(event) }
    override func mouseUp(with event: NSEvent) { endPress(event, type: event.clickCount > 1 ? "doubleClick" : "click") }
    override func rightMouseUp(with event: NSEvent) { endPress(event, type: "rightClick") }
    override func keyDown(with event: NSEvent) {
        if let action = FusionInputRouter.keyboard(event) { emit(action) }
    }

    private func beginPress(_ event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let fraction = normalized(event) else { return }
        pressOrigin = event.locationInWindow
        pressFraction = fraction
        travelled = false
    }

    private func trackPress(_ event: NSEvent) {
        guard pressOrigin != nil, !travelled else { return }
        let origin = event.locationInWindow
        travelled = hypot(origin.x - pressOrigin!.x, origin.y - pressOrigin!.y) > Self.dragThreshold
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
        if travelled {
            emit(FusionInputRouter.drag(
                fromX: press.x, fromY: press.y, toX: release.x, toY: release.y))
        } else {
            emit(FusionInputRouter.pointer(type: type, x: press.x, y: press.y, event: event))
        }
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
