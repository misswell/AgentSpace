import Foundation

/// Keeps pointer *travel* at one request per interval instead of one per event.
///
/// A Fusion proxy emits a move for every mouse-moved event, and a mouse reports
/// at 125 Hz or more. Each of those used to become its own blocking RPC on the
/// proxy's serial queue, so a hand waved across the window in half a second
/// queued a hundred position updates — and the click that followed them was
/// delayed behind all of them.
///
/// Only the newest position matters, so that is the only one kept: at most one
/// travel request is in flight, at most one newer position waits behind it, and
/// anything older is dropped. Deliberate gestures (press, click, drag, scroll,
/// keys) never come through here — they are distinct events the remote app has
/// to see each of, and they must not be rate-limited away.
///
/// The payload is whatever the caller sends: a Fusion proxy carries the wire
/// object, the desktop viewer carries the parsed `InputAction`.
public final class PointerTravelCoalescer<Value> {
    private let lock = NSLock()
    private var minimumInterval: TimeInterval
    private let send: (Value) -> Void
    private var pending: Value?
    private var lastSent: Date?
    private var inFlight = false

    /// - Parameter minimumInterval: shortest gap between two travel requests.
    ///
    ///   Was 1/30 and that was chosen when the picture behind the pointer
    ///   refreshed at 5–15 FPS: a rate above what the viewer could show bought
    ///   nothing. With the desktop viewer defaulting to 30 FPS and the capture
    ///   going to 60 while a gesture is live, a 30 Hz hover is the thing the
    ///   hand notices — a mouse reports at 125 Hz and a trackpad higher, and
    ///   the coalescer's job is to drop the *surplus*, not to add a second
    ///   source of stutter on top of the frame rate. The default is now
    ///   `DisplayRefresh.defaultPointerRate`, which resolves to the local
    ///   display's own rate so a 60 Hz panel is not sent 120 Hz updates that
    ///   only ever alias.
    public init(minimumInterval: TimeInterval = DisplayRefresh.defaultPointerInterval, send: @escaping (Value) -> Void) {
        self.minimumInterval = max(0, minimumInterval)
        self.send = send
    }

    /// Change the rate while a connection is live — the frame budget already
    /// does this (`InputRatePolicy`), and rebuilding the coalescer to change a
    /// number would drop the position that is currently in flight.
    public func setMinimumInterval(_ interval: TimeInterval) {
        lock.lock(); minimumInterval = max(0, interval); lock.unlock()
    }

    public var rateLimit: TimeInterval { lock.lock(); defer { lock.unlock() }; return minimumInterval }

    /// A new position. Replaces any position still waiting; sends immediately
    /// when nothing is in flight and the rate allows it.
    public func offer(_ position: Value, now: Date = Date()) {
        lock.lock(); pending = position; lock.unlock()
        pump(now: now)
    }

    /// The in-flight request came back. The newest waiting position goes next.
    public func finished(now: Date = Date()) {
        lock.lock(); inFlight = false; lock.unlock()
        pump(now: now)
    }

    /// Retry when time has passed on its own — the proxy's frame pump calls
    /// this, so a position that was rate-limited still reaches the agent even
    /// if no further mouse event arrives.
    public func pump(now: Date = Date()) {
        lock.lock()
        guard !inFlight, let position = pending else { lock.unlock(); return }
        if let lastSent, now.timeIntervalSince(lastSent) < minimumInterval {
            // Still too soon; the position stays pending for the next pump.
            lock.unlock()
            return
        }
        inFlight = true
        pending = nil
        lastSent = now
        lock.unlock()
        // Outside the lock: `send` goes to the caller's queue, and a caller
        // that blocks here must not be able to stall an offer.
        send(position)
    }

    /// Forget everything. Used when the window the travel belongs to is no
    /// longer on screen, so a stale position must not be posted after it.
    public func reset() {
        lock.lock(); pending = nil; inFlight = false; lastSent = nil; lock.unlock()
    }

    public var isInFlight: Bool { lock.lock(); defer { lock.unlock() }; return inFlight }
    public var hasPendingPosition: Bool { lock.lock(); defer { lock.unlock() }; return pending != nil }

    /// When a rate-limited final position can be sent. A caller with no frame
    /// timer can arm exactly one wakeup instead of losing the last hover.
    public func pendingDelay(now: Date = Date()) -> TimeInterval? {
        lock.lock(); defer { lock.unlock() }
        guard pending != nil, !inFlight else { return nil }
        guard let lastSent else { return 0 }
        return max(0, minimumInterval - now.timeIntervalSince(lastSent))
    }

    /// How many travel requests could still reach the agent: the one being
    /// answered plus the newest waiting one, and never more. This is the bound
    /// a deliberate gesture queues behind.
    public var outstandingCount: Int {
        lock.lock(); defer { lock.unlock() }
        return (inFlight ? 1 : 0) + (pending == nil ? 0 : 1)
    }
}
