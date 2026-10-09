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
    private static let frameRateOptions = ViewerFrameRate.options

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
    @State private var activityClock = ViewerActivityClock()
    /// The viewer's own input path: gestures in, `input` calls out, with the
    /// pointer-travel coalescing a proxy uses.
    @StateObject private var input = RemoteViewerInput()
    @State private var pendingAction: String?
    /// The bridge that lets this SwiftUI view push the worker's cursor position
    /// into the AppKit layer that draws it. Owned here rather than inside the
    /// surface because the position arrives on the view's `InputClient`, and the
    /// surface is rebuilt whenever SwiftUI feels like it.
    @StateObject private var cursorOverlay = RemoteCursorOverlayProxy()
    /// The display-quality mode, on the same key Settings' picker writes.
    @AppStorage(DisplayQuality.storageKey) private var displayQuality = DisplayQuality.default.rawValue
    @AppStorage(ViewerFrameRate.storageKey) private var previewFPS = ViewerFrameRate.defaultValue
    /// Pointer behavior shared with Fusion surfaces.
    @AppStorage(MouseCaptureMode.storageKey) private var captureMode = MouseCaptureMode.default.rawValue
    /// How long this window stays awake with nobody using it (§353). A window
    /// left open while an agent works for hours is the case worth sleeping
    /// through: activity is the person's hand, never the desktop's busyness.
    @AppStorage(WindowSleepPolicy.storageKey) private var sleepMinutes = WindowSleepPolicy.default
    @State private var showingDetails = false
    /// Whether the stream is asleep (§353). True only through `sleepStream`;
    /// every explicit start (wake, reconnect, play) clears it.
    @State private var asleep = false
    /// The person pressed ⏸ — the one reason an eligible window stays dark.
    /// First-open's race (below) must not override it, and ⏸ clears it.
    @State private var pausedByPerson = false
    /// Whether the paused overlay is on screen. `pausedByPerson` is the
    /// *decision*; this is the *display* of it — set together, cleared together,
    /// so the dark states (asleep, paused, capturing) stay exclusive.
    @State private var showsPausedOverlay = false
    /// The last time the person's hand did anything here — a gesture, a drag,
    /// a key. The idle clock the sleep policy reads.
    @State private var lastActivity = Date()

    /// The mode in force, with anything unreadable falling back to the default
    /// rather than to a guess.
    private var quality: DisplayQuality { DisplayQuality.parse(displayQuality) ?? .default }

    /// The pointer policy in force, on the same "unreadable means default" rule.
    private var pointerPolicy: PointerCapturePolicy {
        (MouseCaptureMode.parse(captureMode) ?? .default).policy(for: .desktop)
    }

    /// The most pixels this viewer asks the worker for — once.
    ///
    /// Bounded by the *agent's* display, not by this window: the mode is a claim
    /// about the source, and it is the stream's fixed size for its whole life.
    /// The surface never re-derives the request from the window (`captureFollowsLayout:
    /// false`), so a resize — down to 800×600, up to fullscreen and back — is
    /// answered by the GPU scaling the picture and never by reopening the
    /// stream. Until the first snapshot arrives the limit is empty, and the
    /// stream opens at the worker's own natural size — which is the mode's own
    /// answer anyway, so the first frame is not a downgrade.
    private var captureLimit: CGSize {
        guard let display = snapshot?.retinaDisplay?.geometry else { return .zero }
        let size = quality.captureSize(sourceWidth: display.pixelWidth, sourceHeight: display.pixelHeight)
        return CGSize(width: size.width, height: size.height)
    }

    /// The width a still snapshot is resampled to; `0` leaves the PNG at the
    /// framebuffer's own size. The same mode, one step outside the live stream.
    private var snapshotMaxWidth: Int {
        guard let display = snapshot?.retinaDisplay?.geometry else { return 0 }
        let width = quality.captureSize(sourceWidth: display.pixelWidth, sourceHeight: display.pixelHeight).width
        return width >= display.pixelWidth ? 0 : width
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: DesktopViewportSizeKey.self, value: geometry.size)
                })
        }
        .frame(minWidth: 720, idealWidth: 1120, minHeight: 520, idealHeight: 760)
        .background(WindowCapture { hostWindow = $0 })
        .onAppear {
            startPreview()
            syncKeyboardState()
        }
        .task {
            while !Task.isCancelled {
                if let id = spaceID ?? model.selected?.space.id {
                    await model.refreshViewerStatus(for: id)
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .task {
            while !Task.isCancelled {
                updateCaptureRate()
                checkSleep()
                try? await Task.sleep(for: .milliseconds(250))
            }
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
        .onChange(of: snapshot?.workerOnline) { _ in
            syncKeyboardState()
            autoStartIfNeeded()
        }
        .onChange(of: snapshot?.desktopLocked) { locked in
            syncKeyboardState()
            if locked == true {
                stopPreview()
            } else {
                autoStartIfNeeded()
            }
        }
        .onChange(of: retinaDesktopRestartKey) { key in
            if lastViewportSize.width > 0 { onViewportSize?(lastViewportSize) }
            if key.isEmpty { stopPreview() } else { restartPreviewIfNeeded() }
            // First arrival of the display report is the moment first-open can
            // actually start (see autoStartIfNeeded).
            autoStartIfNeeded()
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
        // An asleep or paused window consumes no keys: its stream and socket
        // are gone, and a keystroke that fell back to the RPC path would type
        // into the agent's session with no picture showing it.
        let permitted = snapshot?.workerOnline == true && snapshot?.acceptsInput == true
            && !asleep && !pausedByPerson
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
        keyMonitor = RemoteKeyboardMonitor.install(window: hostWindow!, permitsInput: {
            self.snapshot?.workerOnline == true && self.snapshot?.acceptsInput == true
        }) { action in
            guard let snapshot = self.snapshot else { return }
            let space = snapshot.space
            // A forwarded key is the person's hand (§353's idle clock).
            self.lastActivity = Date()
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

    // MARK: - Compact controls

    private var header: some View {
        HStack(spacing: 6) {
            if let snapshot {
                StatusDot(state: snapshot.displayState)
                Text(String(format: NSLocalizedString("%@ Desktop", comment: ""), snapshot.space.displayName))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .leading)
            } else {
                Text("No agent selected").font(.subheadline)
            }
            Spacer(minLength: 4)
            Button { restartPreviewIfNeeded() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(Text("Reconnect"))
            .accessibilityLabel(Text("Reconnect"))
            .disabled(snapshot == nil)

            Button {
                if frameClient == nil {
                    resumeFromPause()
                } else {
                    pausedByPerson = true
                    showsPausedOverlay = true
                    stopPreview()
                    syncKeyboardState()
                }
            } label: {
                Image(systemName: frameClient == nil ? "play.fill" : "pause.fill")
            }
            .help(previewActionLabel)
            .accessibilityLabel(Text(previewActionLabel))
            .accessibilityIdentifier("desktopViewerPreviewToggle")
            .disabled(snapshot == nil)

            DisplayQualityPicker(identifier: "desktopViewerQualityPicker")
                .labelsHidden()

            Picker("Frame rate", selection: $previewFPS) {
                ForEach(Self.frameRateOptions, id: \.self) { fps in
                    Text("\(fps) FPS").tag(fps)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityIdentifier("desktopViewerFPSPicker")

            Picker("Mouse Capture", selection: Binding(
                get: { (MouseCaptureMode.parse(captureMode) ?? .default).rawValue },
                set: { captureMode = $0 })) {
                Text("Auto").tag(MouseCaptureMode.takeoverHidden.rawValue)
                Text("Takeover").tag(MouseCaptureMode.takeover.rawValue)
                Text("Click to Capture").tag(MouseCaptureMode.clickToCapture.rawValue)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityIdentifier("desktopViewerCaptureModePicker")
            .help(Text("Auto takes control on entry and hides the cursor inside the picture while keeping your own cursor visible. Takeover keeps the internal cursor visible. Click to Capture controls only while pressed. Control-Option or Control-Command-G releases control."))

            Button { capture() } label: { Image(systemName: "camera") }
                .help(Text("Save Snapshot"))
                .accessibilityLabel(Text("Save Snapshot"))
                .accessibilityIdentifier("desktopViewerSnapshot")
                .disabled(snapshot == nil)

            Button { showingDetails.toggle() } label: {
                Image(systemName: input.refusal == nil ? "info.circle" : "exclamationmark.triangle.fill")
                    .foregroundStyle(input.refusal == nil ? Color.primary : Color.orange)
            }
            .popover(isPresented: $showingDetails, arrowEdge: .bottom) { details }
            .help(input.refusal?.message ?? snapshot?.statusDisplayName ?? "")
            .accessibilityLabel(Text("Information"))
            .accessibilityIdentifier("desktopViewerDetails")

            Button {
                model.showingDesktopViewer = false
                if let hostWindow {
                    hostWindow.performClose(nil)
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
            }
            .help(Text("Close"))
            .accessibilityLabel(Text("Close"))
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("closeDesktopViewer")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        // The strip is the window's title bar now (§361): the leading inset is
        // where the traffic lights live, and the strip's own empty space drags
        // the window.
        .padding(.leading, 78)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .background(.bar)
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
        } else if let snapshot, snapshot.workerOnline, !snapshot.desktopLocked, snapshot.retinaDisplay == nil {
            VStack(spacing: 10) {
                Image(systemName: "display.trianglebadge.exclamationmark").font(.title)
                Text("A 2× display is required to open this desktop.")
                    .font(.headline)
                Text("Connect a Retina display to the agent session or update its Worker, then reconnect.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let snapshot, snapshot.desktopLocked {
            VStack(spacing: 10) {
                Image(systemName: "lock.display").font(.title)
                Text("The agent desktop is locked")
                    .font(.headline)
                Text("The wallpaper can still be captured, but apps and input are unavailable until the agent account is unlocked.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                Text("Unlock the agent with Sign In or Unlock Agent, then reopen this desktop.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if showsPausedOverlay {
            pausedOverlay
        } else if asleep {
            sleepOverlay
        } else if let frameClient, let snapshot {
            ZStack {
                Color.black
                RemoteSurfaceView(
                    client: frameClient,
                    captureLimit: captureLimit,
                    // The stream keeps the size the quality mode chose for its
                    // whole life: a window resize scales the picture on this
                    // Mac's GPU and never reopens the stream.
                    captureFollowsLayout: false,
                    acceptsInput: snapshot.acceptsInput,
                    remoteContentSize: CGSize(width: snapshot.retinaDisplay?.geometry.width ?? 0,
                                              height: snapshot.retinaDisplay?.geometry.height ?? 0),
                    capturePolicy: snapshot.acceptsInput ? pointerPolicy : .watchOnly,
                    // The local cursor is hidden only once the worker has proved
                    // it publishes one of its own. Hiding it earlier would leave
                    // the person looking at a desktop with no pointer at all —
                    // worse than a cursor that lags by one frame.
                    hidesLocalCursor: input.cursorChannelActive
                        && (MouseCaptureMode.parse(captureMode) ?? .default).hidesLocalCursor,
                    onGesture: { gesture in send(gesture, snapshot: snapshot) },
                    onClaimHuman: { input.claimHuman() },
                    onReleaseHuman: { input.releaseHuman() },
                    sendsRawPresses: true,
                    cursorOverlay: cursorOverlay,
                    onDragActivity: { active in setDragActivity(active) })
                    .onChange(of: captureMode) { _ in
                        // The picker changes the pointer policy mid-stream: the
                        // two cursor decisions follow it without waiting for a
                        // channel bounce (§364).
                        let mode = MouseCaptureMode.parse(captureMode) ?? .default
                        cursorOverlay.hidesCursor = !mode.hidesInternalCursor
                        cursorOverlay.isDrawingCursor = input.cursorChannelActive && !mode.hidesInternalCursor
                        frameClient.setEmbeddedCursor(mode.embedsCursor(cursorChannelActive: input.cursorChannelActive))
                    }
                if !snapshot.acceptsInput { inputBlockedOverlay(snapshot) }
                VStack { HStack { FrameClientStatusOverlay(client: frameClient); Spacer() }; Spacer() }
                PerformanceHUDOverlay(client: frameClient, input: input)
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

    // MARK: - Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let snapshot {
                HStack(spacing: 8) {
                    StatusDot(state: snapshot.displayState)
                    Text(snapshot.space.displayName).font(.headline)
                    Text(snapshot.statusDisplayName).foregroundStyle(.secondary)
                }
                if snapshot.space.uid != 0 {
                    Text(String(format: NSLocalizedString("uid %u", comment: ""), snapshot.space.uid))
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            if let refusal = input.refusal {
                Text(refusal.message).foregroundStyle(.red)
            } else if let pendingAction {
                Text(pendingAction).foregroundStyle(.secondary)
            }
            if let size = liveSurfaceSize, let display = snapshot?.retinaDisplay?.geometry {
                Text(String(format: NSLocalizedString("Stream %1$ld×%2$ld px · desktop %3$ld×%4$ld pt · %5$ld×%6$ld px (%7$ld×)", comment: ""),
                            Int(size.width), Int(size.height), display.width, display.height,
                            display.pixelWidth, display.pixelHeight, display.scale))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("desktopViewerStreamSize")
            }
            if let lastCapture {
                Text(String(format: NSLocalizedString("updated %@", comment: ""), lastCapture.formatted(date: .omitted, time: .standard)))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            if let result {
                Text(String(format: NSLocalizedString("%1$ld×%2$ld px · scale %3$ld", comment: ""), result.width, result.height, result.scale))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                Button { NSWorkspace.shared.selectFile(result.path, inFileViewerRootedAtPath: "") } label: {
                    Label("Reveal File", systemImage: "folder")
                }
            }
            HStack {
                Text("Sleep After")
                Spacer()
                Picker("Sleep After", selection: $sleepMinutes) {
                    ForEach(WindowSleepPolicy.options, id: \.self) { minutes in
                        Text(Self.sleepLabel(minutes)).tag(minutes)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("desktopViewerSleepPicker")
            }
            PerformanceHUDToggle()
        }
        .frame(width: 360, alignment: .leading)
        .padding(16)
    }

    /// The picker's words for the offered idle lengths.
    private static func sleepLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: return NSLocalizedString("Never", comment: "")
        case 60: return NSLocalizedString("1 Hour", comment: "")
        default: return String(format: NSLocalizedString("%ld Minutes", comment: ""), minutes)
        }
    }

    // MARK: - Sleep (§353)

    /// The asleep window: honest about what stopped, one click from live.
    private var sleepOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("Stream asleep").font(.headline)
            Text(String(format: NSLocalizedString("The stream stopped after %ld minutes idle. Click to go live again.", comment: ""),
                        WindowSleepPolicy.parse(sleepMinutes)))
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Click to wake") { wakeUp() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("desktopViewerWakeButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { wakeUp() }
    }

    /// The idle check, on the same 250 ms clock the capture rate rides. Only
    /// the person's hand pushes this clock — a busy desktop is the case the
    /// sleep exists to ride through, and a click on the asleep window wakes it.
    private func checkSleep() {
        guard !asleep, frameClient != nil else { return }
        let minutes = WindowSleepPolicy.parse(sleepMinutes)
        guard WindowSleepPolicy.shouldSleep(now: Date().timeIntervalSinceReferenceDate,
                                            lastActivity: lastActivity.timeIntervalSinceReferenceDate,
                                            minutes: minutes) else { return }
        asleep = true
        stopPreview()
        syncKeyboardState()
    }

    private func wakeUp() {
        asleep = false
        pausedByPerson = false
        showsPausedOverlay = false
        lastActivity = Date()
        startPreview()
        syncKeyboardState()
    }

    /// The ⏸ state, said out loud: the picture is dark because the person
    /// chose it, not because anything is being captured. One click — anywhere,
    /// or the toolbar's ▶ — goes live again.
    private var pausedOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "pause.circle")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("Stream paused").font(.headline)
            Text("The picture is dark because you paused it. Click to go live again.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Click to resume") { resumeFromPause() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("desktopViewerResumeButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { resumeFromPause() }
    }

    private func resumeFromPause() {
        pausedByPerson = false
        showsPausedOverlay = false
        lastActivity = Date()
        startPreview()
        syncKeyboardState()
    }

    // MARK: - Capture

    /// The size of the picture the worker is sending, once one has arrived —
    /// `nil` before the first frame, so the footer never prints 0×0.
    private var liveSurfaceSize: CGSize? {
        guard let size = frameClient?.surfaceSize, size.width > 0, size.height > 0 else { return nil }
        return size
    }

    /// Start the stream once its prerequisites have arrived after the view
    /// did. First open races the three-second viewer-status refresh:
    /// `.onAppear` usually runs while `snapshot.retinaDisplay` is still nil,
    /// `startPreview`'s guard returns silently, and nothing ever re-triggered
    /// it — the person stared at 「正在抓取 Agent 的桌面…」 until they pressed
    /// ▶ themselves, by which time the snapshot had arrived and worked. The
    /// two state arrivals that matter (the display report, the worker coming
    /// online) now re-ask. Never overrides a ⏸ the person chose, never wakes
    /// a window that is asleep.
    private func autoStartIfNeeded() {
        guard !pausedByPerson, !asleep, frameClient == nil,
              snapshot?.workerOnline == true,
              snapshot?.retinaDisplay != nil else { return }
        startPreview()
    }

    private func startPreview() {
        // Every explicit start — wake, reconnect, play, quality change — is a
        // hand on the window, so it clears the sleep and resets its clock.
        asleep = false
        showsPausedOverlay = false
        lastActivity = Date()
        guard frameClient == nil else { return }
        guard let space = snapshot?.space,
              let display = snapshot?.retinaDisplay else { return }
        // The cursor channel and the capture's own cursor are mutually
        // exclusive: while the overlay draws the agent's pointer, the picture
        // must stop painting one, or the person sees two — the trailing ghost
        // this whole path exists to remove.
        let overlay = cursorOverlay
        overlay.hidesCursor = !(MouseCaptureMode.parse(captureMode) ?? .default).hidesInternalCursor
        // The client exists before the closures capture it: a weak capture
        // taken before `frameClient = client` used to be nil forever, so
        // `setEmbeddedCursor` was silently never sent and the picture went on
        // painting its own cursor for the whole life of the mode (§357).
        let limit = captureLimit
        let client = FrameClient(space: space, target: .retinaDesktop, maxFPS: previewFPS,
                                 targetWidth: Int(limit.width), targetHeight: Int(limit.height))
        frameClient = client
        client.setEmbeddedCursor((MouseCaptureMode.parse(captureMode) ?? .default)
            .embedsCursor(cursorChannelActive: input.cursorChannelActive))
        input.onCursor = { [weak overlay] presentation in overlay?.apply(presentation) }
        input.onCursorChannelChange = { [weak client, weak overlay] active in
            // Hidden takeover keeps only the person's own pointer.
            overlay?.isDrawingCursor = active
                && !(MouseCaptureMode.parse(captureMode) ?? .default).hidesInternalCursor
            // Hidden mode suppresses capture painting even without shapes;
            // the other modes retain the channel-dependent fallback.
            client?.setEmbeddedCursor((MouseCaptureMode.parse(captureMode) ?? .default)
                .embedsCursor(cursorChannelActive: active))
        }
        input.configure(space: space, display: display)
        // Opened at the mode's own size, and that is the size for the stream's
        // whole life: the surface does not re-derive the request from the
        // window (`captureFollowsLayout: false`), so no resize — and no
        // fullscreen transition — ever reopens the stream.
        activityClock.tracker = FrameActivityTracker()
        liveFPS = previewFPS
        client.onFrameArrived = { [weak client] in
            guard let client, frameClient === client else { return }
            activityClock.tracker.noteChange(at: Date())
            updateCaptureRate()
        }
        client.start()
    }

    private func stopPreview() {
        frameClient?.onFrameArrived = nil
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
        // Open the replacement before closing the old stream. Both streams count
        // as users of the worker's Retina-desktop layout, so this order never
        // drops the count to zero in between: the agent session's display
        // arrangement does not flip back to the saved one and get applied again
        // in the gap that stop-then-start used to produce on every reopen.
        let previous = frameClient
        previous?.onFrameArrived = nil
        frameClient = nil
        startPreview()
        previous?.stop()
    }

    /// Whether the stream should be rebuilt for the Retina display's current
    /// report: its identity and pixel shape, never its origin. The single-
    /// Retina-desktop layout the stream itself applies moves that display to
    /// (0,0), so an origin change is the stream's own doing — restarting on it
    /// would tear the picture down seconds after every open.
    private var retinaDesktopRestartKey: String {
        guard let display = snapshot?.retinaDisplay else { return "" }
        return "\(display.id) \(display.geometry.width)x\(display.geometry.height)"
             + " \(display.geometry.pixelWidth)x\(display.geometry.pixelHeight)"
    }

    private var previewActionLabel: String {
        frameClient == nil ? NSLocalizedString("Resume Preview", comment: "")
                           : NSLocalizedString("Pause Preview", comment: "")
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
        guard snapshot.acceptsInput, let display = snapshot.retinaDisplay else { return }
        // The person's hand is the idle clock the window sleep reads (§353).
        lastActivity = Date()
        if case .scroll = gesture {
            activityClock.tracker.noteScroll(at: Date())
        } else {
            activityClock.tracker.noteChange(at: Date())
        }
        updateCaptureRate()
        input.configure(space: snapshot.space, display: display)
        input.setPointerRate(HostDisplayRefresh.pointerRate(for: hostWindow))
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
        lastActivity = Date()
        activityClock.tracker.notePress(active, at: Date())
        updateCaptureRate()
    }

    private func updateCaptureRate() {
        guard let frameClient else { return }
        let policy = InputRatePolicy(ceiling: previewFPS,
                                     pointerRate: HostDisplayRefresh.pointerRate(for: hostWindow))
        let target = policy.frames(for: activityClock.tracker.activity(at: Date()))
        guard liveFPS != target else { return }
        liveFPS = target
        frameClient.setFPS(target)
        input.setPointerRate(policy.pointerRate)
    }

}

/// Frame callbacks are frequent; changing this reference's value does not
/// invalidate the entire SwiftUI viewer for every arriving picture.
private final class ViewerActivityClock {
    var tracker = FrameActivityTracker()
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

/// The performance HUD, drawn by its own view.
///
/// The toggle used to live on the viewer itself as an `@AppStorage` the whole
/// `DesktopViewerView` body read, so flipping it — from inside the details
/// popover — re-evaluated the entire viewer: the live `RemoteSurfaceView`, its
/// capture coordinator, the cursor overlay's re-attach, all while the popover
/// was dismissing. The one reported window freeze followed exactly that path.
/// Both halves now observe the key on their own: a flip re-renders this
/// overlay and the popover's toggle row and nothing else, and the viewer's
/// body never reads the key at all.
private struct PerformanceHUDOverlay: View {
    @ObservedObject var client: FrameClient
    let input: RemoteViewerInput

    @AppStorage("desktopPerformanceHUD") private var shows = false

    var body: some View {
        if shows {
            VStack {
                HStack { Spacer(); hud }
                Spacer()
            }
            .allowsHitTesting(false)
        }
    }

    private var hud: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let metrics = client.performance
            let fps = FrameClock.uptime() - metrics.updatedAt > 2.5 ? 0 : metrics.framesPerSecond
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: NSLocalizedString("Frame %.0f FPS", comment: ""), fps))
                if let p50 = input.appliedMoveP50ms, let p95 = input.appliedMoveP95ms {
                    Text(String(format: NSLocalizedString("Move p50 %.1f / p95 %.1f ms", comment: ""), p50, p95))
                }
                if let p50 = input.appliedInputP50ms, let p95 = input.appliedInputP95ms {
                    Text(String(format: NSLocalizedString("Input p50 %.1f / p95 %.1f ms", comment: ""), p50, p95))
                }
                if let p50 = metrics.captureToRenderP50, let p95 = metrics.captureToRenderP95 {
                    Text(String(format: NSLocalizedString("Frame p50 %.1f / p95 %.1f ms", comment: ""), p50, p95))
                }
                if let render = metrics.receiveToRenderP50 {
                    Text(String(format: NSLocalizedString("Render p50 %.1f ms", comment: ""), render))
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white)
            .padding(9)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
            .padding(12)
        }
    }
}

/// The HUD's toggle, isolated for the same reason: it observes the key itself,
/// so flipping it never invalidates the view that hosts the popover, let alone
/// the live surface underneath it.
private struct PerformanceHUDToggle: View {
    @AppStorage("desktopPerformanceHUD") private var shows = false

    var body: some View {
        Toggle("Performance HUD", isOn: $shows)
    }
}
