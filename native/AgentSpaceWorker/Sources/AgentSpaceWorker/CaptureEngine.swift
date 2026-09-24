import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit
import AgentSpaceCore

/// One ScreenCaptureKit implementation shared by Desktop and Fusion. Its
/// output is always BGRA CVPixelBuffer plus damage metadata—never JPEG.
final class CaptureEngine: NSObject {
    typealias Handler = (CapturedSurface) -> Void

    /// How a capture ended, which is the difference between a desktop that is
    /// still and a stream that is gone.
    enum Termination: Equatable {
        /// We asked for it to stop, or it was never running.
        case stopped
        /// ScreenCaptureKit ended the stream itself — the window closed, the
        /// display went away, the session lost the WindowServer. Nothing about
        /// the socket says so, which is why this has to be reported.
        case failed(AgentSpaceError)
    }

    private let target: CaptureTarget
    private let targetWidth: Int
    private let targetHeight: Int
    private let handler: Handler
    private let terminationHandler: (Termination) -> Void
    private let lock = NSLock()
    private var stream: SCStream?
    private var reportedFailure = false
    private var sequence: UInt64 = 0
    /// The rate in force. Kept as state rather than as `let`, because changing
    /// the frame rate must not rebuild the stream: the capture is the same
    /// display at the same size, and only the interval between samples moved.
    private var maxFPS: Int

    /// What a capture resolved to, and what it was resolved from.
    ///
    /// The buffer size is what the stream runs at, so it is the number the whole
    /// pipeline downstream is sized by. The subject's own pixel size and the
    /// ceiling are carried beside it because "the picture is soft" has two
    /// different causes — a request smaller than the source, or a deliberate cut
    /// by the frame budget — and a report that only knows the first cannot tell
    /// them apart.
    struct Geometry: Equatable {
        var width: Int
        var height: Int
        var naturalWidth: Int
        var naturalHeight: Int
        /// The subject's pixels per point, as the capture read it. `1` for a
        /// window whose panel is not HiDPI, and for any window the display
        /// selection could not place.
        var sourceScale: Int
        var capped: Bool
    }

    init(target: CaptureTarget, targetWidth: Int, targetHeight: Int, maxFPS: Int,
         handler: @escaping Handler, onTermination: @escaping (Termination) -> Void = { _ in }) {
        self.target = target; self.targetWidth = targetWidth; self.targetHeight = targetHeight
        self.maxFPS = max(1, min(60, maxFPS)); self.handler = handler; self.terminationHandler = onTermination
    }

    func start() throws -> Geometry {
        let semaphore = DispatchSemaphore(value: 0)
        var content: SCShareableContent?, discoveryError: Error?
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content = $0; discoveryError = $1; semaphore.signal() }
        guard semaphore.wait(timeout: .now() + 10) == .success else { throw AgentSpaceError(code: .noWindowServer, message: "ScreenCaptureKit discovery timed out") }
        if let discoveryError { throw AgentSpaceError(code: .noWindowServer, message: "ScreenCaptureKit discovery failed: \(discoveryError)") }
        guard let content else { throw AgentSpaceError(code: .noWindowServer, message: "ScreenCaptureKit returned no shareable content") }

        let filter: SCContentFilter
        let naturalWidth: Int, naturalHeight: Int, sourceScale: Int
        switch target {
        case .display, .retinaDesktop:
            // A pinned display id goes stale across sleep and re-enumeration, and
            // the viewer's intent is "the session's Retina display" — so a missing
            // id re-resolves to that role rather than stranding the stream (§336
            // row 965). Absent entirely, the refusal is the same as before.
            let resolvedID: UInt32
            switch target {
            case .retinaDesktop:
                resolvedID = CGMainDisplayID()
            case .display(let requestedID):
                resolvedID = requestedID.flatMap { id in
                    content.displays.contains(where: { $0.displayID == id })
                        ? id : ScreenCapture.retinaViewerDisplay()?.id
                } ?? CGMainDisplayID()
            case .window:
                fatalError("the window target is handled below")
            }
            guard let display = content.displays.first(where: { $0.displayID == resolvedID }) else {
                throw AgentSpaceError(code: .noWindowServer, message: "the requested display is not available in this Aqua session")
            }
            filter = SCContentFilter(display: display, excludingWindows: [])
            // `SCDisplay.width/height` are **points** while an
            // `SCStreamConfiguration` is in pixels, so reading the point size as
            // the pixel size asks for half the resolution on any HiDPI display —
            // and this branch was the last place doing it. Read on this machine:
            // the agent session's second display reports 1512×982 points over
            // 3024×1964 pixels, so the point-sized capture held a quarter of the
            // pixels the display was drawing and the viewer scaled them back up
            // (`docs/validation.md` §320 row 837 is the same request read from the
            // other end). The window path has gone through `DisplayScales` since
            // it was written; a display is the same question with a wider subject.
            sourceScale = DisplayScales.pixelsPerPoint(of: display.displayID)
            naturalWidth = max(1, display.width * sourceScale)
            naturalHeight = max(1, display.height * sourceScale)
        case .window(let identity):
            guard let window = content.windows.first(where: { $0.windowID == identity.windowID && $0.owningApplication?.processID == identity.pid }) else {
                throw AgentSpaceError(code: .badRequest, message: "the requested Fusion window is no longer capturable")
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            // `SCWindow.frame` is in points. The panel that actually holds most
            // of the window decides how many pixels a point is worth, because a
            // fixed 2 halves everything on a 1x panel and a fixed 1 blurs menu
            // text on a Retina one — and a window that straddles both has to
            // pick one of them, which is the same decision the legacy window
            // stream already made through `DisplayScaleSelection`.
            let scale = DisplayScales.pixelsPerPoint(for: window.frame)
            sourceScale = scale
            naturalWidth = max(1, Int(window.frame.width) * scale)
            naturalHeight = max(1, Int(window.frame.height) * scale)
        }

        // The subject's aspect wins over the requested box, because a buffer shaped
        // unlike its subject arrives with the picture floating between black pillars
        // and nothing downstream can see them. See `CaptureSizing` — and the pixel
        // ceiling beside it, which is the frame budget's answer rather than a
        // guess at what a display can be.
        let plan = CaptureSizing.planned(naturalWidth: naturalWidth, naturalHeight: naturalHeight,
                                        targetWidth: targetWidth, targetHeight: targetHeight)
        let (width, height) = (plan.width, plan.height)
        let geometry = Geometry(width: width, height: height,
                                naturalWidth: naturalWidth, naturalHeight: naturalHeight,
                                sourceScale: sourceScale, capped: plan.capped)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, width); configuration.height = max(1, height)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(maxFPS))
        configuration.queueDepth = 2; configuration.scalesToFit = true
        configuration.showsCursor = _showsCursor
        lock.lock(); lastWidth = max(1, width); lastHeight = max(1, height); lock.unlock()
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: BundleIdentifiers.worker + ".capture-engine"))
        lock.lock(); self.stream = stream; self.reportedFailure = false; lock.unlock()
        let started = DispatchSemaphore(value: 0); var startError: Error?
        stream.startCapture { startError = $0; started.signal() }
        guard started.wait(timeout: .now() + 10) == .success else { stop(); throw AgentSpaceError(code: .noWindowServer, message: "ScreenCaptureKit start timed out") }
        if let startError { stop(); throw AgentSpaceError(code: .screenRecordingDenied, message: "ScreenCaptureKit failed to start: \(startError)") }
        // One line per stream, at the moment the size is decided and nowhere else.
        // Every "the picture is not sharp" question resolves here: this is the size
        // the buffer is built at, the size the subject actually has, and whether a
        // ceiling moved it.
        Log.capture.info("frame stream capturing \(width)x\(height) of a \(naturalWidth)x\(naturalHeight) \(target.kindDescription) at \(sourceScale)x\(plan.capped ? " (capped by the frame budget)" : "")")
        return geometry
    }

    func stop() {
        lock.lock(); let stream = self.stream; self.stream = nil; lock.unlock()
        guard let stream else { return }
        let stopped = DispatchSemaphore(value: 0); stream.stopCapture { _ in stopped.signal() }; _ = stopped.wait(timeout: .now() + 5)
        terminationHandler(.stopped)
    }

    /// Change the capture rate without touching anything else.
    ///
    /// `SCStream.updateConfiguration` applies a new `minimumFrameInterval` to the
    /// running stream. The alternative — closing and reopening — would rebuild
    /// the shared-memory region, hand the viewer a new descriptor and restart the
    /// decoder, all to move a number that the stream already knows how to change:
    /// measured cost of the naive version was one full reconnect per rate change,
    /// and the desktop viewer changes rate whenever a button goes down.
    ///
    /// Returns the rate now in force, which is what the caller reports.
    @discardableResult
    func updateFrameRate(_ fps: Int) -> Int {
        let clamped = max(1, min(60, fps))
        lock.lock()
        let stream = self.stream
        let previous = maxFPS
        if clamped != previous { maxFPS = clamped }
        lock.unlock()
        guard let stream, clamped != previous else { return clamped }
        let configuration = SCStreamConfiguration()
        configuration.width = lastWidth
        configuration.height = lastHeight
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(clamped))
        configuration.queueDepth = 2
        configuration.showsCursor = showsCursor
        configuration.scalesToFit = true
        let applied = DispatchSemaphore(value: 0)
        var failure: Error?
        stream.updateConfiguration(configuration) { error in failure = error; applied.signal() }
        // Bounded wait: an update that never returns must not park the frame
        // publisher's queue, which is where this is called from.
        _ = applied.wait(timeout: .now() + 2)
        if let failure {
            Log.capture.error("frame stream could not change its rate to \(clamped) FPS (\(failure)), staying at \(previous)")
            lock.lock(); maxFPS = previous; lock.unlock()
            return previous
        }
        Log.capture.info("frame stream rate is now \(clamped) FPS")
        return clamped
    }

    /// Whether the capture paints the session's cursor into the picture.
    ///
    /// Turned off only once the worker has proved it can publish a cursor of its
    /// own over the input channel (`CursorStateProvider.shapesAvailable`).
    /// Turning it off earlier would be a desktop with no pointer at all, which is
    /// worse than a lagging one.
    var showsCursor: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _showsCursor }
        set {
            lock.lock(); let changed = _showsCursor != newValue; _showsCursor = newValue; lock.unlock()
            guard changed else { return }
            updateFrameRate(maxFPS)
            Log.capture.info("capture cursor painting is now \(newValue ? "on" : "off")")
        }
    }

    /// The size the running stream was started at, needed to build a
    /// configuration for an update. Written once in `start()`.
    private var lastWidth = 1
    private var lastHeight = 1
    private var _showsCursor = true
}

extension CaptureEngine: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer), CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return }
        let capture = FrameSignpost.begin("Capture")
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        sequence &+= 1
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let timestamp = pts.isValid ? UInt64(max(0, CMTimeGetSeconds(pts)) * 1_000_000_000) : DispatchTime.now().uptimeNanoseconds
        let damage = FrameSignpost.begin("DamageExtract")
        let regions = DirtyRegionExtractor.regions(from: sampleBuffer, outputWidth: width, outputHeight: height)
        FrameSignpost.end(damage)
        FrameSignpost.end(capture)
        FrameSignpost.event("Captured", Int(min(sequence, UInt64(Int.max))))
        handler(.init(pixelBuffer: buffer, sequence: sequence, width: width, height: height, dirtyRects: regions, timestampNanoseconds: timestamp))
    }
}

extension CaptureEngine: SCStreamDelegate {
    /// ScreenCaptureKit ended the stream on its own. The frame socket is still
    /// open and the viewer is still showing whatever it last received, so the
    /// only thing that can say "this picture is not the desktop now" is this
    /// callback — and it has to say it somewhere else, because a WindowServer
    /// delegate callback is not a place to do teardown work: ScreenCaptureKit
    /// will wait for it to return.
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock()
        self.stream = nil
        let alreadyReported = reportedFailure
        reportedFailure = true
        lock.unlock()
        guard !alreadyReported else { return }
        let termination = Termination.failed(AgentSpaceError(
            code: .captureStreamFailed,
            message: "ScreenCaptureKit stopped the capture stream: \(error.localizedDescription)"))
        // The handler is captured, not `self`: a stream that died while its owner
        // was letting go still has to tell the viewer why the picture stopped.
        DispatchQueue.global().async { [terminationHandler] in terminationHandler(termination) }
    }
}
