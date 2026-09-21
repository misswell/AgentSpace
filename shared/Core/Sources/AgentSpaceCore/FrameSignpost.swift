import Foundation
import os

/// Instruments-visible timing for the live pixel path.
///
/// A frame that arrives late has a reason, and the only way to find it after
/// the fact is a timeline showing where the milliseconds went: capture, damage,
/// shared copy, socket send, receive, GPU upload, present. Ordinary logs cannot
/// carry that at 30 frames a second without drowning the file, so this is a
/// signpost channel: it costs almost nothing while nobody is tracing, and it is
/// the first thing worth reading when somebody is.
///
/// Nothing here is a product decision. `docs/status.md` describes the pipeline
/// this instrument reports on; if the two ever disagree, the trace is right.
public enum FrameSignpost {
    public static let log = OSLog(subsystem: "com.agentspace.AgentSpace", category: "FrameEngine")

    /// Signposts are off unless something is asking for them, because a stream
    /// that instruments every frame writes two events per frame into a buffer
    /// nobody is reading. `AGENTSPACE_FRAME_SIGNPOST=1` turns the timeline on.
    public static let enabled: Bool = {
        if let raw = ProcessInfo.processInfo.environment["AGENTSPACE_FRAME_SIGNPOST"] {
            return ["1", "true", "yes"].contains(raw.lowercased())
        }
        return false
    }()

    private static let signposter = OSSignposter(subsystem: "com.agentspace.AgentSpace", category: "FrameEngine")

    public struct Interval {
        fileprivate let name: StaticString
        fileprivate let state: OSSignpostIntervalState?
    }

    public static func begin(_ name: StaticString) -> Interval {
        guard enabled else { return Interval(name: name, state: nil) }
        return Interval(name: name, state: signposter.beginInterval(name))
    }

    public static func end(_ interval: Interval) {
        guard enabled, let state = interval.state else { return }
        signposter.endInterval(interval.name, state)
    }

    public static func event(_ name: StaticString, _ value: Int) {
        guard enabled else { return }
        signposter.emitEvent(name, "\(value)")
    }
}
