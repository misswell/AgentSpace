import Foundation
import CoreGraphics
import Security

/// The facts about *this* process's session that the safety rules depend on.
///
/// Split behind a protocol so `SessionGuard` — the code that decides whether
/// synthetic input may be posted — is unit-testable against synthetic
/// dictionaries. A guard that can only be tested by actually being on the
/// console is a guard nobody tests.
public protocol SessionInfoSource: Sendable {
    /// `CGSessionCopyCurrentDictionary()`, or nil when it cannot be read.
    func currentSessionDictionary() -> [String: Any]?
    /// `SessionGetInfo(callerSecuritySession, ...)` graphic-access bit, or nil
    /// when the call itself failed.
    func hasGraphicAccess() -> Bool?
    /// Effective uid of this process.
    func currentUID() -> uid_t
}

/// The real world. Every value here was confirmed by running
/// `tests/probes/SessionProbe.swift` on macOS 27.0 (build 26A428, arm64);
/// see docs/validation.md for the captured output.
public struct SystemSessionInfo: SessionInfoSource {
    public init() {}

    public func currentSessionDictionary() -> [String: Any]? {
        CGSessionCopyCurrentDictionary() as? [String: Any]
    }

    public func hasGraphicAccess() -> Bool? {
        var sid: SecuritySessionId = 0
        var bits = SessionAttributeBits(rawValue: 0)
        let status = SessionGetInfo(callerSecuritySession, &sid, &bits)
        guard status == errSecSuccess else { return nil }
        return bits.contains(.sessionHasGraphicAccess)
    }

    public func currentUID() -> uid_t { getuid() }
}

/// The verdict on whether this session may be driven.
public enum SessionVerdict: Equatable, Sendable {
    /// Background Aqua session, not on the console. Input may be posted.
    case usable
    /// This session is the physical console: the human is looking at it.
    /// Posting here would type on their screen. Hard refusal.
    case isConsole
    /// No window server in this session. Nothing GUI can be driven.
    case noWindowServer
    /// The session dictionary could not be read or did not answer the
    /// console question. Treated as `isConsole`: see `SessionGuard`.
    case indeterminate

    public var permitsInput: Bool { self == .usable }

    public var errorCode: AgentSpaceErrorCode {
        switch self {
        case .usable: return .internalError
        case .isConsole, .indeterminate: return .sessionIsConsole
        case .noWindowServer: return .noWindowServer
        }
    }
}

/// Decides whether this session is safe to post input into. Plan §12.
///
/// The rule this type exists to enforce:
///
/// > If we cannot *prove* the session is a background one, we do not post.
///
/// Both failure directions collapse to a refusal. An unreadable session
/// dictionary is not "probably fine"; it is `indeterminate`, and
/// `indeterminate` refuses exactly like `isConsole` does. There is deliberately
/// no code path here that returns `usable` on a missing answer — that is the
/// "fall back to the user's desktop" bug the whole product is built to avoid.
public enum SessionGuard {

    /// The key macOS actually uses in the dictionary returned by
    /// `CGSessionCopyCurrentDictionary()`.
    ///
    /// Measured on macOS 27.0: the dictionary contains
    /// `kCGSSessionOnConsoleKey` (two S's) and does **not** contain the
    /// documented-flavoured `kCGSessionOnConsoleKey` (one S). Both are accepted
    /// so a future OS that switches spelling does not silently disarm the
    /// guard; the double-S form is checked first because that is the one that
    /// has been observed.
    public static let onConsoleKeyDoubleS = "kCGSSessionOnConsoleKey"
    public static let onConsoleKeySingleS = "kCGSessionOnConsoleKey"

    /// Read the console bit. `nil` means "could not tell", which callers must
    /// treat as console.
    public static func onConsole(
        dictionary: [String: Any]?
    ) -> Bool? {
        guard let dictionary else { return nil }
        let raw = dictionary[onConsoleKeyDoubleS] ?? dictionary[onConsoleKeySingleS]
        guard let value = raw else { return nil }
        // CGSessionCopyCurrentDictionary bridges these as CFBoolean/NSNumber.
        // Anything that is not a boolean-ish number is not an answer.
        if let n = value as? NSNumber { return n.boolValue }
        if let b = value as? Bool { return b }
        return nil
    }

    /// The full verdict, in the order the checks must run.
    ///
    /// Window server first: a session with no graphics cannot be a console in
    /// any meaningful sense, and reporting `NO_WINDOW_SERVER` is more useful to
    /// the operator than `SESSION_IS_CONSOLE` for the "you ssh'd in" case.
    public static func verdict(using source: SessionInfoSource) -> SessionVerdict {
        if let graphic = source.hasGraphicAccess(), graphic == false {
            return .noWindowServer
        }
        switch onConsole(dictionary: source.currentSessionDictionary()) {
        case .some(true): return .isConsole
        case .some(false): return .usable
        // Could not read the dictionary, or it carried no usable console bit.
        // Fail closed. This is the single most important branch in the file.
        case .none: return .indeterminate
        }
    }

    /// Convenience for the real system.
    public static func currentVerdict() -> SessionVerdict {
        verdict(using: SystemSessionInfo())
    }

    /// Whether a session that is *not* the console but has no window server
    /// should still be reported as unusable. Always true; named so the intent
    /// is greppable.
    public static let refusesWithoutWindowServer = true
}

/// Guard for the process's own privilege level. Plan §7 / §63.10: the worker is
/// a standard user and must refuse to run as root, because a root worker would
/// hand an injected agent the whole machine.
public enum PrivilegeGuard {
    public static func refuseReason(uid: uid_t) -> AgentSpaceError? {
        if uid == 0 {
            return AgentSpaceError(
                code: .workerIsRoot,
                message: "agentspace-worker is running as root (uid 0). It must run as the AgentSpace user inside that user's own Aqua session.")
        }
        return nil
    }

    public static func check(uid: uid_t) throws {
        if let reason = refuseReason(uid: uid) { throw reason }
    }
}
