import Foundation
import AgentSpaceCore

final class FramePublisher {
    let streamID: UUID
    let target: CaptureTarget
    let shared: SharedFramePublisher
    private(set) var engine: CaptureEngine!
    private let router: FrameSurfaceRouter

    init(configuration: FrameOpenConfiguration, context: WorkerContext) throws {
        self.streamID = UUID(); self.target = configuration.target
        self.shared = SharedFramePublisher(streamID: streamID)
        self.router = FrameSurfaceRouter(shared: shared, preference: configuration.preferredMode, fps: configuration.maxFPS, sessionVerdict: context.sessionVerdict)
        self.engine = CaptureEngine(target: configuration.target, targetWidth: configuration.targetPixelWidth, targetHeight: configuration.targetPixelHeight, maxFPS: configuration.maxFPS,
            handler: { [weak router] surface in router?.receive(surface) },
            // ScreenCaptureKit stopped on its own. The socket is still open and
            // the viewer is still showing the last frame it was given, so the
            // only thing that can end the pretence is this: close the
            // connection, let the client see the EOF and reconnect.
            onTermination: { [weak shared] termination in shared?.captureEnded(termination) })
        self.router.invalidSession = { [weak engine] in DispatchQueue.global().async { engine?.stop() } }
        let dimensions = try engine.start()
        try shared.prepare(width: dimensions.width, height: dimensions.height)
        router.prepare(width: dimensions.width, height: dimensions.height)
    }

    deinit { engine.stop() }
    func stop() { engine.stop(); shared.detach() }
    var mappingBytes: Int { shared.mappingBytes }
    func stats() -> FrameStats { shared.snapshot() }
}

/// Chooses the delivery path for each captured frame, and holds the encoder only
/// while that path needs one.
private final class FrameSurfaceRouter {
    private let shared: SharedFramePublisher
    private let preference: FramePreference
    private let fps: Int
    private var mode = FrameModeController()
    private var encoder: VideoToolboxEncoder?
    /// The shape an encoder would be created at, remembered without creating
    /// one. A `VTCompressionSession` is an allocation with hardware behind it,
    /// and a desktop plus five static Fusion windows would otherwise hold six of
    /// them to encode nothing at all.
    private var videoFormat: (width: Int, height: Int)?
    private var lastTime = FrameClock.uptime()
    private var lastSelected: FrameDeliveryMode?
    private var firstVideo = true
    private let sessionVerdict: () -> SessionVerdict
    var invalidSession: (() -> Void)?
    private var invalidated = false

    init(shared: SharedFramePublisher, preference: FramePreference, fps: Int, sessionVerdict: @escaping () -> SessionVerdict) { self.shared = shared; self.preference = preference; self.fps = fps; self.sessionVerdict = sessionVerdict }

    /// Records what a video path would need, and creates nothing.
    func prepare(width: Int, height: Int) { videoFormat = (width, height) }

    func receive(_ surface: CapturedSurface) {
        guard sessionVerdict() == .usable else {
            if !invalidated {
                invalidated = true
                shared.invalidateConnection()
                invalidSession?()
            }
            return
        }
        let area = max(1, surface.width * surface.height)
        let ratio = min(1, Double(surface.dirtyRects.reduce(UInt64(0)) { $0 + $1.area }) / Double(area))
        let now = FrameClock.uptime(); let elapsed = now - lastTime; lastTime = now
        let selected: FrameDeliveryMode
        switch preference { case .delta: selected = .delta; case .video: selected = .video; case .auto: selected = mode.observe(damageRatio: ratio, elapsed: elapsed) }
        if selected != lastSelected {
            lastSelected = selected
            shared.noteModeSwitch()
            shared.setFrameMode(selected)
        }
        if selected == .video {
            ensureEncoder()
            // The encoder call itself is asynchronous; what this interval can
            // honestly measure is the cost of handing a frame to VideoToolbox,
            // which is the part that sits on the capture callback's thread.
            let encode = FrameSignpost.begin("H264Encode")
            encoder?.encode(surface.pixelBuffer, timestamp: surface.timestampNanoseconds, forceKeyFrame: firstVideo)
            FrameSignpost.end(encode)
            firstVideo = false
        } else {
            if !firstVideo { shared.requestFull(); firstVideo = true }
            releaseEncoder()
            shared.receive(surface)
        }
    }

    private func ensureEncoder() {
        guard encoder == nil, let format = videoFormat else { return }
        let created = VideoToolboxEncoder { [weak shared] data, timestamp in
            shared?.sendVideo(data, width: format.width, height: format.height, capturedAt: timestamp)
        }
        do {
            try created.activate(width: format.width, height: format.height, fps: fps)
            encoder = created
            shared.noteEncoder(active: true)
        } catch {
            // The delta path stays available: an encoder that cannot start is a
            // reason to keep sending pixels, not a reason to stop the stream.
            encoder = nil
        }
    }

    /// Leaving the video path gives the session back. The next entry pays one
    /// activation and starts from a forced IDR, which is what a viewer that has
    /// been showing deltas since the last key frame needs anyway.
    private func releaseEncoder() {
        guard encoder != nil else { return }
        encoder?.invalidate()
        encoder = nil
        shared.noteEncoder(active: false)
    }
}

final class FrameManager {
    private let context: WorkerContext
    private let lock = NSLock()
    private var streams: [UUID: FramePublisher] = [:]
    private let memoryBudget = 256 * 1024 * 1024
    let workerInstanceID = UUID()
    let sessionGeneration = DispatchTime.now().uptimeNanoseconds

    init(context: WorkerContext) { self.context = context }

    func open(_ configuration: FrameOpenConfiguration) throws -> FramePublisher {
        let publisher = try FramePublisher(configuration: configuration, context: context)
        lock.lock()
        let total = streams.values.reduce(publisher.mappingBytes) { $0 + $1.mappingBytes }
        guard total <= memoryBudget else { lock.unlock(); publisher.stop(); throw AgentSpaceError(code: .internalError, message: "frame streams would exceed the 256 MB shared-memory budget") }
        streams[publisher.streamID] = publisher; lock.unlock()
        return publisher
    }

    func publisher(_ id: UUID) -> FramePublisher? { lock.lock(); defer { lock.unlock() }; return streams[id] }

    /// Every stream a viewer has open right now, in a stable order so two calls
    /// can be diffed. A diagnostic reader that did not open these streams cannot
    /// name them, which is why `frame.stats` accepts no stream at all.
    func live() -> [FramePublisher] {
        lock.lock(); let all = Array(streams.values); lock.unlock()
        return all.sorted { $0.streamID.uuidString < $1.streamID.uuidString }
    }

    func close(_ id: UUID) {
        lock.lock(); let stream = streams.removeValue(forKey: id); lock.unlock(); stream?.stop()
    }

    func stopAll() {
        lock.lock(); let all = Array(streams.values); streams.removeAll(); lock.unlock(); all.forEach { $0.stop() }
    }
}
