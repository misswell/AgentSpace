import Foundation

/// How many frames may be sitting in the GPU's queue at once.
///
/// Two is the smallest number that keeps the display fed — one being drawn, one
/// waiting — and the largest that cannot fall behind by more than a frame. A
/// renderer with no bound grows a backlog the moment the GPU is slower than the
/// capture, and every queued command buffer then holds its source slot, so a
/// viewer that lags by a second starts a stream that lags by more.
public struct GPUFrameBudget: Equatable, Sendable {
    public let capacity: Int
    public private(set) var inFlight: Int = 0

    public init(capacity: Int = 2) { self.capacity = max(1, capacity) }

    /// False means "do not queue this one". Dropping a present is the intended
    /// answer: the texture already holds the newest pixels, so the next present
    /// shows a frame that is *newer* than the one that was refused.
    public mutating func begin() -> Bool {
        guard inFlight < capacity else { return false }
        inFlight += 1
        return true
    }

    public mutating func end() { if inFlight > 0 { inFlight -= 1 } }
    public mutating func reset() { inFlight = 0 }
}

/// `GPUFrameBudget` behind a lock, which is the shape a real renderer needs: the
/// permit is taken on the thread a frame arrives on and released on whichever
/// thread Metal reports the command buffer finished.
///
/// The two operations are the whole protocol, so the counting is testable
/// without a GPU and without a command buffer — including from two threads at
/// once, which is exactly how a renderer loses a permit.
public final class InFlightBudget {
    private var budget: GPUFrameBudget
    private let lock = NSLock()

    public init(capacity: Int = 2) { budget = GPUFrameBudget(capacity: capacity) }

    public func begin() -> Bool { lock.lock(); defer { lock.unlock() }; return budget.begin() }
    public func end() { lock.lock(); defer { lock.unlock() }; budget.end() }
    public func reset() { lock.lock(); defer { lock.unlock() }; budget.reset() }
    public var inFlight: Int { lock.lock(); defer { lock.unlock() }; return budget.inFlight }
}

/// What the local renderer did with a shared-memory slot, which is what decides
/// whether the worker may reuse it.
public enum SurfaceApplyOutcome: Equatable, Sendable {
    /// The slot's bytes have been copied into local memory by the time this
    /// returned, so the slot is free.
    ///
    /// This is the whole ACK rule, and it is a rule about *when the copy ends*,
    /// not about when the picture appears: `MTLTexture.replace(region:…)` is a
    /// synchronous CPU upload, so returning from it means the shared memory has
    /// already been read. If this path ever becomes an `MTLBuffer` plus a GPU
    /// blit, the copy finishes on the GPU instead, and acknowledging here would
    /// let the worker overwrite pixels the blit is still reading — `.uploaded`
    /// would then have to wait for the blit command buffer to complete.
    case uploaded
    /// Uploaded, but the GPU queue was full so nothing was presented. The slot
    /// is free and the next present shows these pixels.
    case uploadedWithoutPresent
    /// Nothing was copied, so this frame is not on screen. The slot still must
    /// be released — holding it while asking for a baseline can exhaust both.
    case refused
}

/// What the viewer decided about one received frame, before any local rendering.
public enum FrameAcceptance: Equatable, Sendable {
    case applied(SurfaceApplyOutcome)
    /// Already displayed: the same generation, slot and sequence.
    case duplicate
    /// The frame cannot be continued from — a gap, a new surface, or a stream
    /// that has to restart from a full baseline.
    case needsBaseline
}

/// The commands a viewer sends back for one received frame, in order.
///
/// A frame is always acknowledged. What differs is whether a baseline is asked
/// for after it: a viewer that refuses a frame and also holds its slot would
/// park the stream, because the full frame that would fix it has nowhere to go.
public enum FrameSlotFeedback {
    public static func commands(slot: Int, sequence: UInt64, acceptance: FrameAcceptance) -> [FrameClientCommand] {
        let acknowledge = FrameClientCommand(kind: .acknowledge, slotIndex: slot, sequence: sequence)
        switch acceptance {
        case .applied(.uploaded), .applied(.uploadedWithoutPresent), .duplicate:
            return [acknowledge]
        case .applied(.refused), .needsBaseline:
            return [acknowledge, FrameClientCommand(kind: .requestFull)]
        }
    }
}
