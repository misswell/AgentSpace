import Foundation
import Darwin

/// Login is an explicit human action. Authentication stays in Apple's client;
/// neither the helper nor an agent RPC receives an account password.
public enum AccountLogin {
    /// What the sign-in sheet is still waiting for. These all looked like one
    /// spinner until 2026-10-09, when the owner signed in successfully, watched
    /// 「正在等待 Agent 桌面…」 for minutes with no way to tell that the desktop was
    /// in fact sitting on its own lock screen asking for a password.
    /// Each case asks for a different thing, and only one of them is AgentSpace's
    /// to do.
    public enum Wait: Equatable, Sendable, CaseIterable {
        /// The helper's answer could not be believed. Distinct from `.noSession`
        /// because it is AgentSpace's own component failing, and the thing to
        /// reinstall is AgentSpace's helper rather than the macOS window.
        case probeFailed
        case noSession
        case workerOffline
        case desktopLocked
        case desktopNotReady

        /// For `os_log`, not for the interface: the UI localizes its own copy.
        public var logLabel: String {
            switch self {
            case .probeFailed: return "the session probe did not return an answer AgentSpace can believe"
            case .noSession: return "no desktop session for this account yet"
            case .workerOffline: return "session exists, its Worker is not answering yet"
            case .desktopLocked: return "session and Worker are live, the screen is still locked"
            case .desktopNotReady: return "session and Worker are live, the desktop is not ready"
            }
        }

        /// Whether only a person at the Mac can end this wait. Everything else is
        /// AgentSpace's own work, and a wait on it has to end rather than spin
        /// forever — the exemption exists for the lock screen alone, because how
        /// long someone takes to type a password is not this product's to time
        /// out.
        public var waitsOnAPerson: Bool {
            self == .desktopLocked
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

    /// What the session probe answered, as three outcomes rather than one
    /// boolean. The sheet used to read `try? HelperClient.call(...)`, so a helper
    /// that never answered, one that answered an error, and one that named a
    /// different account all produced the same `false` as "macOS has not signed
    /// this account in yet" — a statement about Apple that AgentSpace had no
    /// evidence for. Measured 2026-10-10: this is how a sign-in that macOS had
    /// already granted looked like a login that never happened, for as long as
    /// the probe itself was broken (`LaunchdDomain`).
    public enum SessionProbe: Equatable, Sendable {
        case graphicalSession
        case noSession
        /// Not answerable. `detail` is diagnostic text for the log, not copy.
        case unusable(detail: String)
    }

    public static func probe(_ response: HelperResponse?, for account: AgentAccount) -> SessionProbe {
        guard let response else { return .unusable(detail: "the privileged helper did not answer") }
        guard response.ok, let result = response.result else {
            return .unusable(detail: response.error?.message ?? "the helper returned no result")
        }
        guard result["username"]?.stringValue == account.username,
              result["uid"]?.intValue == Int(account.uid) else {
            return .unusable(detail: "the answer names "
                + "\(result["username"]?.stringValue ?? "<no user>")/"
                + "\(result["uid"]?.intValue.map(String.init) ?? "<no uid>") for "
                + "\(account.username)/\(account.uid)")
        }
        // An answer that says which of its three outcomes it is. `absent` is what
        // the sheet waits on; `unusable` is the helper's own failure, and waiting
        // on it cannot help.
        if let domain = result["sessionDomain"]?.stringValue {
            switch domain {
            case "graphical": return .graphicalSession
            case "absent": return .noSession
            default: return .unusable(detail: result["detail"]?.stringValue ?? "the probe reported \(domain)")
            }
        }
        // A helper from before the field existed can only say yes or no, and its
        // "no" is the answer this whole round is about: keep believing it only as
        // far as it goes, and never read its silence as a login.
        guard let graphical = result["hasGraphicalSession"]?.boolValue else {
            return .unusable(detail: "the answer carries no sessionDomain or hasGraphicalSession field")
        }
        return graphical ? .graphicalSession : .noSession
    }

    public static func hasSession(_ response: HelperResponse, for account: AgentAccount) -> Bool {
        probe(response, for: account) == .graphicalSession
    }
}
