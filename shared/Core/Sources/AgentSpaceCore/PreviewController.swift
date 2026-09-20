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

    /// How many frames this source has produced, for a client that wants to ask
    /// for "something newer than the one I already have". Sources that cannot
    /// count stay at zero, which disables that question rather than breaking it.
    var frameSequence: Int { get }
}

public extension PreviewFrameSource {
    var frameSequence: Int { 0 }
}

/// One pull against a running stream.
public struct PreviewFrameResult: Equatable, Sendable {
    /// The frame to hand to the client, nil when there is nothing to send.
    public var data: Data?
    /// The source counter `data` came from.
    public var sequence: Int
    /// The client asked for something newer and got the same frame: the pull
    /// refreshed the idle clock, but there is no payload worth encoding.
    public var unchanged: Bool

    public init(data: Data?, sequence: Int, unchanged: Bool = false) {
        self.data = data
        self.sequence = sequence
        self.unchanged = unchanged
    }
}

/// The recurring tick behind `PreviewController`'s idle watchdog.
///
/// Injected because the property it protects — "nobody is pulling anymore" — is
/// only observable after real time passes, and a test that sleeps through an
/// idle timeout is a test that fails slowly and still flakily. A fake keeps one
/// copy of the tick and fires it when the test says so.
public protocol PreviewIdleWatchdog: AnyObject {
    /// Start calling `onTick` every `interval`. Arming twice replaces the first
    /// schedule; `cancel` makes a pending tick impossible from then on.
    func arm(interval: TimeInterval, onTick: @escaping () -> Void)
    func cancel()
}

/// The production watchdog: one serial queue per controller, so a frame source
/// whose `stop` blocks cannot stall another account's or another window's.
public final class DispatchPreviewIdleWatchdog: PreviewIdleWatchdog {
    private let queue = DispatchQueue(label: "com.agentspace.preview-idle-watchdog")
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?

    public init() {}

    public func arm(interval: TimeInterval, onTick: @escaping () -> Void) {
        cancel()
        let source = DispatchSource.makeTimerSource(queue: queue)
        // The first tick lands one interval out, never immediately: arming
        // happens while the controller lock is held.
        source.schedule(deadline: .now() + interval, repeating: interval)
        source.setEventHandler(handler: onTick)
        lock.lock(); timer = source; lock.unlock()
        source.resume()
    }

    public func cancel() {
        lock.lock(); let timer = self.timer; self.timer = nil; lock.unlock()
        timer?.cancel()
    }

    deinit { cancel() }
}

/// The lifecycle behind `preview.start` / `preview.frame` / `preview.stop`.
///
/// Idle auto-stop is the safety property here: a GUI that crashes (or a script
/// that starts a stream and exits) must not leave the worker capturing and
/// encoding forever — §52's "窗口关闭: 0 FPS" taken to its failure-proof end.
/// Every `frame` pull refreshes the idle clock, so a live viewer never trips
/// it, and a stream with no pulls stops itself.
///
/// "Stops itself" is the watchdog's job, not the next pull's. Deciding the
/// timeout only inside `frame` would mean the one client that proves the leak —
/// a client that never calls again — is also the only one that cannot fix it.
public final class PreviewController {
    private let makeSource: (Int) -> PreviewFrameSource
    /// No pulls for this long → the stream stops itself (§52: 0 FPS on close).
    private let idleTimeout: TimeInterval
    private let clock: () -> Date
    private let watchdog: PreviewIdleWatchdog
    private let lock = NSLock()
    private var source: PreviewFrameSource?
    private var lastPull: Date?
    private var configuredFPS: Int = 5

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return source != nil
    }

    /// - Parameters:
    ///   - idleTimeout: how long a stream may go unpulled before auto-stopping.
    ///   - clock: the time the idle decision is made against; a test injects a
    ///     fake instead of waiting for the wall clock.
    ///   - watchdog: the ticker that checks the idle clock when nobody pulls.
    ///   - makeSource: builds the platform frame source for a requested FPS.
    public init(
        idleTimeout: TimeInterval = 10,
        clock: @escaping () -> Date = Date.init,
        watchdog: PreviewIdleWatchdog = DispatchPreviewIdleWatchdog(),
        makeSource: @escaping (Int) -> PreviewFrameSource
    ) {
        self.makeSource = makeSource
        self.idleTimeout = idleTimeout
        self.clock = clock
        self.watchdog = watchdog
    }

    /// How often the watchdog re-checks a stream nobody is pulling: about a
    /// tenth of the patience it is enforcing, so a leak ends within ~10% of the
    /// timeout instead of up to a whole timeout later.
    private var checkInterval: TimeInterval { max(0.05, min(1, idleTimeout / 10)) }

    /// Start (or restart) the stream. Returns the FPS actually in force.
    ///
    /// Idempotent in the useful direction: starting a running stream is a
    /// no-op that re-arms the idle clock, because a second viewer (or a double
    /// click on one) must not tear down what the first viewer is watching.
    @discardableResult
    public func start(maxFPS: Int, now: Date? = nil) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        let fps = max(1, min(maxFPS, 30))
        if source == nil {
            let created = makeSource(fps)
            do {
                try created.start(maxFPS: fps)
            } catch {
                // A failed start must not leave a half-constructed source
                // behind: the next start would think a stream exists. It must
                // not leave a watchdog behind either, and arming only after the
                // source exists is what keeps that true.
                created.stop()
                throw error
            }
            source = created
            configuredFPS = fps
        }
        lastPull = now ?? clock()
        watchdog.arm(interval: checkInterval) { [weak self] in self?.checkIdle() }
        return configuredFPS
    }

    /// Pull the newest frame, auto-stopping when the stream has gone idle.
    /// Returns nil when nothing is running or no frame has arrived yet.
    public func frame(now: Date? = nil) -> Data? {
        pull(now: now).data
    }

    /// Pull, with the client's "I already have frame `seen`" taken into account.
    ///
    /// The pull happens either way — that is what refreshes the idle clock — but
    /// when the capture has not advanced there is no payload worth sending. A
    /// static window then costs one short line over the socket instead of a few
    /// hundred kilobytes of JPEG being encoded, base64'd, parsed and decoded on
    /// both ends for a picture nobody can tell apart.
    public func pull(newerThanSequence seen: Int? = nil, now: Date? = nil) -> PreviewFrameResult {
        let moment = now ?? clock()
        lock.lock()
        guard let source else { lock.unlock(); return PreviewFrameResult(data: nil, sequence: 0) }
        if isIdleLocked(now: moment) {
            let detached = detachLocked()
            lock.unlock()
            // Outside the lock: stopping a ScreenCaptureKit stream blocks for
            // as long as it takes, and a stalled stop must not hold up every
            // other operation on this controller.
            detached?.stop()
            return PreviewFrameResult(data: nil, sequence: 0)
        }
        lastPull = moment
        let sequence = source.frameSequence
        // Sequence 0 means "this source does not count frames", which must not
        // be mistaken for a client that has seen frame 0 and needs nothing.
        if let seen, seen != 0, sequence == seen {
            lock.unlock()
            return PreviewFrameResult(data: nil, sequence: sequence, unchanged: true)
        }
        let frame = source.latestFrame
        lock.unlock()
        return PreviewFrameResult(data: frame, sequence: sequence)
    }

    /// Pull only while the worker can still prove that it belongs to a
    /// background Aqua session. A stream can outlive a Fast User Switch, so
    /// checking only at `start` would let stale capture continue after this
    /// account becomes the physical console. Refusal tears the source down
    /// before returning and therefore also discards its last encoded frame.
    public func pull(
        sessionVerdict: SessionVerdict, newerThanSequence seen: Int? = nil, now: Date? = nil
    ) throws -> PreviewFrameResult {
        guard sessionVerdict == .usable else {
            stop()
            let message: String
            switch sessionVerdict {
            case .isConsole:
                message = "the session is now the physical console"
            case .indeterminate:
                message = "the session's console state can no longer be determined"
            case .noWindowServer:
                message = "the session no longer has a WindowServer"
            case .usable:
                preconditionFailure("handled by the guard")
            }
            throw AgentSpaceError(
                code: sessionVerdict.errorCode,
                message: "the live preview stopped because \(message).")
        }
        return pull(newerThanSequence: seen, now: now)
    }

    public func frame(sessionVerdict: SessionVerdict, now: Date? = nil) throws -> Data? {
        try pull(sessionVerdict: sessionVerdict, now: now).data
    }

    /// Stop the stream. Safe to call when nothing is running, and safe to call
    /// while the watchdog is deciding: exactly one of them gets the source.
    public func stop() {
        lock.lock()
        let detached = detachLocked()
        lock.unlock()
        detached?.stop()
    }

    /// The watchdog's tick. Called from the watchdog's own queue, with nobody
    /// waiting on it.
    private func checkIdle() {
        lock.lock()
        guard source != nil, isIdleLocked(now: clock()) else { lock.unlock(); return }
        let detached = detachLocked()
        lock.unlock()
        detached?.stop()
    }

    /// Caller holds `lock`. A stream whose first pull has not arrived yet is not
    /// idle: the clock started when the stream was opened.
    private func isIdleLocked(now: Date) -> Bool {
        guard let lastPull else { return false }
        return now.timeIntervalSince(lastPull) > idleTimeout
    }

    /// Caller holds `lock`. Returns the source to stop, or nil when someone
    /// else already took it — which is also why a double stop is impossible.
    /// Cancelling the watchdog here means a stream that is no longer running
    /// can never be stopped again by a tick that was already in flight.
    private func detachLocked() -> PreviewFrameSource? {
        watchdog.cancel()
        let detached = source
        source = nil
        lastPull = nil
        return detached
    }

    deinit {
        // Nothing can be running here that is worth leaving behind: every owner
        // of a controller that reached `start` also stops it (`WindowStreamManager.stop`,
        // `preview.stop`, `stopAll`), so the only way to deallocate with a live
        // source is to drop it on purpose. Cancelling is still required — an
        // armed timer holding this controller would keep it alive forever.
        watchdog.cancel()
    }
}
