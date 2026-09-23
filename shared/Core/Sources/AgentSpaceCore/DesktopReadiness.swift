import Foundation

/// The facts a "is this session's desktop up and drivable?" verdict is made
/// from — one struct, so the decision can be tested without a session.
///
/// Every optional means "the probe could not tell". `DesktopReadinessCheck`
/// treats that as a gap rather than a pass, the same posture `SessionGuard`
/// takes with the console bit: an answer nobody could read is not a licence to
/// post events.
public struct DesktopFacts: Equatable, Sendable {
    /// Did `CGSessionCopyCurrentDictionary()` answer at all?
    public var sessionDictionaryReadable: Bool
    /// `kCGSessionLoginDoneKey`. Measured on macOS 27.0 in a background Aqua
    /// session: present, `1` (an `__NSCFBoolean`). It is the session's own
    /// statement that the desktop finished coming up, which is why it is
    /// checked before the process list rather than instead of it.
    public var loginDone: Bool?
    /// `SessionGetInfo`'s graphic-access bit — the only probe that answers
    /// "is there a window server" (there is no `WindowServer` process to look
    /// for: measured 2026-09-23, `NSRunningApplication` reports none).
    public var hasGraphicAccess: Bool?
    public var dockRunning: Bool
    public var finderRunning: Bool
    public var screenLocked: Bool

    public init(
        sessionDictionaryReadable: Bool,
        loginDone: Bool?,
        hasGraphicAccess: Bool?,
        dockRunning: Bool,
        finderRunning: Bool,
        screenLocked: Bool
    ) {
        self.sessionDictionaryReadable = sessionDictionaryReadable
        self.loginDone = loginDone
        self.hasGraphicAccess = hasGraphicAccess
        self.dockRunning = dockRunning
        self.finderRunning = finderRunning
        self.screenLocked = screenLocked
    }
}

/// Why a session is not ready to be driven, in the order the checks run.
public enum DesktopGap: String, CaseIterable, Equatable, Sendable {
    case sessionDictionary
    case windowServer
    case login
    case locked
    case dock
    case finder

    /// One clause, for a log line or a refusal a person has to read.
    public var clause: String {
        switch self {
        case .sessionDictionary: return "the session dictionary could not be read"
        case .windowServer: return "this session has no window server"
        case .login: return "the desktop login has not finished"
        case .locked: return "the session's screen is locked"
        case .dock: return "the Dock is not running"
        case .finder: return "Finder is not running"
        }
    }
}

public struct DesktopReadiness: Equatable, Sendable {
    public let gaps: [DesktopGap]

    public init(gaps: [DesktopGap]) { self.gaps = gaps }

    public var isReady: Bool { gaps.isEmpty }

    /// One line, for `status`, for the startup log, and for the refusal.
    public var summary: String {
        isReady ? "desktop ready" : "desktop not ready: " + gaps.map(\.clause).joined(separator: ", ")
    }
}

/// The rule the worker's startup order and its input path both ask.
///
/// Plan: *Session → Desktop Ready → Capture → Input*, and never a `CGEvent`
/// into a session that is not ready. The session-level refusals this repository
/// already had — `isConsole`, `indeterminate`, `noWindowServer` — are about
/// **safety**; this one is about **existence**: a session whose Dock and Finder
/// are not up is a bare window server, and the symptom a person reports from it
/// is input that lands nowhere.
///
/// The answer is re-read per call rather than cached at startup, so a session
/// that finishes coming up (or gets locked) is picked up without restarting the
/// worker.
public enum DesktopReadinessCheck {

    public static func evaluate(_ facts: DesktopFacts) -> DesktopReadiness {
        var gaps: [DesktopGap] = []
        if !facts.sessionDictionaryReadable { gaps.append(.sessionDictionary) }
        if facts.hasGraphicAccess != true { gaps.append(.windowServer) }
        if facts.loginDone != true { gaps.append(.login) }
        if facts.screenLocked { gaps.append(.locked) }
        if !facts.dockRunning { gaps.append(.dock) }
        if !facts.finderRunning { gaps.append(.finder) }
        return DesktopReadiness(gaps: gaps)
    }

    /// What to throw before posting anything. `nil` when the desktop is ready.
    ///
    /// `SESSION_NOT_READY` is the existing code for exactly this: the session
    /// exists but cannot serve, and it is recoverable by logging in — so the
    /// message names that fix rather than leaving "not ready" to be guessed at.
    public static func refusal(_ readiness: DesktopReadiness, spaceName: String) -> AgentSpaceError? {
        guard !readiness.isReady else { return nil }
        return AgentSpaceError(
            code: .sessionNotReady,
            message: "refusing to inject input into the '\(spaceName)' session: \(readiness.summary). "
                + "Dock and Finder are what make a session a desktop rather than a bare window server, so AgentSpace waits for them before posting events. "
                + "Log the agent account in through the GUI (its Dock and Finder start with the session) and retry.")
    }
}
