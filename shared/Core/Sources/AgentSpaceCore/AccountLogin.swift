import Foundation
import Darwin

/// Login is an explicit human action. Authentication stays in Apple's client;
/// neither the helper nor an agent RPC receives an account password.
public enum AccountLogin {
    /// What the sign-in sheet is still waiting for. These all looked like one
    /// spinner until 2026-10-09, when the owner signed in successfully, watched
    /// 「正在等待 Agent 桌面…」 for nine minutes, and had no way to tell that the
    /// desktop was in fact sitting on its own lock screen asking for a password.
    /// Each case asks for a different thing, and only one of them is AgentSpace's
    /// to do.
    public enum Wait: Equatable, Sendable {
        case noSession
        case workerOffline
        case desktopLocked
        case desktopNotReady

        /// For `os_log`, not for the interface: the UI localizes its own copy.
        public var logLabel: String {
            switch self {
            case .noSession: return "no desktop session for this account yet"
            case .workerOffline: return "session exists, its Worker is not answering yet"
            case .desktopLocked: return "session and Worker are live, the screen is still locked"
            case .desktopNotReady: return "session and Worker are live, the desktop is not ready"
            }
        }
    }

    /// A graphical session and live worker can both exist behind a lock screen.
    /// Unknown desktop readiness must not finish authentication either.
    public static func isReady(workerOnline: Bool, sessionVerdict: String?, desktopReady: Bool?) -> Bool {
        workerOnline && sessionVerdict == "usable" && desktopReady == true
    }

    /// `nil` when `isReady` answers yes — one decision, so the reason a sheet is
    /// still open can never disagree with the condition that closes it.
    public static func wait(
        workerOnline: Bool,
        sessionVerdict: String?,
        desktopReady: Bool?,
        desktopLocked: Bool
    ) -> Wait? {
        guard !isReady(workerOnline: workerOnline, sessionVerdict: sessionVerdict, desktopReady: desktopReady) else {
            return nil
        }
        guard workerOnline else { return .workerOffline }
        return desktopLocked ? .desktopLocked : .desktopNotReady
    }

    public static func permits(_ account: AgentAccount, candidates: [LocalAccount], currentUID: uid_t = getuid()) -> Bool {
        account.uid != currentUID && AccountDiscovery.candidates(from: candidates).contains {
            $0.username == account.username && $0.uid == account.uid
        }
    }

    public static func url(username: String, port: UInt16) -> URL? {
        guard port != 0, port != 5900, !username.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "vnc"
        components.user = username
        components.host = "127.0.0.1"
        components.port = Int(port)
        return components.url
    }

    public static func hasSession(_ response: HelperResponse, for account: AgentAccount) -> Bool {
        response.ok
            && response.result?["username"]?.stringValue == account.username
            && response.result?["uid"]?.intValue == Int(account.uid)
            && response.result?["hasGraphicalSession"]?.boolValue == true
    }
}
