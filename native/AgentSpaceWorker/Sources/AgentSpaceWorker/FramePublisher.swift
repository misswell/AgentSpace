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
        let geometry = try engine.start()
        try shared.prepare(width: geometry.width, height: geometry.height)
        shared.noteCaptureCapped(geometry.capped)
        router.prepare(width: geometry.width, height: geometry.height)
    }

    deinit { engine.stop() }
    func stop() { engine.stop(); shared.detach() }

    /// The rate in force. Reported so a caller that asked for one rate and got
    /// another can see which it got.
    @discardableResult
    func updateFrameRate(_ fps: Int) -> Int { engine.updateFrameRate(fps) }

    /// Whether the capture paints the session cursor into the picture. Turned off
    /// only after the input channel has proved it can publish one of its own.
    func setCursorPainting(_ enabled: Bool) { engine.showsCursor = enabled }
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
    private var lastTaken: FrameDeliveryMode?
    /// What the video path can offer right now: the fallback to delta, the
    /// cooldown after a failure, and the count of them. See `FrameEncoderAccess`
    /// — an encoder that cannot be created is a reason to send pixels, not a
    /// reason to stop the stream.
    private var encoderAccess = FrameEncoderAccess()
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
        shared.noteCaptured(damageRatio: ratio)
        let now = FrameClock.uptime(); let elapsed = now - lastTime; lastTime = now
        let requested: FrameDeliveryMode
        switch preference { case .delta: requested = .delta; case .video: requested = .video; case .auto: requested = mode.observe(damageRatio: ratio, elapsed: elapsed) }
        // Which path this frame actually takes. The two can differ: a video frame
        // with no usable encoder is a delta frame, and pretending otherwise is how
        // a stream ends up with neither — no H.264, no shared pixels, a frozen
        // picture behind a heartbeat that looks alive.
        let taken = encoderAccess.path(for: requested, opening: createEncoder, at: now)
        if taken != lastTaken {
            let previous = lastTaken
            lastTaken = taken
            shared.noteModeSwitch()
            shared.setFrameMode(taken)
            // A sequence resumed after a stretch of shared pixels has nothing to
            // continue from; the delta side needs its own baseline for the same
            // reason, because the shared buffer has been holding whatever was
            // written before the video stretch, not what is on screen now.
            if previous == .video { shared.requireKeyFrame(); shared.requestFull() }
        }
        if taken == .video, let encoder {
            // The encoder call itself is asynchronous; what this interval can
            // honestly measure is the cost of handing a frame to VideoToolbox,
            // which is the part that sits on the capture callback's thread.
            let encode = FrameSignpost.begin("H264Encode")
            switch encoder.encode(surface.pixelBuffer, timestamp: surface.timestampNanoseconds, forceKeyFrame: shared.needsKeyFrame) {
            case .submitted: break
            case .busy:
                // The frame never entered the codec. Counting it is the point:
                // without this the video path can drop half of a desktop's
                // frames while every number that describes it keeps rising.
                shared.noteFrameDropped()
            case let .failed(status):
                // VideoToolbox said no to this frame, which says something about
                // the session that produced it. It is not retried per frame — the
                // next failure of the same kind is what the cooldown counts.
                Log.capture.error("frame stream \(shared.streamID) could not encode a frame (OSStatus \(status))")
            }
            FrameSignpost.end(encode)
        } else {
            releaseEncoder()
            shared.receive(surface)
        }
    }

    /// Creates the encoder the video path asked for and says whether it exists.
    ///
    /// `false` carries a consequence the caller acts on: `FrameEncoderAccess`
    /// turns the frame into a delta one and the surface goes down the shared path
    /// instead, so a machine without a usable VideoToolbox still shows its
    /// desktop. An error message and a comment about the fallback being available
    /// are not the fallback.
    private func createEncoder() -> Bool {
        if encoder != nil { return true }
        guard let format = videoFormat else { return false }
        let created = VideoToolboxEncoder { [weak shared] data, timestamp, isKeyFrame in
            shared?.sendVideo(data, width: format.width, height: format.height, capturedAt: timestamp, isKeyFrame: isKeyFrame)
        }
        do {
            try created.activate(width: format.width, height: format.height, fps: fps)
            encoder = created
            shared.noteEncoder(active: true)
            return true
        } catch {
            // Counted rather than absorbed: a stream that never once encodes
            // looks identical to one that does not need to, and only this number
            // says the machine was asked and could not.
            shared.noteEncoderFailure()
            Log.capture.error("frame stream \(shared.streamID) could not activate the H.264 encoder (\(error)), delivering shared frames until it can be asked again")
            return false
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
    private let retinaDesktop: RetinaDesktopLayout
    private let memoryBudget = 256 * 1024 * 1024
    let workerInstanceID = UUID()
    let sessionGeneration = DispatchTime.now().uptimeNanoseconds
    /// The most recent frame stream this worker could not open, and why.
    ///
    /// Kept on the manager rather than on the stream because a stream that never
    /// started has nothing to ask. Without it, `frame.stats` on a desktop with no
    /// picture answers "zero streams, nothing failed", and the one number that
    /// explains the empty window is in a log file the GUI cannot read.
    private var lastAllocationFailure: SharedFrameAllocationFailure?

    init(context: WorkerContext) {
        self.context = context
        retinaDesktop = RetinaDesktopLayout(runtimeDirectory: context.paths.directory)
        retinaDesktop.recoverIfNeeded()
    }

    func open(_ configuration: FrameOpenConfiguration) throws -> FramePublisher {
        let usesRetinaDesktop = configuration.target == .retinaDesktop
        if usesRetinaDesktop { try retinaDesktop.acquire() }
        let publisher: FramePublisher
        do {
            publisher = try FramePublisher(configuration: configuration, context: context)
        } catch let failure as SharedFrameAllocationError {
            if usesRetinaDesktop { retinaDesktop.release() }
            lock.lock(); lastAllocationFailure = failure.failure; lock.unlock()
            throw failure.agentSpaceError
        } catch {
            if usesRetinaDesktop { retinaDesktop.release() }
            throw error
        }
        lock.lock()
        let total = streams.values.reduce(publisher.mappingBytes) { $0 + $1.mappingBytes }
        guard total <= memoryBudget else {
            lock.unlock(); publisher.stop()
            if usesRetinaDesktop { retinaDesktop.release() }
            throw AgentSpaceError(code: .internalError, message: "frame streams would exceed the 256 MB shared-memory budget")
        }
        streams[publisher.streamID] = publisher; lock.unlock()
        return publisher
    }

    /// Read under the manager's lock, never written after this point in the
    /// stream's life — the value a diagnostic reader wants is the last one.
    func recentAllocationFailure() -> SharedFrameAllocationFailure? {
        lock.lock(); defer { lock.unlock() }
        return lastAllocationFailure
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
        lock.lock(); let stream = streams.removeValue(forKey: id); lock.unlock()
        stream?.stop()
        if stream?.target == .retinaDesktop { retinaDesktop.release() }
    }

    func stopAll() {
        lock.lock(); let all = Array(streams.values); streams.removeAll(); lock.unlock()
        all.forEach { stream in
            stream.stop()
            if stream.target == .retinaDesktop { retinaDesktop.release() }
        }
    }
}
