import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit
import AgentSpaceCore

/// One ScreenCaptureKit implementation shared by Desktop and Fusion. Its
/// output is always BGRA CVPixelBuffer plus damage metadata—never JPEG.
final class CaptureEngine: NSObject {
    typealias Handler = (CapturedSurface) -> Void

    private let target: CaptureTarget
    private let targetWidth: Int
    private let targetHeight: Int
    private let maxFPS: Int
    private let handler: Handler
    private let lock = NSLock()
    private var stream: SCStream?
    private var sequence: UInt64 = 0

    init(target: CaptureTarget, targetWidth: Int, targetHeight: Int, maxFPS: Int, handler: @escaping Handler) {
        self.target = target; self.targetWidth = targetWidth; self.targetHeight = targetHeight
        self.maxFPS = max(1, min(60, maxFPS)); self.handler = handler
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
            naturalWidth = max(1, Int(window.frame.width) * 2); naturalHeight = max(1, Int(window.frame.height) * 2)
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
        lock.lock(); self.stream = stream; lock.unlock()
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
    }
}

extension CaptureEngine: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer), CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        sequence &+= 1
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let timestamp = pts.isValid ? UInt64(max(0, CMTimeGetSeconds(pts)) * 1_000_000_000) : DispatchTime.now().uptimeNanoseconds
        handler(.init(pixelBuffer: buffer, sequence: sequence, width: width, height: height, dirtyRects: DirtyRegionExtractor.regions(from: sampleBuffer, outputWidth: width, outputHeight: height), timestampNanoseconds: timestamp))
    }
}

extension CaptureEngine: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) { lock.lock(); self.stream = nil; lock.unlock() }
}
