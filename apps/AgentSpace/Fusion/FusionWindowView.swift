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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageScaling = .scaleProportionallyUpOrDown
        imageAlignment = .alignCenter
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { window?.acceptsMouseMovedEvents = true }
    override func mouseDown(with event: NSEvent) { emitPointer(event, type: event.clickCount > 1 ? "doubleClick" : "click") }
    override func rightMouseDown(with event: NSEvent) { emitPointer(event, type: "rightClick") }
    override func mouseMoved(with event: NSEvent) { emitPointer(event, type: "move") }
    override func mouseDragged(with event: NSEvent) { emitPointer(event, type: "move") }
    override func scrollWheel(with event: NSEvent) { emitPointer(event, type: "scroll") }
    override func keyDown(with event: NSEvent) {
        if let action = FusionInputRouter.keyboard(event) { send?(action) }
    }

    private func emitPointer(_ event: NSEvent, type: String) {
        window?.makeFirstResponder(self)
        guard let image, bounds.width > 0, bounds.height > 0 else { return }
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
        guard fitted.contains(point) else { return }
        let x = (point.x - fitted.minX) / fitted.width
        let y = 1 - ((point.y - fitted.minY) / fitted.height)
        send?(FusionInputRouter.pointer(type: type, x: x, y: y, event: event))
    }
}
