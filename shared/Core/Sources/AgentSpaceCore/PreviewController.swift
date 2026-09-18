import Foundation

/// The live Desktop Preview (plan §52, the upgrade over the 1 FPS MVP).
///
/// Pull model on purpose. The protocol is one request per connection, and a
/// push stream would either need a second socket or a protocol change; a pull
/// also fits §52's economics naturally — the client asks for frames only while
/// its viewer is open, the worker keeps at most one captured frame, and frames
/// captured faster than the client pulls are simply dropped (the *newest* one
/// wins, which is what a preview means).
///
/// The controller owns the state machine; the frame source is injected so the
/// whole lifecycle is testable without ScreenCaptureKit, a GPU, or a session.
/// The real source (`ScreenCaptureFrameSource`, worker target) is a thin
/// adapter and is where every unverifiable-here behaviour lives.
public protocol PreviewFrameSource: AnyObject {
    /// Begin capturing. Throws when capture cannot be set up at all — no
    /// WindowServer, no grant — so the caller can surface the typed code.
    func start(maxFPS: Int) throws

    /// Stop capturing and release everything. Must be idempotent.
    func stop()

    /// The newest captured frame, already encoded, or nil before the first
    /// frame arrives. Reading it must be safe from any thread.
    var latestFrame: Data? { get }
}

/// The lifecycle behind `preview.start` / `preview.frame` / `preview.stop`.
///
/// Idle auto-stop is the safety property here: a GUI that crashes (or a script
/// that starts a stream and exits) must not leave the worker capturing and
/// encoding forever — §52's "窗口关闭: 0 FPS" taken to its failure-proof end.
/// Every `frame` pull refreshes the idle clock, so a live viewer never trips
/// it, and a stream with no pulls stops itself.
public final class PreviewController {
    private let makeSource: (Int) -> PreviewFrameSource
    /// No pulls for this long → the stream stops itself (§52: 0 FPS on close).
    private let idleTimeout: TimeInterval
    private let lock = NSLock()
    private var source: PreviewFrameSource?
    private var lastPull: Date?
    private var configuredFPS: Int = 5

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return source != nil
    }

    /// - Parameters:
    ///   - makeSource: builds the platform frame source for a requested FPS.
    ///   - idleTimeout: how long a stream may go unpulled before auto-stopping.
    public init(idleTimeout: TimeInterval = 10, makeSource: @escaping (Int) -> PreviewFrameSource) {
        self.makeSource = makeSource
        self.idleTimeout = idleTimeout
    }

    /// Start (or restart) the stream. Returns the FPS actually in force.
    ///
    /// Idempotent in the useful direction: starting a running stream is a
    /// no-op that re-arms the idle clock, because a second viewer (or a double
    /// click on one) must not tear down what the first viewer is watching.
    public func start(maxFPS: Int, now: Date = Date()) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        let fps = max(1, min(maxFPS, 30))
        if source == nil {
            let created = makeSource(fps)
            do {
                try created.start(maxFPS: fps)
            } catch {
                // A failed start must not leave a half-constructed source
                // behind: the next start would think a stream exists.
                created.stop()
                throw error
            }
            source = created
            configuredFPS = fps
        }
        lastPull = now
        return configuredFPS
    }

    /// Pull the newest frame, auto-stopping when the stream has gone idle.
    /// Returns nil when nothing is running or no frame has arrived yet.
    public func frame(now: Date = Date()) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard let source else { return nil }
        if let lastPull, now.timeIntervalSince(lastPull) > idleTimeout {
            source.stop()
            self.source = nil
            self.lastPull = nil
            return nil
        }
        lastPull = now
        return source.latestFrame
    }

    /// Stop the stream. Safe to call when nothing is running.
    public func stop() {
        lock.lock(); defer { lock.unlock() }
        source?.stop()
        source = nil
        lastPull = nil
    }
}
