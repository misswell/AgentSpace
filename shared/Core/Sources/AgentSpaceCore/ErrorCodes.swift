import Foundation

/// Every failure AgentSpace can report, spelled out.
///
/// Design rule (plan §21): never return "something went wrong". A caller that
/// gets one of these codes can decide what to do without guessing, and — more
/// importantly — can tell "the agent desktop is not there" apart from "the
/// agent desktop is there but refused". Only the second is safe to retry.
public enum AgentSpaceErrorCode: String, Codable, Sendable, CaseIterable {
    // --- Session / liveness -------------------------------------------------
    /// The Space has no usable background Aqua session. Terminal for this call.
    case sessionNotReady = "SESSION_NOT_READY"
    /// The Space's session is currently the physical console. Input refused.
    case sessionIsConsole = "SESSION_IS_CONSOLE"
    /// No WindowServer connection in this session: no GUI can be driven.
    case noWindowServer = "NO_WINDOW_SERVER"
    /// Nothing is listening on the Space's socket.
    case workerOffline = "WORKER_OFFLINE"
    /// The worker was asked to run as root and refused.
    case workerIsRoot = "WORKER_IS_ROOT"

    // --- Permissions --------------------------------------------------------
    case accessibilityDenied = "ACCESSIBILITY_DENIED"
    case screenRecordingDenied = "SCREEN_RECORDING_DENIED"

    // --- Input --------------------------------------------------------------
    case invalidCoordinate = "INVALID_COORDINATE"
    case invalidAction = "INVALID_ACTION"
    /// There is no frontmost application in the Space to deliver input to, so
    /// an event would be posted into nothing and the caller would believe it
    /// landed. Refused instead of silently no-op'd.
    case noInputTarget = "NO_INPUT_TARGET"

    // --- Apps ---------------------------------------------------------------
    case appNotFound = "APP_NOT_FOUND"
    case appLaunchTimeout = "APP_LAUNCH_TIMEOUT"
    case appNotRunning = "APP_NOT_RUNNING"

    // --- Workspace / exec ---------------------------------------------------
    case workspaceDenied = "WORKSPACE_DENIED"
    case commandTimeout = "COMMAND_TIMEOUT"
    case execDenied = "EXEC_DENIED"

    // --- Transport ----------------------------------------------------------
    case unauthorized = "UNAUTHORIZED"
    case badRequest = "BAD_REQUEST"
    case methodNotFound = "METHOD_NOT_FOUND"
    case protocolMismatch = "PROTOCOL_MISMATCH"
    case internalError = "INTERNAL_ERROR"

    /// Whether retrying the identical request could plausibly succeed later.
    ///
    /// A console collision is recoverable (switch back and it works). A
    /// missing background session is recoverable only after a login. A denied
    /// TCC grant is *not* something an agent can fix by retrying, so it says so
    /// rather than inviting a retry loop.
    public var isRecoverable: Bool {
        switch self {
        case .sessionNotReady, .workerOffline, .noWindowServer,
             .sessionIsConsole, .appLaunchTimeout, .commandTimeout,
             .appNotFound, .appNotRunning, .noInputTarget:
            return true
        case .accessibilityDenied, .screenRecordingDenied,
             .workerIsRoot, .workspaceDenied, .execDenied,
             .invalidCoordinate, .invalidAction,
             .unauthorized, .badRequest, .methodNotFound, .protocolMismatch,
             .internalError:
            return false
        }
    }

    /// The operator-facing next step. Present on every error the worker emits,
    /// because "it failed" without "do this" is the thing that makes a tool
    /// unusable at 2am.
    public var remediation: String {
        switch self {
        case .sessionNotReady:
            return "Fast user switch into the AgentSpace user once (System Settings → Control Center → Fast User Switching), then switch back. The session stays alive afterwards."
        case .sessionIsConsole:
            return "The AgentSpace desktop is on your physical display right now. Switch back to your own account; input resumes automatically and is refused until then."
        case .noWindowServer:
            return "The AgentSpace session has no window server. Log the AgentSpace user in through the GUI (not ssh) and retry."
        case .workerOffline:
            return "Start the Space's worker: `agentspace start <space>`, or check `agentspace doctor`."
        case .workerIsRoot:
            return "The worker refuses to run as root. It must run as the AgentSpace user inside that user's Aqua session."
        case .accessibilityDenied:
            return "In the AgentSpace session: System Settings → Privacy & Security → Accessibility → enable agentspace-worker. Then run `agentspace restart <space>`."
        case .screenRecordingDenied:
            return "In the AgentSpace session: System Settings → Privacy & Security → Screen & System Audio Recording → enable agentspace-worker. Then run `agentspace restart <space>`."
        case .invalidCoordinate:
            return "Coordinates are display POINTS (x right, y down, origin top-left of the main display), not screenshot pixels. Divide a pixel by the reported `scale`."
        case .invalidAction:
            return "Check the action list against docs/protocol.md. The whole batch is validated before anything is performed, so nothing was done."
        case .noInputTarget:
            return "No app is frontmost in the AgentSpace session, so the events would go nowhere. Launch or activate something there first, e.g. `agentspace launch <space> Finder`."
        case .appNotFound:
            return "Pass an app name that exists in the AgentSpace session (`agentspace apps <space>`) or an absolute path to a .app bundle."
        case .appLaunchTimeout:
            return "The app was launched but never registered with the window server. It may be showing a modal in the AgentSpace session; take a screenshot to look."
        case .appNotRunning:
            return "The app is not running in that Space. `agentspace apps <space>` lists what is."
        case .workspaceDenied:
            return "The path is outside this Space's workspace and shared folders. Add it in the Space's Shared Folders settings first."
        case .commandTimeout:
            return "Raise the timeout or make the command shorter. The process group was terminated."
        case .execDenied:
            return "That command is on AgentSpace's refusal list. Run it yourself in your own terminal if you really mean it."
        case .unauthorized:
            return "The session token does not match this Space. Re-read it from the runtime directory, or recreate the Space."
        case .badRequest:
            return "Malformed request. See docs/protocol.md for the exact shape."
        case .methodNotFound:
            return "Unknown method. `agentspace doctor --json` prints the protocol this build speaks."
        case .protocolMismatch:
            return "GUI, CLI and worker are different builds. Reinstall so all three come from the same release."
        case .internalError:
            return "Export diagnostics (`agentspace doctor --export`) and attach them to a bug report."
        }
    }
}

/// The error object inside a failed RPC reply (plan §21).
public struct AgentSpaceError: Error, Codable, Sendable, Equatable {
    public let code: AgentSpaceErrorCode
    public let message: String
    public let recoverable: Bool

    /// `recoverable` defaults to the code's own classification so callers
    /// cannot accidentally mark a hard failure as retryable.
    public init(code: AgentSpaceErrorCode, message: String, recoverable: Bool? = nil) {
        self.code = code
        self.message = message
        self.recoverable = recoverable ?? code.isRecoverable
    }
}

extension AgentSpaceError: LocalizedError {
    public var errorDescription: String? { "\(code.rawValue): \(message)" }
    public var recoverySuggestion: String? { code.remediation }
}
