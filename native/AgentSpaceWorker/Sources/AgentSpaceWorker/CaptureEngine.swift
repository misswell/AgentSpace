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
    private let maxFPS: Int
    private let handler: Handler
    private let terminationHandler: (Termination) -> Void
    private let lock = NSLock()
    private var stream: SCStream?
    private var reportedFailure = false
    private var sequence: UInt64 = 0

    init(target: CaptureTarget, targetWidth: Int, targetHeight: Int, maxFPS: Int,
         handler: @escaping Handler, onTermination: @escaping (Termination) -> Void = { _ in }) {
        self.target = target; self.targetWidth = targetWidth; self.targetHeight = targetHeight
        self.maxFPS = max(1, min(60, maxFPS)); self.handler = handler; self.terminationHandler = onTermination
    }

    func start() throws -> (width: Int, height: Int) {
        let semaphore = DispatchSemaphore(value: 0)
        var content: SCShareableContent?, discoveryError: Error?
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content = $0; discoveryError = $1; semaphore.signal() }
        guard semaphore.wait(timeout: .now() + 10) == .success else { throw AgentSpaceError(code: .noWindowServer, message: "ScreenCaptureKit discovery timed out") }
        if let discoveryError { throw AgentSpaceError(code: .noWindowServer, message: "ScreenCaptureKit discovery failed: \(discoveryError)") }
        guard let content else { throw AgentSpaceError(code: .noWindowServer, message: "ScreenCaptureKit returned no shareable content") }

        let filter: SCContentFilter
        let naturalWidth: Int, naturalHeight: Int
        switch target {
        case .display(let requestedID):
            guard let display = content.displays.first(where: { requestedID == nil || $0.displayID == requestedID! }) else {
                throw AgentSpaceError(code: .noWindowServer, message: "the requested display is not available in this Aqua session")
            }
            filter = SCContentFilter(display: display, excludingWindows: [])
            naturalWidth = display.width; naturalHeight = display.height
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
            naturalWidth = max(1, Int(window.frame.width) * scale)
            naturalHeight = max(1, Int(window.frame.height) * scale)
        }

        let width: Int, height: Int
        if targetWidth > 0, targetHeight == 0 {
            width = targetWidth; height = max(1, naturalHeight * targetWidth / max(1, naturalWidth))
        } else if targetHeight > 0, targetWidth == 0 {
            height = targetHeight; width = max(1, naturalWidth * targetHeight / max(1, naturalHeight))
        } else {
            width = targetWidth > 0 ? targetWidth : naturalWidth
            height = targetHeight > 0 ? targetHeight : naturalHeight
        }
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, width); configuration.height = max(1, height)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(maxFPS))
        configuration.queueDepth = 2; configuration.showsCursor = true; configuration.scalesToFit = true
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: BundleIdentifiers.worker + ".capture-engine"))
        lock.lock(); self.stream = stream; self.reportedFailure = false; lock.unlock()
        let started = DispatchSemaphore(value: 0); var startError: Error?
        stream.startCapture { startError = $0; started.signal() }
        guard started.wait(timeout: .now() + 10) == .success else { stop(); throw AgentSpaceError(code: .noWindowServer, message: "ScreenCaptureKit start timed out") }
        if let startError { stop(); throw AgentSpaceError(code: .screenRecordingDenied, message: "ScreenCaptureKit failed to start: \(startError)") }
        return (width, height)
    }

    func stop() {
        lock.lock(); let stream = self.stream; self.stream = nil; lock.unlock()
        guard let stream else { return }
        let stopped = DispatchSemaphore(value: 0); stream.stopCapture { _ in stopped.signal() }; _ = stopped.wait(timeout: .now() + 5)
        terminationHandler(.stopped)
    }
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
