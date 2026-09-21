import Foundation

/// One published AgentSpace release, reduced to what an update needs: a
/// version, the notes, and an archive whose digest GitHub already knows.
public struct SoftwareRelease: Equatable, Sendable {
    public let version: SoftwareVersion
    public let releaseNotes: String
    public let archiveURL: URL
    public let sha256: String

    public init(version: SoftwareVersion, releaseNotes: String, archiveURL: URL, sha256: String) {
        self.version = version
        self.releaseNotes = releaseNotes
        self.archiveURL = archiveURL
        self.sha256 = sha256
    }

    public func isNewer(than currentVersion: String) -> Bool {
        guard let current = SoftwareVersion(currentVersion) else { return false }
        return current < version
    }

    /// The `/releases/latest` API response.
    ///
    /// The digest is required rather than optional: GitHub publishes the SHA-256
    /// it stored for the asset, so an update never has to trust a checksum that
    /// travelled with the bytes it is meant to describe.
    public static func decodeGitHubResponse(_ data: Data) throws -> SoftwareRelease {
        let response = try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
        guard !response.draft, !response.prerelease,
              let version = SoftwareVersion(response.tagName) else {
            throw SoftwareUpdateError.invalidRelease
        }
        let expectedName = AgentSpaceIdentity.archiveName(for: version.description)
        guard let asset = response.assets.first(where: { $0.name == expectedName }),
              asset.url.scheme == "https",
              let digest = asset.digest, digest.hasPrefix("sha256:") else {
            throw SoftwareUpdateError.missingVerifiedArchive
        }
        return SoftwareRelease(
            version: version,
            releaseNotes: response.body,
            archiveURL: asset.url,
            sha256: try validatedDigest(digest)
        )
    }

    /// The release page's asset fragment, used when the anonymous API limit for
    /// this IP is exhausted. The public page still carries GitHub's stored
    /// digest, so the fallback keeps the property that matters: the expected
    /// checksum comes from GitHub, not from the source of the bytes.
    public static func decodeGitHubAssetsHTML(
        _ data: Data,
        tagName: String,
        repository: String = AgentSpaceIdentity.githubRepository
    ) throws -> SoftwareRelease {
        guard let version = SoftwareVersion(tagName) else {
            throw SoftwareUpdateError.invalidRelease
        }
        let expectedName = AgentSpaceIdentity.archiveName(for: version.description)
        let html = String(decoding: data, as: UTF8.self)
        let escapedRepository = NSRegularExpression.escapedPattern(for: repository)
        let pattern =
            #"href="(/\#(escapedRepository)/releases/download/[^/]+/([^"/]+\.dmg))"[\s\S]*?sha256:([0-9a-fA-F]{64})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            throw SoftwareUpdateError.invalidRelease
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.matches(in: html, range: range).first(where: {
            guard let nameRange = Range($0.range(at: 2), in: html) else { return false }
            return String(html[nameRange]) == expectedName
        }),
          let pathRange = Range(match.range(at: 1), in: html),
          let digestRange = Range(match.range(at: 3), in: html),
          let url = URL(string: "https://github.com\(html[pathRange])") else {
            throw SoftwareUpdateError.missingVerifiedArchive
        }
        return SoftwareRelease(
            version: version,
            releaseNotes: "",
            archiveURL: url,
            sha256: try validatedDigest("sha256:" + String(html[digestRange]))
        )
    }

    private static func validatedDigest(_ digest: String) throws -> String {
        let value = String(digest.dropFirst("sha256:".count)).lowercased()
        guard value.count == 64, value.allSatisfy(\.isHexDigit) else {
            throw SoftwareUpdateError.missingVerifiedArchive
        }
        return value
    }
}

private struct GitHubReleaseResponse: Decodable {
    struct Asset: Decodable {
        let name: String
        let url: URL
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name
            case url = "browser_download_url"
            case digest
        }
    }

    let tagName: String
    let body: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case draft
        case prerelease
        case assets
    }
}
