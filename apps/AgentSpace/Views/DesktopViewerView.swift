import SwiftUI
import AgentSpaceCore

/// The Desktop Viewer — plan §17 and §52.
///
/// The user sees the agent's actual desktop inside the main app, and can click
/// and type into it, without fast-user-switching.
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
    @EnvironmentObject private var model: AppModel
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

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear {
            capture()
            startPreview()
        }
        .onDisappear(perform: stopPreview)
    }

    private var snapshot: SpaceSnapshot? { model.selected }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            if let snapshot {
                StatusDot(state: snapshot.effectiveState)
                Text(snapshot.space.name).font(.headline)
                Text(snapshot.effectiveState.displayName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if snapshot.space.uid != 0 {
                    Text("uid \(snapshot.space.uid)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("No Space selected").font(.headline)
            }
            Spacer()
            if let result {
                Text("\(result.width)×\(result.height) px · scale \(result.scale)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let captureError {
            VStack {
                RefusalBanner(title: "Cannot show the agent's desktop",
                              code: captureError.code,
                              message: captureError.message,
                              fix: captureError.fix)
                .padding(16)
                Spacer()
            }
        } else if let image, let result, let snapshot {
            GeometryReader { proxy in
                let mapping = PreviewMapping.fitting(
                    imageWidth: result.width,
                    imageHeight: result.height,
                    geometry: snapshot.display ?? DisplayGeometry(
                        width: result.pixelWidth, height: result.pixelHeight,
                        pixelWidth: result.pixelWidth, pixelHeight: result.pixelHeight, scale: result.scale),
                    viewWidth: proxy.size.width,
                    viewHeight: proxy.size.height)

                ZStack {
                    Color.black
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fit)

                    // Where the last click was sent, in the agent's coordinates.
                    // Drawing it is what makes a mis-scaled mapping visible
                    // immediately instead of as a mysterious misplaced click.
                    if let point = lastClickPoint, let view = mapping.viewPoint(displayX: point.x, displayY: point.y) {
                        Circle()
                            .stroke(Color.accentColor, lineWidth: 2)
                            .frame(width: 18, height: 18)
                            .position(x: view.x, y: view.y)
                            .allowsHitTesting(false)
                    }

                    if !snapshot.acceptsInput {
                        inputBlockedOverlay(snapshot)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            sendClick(at: value.location, mapping: mapping, snapshot: snapshot)
                        }
                )
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
                 ? "This desktop is on your physical display"
                 : "Input is not available")
                .font(.headline)
            Text(snapshot.effectiveState == .console
                 ? "Clicks are disabled: they would land on your own screen. Fast-user-switch back and they resume automatically."
                 : (snapshot.problem?.message ?? "The worker has not permitted input for this Space."))
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
        HStack(spacing: 10) {
            Button {
                capture()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(snapshot == nil)

            Toggle("Live preview (1 FPS)", isOn: Binding(
                get: { timer != nil },
                set: { $0 ? startPreview() : stopPreview() }))
                .toggleStyle(.switch)
                .controlSize(.small)

            if let pendingAction {
                Text(pendingAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let lastCapture {
                Text("updated \(lastCapture.formatted(date: .omitted, time: .standard))")
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
        if case .success = SpaceService().previewStart(for: space) {
            previewStreaming = true
        }
        let interval: TimeInterval = previewStreaming ? 1.0 / 5.0 : 1.0
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
                    message: "the worker wrote a capture to \(shot.path) but it could not be read",
                    fix: "Check the Space's runtime directory permissions.",
                    spaceName: snapshot.space.name)
                stopPreview()
            }
        }
    }

    // MARK: - Input

    private func sendClick(at location: CGPoint, mapping: PreviewMapping, snapshot: SpaceSnapshot) {
        guard snapshot.acceptsInput else { return }
        guard let point = mapping.displayPoint(viewX: Double(location.x), viewY: Double(location.y)) else {
            // A click on the letterbox. Not an error worth a banner — the user
            // aimed at the black bar — but it must not become a click at the edge.
            pendingAction = "click outside the desktop: ignored"
            return
        }

        lastClickPoint = point
        pendingAction = "click → \(Int(point.x)), \(Int(point.y))"

        let space = snapshot.space
        let action = InputAction.click(x: point.x, y: point.y, button: .left, count: 1, modifiers: [])
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
