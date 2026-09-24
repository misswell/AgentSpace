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
/// 1. **The binary frame stream exists only while this view exists.** Closing
///    the window releases capture, the persistent socket, mmap and Metal state.
/// 2. **A click is translated, never forwarded.** The local normalized point is
///    mapped through the worker-reported remote display geometry.
/// 3. **It is disabled unless the worker says input is permitted.** When the agent
///    desktop is on the physical console, the overlay says so and the surface stops
///    accepting clicks, because the alternative is clicking on the user's own
///    screen.
struct DesktopViewerView: View {
    /// Pin a detached viewer to the account that opened it.  A nil value keeps
    /// the selected-account behaviour used by previews and older callers.
    private let spaceID: UUID?
    private let onViewportSize: ((CGSize) -> Void)?

    init(spaceID: UUID? = nil, onViewportSize: ((CGSize) -> Void)? = nil) {
        self.spaceID = spaceID
        self.onViewportSize = onViewportSize
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

    /// The rates a person can choose. 30 is the default because the previous
    /// default of 5 was the single largest contributor to the desktop feeling
    /// remote: a cursor that lives inside the captured picture can be no newer
    /// than the newest frame, so 5 FPS meant a quarter of a second of lag on the
    /// thing a hand judges first, whatever the input path cost.
    ///
    /// 60 is offered because the capture path can do it and because a drag looks
    /// wrong below the panel's own rate; the rate policy raises the *stream* to
    /// 60 while a button is held even at a lower stored preference, because a
    /// window being dragged has to move with the hand that is dragging it.
    private static let frameRateOptions = [1, 5, 10, 15, 30, 60]

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var result: ScreenshotResult?
    @State private var lastCapture: Date?
    @State private var captureError: AppModel.PresentedError?
    @State private var frameClient: FrameClient?
    @State private var lastViewportSize: CGSize = .zero
    /// The capture rate actually asked for, which differs from the stored
    /// preference while a gesture is live: a drag raises the stream to 60 FPS
    /// whatever the preference says, because a dragged window that updates at
    /// 15 FPS does not look like it is being dragged.
    @State private var liveFPS: Int?
    /// The viewer's own input path: gestures in, `input` calls out, with the
    /// pointer-travel coalescing a proxy uses.
    @StateObject private var input = DesktopViewerInput()
    @State private var pendingAction: String?
    /// The bridge that lets this SwiftUI view push the worker's cursor position
    /// into the AppKit layer that draws it. Owned here rather than inside the
    /// surface because the position arrives on the view's `InputClient`, and the
    /// surface is rebuilt whenever SwiftUI feels like it.
    @StateObject private var cursorOverlay = RemoteCursorOverlayProxy()
    /// The display-quality mode, on the same key Settings' picker writes.
    @AppStorage(DisplayQuality.storageKey) private var displayQuality = DisplayQuality.default.rawValue
    @AppStorage("previewFPS") private var previewFPS = 30
    /// How the pointer behaves over the agent's desktop. See `MouseCaptureMode`:
    /// the default hands the pointer over on entry, which is what makes Desktop
    /// Mode feel like the machine in front of the person rather than a picture of
    /// one.
    @AppStorage(MouseCaptureMode.storageKey) private var captureMode = MouseCaptureMode.default.rawValue
    @State private var zoom = ViewerZoom.fit

    /// The mode in force, with anything unreadable falling back to the default
    /// rather than to a guess.
    private var quality: DisplayQuality { DisplayQuality.parse(displayQuality) ?? .default }

    /// The pointer policy in force, on the same "unreadable means default" rule.
    private var pointerPolicy: PointerCapturePolicy {
        (MouseCaptureMode.parse(captureMode) ?? .default).policy(for: .desktop)
    }

    /// The most pixels this viewer may ask the worker for.
    ///
    /// Bounded by the *agent's* display, not by this window: the mode is a claim
    /// about the source, and the surface takes the smaller of this and its own
    /// device pixels. Until the first snapshot arrives the limit is empty, and the
    /// stream opens at the worker's own natural size — which is the mode's own
    /// answer anyway, so the first frame is not a downgrade.
    private var captureLimit: CGSize {
        guard let display = snapshot?.display else { return .zero }
        let size = quality.captureSize(sourceWidth: display.pixelWidth, sourceHeight: display.pixelHeight)
        return CGSize(width: size.width, height: size.height)
    }

    /// The width a still snapshot is resampled to; `0` leaves the PNG at the
    /// framebuffer's own size. The same mode, one step outside the live stream.
    private var snapshotMaxWidth: Int {
        guard let display = snapshot?.display else { return 0 }
        let width = quality.captureSize(sourceWidth: display.pixelWidth, sourceHeight: display.pixelHeight).width
        return width >= display.pixelWidth ? 0 : width
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: DesktopViewportSizeKey.self, value: geometry.size)
                })
            Divider()
            footer
        }
        .frame(minWidth: 720, idealWidth: 1120, minHeight: 520, idealHeight: 760)
        .background(WindowCapture { hostWindow = $0 })
        .onAppear {
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
        .onChange(of: snapshot?.display) { _ in
            if lastViewportSize.width > 0 { onViewportSize?(lastViewportSize) }
        }
        .onChange(of: snapshot?.acceptsInput) { _ in syncKeyboardState() }
        .onChange(of: hostWindow) { _ in syncKeyboardState() }
        .onChange(of: previewFPS) { _ in restartPreviewIfNeeded() }
        .onChange(of: displayQuality) { _ in
            restartPreviewIfNeeded()
        }
        .onPreferenceChange(DesktopViewportSizeKey.self) { size in
            if size.width > 0, size.height > 0 {
                lastViewportSize = size
                onViewportSize?(size)
            }
        }
    }

    /// Install or tear down the keyboard monitor to match the current
    /// permission state. Installed only when the worker is online, input is
    /// permitted, and this view has a host window; removed in every other
    /// combination, so a monitor never outlives its authorization.
    private func syncKeyboardState() {
        let permitted = snapshot?.workerOnline == true && snapshot?.acceptsInput == true
        if permitted { syncKeyboardMonitor() } else { removeKeyboardMonitor() }
        // Travel collected while input was permitted must not reach the agent
        // after it was revoked — the same rule the monitor follows, one level up.
        if !permitted { input.reset() }
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
            // Keys take the fast channel when it is up, and the RPC path when it
            // is not. Both end in the worker's own `KeyCombo` parser and the same
            // session gates, so the only difference is which socket carries the
            // bytes — and a keystroke that shares a socket with the pointer cannot
            // be queued behind a JSON encode.
            let channelUp = self.input.sendKeyAction(action)
            if !channelUp {
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
        } else if let frameClient, let snapshot {
            ZStack {
                Color.black
                RemoteSurfaceView(
                    client: frameClient,
                    captureLimit: captureLimit,
                    captureMagnification: zoom.factor,
                    acceptsInput: snapshot.acceptsInput,
                    remoteContentSize: CGSize(width: snapshot.display?.width ?? 0,
                                              height: snapshot.display?.height ?? 0),
                    capturePolicy: snapshot.acceptsInput ? pointerPolicy : .watchOnly,
                    // The local cursor is hidden only once the worker has proved
                    // it publishes one of its own. Hiding it earlier would leave
                    // the person looking at a desktop with no pointer at all —
                    // worse than a cursor that lags by one frame.
                    hidesLocalCursor: input.cursorChannelActive,
                    onGesture: { gesture in send(gesture, snapshot: snapshot) },
                    onClaimHuman: { input.claimHuman() },
                    onReleaseHuman: { input.releaseHuman() },
                    sendsRawPresses: true,
                    cursorOverlay: cursorOverlay,
                    onDragActivity: { active in setDragActivity(active) })
                if !snapshot.acceptsInput { inputBlockedOverlay(snapshot) }
                VStack { HStack { FrameClientStatusOverlay(client: frameClient); Spacer() }; Spacer() }
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
                    restartPreviewIfNeeded()
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                }
                .disabled(snapshot == nil)

                Toggle(livePreviewLabel, isOn: Binding(
                    get: { frameClient != nil },
                    set: { $0 ? startPreview() : stopPreview() }))
                    .toggleStyle(.switch)
                    .controlSize(.small)

                if let refusal = input.refusal {
                    // A gesture the worker refused is said where the desktop stays
                    // visible: the refusal is about one click, and replacing a live
                    // desktop with a banner would make it about nothing.
                    Text(refusal.message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .help(refusal.message)
                } else if let pendingAction {
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
                    capture()
                } label: {
                    Label("Save Snapshot", systemImage: "camera")
                }
                .disabled(snapshot == nil)
                if let result {
                    Button { NSWorkspace.shared.selectFile(result.path, inFileViewerRootedAtPath: "") } label: { Label("Reveal File", systemImage: "folder") }
                }
            }

            HStack(spacing: 12) {
                Picker("Zoom", selection: $zoom) {
                    ForEach(ViewerZoom.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("desktopViewerZoomPicker")

                DisplayQualityPicker(identifier: "desktopViewerQualityPicker")

                Picker("Frame rate", selection: $previewFPS) {
                    ForEach(Self.frameRateOptions, id: \.self) { fps in
                        Text("\(fps) FPS").tag(fps)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("desktopViewerFPSPicker")

                // Mouse capture is a preference rather than a fixed behaviour:
                // taking the pointer on entry is what makes the desktop feel
                // local, and it is also the thing a person may not want if they
                // are watching the agent work.
                Picker("Mouse Capture", selection: $captureMode) {
                    Text("Auto").tag(MouseCaptureMode.auto.rawValue)
                    Text("Click to Capture").tag(MouseCaptureMode.clickToCapture.rawValue)
                    Text("Off").tag(MouseCaptureMode.off.rawValue)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("desktopViewerCaptureModePicker")
                .help(Text("When the agent's desktop takes your pointer. Control-Option or Control-Command-G hands it back."))

                Spacer(minLength: 0)

                // What the stream actually is, in the two sizes that answer every
                // "why is this not sharp?" question: the buffer the worker is
                // sending, and the desktop it was taken from. A viewer set to
                // 「原生」 on a 2x panel should read two equal numbers here; two
                // different ones mean the source is smaller than the window, or a
                // ceiling is in play.
                if let size = liveSurfaceSize, let display = snapshot?.display {
                    Text(String(format: NSLocalizedString("Stream %1$ld×%2$ld px · source %3$ld×%4$ld px", comment: ""),
                                Int(size.width), Int(size.height), display.pixelWidth, display.pixelHeight))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("desktopViewerStreamSize")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    // MARK: - Capture

    /// The size of the picture the worker is sending, once one has arrived —
    /// `nil` before the first frame, so the footer never prints 0×0.
    private var liveSurfaceSize: CGSize? {
        guard let size = frameClient?.surfaceSize, size.width > 0, size.height > 0 else { return nil }
        return size
    }

    private func startPreview() {
        guard frameClient == nil else { return }
        guard let space = snapshot?.space else { return }
        // The cursor channel and the capture's own cursor are mutually
        // exclusive: while the overlay draws the agent's pointer, the picture
        // must stop painting one, or the person sees two — the trailing ghost
        // this whole path exists to remove.
        let overlay = cursorOverlay
        input.onCursor = { [weak overlay] presentation in overlay?.apply(presentation) }
        input.onCursorChannelChange = { [weak frameClient, weak overlay] active in
            overlay?.isDrawingCursor = active
            // Only once the worker has *proved* it can publish shapes: turning
            // the painted cursor off for a channel that then fails would leave
            // the desktop with no pointer at all.
            frameClient?.setEmbeddedCursor(!active)
        }
        if let display = snapshot?.display { input.configure(space: space, display: display) }
        // Opened at the mode's own size rather than at "whatever the worker
        // thinks", so the first stream and the first `layout()` agree: the
        // surface's debounce reopens the stream when the requested size changes
        // by 16 px or more, and a first request of (0,0) followed by the real one
        // was one reconnect per window open.
        let limit = captureLimit
        let client = FrameClient(space: space, target: .display(displayID: nil), maxFPS: previewFPS,
                                targetWidth: Int(limit.width), targetHeight: Int(limit.height))
        frameClient = client; client.start()
    }

    private func stopPreview() {
        frameClient?.stop(); frameClient = nil
        liveFPS = nil
        // Nothing collected for a desktop that is no longer being watched may
        // still be posted afterwards, and the fast channel closes with the
        // window: it exists for a person who is looking at the desktop.
        input.reset()
        cursorOverlay.detach()
        input.onCursor = nil
        input.onCursorChannelChange = nil
    }

    private func restartPreviewIfNeeded() {
        guard frameClient != nil else { return }
        stopPreview()
        startPreview()
    }

    private var livePreviewLabel: String {
        String(format: NSLocalizedString("Live preview (%ld FPS)", comment: ""), previewFPS)
    }

    private func capture() {
        guard let snapshot else { return }
        // The still snapshot follows the same mode as the stream, so the file a
        // person saves is the picture they were looking at. `0` means "leave the
        // framebuffer's own size alone".
        switch SpaceService().screenshot(for: snapshot.space, maxWidth: snapshotMaxWidth, inline: false) {
        case .failure(let error):
            captureError = AppModel.PresentedError(
                code: error.code.rawValue,
                message: error.message,
                fix: error.code.remediation,
                spaceName: snapshot.space.name)
        case .success(let shot):
            captureError = nil
            result = shot
            lastCapture = Date()
        }
    }

    /// One gesture from the surface, sent to the account this viewer is pinned to.
    ///
    /// The snapshot travels with the gesture rather than being stored, so the
    /// worker's answer always applies to the desktop the person was looking at —
    /// and a click is translated through the geometry that desktop reported, never
    /// forwarded as a local point.
    private func send(_ gesture: RemotePointerGesture, snapshot: SpaceSnapshot) {
        guard snapshot.acceptsInput, let display = snapshot.display else { return }
        input.configure(space: snapshot.space, display: display)
        input.send(gesture)
    }

    /// A gesture started or ended, so the capture rate can follow it.
    ///
    /// A dragged or resized window at 15 FPS does not look dragged: the picture
    /// updates four times in the time the hand crosses the screen. The rate is
    /// raised to 60 while the button is down and returned to the person's own
    /// preference when it comes up — in place, through `frame.setFPS`, because
    /// reopening the stream would rebuild the shared region and restart the
    /// decoder to move one number.
    private func setDragActivity(_ active: Bool) {
        let policy = InputRatePolicy(ceiling: previewFPS)
        let target = policy.frames(for: active ? .interactive : .active)
        guard liveFPS != target else { return }
        liveFPS = target
        frameClient?.setFPS(target)
        input.setPointerRate(policy.pointerRate)
    }

}

private struct DesktopViewportSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 { value = next }
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
