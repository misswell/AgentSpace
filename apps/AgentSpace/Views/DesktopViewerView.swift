import SwiftUI
import AgentSpaceCore

/// The Desktop Viewer — plan §17 and §52.
///
/// The user sees the agent's actual desktop in a detached native window and can
/// click and type into it, without fast-user-switching.
///
/// Three properties are worth naming, because each is a decision rather than an
/// implementation detail.
///
/// 1. **The preview polls at 1 FPS, and only while this view exists.** §52 asks
///    for playback that costs nothing when nobody is watching, so the timer is
///    tied to the view's lifetime: `onDisappear` stops it, and closing the window
///    ends the captures.
/// 2. **A click is translated, never forwarded.** The click's position in this
///    window has nothing to do with the agent's screen. `PreviewMapping` converts
///    it through the image's fraction and the *display's* point size, and a click
///    on the letterbox is dropped rather than clamped to an edge.
/// 3. **It is disabled unless the worker says input is permitted.** When the agent
///    desktop is on the physical console, the overlay says so and the surface stops
///    accepting clicks, because the alternative is clicking on the user's own
///    screen.
struct DesktopViewerView: View {
    /// Pin a detached viewer to the account that opened it.  A nil value keeps
    /// the selected-account behaviour used by previews and older callers.
    private let spaceID: UUID?

    init(spaceID: UUID? = nil) {
        self.spaceID = spaceID
    }

    /// The viewer's scale is deliberately independent from the agent's
    /// display mode. "Fit" is the local-window equivalent of a native desktop
    /// viewer; the other values zoom the captured surface and keep scrolling
    /// available when it is larger than this window.
    private enum ViewerZoom: String, CaseIterable, Identifiable {
        case fit
        case seventyFive = "0.75"
        case one = "1.0"
        case oneTwentyFive = "1.25"
        case oneFifty = "1.5"
        case two = "2.0"

        var id: String { rawValue }

        var factor: Double {
            switch self {
            case .fit: return 1
            case .seventyFive: return 0.75
            case .one: return 1
            case .oneTwentyFive: return 1.25
            case .oneFifty: return 1.5
            case .two: return 2
            }
        }

        var title: String {
            switch self {
            case .fit: return NSLocalizedString("Fit", comment: "")
            case .seventyFive: return "75%"
            case .one: return "100%"
            case .oneTwentyFive: return "125%"
            case .oneFifty: return "150%"
            case .two: return "200%"
            }
        }
    }

    private static let frameRateOptions = [1, 5, 10, 15, 30]
    private static let captureWidthOptions = [960, 1280, 1600, 1920]

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var image: NSImage?
    @State private var result: ScreenshotResult?
    @State private var lastCapture: Date?
    @State private var captureError: AppModel.PresentedError?
    @State private var timer: Timer?
    /// True while the worker's ScreenCaptureKit stream is serving frames.
    @State private var previewStreaming = false
    @State private var lastClickPoint: (x: Double, y: Double)?
    @State private var pendingAction: String?
    @AppStorage("previewMaxWidth") private var previewMaxWidth = 1600
    @AppStorage("previewFPS") private var previewFPS = 5
    @State private var zoom = ViewerZoom.fit

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 720, idealWidth: 1120, minHeight: 520, idealHeight: 760)
        .background(WindowCapture { hostWindow = $0 })
        .onAppear {
            capture()
            startPreview()
            syncKeyboardState()
        }
        .onDisappear {
            stopPreview()
            removeKeyboardMonitor()
        }
        // The worker's readiness changes while the viewer sits open — the
        // first sign-in happens in the *other* session — so installation is
        // state-driven, not just appearance-driven. Revocation (worker gone,
        // console switch) tears the monitor down instead of leaving it
        // consuming keys.
        .onChange(of: snapshot?.workerOnline) { _ in syncKeyboardState() }
        .onChange(of: snapshot?.acceptsInput) { _ in syncKeyboardState() }
        .onChange(of: hostWindow) { _ in syncKeyboardState() }
        .onChange(of: previewFPS) { _ in restartPreviewIfNeeded() }
        .onChange(of: previewMaxWidth) { _ in
            // A live SCK stream is native-sized; the capture-width picker
            // applies to the screenshot fallback and is picked up on its next
            // tick. Capture immediately when that is the active mode.
            if timer != nil, !previewStreaming { capture() }
        }
    }

    /// Install or tear down the keyboard monitor to match the current
    /// permission state. Installed only when the worker is online, input is
    /// permitted, and this view has a host window; removed in every other
    /// combination, so a monitor never outlives its authorization.
    private func syncKeyboardState() {
        let permitted = snapshot?.workerOnline == true && snapshot?.acceptsInput == true
        if permitted { syncKeyboardMonitor() } else { removeKeyboardMonitor() }
    }

    private var snapshot: SpaceSnapshot? {
        guard let spaceID else { return model.selected }
        return model.snapshots.first(where: { $0.space.id == spaceID })
    }

    // MARK: - Keyboard forwarding (§17 "键盘输入也一样", §52 输入)

    /// The window this view lives in, captured so the local key monitor can
    /// tell whether a key-down belongs to *this* viewer.
    @State private var hostWindow: NSWindow?
    /// The local monitor's token; nil while keyboard forwarding is off.
    @State private var keyMonitor: Any?

    /// Install the key monitor only while the worker permits input — and
    /// re-check at delivery time, so a mid-keystroke console switch cannot
    /// let a consumed key become an injected one (§2.1, fail closed).
    private func syncKeyboardMonitor() {
        guard keyMonitor == nil,
              let snapshot, snapshot.workerOnline, snapshot.acceptsInput,
              hostWindow != nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak hostWindow] event in
            guard event.window === hostWindow, let snapshot = self.snapshot,
                  snapshot.workerOnline, snapshot.acceptsInput else { return event }
            let action = KeyboardForwarding.action(
                characters: event.characters,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                command: event.modifierFlags.contains(.command),
                shift: event.modifierFlags.contains(.shift),
                option: event.modifierFlags.contains(.option),
                control: event.modifierFlags.contains(.control))
            guard let action else { return event }
            let space = snapshot.space
            self.pendingAction = Self.describe(action)
            Task { @MainActor in
                let error = await Task.detached(priority: .userInitiated) {
                    SpaceService().input(for: space, actions: [action])
                }.value
                if let error {
                    self.captureError = AppModel.PresentedError(
                        code: error.code.rawValue,
                        message: error.message,
                        fix: error.code.remediation,
                        spaceName: space.name)
                }
            }
            return nil // consumed: the key went to the agent session
        }
    }

    private func removeKeyboardMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private static func describe(_ action: InputAction) -> String {
        switch action {
        case .key(let combo):
            return String(format: NSLocalizedString("key → %@", comment: ""), combo)
        case .type(let text):
            return String(format: NSLocalizedString("type → %@", comment: ""),
                          text.replacingOccurrences(of: "\n", with: "⏎"))
        default:
            return ""
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            if let snapshot {
                StatusDot(state: snapshot.effectiveState)
                Text(String(format: NSLocalizedString("%@ Desktop", comment: ""), snapshot.space.displayName))
                    .font(.headline)
                Text(snapshot.effectiveState.displayName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if snapshot.space.uid != 0 {
                    Text(String(format: NSLocalizedString("uid %u", comment: ""), snapshot.space.uid))
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("No agent selected").font(.headline)
            }
            Spacer()
            if let result {
                Text(String(format: NSLocalizedString("%1$ld×%2$ld px · scale %3$ld", comment: ""), result.width, result.height, result.scale))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Button {
                model.showingDesktopViewer = false
                if let hostWindow {
                    hostWindow.performClose(nil)
                } else {
                    dismiss()
                }
            } label: {
                Label(NSLocalizedString("Close", comment: ""), systemImage: "xmark")
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("closeDesktopViewer")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let captureError {
            VStack {
                RefusalBanner(title: NSLocalizedString("Cannot show the agent's desktop", comment: ""),
                              code: captureError.code,
                              message: captureError.message,
                              fix: captureError.fix)
                .padding(16)
                Spacer()
            }
        } else if let image, let result, let snapshot {
            GeometryReader { proxy in
                let geometry = snapshot.display ?? DisplayGeometry(
                    width: result.pixelWidth, height: result.pixelHeight,
                    pixelWidth: result.pixelWidth, pixelHeight: result.pixelHeight, scale: result.scale)
                let fitted = fittedImageSize(
                    imageWidth: result.width,
                    imageHeight: result.height,
                    in: proxy.size)
                let imageSize = CGSize(
                    width: max(1, fitted.width * zoom.factor),
                    height: max(1, fitted.height * zoom.factor))
                let mapping = PreviewMapping.fitting(
                    imageWidth: result.width,
                    imageHeight: result.height,
                    geometry: geometry,
                    viewWidth: imageSize.width,
                    viewHeight: imageSize.height)

                ZStack {
                    Color.black
                    if zoom == .fit {
                        previewImage(image, size: imageSize, mapping: mapping, snapshot: snapshot)
                    } else {
                        ScrollView([.horizontal, .vertical]) {
                            previewImage(image, size: imageSize, mapping: mapping, snapshot: snapshot)
                                .frame(
                                    width: max(imageSize.width, proxy.size.width),
                                    height: max(imageSize.height, proxy.size.height))
                        }
                        .scrollIndicators(.automatic)
                    }

                    if !snapshot.acceptsInput {
                        inputBlockedOverlay(snapshot)
                    }
                }
            }
        } else {
            VStack(spacing: 10) {
                ProgressView()
                Text("Capturing the agent's desktop…").font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func inputBlockedOverlay(_ snapshot: SpaceSnapshot) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(snapshot.effectiveState == .console
                 ? NSLocalizedString("This desktop is on your physical display", comment: "")
                 : NSLocalizedString("Input is not available", comment: ""))
                .font(.headline)
            Text(snapshot.effectiveState == .console
                 ? NSLocalizedString("Clicks are disabled: they would land on your own screen. Fast-user-switch back and they resume automatically.", comment: "")
                 : (snapshot.problem?.message ?? NSLocalizedString("The worker has not permitted input for this agent.", comment: "")))
                .font(.callout)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if let fix = snapshot.problem?.code.remediation {
                Text(fix).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 380)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    capture()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(snapshot == nil)

                Toggle(livePreviewLabel, isOn: Binding(
                    get: { timer != nil },
                    set: { $0 ? startPreview() : stopPreview() }))
                    .toggleStyle(.switch)
                    .controlSize(.small)

                if let pendingAction {
                    Text(pendingAction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let lastCapture {
                    Text(String(format: NSLocalizedString("updated %@", comment: ""), lastCapture.formatted(date: .omitted, time: .standard)))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Button {
                    if let result { NSWorkspace.shared.selectFile(result.path, inFileViewerRootedAtPath: "") }
                } label: {
                    Label("Reveal File", systemImage: "folder")
                }
                .disabled(result == nil)
            }

            HStack(spacing: 12) {
                Picker("Zoom", selection: $zoom) {
                    ForEach(ViewerZoom.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("desktopViewerZoomPicker")

                Picker("Capture width", selection: $previewMaxWidth) {
                    ForEach(Self.captureWidthOptions, id: \.self) { width in
                        Text("\(width) px").tag(width)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("desktopViewerResolutionPicker")

                Picker("Frame rate", selection: $previewFPS) {
                    ForEach(Self.frameRateOptions, id: \.self) { fps in
                        Text("\(fps) FPS").tag(fps)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("desktopViewerFPSPicker")

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    // MARK: - Capture

    private func startPreview() {
        guard timer == nil else { return }
        // §52: the live stream runs at 5 FPS while the viewer is open, and the
        // worker auto-stops it if this window goes away without a clean close.
        // When the stream is refused (console session, missing grant), the
        // viewer falls back to the 1 FPS screenshot MVP — the verified path —
        // rather than showing nothing.
        guard let space = snapshot?.space else { return }
        if case .success = SpaceService().previewStart(for: space, maxFPS: previewFPS) {
            previewStreaming = true
        }
        let interval: TimeInterval = previewStreaming ? 1.0 / Double(max(1, previewFPS)) : 1.0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                if previewStreaming {
                    pullPreviewFrame()
                } else {
                    capture()
                }
            }
        }
    }

    private func stopPreview() {
        timer?.invalidate()
        timer = nil
        if previewStreaming {
            previewStreaming = false
            if let snapshot {
                _ = SpaceService().previewStop(for: snapshot.space)
            }
        }
    }

    private func restartPreviewIfNeeded() {
        guard timer != nil else { return }
        stopPreview()
        startPreview()
    }

    private var livePreviewLabel: String {
        String(format: NSLocalizedString("Live preview (%ld FPS)", comment: ""), previewFPS)
    }

    private func fittedImageSize(imageWidth: Int, imageHeight: Int, in viewport: CGSize) -> CGSize {
        guard imageWidth > 0, imageHeight > 0, viewport.width > 0, viewport.height > 0 else {
            return .zero
        }
        let imageAspect = CGFloat(imageWidth) / CGFloat(imageHeight)
        let viewportAspect = viewport.width / viewport.height
        if imageAspect > viewportAspect {
            return CGSize(width: viewport.width, height: viewport.width / imageAspect)
        }
        return CGSize(width: viewport.height * imageAspect, height: viewport.height)
    }

    /// The image owns the gesture so a zoomed, scrolled surface reports local
    /// image coordinates. This keeps click mapping correct without guessing a
    /// ScrollView offset, and it makes black letterbox bars non-interactive.
    private func previewImage(
        _ image: NSImage,
        size: CGSize,
        mapping: PreviewMapping,
        snapshot: SpaceSnapshot
    ) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.medium)
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .overlay {
                if let point = lastClickPoint,
                   let view = mapping.viewPoint(displayX: point.x, displayY: point.y) {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .frame(width: 18, height: 18)
                        .position(x: view.x, y: view.y)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                MouseInputSurface(
                    onLeftClick: { point in
                        sendClick(at: point, mapping: mapping, snapshot: snapshot, button: .left)
                    },
                    onRightClick: { point in
                        sendClick(at: point, mapping: mapping, snapshot: snapshot, button: .right)
                    })
            }
    }

    /// One pull of the live stream. A frame updates the image in place; a
    /// failure (including the stream's own idle-stop) falls back to the 1 FPS
    /// screenshot loop rather than ending the preview.
    private func pullPreviewFrame() {
        guard let snapshot else { return }
        switch SpaceService().previewFrame(for: snapshot.space) {
        case .success(let frame):
            image = frame
        case .failure:
            previewStreaming = false
            stopPreview()
            startPreview()
        }
    }

    private func capture() {
        guard let snapshot else { return }
        // A modest width keeps an idle preview cheap without making the geometry
        // lie:
        // the mapping uses the image's own size for the fraction and the display's
        // point size for the conversion, so a downscale cannot shift a click.
        switch SpaceService().screenshot(for: snapshot.space, maxWidth: previewMaxWidth, inline: false) {
        case .failure(let error):
            captureError = AppModel.PresentedError(
                code: error.code.rawValue,
                message: error.message,
                fix: error.code.remediation,
                spaceName: snapshot.space.name)
            stopPreview()
        case .success(let shot):
            captureError = nil
            result = shot
            lastCapture = Date()
            if let loaded = NSImage(contentsOfFile: shot.path) {
                image = loaded
            } else {
                captureError = AppModel.PresentedError(
                    code: "INTERNAL_ERROR",
                    message: String(format: NSLocalizedString("the worker wrote a capture to %@ but it could not be read", comment: ""), shot.path),
                    fix: NSLocalizedString("Check the agent's runtime directory permissions.", comment: ""),
                    spaceName: snapshot.space.name)
                stopPreview()
            }
        }
    }

    // MARK: - Input

    private func sendClick(
        at location: CGPoint,
        mapping: PreviewMapping,
        snapshot: SpaceSnapshot,
        button: MouseButton
    ) {
        guard snapshot.acceptsInput else { return }
        // MouseInputNSView reports its native AppKit (bottom-left) coordinates;
        // PreviewMapping owns the bridge back to the SwiftUI (top-left) space.
        // Keeping this conversion at the boundary prevents an upper-half click
        // from being delivered to the lower half of the agent's desktop.
        guard let point = mapping.displayPoint(
            appKitX: Double(location.x), appKitY: Double(location.y)) else {
            // A click on the letterbox. Not an error worth a banner — the user
            // aimed at the black bar — but it must not become a click at the edge.
            pendingAction = NSLocalizedString("click outside the desktop: ignored", comment: "")
            return
        }

        lastClickPoint = point
        let label = button == .right ? "right click → %1$ld, %2$ld" : "click → %1$ld, %2$ld"
        pendingAction = String(format: NSLocalizedString(label, comment: ""), Int(point.x), Int(point.y))

        let space = snapshot.space
        let action = InputAction.click(x: point.x, y: point.y, button: button, count: 1, modifiers: [])
        Task { @MainActor in
            let error = await Task.detached(priority: .userInitiated) {
                SpaceService().input(for: space, actions: [action])
            }.value
            if let error {
                captureError = AppModel.PresentedError(
                    code: error.code.rawValue,
                    message: error.message,
                    fix: error.code.remediation,
                    spaceName: space.name)
                stopPreview()
            }
        }
    }
}

/// A transparent AppKit surface is used instead of SwiftUI's `DragGesture` so
/// the viewer can distinguish a secondary click. The callback fires on mouse
/// up, matching a native desktop: pressing and releasing outside the image is
/// not turned into an input action by the image itself.
private struct MouseInputSurface: NSViewRepresentable {
    let onLeftClick: (CGPoint) -> Void
    let onRightClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> MouseInputNSView {
        MouseInputNSView(onLeftClick: onLeftClick, onRightClick: onRightClick)
    }

    func updateNSView(_ view: MouseInputNSView, context: Context) {
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
    }

    final class MouseInputNSView: NSView {
        var onLeftClick: (CGPoint) -> Void
        var onRightClick: (CGPoint) -> Void
        private var leftDown: CGPoint?
        private var rightDown: CGPoint?

        init(onLeftClick: @escaping (CGPoint) -> Void,
             onRightClick: @escaping (CGPoint) -> Void) {
            self.onLeftClick = onLeftClick
            self.onRightClick = onRightClick
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func mouseDown(with event: NSEvent) {
            leftDown = convert(event.locationInWindow, from: nil)
        }

        override func mouseUp(with event: NSEvent) {
            defer { leftDown = nil }
            guard leftDown != nil else { return }
            onLeftClick(convert(event.locationInWindow, from: nil))
        }

        override func rightMouseDown(with event: NSEvent) {
            rightDown = convert(event.locationInWindow, from: nil)
        }

        override func rightMouseUp(with event: NSEvent) {
            defer { rightDown = nil }
            guard rightDown != nil else { return }
            onRightClick(convert(event.locationInWindow, from: nil))
        }
    }
}

/// Captures the SwiftUI host window so the keyboard monitor can tell which
/// window a key-down arrived in. Reported from `viewDidMoveToWindow`, which
/// fires both on attach and on teardown.
private struct WindowCapture: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView { CaptureView(onChange: onChange) }
    func updateNSView(_ view: NSView, context: Context) {
        (view as? CaptureView)?.onChange = onChange
    }

    private final class CaptureView: NSView {
        var onChange: (NSWindow?) -> Void
        init(onChange: @escaping (NSWindow?) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("not used") }
        override func viewDidMoveToWindow() {
            if let window {
                // Keep the host resizable even when the view is embedded by a
                // caller that still uses the legacy sheet presentation.
                window.styleMask.insert(.resizable)
                window.minSize = NSSize(width: 720, height: 520)
            }
            onChange(window)
        }
    }
}
