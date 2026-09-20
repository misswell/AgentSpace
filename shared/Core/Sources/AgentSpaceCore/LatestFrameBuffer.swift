import Foundation

/// One-slot buffer: storing a newer frame replaces an unconsumed old frame.
/// This is the capture back-pressure contract—latency never grows into a queue.
public final class LatestFrameBuffer<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?

    public init() {}

    public func store(_ value: Value) {
        lock.lock(); defer { lock.unlock() }
        self.value = value
    }

    public func take() -> Value? {
        lock.lock(); defer { lock.unlock() }
        defer { value = nil }
        return value
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        value = nil
    }
}
