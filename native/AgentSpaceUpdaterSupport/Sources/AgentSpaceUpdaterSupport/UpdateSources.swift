import Foundation

/// Where the archive bytes may be fetched from.
///
/// Only this project's own GitHub release assets are ever rewritten, and only
/// onto a built-in mirror domain. What a mirror can affect is whether the
/// download is fast; it cannot affect what gets installed, because the expected
/// SHA-256 comes from GitHub's own record of the asset and every mirror result
/// is checked against it before anything is unpacked.
public enum UpdateSources {
    /// GitHub paths of the form `/owner/repo/releases/download/tag/asset`,
    /// which a mirror serves under its own host.
    static let pathPrefixMirror = "xget.xi-xu.me"
    /// Mirrors that proxy an absolute URL passed through as their path.
    static let absoluteURLMirrors = ["ghfast.top", "gh-proxy.org"]

    /// Candidate sources for `original`: mirrors in this order, then the origin
    /// last. A previously successful mirror host is hoisted to the front;
    /// everything else keeps this order. A URL that is not one of this project's
    /// GitHub release assets is returned unchanged.
    public static func sources(for original: URL, preferredHost: String? = nil) -> [URL] {
        guard original.scheme == "https", original.host == "github.com",
              original.user == nil, original.password == nil, original.port == nil,
              original.path.hasPrefix("/\(AgentSpaceIdentity.githubRepository)/releases/download/"),
              let components = URLComponents(url: original, resolvingAgainstBaseURL: false) else {
            return [original]
        }
        var mirrors: [URL] = []
        var pathPrefixed = components
        pathPrefixed.host = pathPrefixMirror
        pathPrefixed.percentEncodedPath = "/gh" + components.percentEncodedPath
        if let url = pathPrefixed.url { mirrors.append(url) }
        for host in absoluteURLMirrors {
            if let url = URL(string: "https://\(host)/\(original.absoluteString)") {
                mirrors.append(url)
            }
        }
        if let index = mirrors.firstIndex(where: { $0.host == preferredHost }) {
            mirrors.insert(mirrors.remove(at: index), at: 0)
        }
        return mirrors + [original]
    }

    /// Whether `host` is one of the built-in mirrors, and so worth remembering as
    /// the preferred source. Anything else — including GitHub itself — clears the
    /// preference and returns to the default order.
    public static func isBuiltinMirror(_ host: String?) -> Bool {
        guard let host else { return false }
        return host == pathPrefixMirror || absoluteURLMirrors.contains(host)
    }
}
