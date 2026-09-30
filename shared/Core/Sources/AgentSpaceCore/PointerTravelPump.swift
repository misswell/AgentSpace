import Foundation

/// A display-rate coalescer that also delivers the last point of a burst.
@MainActor
public final class PointerTravelPump<Value> {
    private var coalescer: PointerTravelCoalescer<Value>!
    private var wakeup: Task<Void, Never>?

    public init(minimumInterval: TimeInterval = DisplayRefresh.defaultPointerInterval,
                send: @escaping (Value) -> Void) {
        coalescer = PointerTravelCoalescer(minimumInterval: minimumInterval) { [weak self] value in
            guard let self else { return }
            send(value)
            self.coalescer.finished()
        }
    }

    public func offer(_ value: Value) {
        coalescer.offer(value)
        scheduleWakeup()
    }

    public func setMinimumInterval(_ interval: TimeInterval) {
        coalescer.setMinimumInterval(interval)
        scheduleWakeup()
    }

    public func reset() {
        wakeup?.cancel(); wakeup = nil
        coalescer.reset()
    }

    deinit { wakeup?.cancel() }

    private func scheduleWakeup() {
        guard wakeup == nil, let delay = coalescer.pendingDelay() else { return }
        wakeup = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(1, ceil(delay * 1_000_000_000))))
            guard !Task.isCancelled, let self else { return }
            self.wakeup = nil
            self.coalescer.pump()
            self.scheduleWakeup()
        }
    }
}
