import Foundation
import ScreenCaptureKit
import CoreImage
import AppKit
import AgentSpaceCore

/// The real §52 frame source: a ScreenCaptureKit stream over the worker's own
/// session's main display, keeping exactly one encoded frame.
///
/// This is the only ScreenCaptureKit code in the project, and it is thin on
/// purpose — the state machine lives in `PreviewController` (Core), which is
/// unit-tested with a fake source. What cannot be verified in this environment
/// (a background Aqua session holding a Screen Recording grant) is documented
/// in docs/validation.md rather than pretended away.
///
/// Fail-closed order matters and is enforced by `Operations` before this is
/// ever constructed: no console session, no missing grant. The stream itself
/// captures the *worker's own session by construction* — SCK sees what this
/// session's WindowServer composits, which after §54's fix is only ever asked
/// to run in a genuine background session.
final class ScreenCaptureFrameSource: NSObject, PreviewFrameSource {
    private let lock = NSLock()
    private var stream: SCStream?
    private var latest: Data?
    private var width = 0
    private var height = 0
    private var scale = 1
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    func start(maxFPS: Int) throws {
        // SCK's discovery and start are async; the worker's dispatch is
        // synchronous, so the two waits below are semaphores. The worker only
        // ever calls this from its RPC handler thread, and the waits are
        // bounded by SCK's own timeouts in practice — but the frame pull path
        // (the hot path) is lock-only, never waiting on SCK.
        let contentSemaphore = DispatchSemaphore(value: 0)
        var discovered: SCShareableContent?
        var discoveryError: Error?
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) {
            content, error in
            discovered = content
            discoveryError = error
            contentSemaphore.signal()
        }
        guard contentSemaphore.wait(timeout: .now() + 10) == .success else {
            throw AgentSpaceError(code: .noWindowServer, message: "ScreenCaptureKit did not report the session's windows within 10s.")
        }
        if let discoveryError {
            throw AgentSpaceError(code: .noWindowServer, message: "could not discover the session's displays: \(discoveryError)")
        }
        guard let display = discovered?.displays.first else {
            throw AgentSpaceError(code: .noWindowServer, message: "this session has no display to capture.")
        }

        // `CGDisplayPixelsWide` returns *points* on scaled displays — the trap
        // recorded in docs/validation.md — so the scale comes from the CG
        // display mode's pixel width over SCDisplay's point width.
        let cgID = CGDirectDisplayID(display.displayID)
        let pixelWidth = CGDisplayPixelsWide(cgID) // points
        let measuredScale: Int
        if let mode = CGDisplayCopyDisplayMode(cgID) {
            measuredScale = max(1, mode.pixelWidth / max(1, mode.width))
        } else {
            measuredScale = max(1, pixelWidth / max(1, display.width))
        }

        lock.lock()
        width = display.width
        height = display.height
        scale = measuredScale
        lock.unlock()

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, maxFPS)))
        configuration.queueDepth = 2
        configuration.showsCursor = true
        configuration.width = display.width
        configuration.height = display.height
        configuration.scalesToFit = false

        let stream = SCStream(
            filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: BundleIdentifiers.worker + ".preview"))
        // Publish ownership before the asynchronous start, as
        // `WindowCaptureFrameSource` does. Assigning only after `startCapture`
        // returns makes a timed-out start un-stoppable: `PreviewController`'s
        // failure cleanup calls `stop()`, which would find no stream and return,
        // leaving a live capture running once ScreenCaptureKit finished late.
        lock.lock(); self.stream = stream; lock.unlock()

        let startSemaphore = DispatchSemaphore(value: 0)
        var startError: Error?
        stream.startCapture { error in
            startError = error
            startSemaphore.signal()
        }
        guard startSemaphore.wait(timeout: .now() + 10) == .success else {
            throw AgentSpaceError(code: .noWindowServer, message: "ScreenCaptureKit did not start within 10s.")
        }
        if let startError {
            throw AgentSpaceError(code: .noWindowServer, message: "ScreenCaptureKit failed to start: \(startError)")
        }
    }

    func stop() {
        lock.lock()
        let stream = self.stream
        self.stream = nil
        latest = nil
        lock.unlock()
        guard let stream else { return }
        let semaphore = DispatchSemaphore(value: 0)
        stream.stopCapture { _ in semaphore.signal() }
        _ = semaphore.wait(timeout: .now() + 5)
    }

    var latestFrame: Data? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    /// Geometry of the encoded frames, for the client's coordinate mapping (§17).
    var frameGeometry: (width: Int, height: Int, scale: Int) {
        lock.lock(); defer { lock.unlock() }
        return (width, height, scale)
    }
}

extension ScreenCaptureFrameSource: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Frames arrive faster than anyone pulls them; encode only the newest
        // and let the rest go. JPEG at 0.5 is plenty for a preview and far
        // cheaper than PNG at 15 FPS.
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.5]) else { return }
        lock.lock()
        latest = data
        lock.unlock()
    }
}

extension ScreenCaptureFrameSource: SCStreamDelegate {
    /// A stream error (display reconfiguration, session teardown) stops the
    /// source rather than leaving it half-alive, and it drops the last frame: a
    /// dead stream that keeps serving its newest image is how a preview starts
    /// lying. The next `preview.frame` therefore reports no frame instead of a
    /// stale one, and `preview.start` after a failure rebuilds from scratch.
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock()
        self.stream = nil
        latest = nil
        lock.unlock()
    }
}
