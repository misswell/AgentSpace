import Foundation
import AgentSpaceCore

final class WindowStreamManager {
    private let lock = NSLock()
    private var streams: [WindowIdentity: PreviewController] = [:]

    func start(window: RemoteWindow, maxFPS: Int) throws -> Int {
        lock.lock()
        if let existing = streams[window.identity] {
            lock.unlock()
            return try existing.start(maxFPS: maxFPS)
        }

        let identity = window.identity
        let controller = PreviewController(idleTimeout: 10) { _ in
            WindowCaptureFrameSource(windowID: identity.windowID, pid: identity.pid)
        }
        streams[identity] = controller
        lock.unlock()

        // Publish before starting so frame/stop can find the controller while
        // ScreenCaptureKit performs its synchronous discovery. PreviewController
        // serializes concurrent starts for this identity; importantly, a failed
        // starter does not remove the shared controller after a waiting starter
        // has successfully brought it up. The empty controller is harmless and
        // can be retried or removed by stop/stopAll.
        return try controller.start(maxFPS: maxFPS)
    }

    func frame(identity: WindowIdentity, verdict: SessionVerdict) throws -> Data? {
        lock.lock(); let controller = streams[identity]; lock.unlock()
        guard let controller else {
            throw AgentSpaceError(code: .previewNotRunning, message: "no capture stream is running for this window")
        }
        guard controller.isRunning else {
            throw AgentSpaceError(code: .previewNotRunning, message: "no capture stream is running for this window")
        }
        do {
            return try controller.frame(sessionVerdict: verdict)
        } catch {
            stop(identity: identity)
            throw error
        }
    }

    func stop(identity: WindowIdentity) {
        lock.lock(); let controller = streams.removeValue(forKey: identity); lock.unlock()
        controller?.stop()
    }

    func stopAll() {
        lock.lock(); let active = Array(streams.values); streams.removeAll(); lock.unlock()
        active.forEach { $0.stop() }
    }
}
