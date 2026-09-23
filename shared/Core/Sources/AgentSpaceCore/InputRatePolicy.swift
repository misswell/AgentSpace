import CoreGraphics
import Foundation

/// What the local display can actually show.
///
/// A pointer coalescer that sends faster than the panel refreshes is producing
/// updates that only ever alias — and one that sends slower is adding a stutter
/// of its own on top of everything else. The number therefore comes from the
/// display rather than from a constant somebody liked: a 60 Hz panel gets 60,
/// a ProMotion panel reports up to 120 and gets that.
///
/// `CGDisplayCopyDisplayMode` answers in *display mode* terms, and on a ProMotion
/// panel it reports the maximum the panel offers rather than the rate in force
/// at this instant. That is the right direction to be wrong in for this use: an
/// over-fast pointer update degrades to a coalesced no-op, while an under-fast
/// one is visible.
public enum DisplayRefresh {
    /// Refreshes per second for a display id, or `nil` when it cannot be read.
    public static func hertz(for displayID: CGDirectDisplayID?) -> Double? {
        let id = displayID ?? CGMainDisplayID()
        guard let mode = CGDisplayCopyDisplayMode(id) else { return nil }
        let rate = mode.refreshRate
        guard rate.isFinite, rate >= 1 else { return nil }
        return rate
    }

    /// The local display's rate, clamped to the range a pointer actually
    /// benefits from: below 30 Hz nothing is gained by pretending, and above
    /// 120 Hz the extra packets cost more than the hand can tell.
    public static func pointerRate(for displayID: CGDirectDisplayID? = nil) -> Double {
        let measured = hertz(for: displayID) ?? 60
        return min(120, max(30, measured.rounded()))
    }

    public static var defaultPointerRate: Double { pointerRate() }

    /// The same number as an interval, which is what a coalescer is configured
    /// with.
    public static var defaultPointerInterval: TimeInterval { 1.0 / defaultPointerRate }

    public static func pointerInterval(for displayID: CGDirectDisplayID) -> TimeInterval {
        1.0 / pointerRate(for: displayID)
    }
}

/// How fast the capture stream should run, given what is happening on it.
///
/// One number was made to serve every situation and it could not: an idle
/// desktop that captures at 60 FPS is 60 frames of nothing, and a desktop being
/// dragged at 5 FPS is a window that lags a hand. The states here are what the
/// frame budget can actually tell apart, and each one exists because it was
/// asked for by a measurement:
///
/// - `idle` — nothing has changed and no pointer has moved. The stream still
///   has to run: the first thing that changes must appear without a new
///   configuration being negotiated.
/// - `active` — the desktop is changing, or the pointer is moving inside it.
/// - `interactive` — a button is held. A drag or a resize is the case where the
///   picture and the hand are the same motion.
public enum FrameActivity: Equatable, Sendable {
    case idle
    case active
    case interactive
    /// A video is playing: sustained, high-damage content. It wants the top
    /// rate that the budget allows.
    case video
}

/// The frame rate policy, as a value: what to ask the capture for, and what
/// pointer rate makes sense beside it.
///
/// The ceiling is the *viewer's* configured rate (`previewFPS`), which is why
/// every rate here is a fraction of it rather than an absolute: a person who set
/// 10 FPS on purpose has said what they want, and a policy that overrode it
/// during a drag would be spending their bandwidth against their instruction.
public struct InputRatePolicy: Equatable, Sendable {
    /// What the person configured, in frames per second.
    public var ceiling: Int
    /// Pointer updates per second, independent of the frame rate once the
    /// cursor channel is in play: a cursor overlay is drawn locally, so a fast
    /// pointer costs no encoder time at all.
    public var pointerRate: Double

    public init(ceiling: Int, pointerRate: Double = DisplayRefresh.defaultPointerRate) {
        self.ceiling = max(1, min(120, ceiling))
        self.pointerRate = min(120, max(30, pointerRate))
    }

    /// How much of the ceiling a situation is worth.
    ///
    /// A still desktop gets a third of the ceiling rather than zero: the stream
    /// has to notice the next change immediately, and the cost of an idle
    /// frame on a local socket is one dirty-region comparison. The rate is
    /// never zero for exactly that reason, and never above the ceiling because
    /// that is what the person asked for.
    public func frames(for activity: FrameActivity) -> Int {
        switch activity {
        case .idle:
            return max(2, min(ceiling, Int(Double(ceiling) / 2.5)))
        case .active:
            return ceiling
        case .interactive, .video:
            // The one case that deliberately exceeds the stored preference, and
            // only because a drag looks broken below the panel's rate: the
            // desktop a person is dragging has to move with their hand. 60 is
            // the top rate the capture path is asked for at all — the frame
            // budget's own ceiling — and a viewer set to 30 gets 60 while its
            // button is down.
            return min(60, max(ceiling, 60))
        }
    }

    /// Whether pointer travel should be forwarded at the full pointer rate.
    /// True unless the surface is only being watched; a Fusion background
    /// window is the case that wants less, and it is the surface's decision
    /// rather than this policy's.
    public func pointerInterval(for activity: FrameActivity) -> TimeInterval {
        switch activity {
        case .idle: return 1.0 / min(pointerRate, 60)
        case .active, .interactive, .video: return 1.0 / pointerRate
        }
    }
}

/// Turns events on a desktop into the activity a rate policy is asked about.
///
/// Kept as a value with a clock passed in, so the "a pointer that stopped
/// moving is idle" transition is testable without waiting for it.
public struct FrameActivityTracker {
    /// How long after the last change the desktop counts as idle. Shorter than
    /// a person's idea of "a while" on purpose: the cost of being wrong is one
    /// dropped frame rate, and the cost of being slow is a bounce.
    public static let idleAfter: TimeInterval = 1.5

    private var lastActivity: Date
    private var pressHeld = false
    private var sustainedDamage = false

    public init(now: Date = Date()) {
        lastActivity = now
    }

    public mutating func noteChange(at now: Date) { lastActivity = now }

    public mutating func notePress(_ held: Bool, at now: Date) {
        pressHeld = held
        if held { lastActivity = now }
    }

    /// High-damage content over several frames: a video, an animation.
    public mutating func noteSustainedDamage(_ value: Bool) { sustainedDamage = value }

    public func activity(at now: Date) -> FrameActivity {
        if pressHeld { return .interactive }
        if sustainedDamage { return .video }
        return now.timeIntervalSince(lastActivity) < Self.idleAfter ? .active : .idle
    }
}
