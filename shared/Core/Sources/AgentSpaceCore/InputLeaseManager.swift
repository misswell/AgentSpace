import Foundation

/// Arbitration between automation and direct human interaction with a Fusion
/// proxy. Human activity owns a short renewable lease; automation resumes
/// automatically when that lease expires.
public final class InputLeaseManager: @unchecked Sendable {
    private let duration: TimeInterval
    private let lock = NSLock()
    private var humanUntil: Date?

    public init(duration: TimeInterval = 5) {
        self.duration = max(0, duration)
    }

    public func claimHuman(now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        humanUntil = now.addingTimeInterval(duration)
    }

    public func automationAllowed(now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let humanUntil else { return true }
        if now >= humanUntil {
            self.humanUntil = nil
            return true
        }
        return false
    }

    public func remaining(now: Date = Date()) -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return max(0, humanUntil?.timeIntervalSince(now) ?? 0)
    }

    /// Whether pointer travel is worth posting to the agent right now.
    ///
    /// A `move` with no button held is the cursor crossing the window, not a
    /// person taking control. It is forwarded only while a lease someone else
    /// already took is still live — mid-gesture inside this very proxy — and
    /// asking never extends that lease, or a hovering cursor would keep the
    /// agent paused in five-second slices forever.
    public func deliversHover(now: Date = Date()) -> Bool {
        remaining(now: now) > 0
    }
}
