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
        // `SCWindow.frame` is in points, so a 1:1 buffer on a Retina panel
        // halves the resolution of everything small enough to matter — menu
        // text, 12 pt body copy. Ask for the panel's pixel size instead.
        let backingScale = Self.pixelsPerPoint(for: window.frame)
        configuration.width = max(1, Int(window.frame.width) * backingScale)
        configuration.height = max(1, Int(window.frame.height) * backingScale)
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

    /// Backing scale of the display this window sits on. `CGDisplayBounds` and
    /// the captured window frame share the top-left global space, so the frame
    /// can be compared with the displays directly; the busiest overlap wins.
    /// Same pixel-over-points probe `ScreenCaptureFrameSource` uses, so a
    /// mirrored or scaled panel reports what it actually encodes.
    private static func pixelsPerPoint(for frame: CGRect) -> Int {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return 1 }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return 1 }
        let visible = displays.filter { CGDisplayIsActive($0) != 0 }
        guard let best = (visible.isEmpty ? displays : visible).max(by: {
            area(CGDisplayBounds($0).intersection(frame)) > area(CGDisplayBounds($1).intersection(frame))
        }), let mode = CGDisplayCopyDisplayMode(best) else { return 1 }
        return max(1, mode.pixelWidth / max(1, mode.width))
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        max(0, rect.width) * max(0, rect.height)
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
