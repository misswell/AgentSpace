import Foundation

/// The URL scheme that lets anything outside the app — the CLI's `open`
/// (formerly `desktop`) command, an integration, a user's own script — put a
/// specific agent account's Desktop Viewer in front of the user:
/// `agentspace://agent/<uuid>`.
///
/// It is one-way and deliberately small. The CLI never drives the app beyond
/// "open this Space's viewer"; everything after that is the app's own §52
/// pull-model preview, so a stray link cannot start a stream, let alone touch
/// a session. A link for a Space that does not exist is reported inside the
/// app (SPACE_NOT_FOUND), not by whatever posted it — the poster may be long
/// gone by the time the click lands.
public enum AppDeepLink {

    public static let scheme = "agentspace"

    /// `agentspace://agent/<uuid>` (plan(v2) §16). The previous host
    /// `space` is still parsed below, so links made before the rename keep
    /// working.
    public static func url(forSpaceID id: UUID) -> URL {
        url(forAccountID: id)
    }

    /// The V2 spelling of the same link.
    public static func url(forAccountID id: UUID) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "agent"
        components.path = "/" + id.uuidString
        return components.url!
    }

    /// The account ID inside a deep link, or nil for anything else. Both the
    /// current `agentspace://agent/<uuid>` and the pre-rename
    /// `agentspace://space/<uuid>` resolve; unknown hosts and malformed
    /// paths are refused rather than guessed at.
    public static func spaceID(in url: URL) -> UUID? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == "agent"
                  || url.host?.lowercased() == "space" else { return nil }
        let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return UUID(uuidString: raw)
    }
}
