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

    public func releaseHuman() {
        lock.lock(); defer { lock.unlock() }
        humanUntil = nil
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
}
