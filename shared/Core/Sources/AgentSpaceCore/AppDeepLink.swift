import Foundation

/// The URL scheme that lets anything outside the app — the CLI's `desktop`
/// command, an integration, a user's own script — put a specific Space's
/// Desktop Viewer in front of the user: `agentspace://space/<uuid>`.
///
/// It is one-way and deliberately small. The CLI never drives the app beyond
/// "open this Space's viewer"; everything after that is the app's own §52
/// pull-model preview, so a stray link cannot start a stream, let alone touch
/// a session. A link for a Space that does not exist is reported inside the
/// app (SPACE_NOT_FOUND), not by whatever posted it — the poster may be long
/// gone by the time the click lands.
public enum AppDeepLink {

    public static let scheme = "agentspace"

    /// `agentspace://space/<uuid>`
    public static func url(forSpaceID id: UUID) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "space"
        components.path = "/" + id.uuidString
        return components.url!
    }

    /// The Space ID inside a deep link, or nil for anything else. Only exact
    /// `agentspace://space/<uuid>` links resolve; unknown hosts and malformed
    /// paths are refused rather than guessed at.
    public static func spaceID(in url: URL) -> UUID? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == "space" else { return nil }
        let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return UUID(uuidString: raw)
    }
}
