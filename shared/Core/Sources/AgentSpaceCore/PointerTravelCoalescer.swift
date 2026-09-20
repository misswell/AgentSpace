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
public final class PointerTravelCoalescer {
    private let lock = NSLock()
    private let minimumInterval: TimeInterval
    private let send: (JSONValue) -> Void
    private var pending: JSONValue?
    private var lastSent: Date?
    private var inFlight = false

    /// - Parameter minimumInterval: shortest gap between two travel requests.
    ///   The default caps hover at 30 Hz, which is above what a preview running
    ///   at 5-15 FPS can show anyway.
    public init(minimumInterval: TimeInterval = 1.0 / 30.0, send: @escaping (JSONValue) -> Void) {
        self.minimumInterval = max(0, minimumInterval)
        self.send = send
    }

    /// A new position. Replaces any position still waiting; sends immediately
    /// when nothing is in flight and the rate allows it.
    public func offer(_ position: JSONValue, now: Date = Date()) {
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

    /// How many travel requests could still reach the agent: the one being
    /// answered plus the newest waiting one, and never more. This is the bound
    /// a deliberate gesture queues behind.
    public var outstandingCount: Int {
        lock.lock(); defer { lock.unlock() }
        return (inFlight ? 1 : 0) + (pending == nil ? 0 : 1)
    }
}
