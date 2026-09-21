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
        self.engine = CaptureEngine(target: configuration.target, targetWidth: configuration.targetPixelWidth, targetHeight: configuration.targetPixelHeight, maxFPS: configuration.maxFPS) { [weak router] surface in router?.receive(surface) }
        self.router.invalidSession = { [weak engine] in DispatchQueue.global().async { engine?.stop() } }
        let dimensions = try engine.start()
        try shared.prepare(width: dimensions.width, height: dimensions.height)
        try router.prepare(width: dimensions.width, height: dimensions.height)
    }

    deinit { engine.stop() }
    func stop() { engine.stop(); shared.detach() }
    var mappingBytes: Int { shared.mappingBytes }
}

private final class FrameSurfaceRouter {
    private let shared: SharedFramePublisher
    private let preference: FramePreference
    private let fps: Int
    private var mode = FrameModeController()
    private var encoder: VideoToolboxEncoder?
    private var lastTime = DispatchTime.now().uptimeNanoseconds
    private var firstVideo = true
    private let sessionVerdict: () -> SessionVerdict
    var invalidSession: (() -> Void)?
    private var invalidated = false

    init(shared: SharedFramePublisher, preference: FramePreference, fps: Int, sessionVerdict: @escaping () -> SessionVerdict) { self.shared = shared; self.preference = preference; self.fps = fps; self.sessionVerdict = sessionVerdict }
    func prepare(width: Int, height: Int) throws {
        let encoder = VideoToolboxEncoder { [weak shared] data, timestamp in shared?.sendVideo(data, width: width, height: height, timestamp: timestamp) }
        try encoder.activate(width: width, height: height, fps: fps); self.encoder = encoder
    }
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
        let now = DispatchTime.now().uptimeNanoseconds; let elapsed = Double(now - lastTime) / 1_000_000_000; lastTime = now
        let selected: FrameDeliveryMode
        switch preference { case .delta: selected = .delta; case .video: selected = .video; case .auto: selected = mode.observe(damageRatio: ratio, elapsed: elapsed) }
        if selected == .video {
            encoder?.encode(surface.pixelBuffer, timestamp: surface.timestampNanoseconds, forceKeyFrame: firstVideo); firstVideo = false
        } else {
            if !firstVideo { shared.requestFull(); firstVideo = true }
            shared.receive(surface)
        }
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

    func close(_ id: UUID) {
        lock.lock(); let stream = streams.removeValue(forKey: id); lock.unlock(); stream?.stop()
    }

    func stopAll() {
        lock.lock(); let all = Array(streams.values); streams.removeAll(); lock.unlock(); all.forEach { $0.stop() }
    }
}
