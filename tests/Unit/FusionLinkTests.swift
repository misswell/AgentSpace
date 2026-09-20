import Foundation
import XCTest
@testable import AgentSpaceCore

/// The Fusion link policy: which refusal is which state, and how long the GUI
/// waits before it is allowed to ask the worker again. Everything here is a
/// pure function of the error and the failure count, so the retry behaviour a
/// user sees during a worker restart is provable without a timer or a session.
final class FusionLinkTests: XCTestCase {
    private let policy = FusionLinkPolicy()

    private func error(_ code: AgentSpaceErrorCode) -> AgentSpaceError {
        AgentSpaceError(code: code, message: "test")
    }

    func testAWorkingPollIsTheSteadyInterval() {
        let status = policy.connected
        XCTAssertEqual(status.state, .connected)
        XCTAssertEqual(status.failures, 0)
        XCTAssertEqual(status.nextPollInSeconds, 1)
        XCTAssertNil(status.error)
    }

    /// A worker that is restarting must cost a decaying trickle, not one RPC
    /// per second forever.
    func testTransientFailuresBackOffAndThenHoldAtTheTop() {
        let ladder: [(Int, TimeInterval)] = [(1, 1), (2, 2), (3, 5), (4, 5), (40, 5)]
        for (failures, expected) in ladder {
            let status = policy.status(after: error(.internalError), failures: failures)
            XCTAssertEqual(status.state, .reconnecting, "attempt \(failures)")
            XCTAssertEqual(status.nextPollInSeconds, expected, "attempt \(failures)")
            XCTAssertEqual(status.failures, failures)
        }
    }

    /// The guard refusing because the human is at the agent's keyboard is the
    /// product working. It is reported as itself and never as "reconnecting".
    func testConsoleAndWindowServerRefusalsAreNotReconnectLoops() {
        for code: AgentSpaceErrorCode in [.sessionIsConsole, .noWindowServer, .screenRecordingDenied,
                                          .accessibilityDenied] {
            for failures in [1, 9] {
                let status = policy.status(after: error(code), failures: failures)
                XCTAssertNotEqual(status.state, .reconnecting, "\(code) attempt \(failures)")
                XCTAssertNotEqual(status.state, .connected)
                XCTAssertEqual(status.nextPollInSeconds, 5, "\(code) must not poll faster than the cap")
                XCTAssertEqual(status.error?.code, code, "the reason survives to the interface")
            }
        }
        XCTAssertEqual(policy.status(after: error(.sessionIsConsole), failures: 2).state, .console)
        XCTAssertEqual(policy.status(after: error(.noWindowServer), failures: 2).state, .permissionRequired)
    }

    /// A sleeping agent is not an error the user caused; the vocabulary table
    /// calls it Sleeping, and the link says the same.
    func testASleepingAgentIsSuspended() {
        XCTAssertEqual(policy.status(after: error(.workerOffline), failures: 1).state, .suspended)
        XCTAssertEqual(policy.status(after: error(.sessionNotReady), failures: 1).state, .suspended)
    }

    /// Recovery has to be automatic: the first poll that answers resets both the
    /// counter and the delay, or a session that came back from a fast user
    /// switch would keep the console's slow probe forever.
    func testTheFirstSuccessfulPollClearsTheLadder() {
        var failures = 0
        for _ in 0..<6 {
            failures = policy.status(after: error(.internalError), failures: failures + 1).failures
        }
        XCTAssertEqual(failures, 6)
        let status = policy.connected
        XCTAssertEqual(status.failures, 0)
        XCTAssertEqual(status.nextPollInSeconds, 1)
    }

    func testAnEmptyLadderCannotProduceABusyLoop() {
        let bare = FusionLinkPolicy(pollInterval: 2, retryLadder: [])
        XCTAssertEqual(bare.status(after: error(.internalError), failures: 1).nextPollInSeconds, 2)
        XCTAssertEqual(bare.connected.nextPollInSeconds, 2)
    }

    /// A custom ladder is what the tests above would want broken: index the
    /// count by position, not by arithmetic on a hardcoded array.
    func testTheLadderIsThePolicySaysItIs() {
        let slow = FusionLinkPolicy(pollInterval: 0.5, retryLadder: [3, 7])
        XCTAssertEqual(slow.status(after: error(.internalError), failures: 1).nextPollInSeconds, 3)
        XCTAssertEqual(slow.status(after: error(.internalError), failures: 2).nextPollInSeconds, 7)
        XCTAssertEqual(slow.status(after: error(.internalError), failures: 3).nextPollInSeconds, 7)
        XCTAssertEqual(slow.status(after: error(.sessionIsConsole), failures: 1).nextPollInSeconds, 7)
    }
}
