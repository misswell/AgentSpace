import AppKit
import CoreImage
import Foundation
import ScreenCaptureKit
import AgentSpaceCore

/// ScreenCaptureKit adapter for one desktop-independent application window.
final class WindowCaptureFrameSource: NSObject, PreviewFrameSource {
    private let windowID: UInt32
    private let pid: Int32
    private let lock = NSLock()
    private var stream: SCStream?
    private var latest: Data?
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    init(windowID: UInt32, pid: Int32) {
        self.windowID = windowID
        self.pid = pid
    }

    func start(maxFPS: Int) throws {
        let discovery = DispatchSemaphore(value: 0)
        var content: SCShareableContent?
        var discoveryError: Error?
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { value, error in
            content = value
            discoveryError = error
            discovery.signal()
        }
        guard discovery.wait(timeout: .now() + 10) == .success else {
            throw AgentSpaceError(code: .noWindowServer, message: "ScreenCaptureKit did not return the window list within 10s.")
        }
        if let discoveryError {
            throw AgentSpaceError(code: .noWindowServer, message: "could not discover windows: \(discoveryError)")
        }
        guard let window = content?.windows.first(where: {
            $0.windowID == windowID && $0.owningApplication?.processID == pid
        }) else {
            throw AgentSpaceError(code: .badRequest, message: "window \(windowID) is no longer capturable")
        }

        let configuration = SCStreamConfiguration()
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, maxFPS)))
        configuration.queueDepth = 2
        configuration.showsCursor = true
        configuration.width = max(1, Int(window.frame.width))
        configuration.height = max(1, Int(window.frame.height))
        configuration.scalesToFit = true

        let stream = SCStream(
            filter: SCContentFilter(desktopIndependentWindow: window),
            configuration: configuration,
            delegate: self)
        // Publish ownership before the asynchronous start. If the wait times
        // out, PreviewController's failure cleanup can still stop this exact
        // stream even when ScreenCaptureKit completes late.
        lock.lock(); self.stream = stream; lock.unlock()
        try stream.addStreamOutput(
            self, type: .screen,
            sampleHandlerQueue: DispatchQueue(label: BundleIdentifiers.worker + ".window-capture.\(windowID)"))

        let started = DispatchSemaphore(value: 0)
        var startError: Error?
        stream.startCapture { error in startError = error; started.signal() }
        guard started.wait(timeout: .now() + 10) == .success else {
            throw AgentSpaceError(code: .noWindowServer, message: "window capture did not start within 10s")
        }
        if let startError {
            throw AgentSpaceError(code: .screenRecordingDenied, message: "window capture failed: \(startError)")
        }
    }

    func stop() {
        lock.lock()
        let stream = self.stream
        self.stream = nil
        latest = nil
        lock.unlock()
        guard let stream else { return }
        let stopped = DispatchSemaphore(value: 0)
        stream.stopCapture { _ in stopped.signal() }
        _ = stopped.wait(timeout: .now() + 5)
    }

    var latestFrame: Data? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }
}

extension WindowCaptureFrameSource: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(image, from: image.extent),
              let data = NSBitmapImageRep(cgImage: cgImage).representation(
                using: .jpeg, properties: [.compressionFactor: 0.58]) else { return }
        lock.lock(); latest = data; lock.unlock()
    }
}

extension WindowCaptureFrameSource: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock(); self.stream = nil; latest = nil; lock.unlock()
    }
}
