import Foundation
import AgentSpaceCore

final class WindowStreamManager {
    private let lock = NSLock()
    private var streams: [WindowIdentity: PreviewController] = [:]

    func start(window: RemoteWindow, maxFPS: Int) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        if let existing = streams[window.identity] {
            return try existing.start(maxFPS: maxFPS)
        }

        let identity = window.identity
        let controller = PreviewController(idleTimeout: 10) { _ in
            WindowCaptureFrameSource(windowID: identity.windowID, pid: identity.pid)
        }
        // Do not publish a controller until its source is running. Keeping the
        // manager lock through start also makes concurrent starts for the same
        // identity linear: a failed starter cannot remove a later successful
        // stream, and every published stream remains reachable by frame/stop.
        let configuredFPS = try controller.start(maxFPS: maxFPS)
        streams[identity] = controller
        return configuredFPS
    }

    func frame(identity: WindowIdentity, verdict: SessionVerdict) throws -> Data? {
        lock.lock(); let controller = streams[identity]; lock.unlock()
        guard let controller else {
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
