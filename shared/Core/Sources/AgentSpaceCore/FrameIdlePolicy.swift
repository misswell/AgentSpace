import Foundation

/// When a frame socket is quiet, the reader cannot tell "nothing changed" from
/// "the sender is gone" — a still desktop and a stuck worker look identical on
/// the wire. These are the two numbers that separate them: the worker speaks at
/// least every `heartbeatInterval`, so a peer that has heard nothing for
/// `staleAfter` is not a stationary desktop but a lost connection.
///
/// The stale window is deliberately several times the heartbeat interval. A
/// desktop that publishes nothing at all must stay displayed indefinitely, and
/// a reader that reconnects on a schedule it cannot meet turns every idle
/// second into a new handshake.
public struct FrameIdlePolicy: Equatable, Sendable {
    public var heartbeatInterval: TimeInterval
    public var staleAfter: TimeInterval

    public init(heartbeatInterval: TimeInterval = 2, staleAfter: TimeInterval = 8) {
        self.heartbeatInterval = max(0.1, heartbeatInterval)
        // A heartbeat that cannot arrive before the stale deadline would be
        // decoration, so the floor is two intervals' worth of grace.
        self.staleAfter = max(self.heartbeatInterval * 2, staleAfter)
    }
}

/// One timeline of socket silence, used by both ends: the worker asks whether a
/// heartbeat is owed, the client asks whether the peer has gone quiet for too
/// long. Anything received counts as activity, because a moving desktop is
/// already a heartbeat and a still one must not be punished for it.
public struct FrameStreamLiveness: Sendable {
    public let policy: FrameIdlePolicy
    public private(set) var lastActivity: TimeInterval
    public private(set) var lastHeartbeat: TimeInterval

    public init(policy: FrameIdlePolicy = .init(), at now: TimeInterval) {
        self.policy = policy
        lastActivity = now
        lastHeartbeat = now
    }

    public mutating func noteActivity(at now: TimeInterval) {
        lastActivity = max(lastActivity, now)
        lastHeartbeat = max(lastHeartbeat, now)
    }

    public mutating func noteHeartbeatSent(at now: TimeInterval) { lastHeartbeat = max(lastHeartbeat, now) }

    public mutating func heartbeatDue(at now: TimeInterval) -> Bool {
        now - lastHeartbeat >= policy.heartbeatInterval
    }

    public mutating func isStale(at now: TimeInterval) -> Bool {
        now - lastActivity >= policy.staleAfter
    }
}
