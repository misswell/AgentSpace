import AppKit
import SwiftUI
import AgentSpaceCore

struct RemoteSurfaceView: NSViewRepresentable {
    let client: FrameClient
    /// The most pixels the capture may be asked for, in each axis — the source's
    /// own pixel size, held to `DisplayQuality`. `.zero` means "no ceiling of its
    /// own": a caller that does not know the source (a Fusion proxy) keeps asking
    /// for the pixels its view can show.
    ///
    /// The viewer's request is the *smaller* of this and its own window's device
    /// pixels, so 「原生」 cannot ask a 1920-wide desktop for 2280 pixels and be
    /// handed an enlargement. See `DisplayQuality` for the cost of the other way.
    var captureLimit: CGSize = .zero
    var captureMagnification: Double = 1
    /// Whether pointer gestures may be turned into input at all. The caller's
    /// answer to "does the worker permit input right now"; a surface that is not
    /// an input target collects no press, claims no lease and emits nothing.
    var acceptsInput = false
    /// The remote surface's size in the unit `onGesture` positions are converted
    /// into — display points for the desktop viewer. Fractions do not need it,
    /// so a proxy that only sends fractions leaves it alone.
    var remoteContentSize: CGSize = .zero
    /// Whether the pointer is captured on entry (Desktop Mode) or only on a
    /// press (a Fusion proxy). See `PointerCapturePolicy`.
    var capturePolicy: PointerCapturePolicy = .watchOnly
    /// Whether the local cursor may be hidden at all. False while the worker has
    /// not confirmed it will publish a cursor of its own — a hidden local cursor
    /// and no remote one is a desktop with no pointer.
    var hidesLocalCursor = false
    var onGesture: ((RemotePointerGesture) -> Void)? = nil
    var onClaimHuman: (() -> Void)? = nil
    var onReleaseHuman: (() -> Void)? = nil
    /// A press that must reach the agent immediately (raw phases) rather than
    /// after the click/drag threshold.
    var sendsRawPresses = false
    /// Where the drawn remote cursor lives, so the view that owns the worker's
    /// published position can put it on screen.
    var cursorOverlay: RemoteCursorOverlayProxy?
    /// A drag started or ended. The host uses it to raise the capture rate: a
    /// window being dragged at a low frame rate does not look dragged.
    var onDragActivity: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> RemoteSurfaceNSView {
        let view = RemoteSurfaceNSView(client: client)
        configure(view)
        return view
    }

    func updateNSView(_ view: RemoteSurfaceNSView, context: Context) {
        configure(view)
        view.needsLayout = true
    }

    private func configure(_ view: RemoteSurfaceNSView) {
        view.captureLimit = captureLimit; view.captureMagnification = captureMagnification
        view.acceptsInput = acceptsInput; view.remoteContentSize = remoteContentSize
        view.onGesture = onGesture; view.onClaimHuman = onClaimHuman
        view.onReleaseHuman = onReleaseHuman
        view.sendsRawPresses = sendsRawPresses
        view.capture.configure(capturePolicy)
        view.allowsLocalCursorHiding = hidesLocalCursor
        view.onDragActivity = onDragActivity
        cursorOverlay?.attach(view.cursorOverlay)
    }
}

struct FrameClientStatusOverlay: View {
    @ObservedObject var client: FrameClient

    var body: some View {
        Group {
            switch client.streamNotice {
            case .unrecoverable:
                // Connections have failed the same way repeatedly, so a fourth
                // "reconnecting…" would be reporting the app's patience instead of
                // the picture's absence. This one names the step that can actually
                // change the answer.
                VStack(alignment: .leading, spacing: 5) {
                    Text("Frame stream unavailable").font(.headline)
                    Text("The shared picture could not be recovered. Reconnect, and if it keeps happening, update AgentSpace.").font(.caption)
                }
            case .resynchronising:
                // The protocol's own words for this — "logical mapping size
                // mismatch", "descriptor outside the region" — name a bookkeeping
                // disagreement between two binaries, which is not something a
                // person watching a desktop can repair. The sizes are in the unified
                // log; the window says what is being done about it.
                VStack(alignment: .leading, spacing: 5) {
                    Text("Frame stream is out of sync").font(.headline)
                    Text("AgentSpace is reconnecting the shared picture.").font(.caption)
                }
            case .none:
                if let error = client.lastError {
                    VStack(alignment: .leading, spacing: 5) {
                        if SharedFrameAllocation.classify(message: error.message) != nil {
                            // The syscall's own words belong in the log and in
                            // Diagnostics, which carry the full message. Over a
                            // desktop that is simply not appearing, what this viewer
                            // owes the person is the one thing they can still do.
                            //
                            // Read from the message because that is all that crosses
                            // the socket: a refusal is an ordinary internal error with
                            // this shape of text, and a structured field for it would
                            // make every older viewer fail to decode the error at all.
                            Text("Frame stream failed to start").font(.headline)
                            Text("Could not create the shared frame buffer. Reconnect; if it keeps happening, update AgentSpace.").font(.caption)
                        } else {
                            Text("Frame stream unavailable").font(.headline)
                            Text(error.message).font(.caption)
                        }
                    }
                } else if client.state == .connecting || client.state == .reconnecting {
                    Label(client.state == .connecting ? NSLocalizedString("Connecting frame stream…", comment: "") : NSLocalizedString("Reconnecting frame stream…", comment: ""),
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.callout)
                }
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(12)
    }
}

extension RemotePointerGesture {
    /// Which button was held and which command modifiers came with the event.
    ///
    /// These are the names `InputAction.parse` already accepts, so a shift-click
    /// here means what a shift-click means from `agentspace input`.
    static func attributes(of event: NSEvent) -> (button: MouseButton, modifiers: [Modifier]) {
        var modifiers: [Modifier] = []
        let flags = event.modifierFlags
        if flags.contains(.command) { modifiers.append(.cmd) }
        if flags.contains(.control) { modifiers.append(.ctrl) }
        if flags.contains(.option) { modifiers.append(.alt) }
        if flags.contains(.shift) { modifiers.append(.shift) }
        // `fn` is left out deliberately: on a Mac keyboard it is not held as a
        // modifier for mouse gestures, and reporting it would send a flag the
        // remote cannot honour.
        return (button(event.buttonNumber) ?? .left, modifiers)
    }

    static func button(_ number: Int) -> MouseButton? {
        switch number {
        case 0: return .left
        case 1: return .right
        case 2: return .middle
        default: return nil
        }
    }
}

class RemoteSurfaceNSView: NSView {
    let client: FrameClient
    var captureLimit: CGSize = .zero
    var captureMagnification = 1.0
    /// See `RemoteSurfaceView.acceptsInput`. Revoking input drops the gesture in
    /// progress *and* releases pointer capture: a press collected while input was
    /// permitted must not become a click after the worker said stop, and a
    /// hidden local cursor must not survive a worker that went offline.
    var acceptsInput = false {
        didSet {
            guard !acceptsInput else { return }
            forward(gestures.cancelPress())
            gestures.reset()
            capture.release()
            refreshCursorRects()
        }
    }
    var remoteContentSize: CGSize = .zero
    var onGesture: ((RemotePointerGesture) -> Void)?
    /// Takes the worker's human lease without performing any input.
    var onClaimHuman: (() -> Void)?
    /// The person left the surface. Releasing explicitly is what lets automation
    /// resume immediately instead of waiting out the five-second fail-safe.
    var onReleaseHuman: (() -> Void)?
    /// A drag started or ended, so a host can raise the capture rate: a window
    /// being dragged at a low frame rate does not look like it is being dragged.
    var onDragActivity: ((Bool) -> Void)?
    /// Whether every press is forwarded as a press. Desktop Mode sets it; a
    /// proxy keeps the threshold model that makes a click out of a press.
    var sendsRawPresses = false {
        didSet { if sendsRawPresses != gestures.isRaw, capture.isControlling { gestures.beginControl(rawPhases: sendsRawPresses) } }
    }
    /// Whether this surface may hide the local cursor at all. False until the
    /// worker has promised a cursor of its own.
    var allowsLocalCursorHiding = false {
        didSet {
            guard oldValue != allowsLocalCursorHiding else { return }
            if !allowsLocalCursorHiding { capture.release() }
            refreshCursorRects()
        }
    }
    /// The pointer half of this surface's state: capture, the image rect, and
    /// when to hide the local cursor.
    let capture = PointerCaptureCoordinator()
    /// The agent's own pointer, drawn locally from the worker's published
    /// position. Nil until a cursor channel exists, in which case the cursor
    /// inside the captured picture is what the person sees.
    var cursorOverlay: RemoteCursorOverlayLayer? { cursorOverlayLayer }
    private var gestures = RemotePointerGestureTracker()
    private var trackingArea: NSTrackingArea?
    private let cursorOverlayLayer: RemoteCursorOverlayLayer?
    /// The display point of the last position this surface sent, so a correction
    /// from the worker can be compared against what the hand actually asked for.
    private var lastSentDisplayPoint: CGPoint?
    private let renderer: MetalSurfaceRenderer?
    private let cpuLayer = CALayer()
    private let cpuLock = NSLock()
    private var cpuPixels = Data()
    private var cpuWidth = 0
    private var cpuHeight = 0

    init(client: FrameClient) {
        self.client = client; self.renderer = MetalSurfaceRenderer()
        self.cursorOverlayLayer = RemoteCursorOverlayLayer()
        super.init(frame: .zero)
        wantsLayer = true
        if let metalLayer = renderer?.layer { layer = metalLayer }
        cpuLayer.contentsGravity = .resizeAspect
        cpuLayer.backgroundColor = NSColor.black.cgColor
        cpuLayer.isHidden = true
        layer?.addSublayer(cpuLayer)
        // Above the picture, below nothing: the overlay is the agent's pointer,
        // and the menu bar and Dock of the agent's desktop are part of the
        // picture it has to be drawn on top of.
        if let overlay = cursorOverlayLayer { layer?.addSublayer(overlay) }
        capture.onCaptureBegan = { [weak self] in
            guard let self else { return }
            self.gestures.beginControl(rawPhases: self.sendsRawPresses)
            self.onClaimHuman?()
            self.refreshCursorRects()
        }
        capture.onCaptureEnded = { [weak self] in
            guard let self else { return }
            self.gestures.endControl()
            self.onReleaseHuman?()
            self.refreshCursorRects()
        }
        client.handleSharedFrame = { [weak self] mapping, _, _, slot, patches, presented in
            guard let self else { return .refused }
            let outcome = self.renderer?.apply(mapping: mapping, slot: slot, patches: patches, presented: presented) ?? .refused
            switch outcome {
            case .uploaded, .uploadedWithoutPresent:
                DispatchQueue.main.async { self.cpuLayer.isHidden = true }
                return outcome
            case .refused:
                // No Metal, or a texture this view could not build: the CPU layer is
                // the renderer now, and a frame it also refuses is the one case
                // where the viewer asks the worker for a baseline. The CPU path
                // reports no present timestamp — a stamped guess is worse than no
                // sample, because it is the flattering kind.
                return self.applyCPU(mapping: mapping, slot: slot, patches: patches) ? .uploaded : .refused
            }
        }
        client.handleVideoFrame = { [weak self] buffer in
            guard let self else { return }
            if self.renderer?.applyVideo(buffer) == true {
                DispatchQueue.main.async { self.cpuLayer.isHidden = true }
            } else {
                self.applyCPU(pixelBuffer: buffer)
            }
        }
        client.resetSurface = { [weak self] in
            self?.renderer?.clear()
            self?.cpuLayer.contents = nil
            self?.cpuLayer.isHidden = true
            self?.cpuLock.lock(); self?.cpuPixels.removeAll(keepingCapacity: false); self?.cpuWidth = 0; self?.cpuHeight = 0; self?.cpuLock.unlock()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        if window == nil {
            forward(gestures.cancelPress())
            gestures.reset()
            // The picture is gone, so nothing may still claim the pointer: a
            // hidden cursor belongs to a window that is on screen.
            capture.release()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // `.activeInKeyWindow`: travel is only worth forwarding to a surface the
        // person is actually working in. An inactive picture of another session
        // is the main cursor passing over it, and moving the agent's pointer
        // because of that is the opposite of isolation.
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 2
        renderer?.resize(bounds.size, scale: scale)
        cpuLayer.frame = bounds
        // What this window can show, in its own device pixels…
        let naturalWidth = max(1, Int(bounds.width * scale))
        let naturalHeight = max(1, Int(bounds.height * scale))
        // …held to what the source has, when the caller knows. Asking for more
        // pixels than the subject has buys an enlargement: ScreenCaptureKit scales
        // the desktop *up* into the buffer it is handed, so the encoder spends bits
        // describing interpolation, and the picture on screen is the same one the
        // renderer would have made locally for free. Bounded here rather than in the
        // worker because this is where the local window size is known, and the
        // worker's own ceiling (`SharedFrameGeometry.maximumPixels`) is about the
        // frame budget rather than about sharpness.
        // Apply the source ceiling *after* magnification. A 200% selection must
        // not request a fake 3840×2160 frame from a 1920×1080, 1× desktop:
        // that only enlarges existing pixels, forces a stream reconnect and
        // can exhaust the shared-frame budget without adding Retina detail.
        let request = CaptureSizing.viewerRequest(
            viewPixelWidth: naturalWidth, viewPixelHeight: naturalHeight,
            magnification: captureMagnification,
            sourceLimitWidth: Int(captureLimit.width), sourceLimitHeight: Int(captureLimit.height))
        client.configure(width: request.width, height: request.height)
        refreshCaptureGeometry()
        refreshCursorRects()
    }

    // MARK: - Pointer gestures

    // What the hand did is decided once, by `RemotePointerGestureTracker`. What
    // it means on the wire belongs to whoever hosts the surface: a Fusion proxy
    // forwards the fractions, the desktop viewer converts them to display points.

    override func mouseMoved(with event: NSEvent) {
        let point = viewPoint(of: event)
        // Capture first: the hand may have just entered the picture, which in
        // Desktop Mode *is* taking control, and the travel it produces belongs to
        // the same event rather than to the next one.
        capture.pointer(movedTo: point)
        predictCursor(at: point)
        forward(gestures.pointerMoved(to: point, in: surfaceMapping(), now: Date()))
    }

    /// The pointer left the view's bounds entirely. A tracking area with
    /// `.inVisibleRect` reports this as `mouseExited`; capture must end here even
    /// if no further event arrives, because the local cursor has to come back.
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        capture.pointerLeftView()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        capture.pointer(movedTo: viewPoint(of: event))
    }

    override func mouseDown(with event: NSEvent) { beganPress(event, clickCount: event.clickCount) }
    override func rightMouseDown(with event: NSEvent) { beganPress(event, clickCount: event.clickCount) }
    override func otherMouseDown(with event: NSEvent) { beganPress(event, clickCount: 1) }
    override func mouseDragged(with event: NSEvent) { dragged(event) }
    override func rightMouseDragged(with event: NSEvent) { dragged(event) }
    override func otherMouseDragged(with event: NSEvent) { dragged(event) }
    override func mouseUp(with event: NSEvent) { endPress(event, clickCount: event.clickCount) }
    override func rightMouseUp(with event: NSEvent) { endPress(event, clickCount: event.clickCount) }
    override func otherMouseUp(with event: NSEvent) { endPress(event, clickCount: 1) }

    override func scrollWheel(with event: NSEvent) {
        guard acceptsInput else { return }
        let point = viewPoint(of: event)
        // A scroll is a deliberate act, so it captures the pointer in a proxy
        // that has not captured it yet: a person scrolling inside a remote window
        // is working in it.
        if !capture.isControlling, imageContains(point) {
            capture.pointer(movedTo: point)
            capture.pressStarted()
            capture.pressEnded(pointerInside: true)
        }
        forward(gestures.scrolled(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                                 at: point, in: surfaceMapping(), now: Date()))
    }

    private func beganPress(_ event: NSEvent, clickCount: Int) {
        guard acceptsInput, onGesture != nil else { return }
        window?.makeFirstResponder(self)
        let point = viewPoint(of: event)
        let attributes = RemotePointerGesture.attributes(of: event)
        if sendsRawPresses {
            // Raw mode: the press goes out now, as a press, because the remote
            // window server is what decides whether it is a click or the start of
            // a drag — and it can only decide that if it sees the press while the
            // button is still down.
            capture.pressStarted()
            let gesture = gestures.beganPressPhases(at: point, button: attributes.button,
                                                    clickCount: clickCount,
                                                    modifiers: attributes.modifiers,
                                                    in: surfaceMapping(), now: Date())
            forward(gesture)
            predictCursor(at: point)
            onDragActivity?(true)
            return
        }
        let claimed = gestures.beganPress(at: point, button: attributes.button,
                                          modifiers: attributes.modifiers,
                                          in: surfaceMapping(), now: Date(), clickCount: clickCount)
        capture.pressStarted()
        // The pause on automation starts with the press, not with the gesture it
        // eventually produces.
        if claimed { onClaimHuman?() }
    }

    private func dragged(_ event: NSEvent) {
        guard acceptsInput else { return }
        let point = viewPoint(of: event)
        let update = gestures.draggedPhases(to: point, in: surfaceMapping(), now: Date())
        if update.renewLease { onClaimHuman?() }
        for gesture in update.gestures { forward(gesture) }
        predictCursor(at: point)
    }

    private func endPress(_ event: NSEvent, clickCount: Int) {
        guard acceptsInput else { return }
        window?.makeFirstResponder(self)
        let point = viewPoint(of: event)
        // The final position must reach the agent before mouse-up. It is also
        // the first streamed point if the threshold was crossed only on release.
        let update = gestures.releaseTravelPhases(to: point, in: surfaceMapping(), now: Date())
        for gesture in update.gestures { forward(gesture) }
        forward(gestures.endedPress(at: point, clickCount: clickCount,
                                    in: surfaceMapping(), now: Date()))
        predictCursor(at: point)
        let inside = imageContains(point)
        onDragActivity?(false)
        capture.pressEnded(pointerInside: inside)
        // A press outside the picture that captured nothing must not leave the
        // surface believing it holds the pointer.
        if !inside, capture.state == .hovering { capture.pointerLeftView() }
    }

    private func forward(_ gesture: RemotePointerGesture?) {
        guard acceptsInput, let gesture, let onGesture else { return }
        onGesture(gesture)
    }

    private func imageContains(_ point: CGPoint) -> Bool {
        let rect = surfaceMapping().fittedRect
        guard let rect, rect.width >= 1, rect.height >= 1 else { return false }
        return rect.contains(x: Double(point.x), y: Double(point.y))
    }

    /// Move the drawn cursor to where the hand is, immediately.
    ///
    /// This is what makes the pointer feel attached: the position the person's
    /// hand moved to is known locally the instant it moves, so the sprite can be
    /// drawn there without waiting for the worker's echo — which arrives in
    /// single-digit milliseconds but is nevertheless a round trip the eye can be
    /// trained to see. The worker's answer corrects the drawing when it
    /// disagrees (see `RemoteCursorOverlayLayer.apply`).
    private func predictCursor(at point: CGPoint) {
        guard let overlay = cursorOverlayLayer,
              let displayPoint = surfaceMapping().displayPoint(appKitX: Double(point.x), appKitY: Double(point.y)) else { return }
        lastSentDisplayPoint = CGPoint(x: displayPoint.x, y: displayPoint.y)
        overlay.predict(displayPoint: CGPoint(x: displayPoint.x, y: displayPoint.y))
    }

    /// The worker's authoritative cursor position and shape.
    func applyCursor(_ presentation: InputClient.CursorPresentation) {
        cursorOverlayLayer?.mapping = surfaceMapping()
        cursorOverlayLayer?.apply(presentation)
    }

    /// Show or hide the agent's own cursor sprite. Off while the picture still
    /// carries the cursor inside it: two cursors drawn from two sources is the
    /// trailing ghost this overlay exists to remove.
    func setCursorOverlayVisible(_ visible: Bool) {
        cursorOverlayLayer?.isHidden = !visible || cursorOverlayLayer?.contents == nil
    }

    // MARK: - Cursor rects

    /// AppKit asks this whenever the pointer moves over the view. In capture the
    /// remote image gets a transparent cursor; everywhere else — the header, the
    /// footer, a Fusion title bar, the letterbox bars — the ordinary cursor is
    /// what a person is entitled to.
    ///
    /// This is deliberately the *only* mechanism the product uses to hide the
    /// pointer. `NSCursor.hide()` keeps a process-wide count that any missed
    /// unhide leaves wrong, so a crash or a fast user switch mid-gesture could
    /// leave the person with no cursor anywhere on their Mac. Cursor rects are
    /// scoped to one view and are recomputed by AppKit on demand, so the worst
    /// failure mode is the ordinary cursor reappearing.
    override func resetCursorRects() {
        super.resetCursorRects()
        guard allowsLocalCursorHiding, capture.isControlling,
              let rect = capture.cursorRect else { return }
        addCursorRect(rect, cursor: TransparentCursor.cursor)
    }

    /// Tell AppKit the cursor rects changed.
    ///
    /// `resetCursorRects()` alone is not enough: AppKit asks for cursor rects
    /// when the pointer moves or the view is laid out, so a capture that begins
    /// while the hand is *still* would keep showing the local cursor until the
    /// next twitch. Invalidating makes AppKit ask now — and it is the invalidation
    /// that also makes the release path immediate, which is the half that matters
    /// more.
    private func refreshCursorRects() {
        if let window {
            window.invalidateCursorRects(for: self)
        } else {
            resetCursorRects()
        }
    }

    /// The image rect, refreshed on layout so a cursor rect is never computed
    /// against a stale window size.
    private func refreshCaptureGeometry() {
        guard let rect = surfaceMapping().fittedRect else {
            capture.imageRect = .zero
            return
        }
        capture.imageRect = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        cursorOverlayLayer?.mapping = surfaceMapping()
    }

    /// Escape — Control-Option or Control-Command-G — hands the pointer back
    /// without leaving the surface. Absolute Desktop Mode normally releases on
    /// exit alone; this is for the case where the person wants to reach their own
    /// window controls while still looking at the agent's desktop.
    override func keyDown(with event: NSEvent) {
        if ReleaseCaptureGesture.matches(event) {
            capture.escape()
            return
        }
        super.keyDown(with: event)
    }

    /// Marks a deliberate interaction the subclass handled itself — for a proxy
    /// that is the keyboard — so the pointer travel that follows it still means
    /// something. Takes no lease: a keystroke is not a person holding the mouse.
    func noteEngagement() {
        gestures.noteEngagement(now: Date())
    }

    private func viewPoint(of event: NSEvent) -> NSPoint {
        convert(event.locationInWindow, from: nil)
    }

    /// Where the remote image actually sits inside this view. The renderer fits
    /// the image into the view rather than stretching it, so the letterbox bars
    /// belong to the window, not to the desktop — and `PreviewMapping` is the one
    /// place that arithmetic is written down.
    private func surfaceMapping() -> PreviewMapping {
        PreviewMapping(imageWidth: Int(client.surfaceSize.width),
                       imageHeight: Int(client.surfaceSize.height),
                       displayWidth: Int(remoteContentSize.width),
                       displayHeight: Int(remoteContentSize.height),
                       viewWidth: bounds.width,
                       viewHeight: bounds.height)
    }

    private func applyCPU(mapping: SharedFrameMapping, slot: SharedFrameSlotHeader, patches: [SharedPatchDescriptor]) -> Bool {
        let width = Int(slot.width), height = Int(slot.height), rowBytes = width * 4
        guard width > 0, height > 0 else { return false }
        cpuLock.lock(); defer { cpuLock.unlock() }
        if slot.frameKind == .fullBGRA || cpuWidth != width || cpuHeight != height {
            guard slot.frameKind == .fullBGRA else { return false }
            cpuPixels = Data(count: rowBytes * height); cpuWidth = width; cpuHeight = height
        }
        let copied = cpuPixels.withUnsafeMutableBytes { destination -> Bool in
            guard let base = destination.baseAddress else { return false }
            for patch in patches {
                let sourceOffset = Int(patch.payloadOffset)
                let patchRowBytes = Int(patch.bytesPerRow)
                guard sourceOffset >= 0,
                      sourceOffset + Int(patch.payloadLength) <= mapping.mappedCapacity,
                      Int(patch.x + patch.width) <= width,
                      Int(patch.y + patch.height) <= height else { return false }
                for row in 0..<Int(patch.height) {
                    memcpy(base.advanced(by: (Int(patch.y) + row) * rowBytes + Int(patch.x) * 4),
                           mapping.pointer.advanced(by: sourceOffset + row * patchRowBytes),
                           Int(patch.width) * 4)
                }
            }
            return true
        }
        guard copied else { return false }
        showCPU(pixels: cpuPixels, width: width, height: height, rowBytes: rowBytes)
        return true
    }

    private func applyCPU(pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer), height = CVPixelBufferGetHeight(pixelBuffer)
        let sourceRow = CVPixelBufferGetBytesPerRow(pixelBuffer), rowBytes = width * 4
        var pixels = Data(count: rowBytes * height)
        pixels.withUnsafeMutableBytes { destination in
            guard let output = destination.baseAddress else { return }
            for row in 0..<height { memcpy(output.advanced(by: row * rowBytes), base.advanced(by: row * sourceRow), rowBytes) }
        }
        cpuLock.lock(); cpuPixels = pixels; cpuWidth = width; cpuHeight = height; cpuLock.unlock()
        showCPU(pixels: pixels, width: width, height: height, rowBytes: rowBytes)
    }

    private func showCPU(pixels: Data, width: Int, height: Int, rowBytes: Int) {
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return }
        DispatchQueue.main.async { [weak self] in self?.cpuLayer.contents = image; self?.cpuLayer.isHidden = false }
    }
}
