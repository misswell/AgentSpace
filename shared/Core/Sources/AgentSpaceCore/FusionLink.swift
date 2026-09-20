import Foundation

/// What the Fusion link is doing, in terms the user can act on.
///
/// The GUI polls the worker's window list; before this type existed every
/// failure of that poll was thrown away and the next one came a second later.
/// A sleeping agent was therefore indistinguishable from a broken one, and a
/// session that is *refused* — the agent is sitting at the physical console —
/// was retried at the same rate as a dropped packet.
public enum FusionLinkState: Equatable, Sendable {
    /// The worker answers and the proxy shows the agent's windows.
    case connected
    /// Nothing useful came back, and asking again is the right response.
    case reconnecting
    /// The agent has no running worker. Sleeping, not broken.
    case suspended
    /// The agent's session is the physical console. Capture and input are
    /// refused *because that is the product*; the human is using it.
    case console
    /// There is no window server, or the capture/accessibility permission is
    /// missing. Retrying the poll cannot grant anything.
    case permissionRequired
}

/// A poll outcome reduced to a delay and a reason.
public struct FusionLinkStatus: Equatable, Sendable {
    public var state: FusionLinkState
    /// Consecutive polls that did not answer. Drives the retry ladder.
    public var failures: Int
    /// How long the GUI waits before it is allowed to poll again.
    public var nextPollInSeconds: TimeInterval
    /// The refusal behind the state, for the interface to show.
    public var error: AgentSpaceError?

    public init(
        state: FusionLinkState, failures: Int, nextPollInSeconds: TimeInterval,
        error: AgentSpaceError? = nil
    ) {
        self.state = state
        self.failures = failures
        self.nextPollInSeconds = nextPollInSeconds
        self.error = error
    }
}

/// Turns each poll outcome into a state and a delay.
///
/// Pure on purpose: `connected` and the ladder are derived, never stored, so a
/// test can prove the retry behaviour without a timer, a socket or a second
/// macOS user.
public struct FusionLinkPolicy: Sendable {
    /// The steady-state interval between window lists.
    public let pollInterval: TimeInterval
    /// Gaps after the 1st, 2nd, 3rd … failed poll; the last one repeats.
    public let retryLadder: [TimeInterval]

    public init(pollInterval: TimeInterval = 1, retryLadder: [TimeInterval] = [1, 2, 5]) {
        self.pollInterval = pollInterval
        // A ladder with no entries would produce a zero delay, i.e. a busy
        // loop against a worker that just refused.
        self.retryLadder = retryLadder.isEmpty ? [pollInterval] : retryLadder
    }

    public var connected: FusionLinkStatus {
        FusionLinkStatus(state: .connected, failures: 0, nextPollInSeconds: pollInterval)
    }

    /// The status to show after a poll that did not answer.
    public func status(after error: AgentSpaceError, failures: Int) -> FusionLinkStatus {
        let count = max(1, failures)
        let state = FusionLinkState(error: error)
        // A dropped connection earns a growing wait; a refusal that will not
        // change by asking earns the top of the ladder and stays there.
        let delay: TimeInterval
        switch state {
        case .reconnecting:
            delay = retryLadder[min(count, retryLadder.count) - 1]
        case .connected, .suspended, .console, .permissionRequired:
            delay = longestRetry
        }
        return FusionLinkStatus(
            state: state, failures: count, nextPollInSeconds: delay, error: error)
    }

    private var longestRetry: TimeInterval { retryLadder.last ?? pollInterval }
}

extension FusionLinkState {
    /// Which kind of refusal this is, so the interface can say something the
    /// user can act on instead of "retry 47".
    ///
    /// `SESSION_IS_CONSOLE` and `NO_WINDOW_SERVER` deliberately land in their
    /// own states: both are the guard doing its job, and a reconnect loop that
    /// pretends otherwise turns a correct refusal into a spinning wheel.
    public init(error: AgentSpaceError) {
        switch error.code {
        case .sessionIsConsole: self = .console
        case .noWindowServer, .screenRecordingDenied, .accessibilityDenied: self = .permissionRequired
        case .workerOffline, .sessionNotReady: self = .suspended
        default: self = .reconnecting
        }
    }
}
