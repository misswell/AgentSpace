import Foundation
import Darwin

/// Login is an explicit human action. Authentication stays in Apple's client;
/// neither the helper nor an agent RPC receives an account password.
public enum AccountLogin {
    /// A graphical session and live worker can both exist behind a lock screen.
    /// Unknown desktop readiness must not finish authentication either.
    public static func isReady(workerOnline: Bool, sessionVerdict: String?, desktopReady: Bool?) -> Bool {
        workerOnline && sessionVerdict == "usable" && desktopReady == true
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
