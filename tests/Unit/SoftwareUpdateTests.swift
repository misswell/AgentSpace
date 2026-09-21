import XCTest
import Foundation
import AgentSpaceUpdaterSupport

/// The update channel's decisions, asserted without a network, a bundle, or a
/// GUI session — everything that reaches the filesystem is a temp file this test
/// creates and removes, and nothing here touches /Applications.
final class SoftwareUpdateTests: XCTestCase {

    private static let digest = String(repeating: "ab", count: 32)

    private func json(
        tag: String = "v0.1.19",
        draft: Bool = false,
        prerelease: Bool = false,
        assets: String
    ) -> Data {
        Data("""
        {"tag_name":"\(tag)","name":"AgentSpace \(tag)","body":"Two things changed.",
         "draft":\(draft),"prerelease":\(prerelease),"assets":[\(assets)]}
        """.utf8)
    }

    private func asset(
        name: String = "AgentSpace-0.1.19.dmg",
        url: String = "https://github.com/misswell/AgentSpace/releases/download/v0.1.19/AgentSpace-0.1.19.dmg",
        digest: String? = "sha256:" + SoftwareUpdateTests.digest
    ) -> String {
        let digestField = digest.map { "\"digest\":\"\($0)\"," } ?? ""
        return "{\"name\":\"\(name)\",\(digestField)\"browser_download_url\":\"\(url)\"}"
    }

    // MARK: - Versions

    func testVersionOrderingPadsMissingComponentsAndAcceptsTheTagSpelling() {
        XCTAssertLessThan(SoftwareVersion("0.1.18")!, SoftwareVersion("0.1.19")!)
        XCTAssertLessThan(SoftwareVersion("0.9.9")!, SoftwareVersion("0.10.0")!)
        XCTAssertLessThan(SoftwareVersion("0.1.18")!, SoftwareVersion("1.0.0")!)
        XCTAssertEqual(SoftwareVersion("v0.1.19")!, SoftwareVersion("0.1.19")!)
        XCTAssertEqual(SoftwareVersion("0.1.19")!, SoftwareVersion("0.1.19.0")!)
        XCTAssertNil(SoftwareVersion("0.1.19-beta"))
        XCTAssertNil(SoftwareVersion(""))
    }

    func testAReleaseIsOnlyNewerWhenItIs() {
        let release = try! SoftwareRelease.decodeGitHubResponse(
            json(assets: asset()))
        XCTAssertTrue(release.isNewer(than: "0.1.18"))
        XCTAssertFalse(release.isNewer(than: "0.1.19"))
        XCTAssertFalse(release.isNewer(than: "0.1.20"))
        // A version string this comparison cannot read must never be outranked.
        XCTAssertFalse(release.isNewer(than: "dev"))
    }

    // MARK: - Release metadata

    func testGitHubResponseYieldsTheVersionNotesArchiveAndDigest() throws {
        let release = try SoftwareRelease.decodeGitHubResponse(json(assets: asset()))
        XCTAssertEqual(release.version, SoftwareVersion("0.1.19"))
        XCTAssertEqual(release.releaseNotes, "Two things changed.")
        XCTAssertEqual(release.archiveURL.scheme, "https")
        XCTAssertEqual(release.sha256, Self.digest)
    }

    func testAReleaseThatCannotBeTrustedToInstallIsRejected() {
        let cases: [(String, Data)] = [
            ("draft", json(draft: true, assets: asset())),
            ("prerelease", json(prerelease: true, assets: asset())),
            ("tag this parser cannot read", json(tag: "nightly", assets: asset())),
            ("no asset at all", json(assets: "")),
            ("an asset from another version", json(assets: asset(name: "AgentSpace-0.1.2.dmg"))),
        ]
        for (name, data) in cases {
            XCTAssertThrowsError(try SoftwareRelease.decodeGitHubResponse(data), name)
        }
    }

    /// The property the whole channel rests on: an archive with no checksum
    /// GitHub itself recorded is not offered, rather than being trusted.
    func testAnArchiveWithoutAStoredDigestIsNotOffered() {
        let malformed = [
            asset(digest: nil),
            asset(digest: "md5:\(Self.digest)"),
            asset(digest: "sha256:deadbeef"),
            asset(digest: "sha256:\(String(repeating: "z", count: 64))"),
        ]
        for each in malformed {
            XCTAssertThrowsError(
                try SoftwareRelease.decodeGitHubResponse(json(assets: each)), each)
        }
    }

    func testAnAssetServedOverHTTPIsRejected() {
        XCTAssertThrowsError(try SoftwareRelease.decodeGitHubResponse(json(assets: asset(
            url: "http://github.com/misswell/AgentSpace/releases/download/v0.1.19/AgentSpace-0.1.19.dmg"
        ))))
    }

    func testTheAssetsPageFallbackFindsTheSameArchiveAndDigest() throws {
        let html = """
        <div><a href="/misswell/AgentSpace/releases/download/v0.1.19/AgentSpace-0.1.19.dmg">\
        AgentSpace-0.1.19.dmg</a><span class="Truncate">sha256:\(Self.digest)</span></div>
        """
        let release = try SoftwareRelease.decodeGitHubAssetsHTML(
            Data(html.utf8), tagName: "v0.1.19")
        XCTAssertEqual(release.version, SoftwareVersion("0.1.19"))
        XCTAssertEqual(release.archiveURL.absoluteString,
                       "https://github.com/misswell/AgentSpace/releases/download/v0.1.19/AgentSpace-0.1.19.dmg")
        XCTAssertEqual(release.sha256, Self.digest)
    }

    func testTheAssetsPageFallbackIgnoresOtherProjectsAndUnrelatedDigests() {
        let foreign = """
        <a href="/someone/Else/releases/download/v0.1.19/AgentSpace-0.1.19.dmg">\
        AgentSpace-0.1.19.dmg</a> sha256:\(Self.digest)
        """
        XCTAssertThrowsError(try SoftwareRelease.decodeGitHubAssetsHTML(
            Data(foreign.utf8), tagName: "v0.1.19"))
        let noDigest = """
        <a href="/misswell/AgentSpace/releases/download/v0.1.19/AgentSpace-0.1.19.dmg">\
        AgentSpace-0.1.19.dmg</a>
        """
        XCTAssertThrowsError(try SoftwareRelease.decodeGitHubAssetsHTML(
            Data(noDigest.utf8), tagName: "v0.1.19"))
    }

    // MARK: - Download sources

    func testOnlyThisProjectsReleaseAssetsAreEverRewrittenOntoAMirror() {
        let release = URL(string: "https://github.com/misswell/AgentSpace/releases/download/v0.1.19/AgentSpace-0.1.19.dmg")!
        let sources = UpdateSources.sources(for: release)
        XCTAssertEqual(sources.count, 4)
        XCTAssertEqual(sources.last, release, "the origin must always be attempted")
        XCTAssertEqual(sources[0].absoluteString,
            "https://xget.xi-xu.me/gh/misswell/AgentSpace/releases/download/v0.1.19/AgentSpace-0.1.19.dmg")
        XCTAssertEqual(sources[1].absoluteString,
            "https://ghfast.top/https://github.com/misswell/AgentSpace/releases/download/v0.1.19/AgentSpace-0.1.19.dmg")
        XCTAssertEqual(sources[2].absoluteString,
            "https://gh-proxy.org/https://github.com/misswell/AgentSpace/releases/download/v0.1.19/AgentSpace-0.1.19.dmg")
        for mirror in sources.dropLast() {
            XCTAssertNotEqual(mirror.host, "github.com")
            XCTAssertEqual(mirror.scheme, "https")
        }

        let foreign = URL(string: "https://github.com/other/repo/releases/download/v1/thing.dmg")!
        XCTAssertEqual(UpdateSources.sources(for: foreign), [foreign])
        let notAnAsset = URL(string: "https://github.com/misswell/AgentSpace/releases")!
        XCTAssertEqual(UpdateSources.sources(for: notAnAsset), [notAnAsset])
    }

    func testAPreviouslyGoodMirrorGoesFirstAndTheRestKeepTheirOrder() {
        let release = URL(string: "https://github.com/misswell/AgentSpace/releases/download/v0.1.19/AgentSpace-0.1.19.dmg")!
        let sources = UpdateSources.sources(for: release, preferredHost: "gh-proxy.org")
        XCTAssertEqual(sources.map { $0.host },
                       ["gh-proxy.org", "xget.xi-xu.me", "ghfast.top", "github.com"])
        // A host that is not built in — including one an attacker controls and a
        // stale direct-download record — must not reorder anything.
        XCTAssertEqual(
            UpdateSources.sources(for: release, preferredHost: "evil.example").map { $0.host },
            UpdateSources.sources(for: release).map { $0.host })
        XCTAssertTrue(UpdateSources.isBuiltinMirror("xget.xi-xu.me"))
        XCTAssertFalse(UpdateSources.isBuiltinMirror("github.com"))
        XCTAssertFalse(UpdateSources.isBuiltinMirror(nil))
    }

    // MARK: - The GUI/updater contract

    func testTheArgumentVectorTheGUIBuildsIsTheOneTheUpdaterReads() {
        let plan = UpdaterLaunchPlan.Arguments(
            parentPID: 4242,
            sourceApplication: URL(fileURLWithPath: "/private/tmp/Stage/AgentSpace.app"),
            destinationApplication: URL(fileURLWithPath: "/Applications/AgentSpace.app"),
            stagingDirectory: URL(fileURLWithPath: "/private/tmp/Stage"),
            helperDirectory: URL(fileURLWithPath: "/private/tmp/Helper"),
            logURL: URL(fileURLWithPath: "/Users/tester/Library/Logs/AgentSpace/update.log"))
        let vector = ["agentspace-updater"] + UpdaterLaunchPlan.arguments(plan)
        XCTAssertEqual(UpdaterLaunchPlan.parse(vector), plan)
    }

    func testTheUpdaterRefusesAnyVectorThatIsNotExactlyWhatTheGUIPromised() {
        let good = ["agentspace-updater"] + UpdaterLaunchPlan.arguments(
            UpdaterLaunchPlan.Arguments(
                parentPID: 1,
                sourceApplication: URL(fileURLWithPath: "/s"),
                destinationApplication: URL(fileURLWithPath: "/d"),
                stagingDirectory: URL(fileURLWithPath: "/st"),
                helperDirectory: URL(fileURLWithPath: "/h"),
                logURL: URL(fileURLWithPath: "/l")))
        XCTAssertNil(UpdaterLaunchPlan.parse(Array(good.dropLast())))
        XCTAssertNil(UpdaterLaunchPlan.parse(good + ["/extra"]))
        var zeroPID = good
        zeroPID[1] = "0"
        XCTAssertNil(UpdaterLaunchPlan.parse(zeroPID),
                     "a parent pid of 0 would let the updater swap a bundle under a running app")
        XCTAssertNil(UpdaterLaunchPlan.parse(["agentspace-updater", "not-a-pid", "/s", "/d", "/st", "/h", "/l"]))
    }

    func testThePathsBothSidesDeriveFromTheDestination() {
        let destination = URL(fileURLWithPath: "/Applications/AgentSpace.app")
        XCTAssertEqual(UpdaterLaunchPlan.directExecutableURL(for: destination).path,
                       "/Applications/AgentSpace.app/Contents/MacOS/AgentSpace")
        XCTAssertEqual(UpdaterLaunchPlan.updaterURL(in: destination).path,
                       "/Applications/AgentSpace.app/Contents/Helpers/agentspace-updater")
        let token = "T"
        XCTAssertEqual(UpdaterLaunchPlan.incomingApplicationURL(replacing: destination, token: token).path,
                       "/Applications/.AgentSpace-update-T.app")
        XCTAssertEqual(UpdaterLaunchPlan.backupApplicationURL(replacing: destination, token: token).path,
                       "/Applications/.AgentSpace-backup-T.app")
        XCTAssertEqual(UpdaterLaunchPlan.logURL(
            homeDirectory: URL(fileURLWithPath: "/Users/tester")).path,
            "/Users/tester/Library/Logs/AgentSpace/update.log")
    }

    // MARK: - Where an update may be applied

    func testOnlyAnInstalledCopyMayReplaceItself() {
        XCTAssertEqual(UpdateInstallation.classify(
            applicationURL: URL(fileURLWithPath: "/Applications/AgentSpace.app")),
            .applicationsDirectory)
        XCTAssertEqual(UpdateInstallation.classify(
            applicationURL: URL(fileURLWithPath: "/System/Volumes/Data/Applications/AgentSpace.app")),
            .applicationsDirectory)
        XCTAssertEqual(UpdateInstallation.classify(
            applicationURL: URL(fileURLWithPath: "/Users/g/Code/solo/AgentSpace/dist/AgentSpace.app")),
            .elsewhere)
        // A quarantined copy runs from a randomized read-only path.
        XCTAssertEqual(UpdateInstallation.classify(
            applicationURL: URL(fileURLWithPath: "/private/var/folders/xx/AppTranslocation/"
                + "D5F1572F-D/AgentSpace.app")), .translocated)
        // Anything that merely *looks* like the applications folder does not pass.
        XCTAssertEqual(UpdateInstallation.classify(
            applicationURL: URL(fileURLWithPath: "/Applications/Else.app")), .elsewhere)
    }

    func testTheObstructionNamedForTheUIIsThePathTheUserHasToActOn() {
        let installed = URL(fileURLWithPath: "/Applications/AgentSpace.app")
        XCTAssertNil(UpdateInstallation.obstruction(
            for: .applicationsDirectory, applicationURL: installed, isParentWritable: true))
        XCTAssertEqual(
            UpdateInstallation.obstruction(
                for: .applicationsDirectory, applicationURL: installed, isParentWritable: false),
            "/Applications")
        XCTAssertEqual(
            UpdateInstallation.obstruction(
                for: .elsewhere,
                applicationURL: URL(fileURLWithPath: "/tmp/dist/AgentSpace.app"),
                isParentWritable: true),
            "/tmp/dist/AgentSpace.app")
    }

    // MARK: - Failures

    func testEveryFailureKindMapsToExactlyOneMessage() {
        let expectations: [(SoftwareUpdateError, SoftwareUpdateFailure.Message)] = [
            (.invalidRelease, .release),
            (.missingVerifiedArchive, .release),
            (.invalidResponse, .release),
            (.digestMismatch, .integrity),
            (.invalidApplication, .verification),
            (.versionMismatch, .verification),
            (.invalidSignature, .verification),
            (.wrongDeveloperTeam, .verification),
            (.identityMismatch, .verification),
            (.gatekeeperRejected, .verification),
            (.archiveMountFailed, .verification),
            (.installationUnavailable("/tmp/AgentSpace.app"), .location),
            (.updaterHelperMissing, .helper),
            (.commandFailed("ditto said no"), .command),
        ]
        for (error, message) in expectations {
            XCTAssertEqual(SoftwareUpdateFailure(error).message, message, String(describing: error))
        }
        // Anything else is a transport failure, and its text survives for the log.
        let other = SoftwareUpdateFailure(URLError(.notConnectedToInternet))
        XCTAssertEqual(other.message, .network)
        XCTAssertEqual(other.detail, URLError(.notConnectedToInternet).localizedDescription)
        XCTAssertEqual(
            SoftwareUpdateFailure(SoftwareUpdateError.commandFailed("ditto said no")).detail,
            "ditto said no")
    }

    func testBusyStatesAreBusyAndOnlyTheyExposeAnActivity() {
        let release = try! SoftwareRelease.decodeGitHubResponse(json(assets: asset()))
        XCTAssertEqual(SoftwareUpdateState.checking.activity, .checking)
        XCTAssertEqual(SoftwareUpdateState.downloading(release).activity, .downloading)
        XCTAssertEqual(SoftwareUpdateState.installing(release).activity, .installing)
        for idle in [SoftwareUpdateState.idle, .upToDate, .available(release),
                     .failed(SoftwareUpdateFailure(SoftwareUpdateError.invalidRelease))] {
            XCTAssertNil(idle.activity)
            XCTAssertFalse(idle.isBusy, String(describing: idle))
        }
        XCTAssertEqual(SoftwareUpdateState.available(release).availableRelease, release)
        XCTAssertNil(SoftwareUpdateState.upToDate.availableRelease)
    }

    // MARK: - Digests and requirement parsing

    func testTheDigestOfAKnownFileMatchesThePublishedTestVector() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentspace-digest-\(UUID().uuidString)")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try ArchiveDigest.sha256(of: url),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testTheDesignatedRequirementIsTheExpressionAfterTheArrow() {
        let output = """
            Identifier=com.agentspace.AgentSpace
            CodeDirectory v=20500 size=1234 flags=0x10000(runtime)
            TeamIdentifier=U8U443D7ZL
            designated => identifier "com.agentspace.AgentSpace" and anchor apple generic \
            and certificate leaf[field.1.2.840.113635.100.6.2.1] /* exists */
        """
        XCTAssertEqual(
            CodesignRequirement.parse(from: output),
            "identifier \"com.agentspace.AgentSpace\" and anchor apple generic "
            + "and certificate leaf[field.1.2.840.113635.100.6.2.1] /* exists */")
        XCTAssertEqual(CodesignRequirement.parse(from: "Identifier=com.agentspace.AgentSpace"), "")
    }
}

/// The channel's constants are copies of decisions made elsewhere in the repo.
/// These tests read those sources so a drift fails the build instead of failing
/// an update on a user's machine.
final class SoftwareUpdateDriftTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        let url = repoRoot.appendingPathComponent(relative)
        guard let data = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("\(relative) is not in this checkout")
        }
        return data
    }

    /// The helper asks "is this AgentSpace, signed by us?" about its caller; the
    /// updater asks the same question about a candidate. Two literals that drift
    /// apart mean either a refused update or an accepted impostor.
    func testTheUpdaterTrustsExactlyTheTeamTheHelperTrusts() throws {
        let caller = try source(
            "native/AgentSpacePrivilegedHelper/Sources/AgentSpacePrivilegedHelper/CallerVerification.swift")
        let pin = try XCTUnwrap(
            #"teamIdentifier = "([0-9A-Z]+)""#.matchingGroups(in: caller)?
                .first, "CallerVerification no longer pins a team identifier")
        XCTAssertEqual(AgentSpaceIdentity.developerTeamIdentifier, pin)
    }

    func testEveryNestedBinaryTheUpdateChecksForIsOneTheBundleBuilds() throws {
        let bundle = try source("scripts/bundle-app.sh")
        for path in AgentSpaceIdentity.nestedCodePaths {
            XCTAssertTrue(bundle.contains("\"$APP/\(path)\""),
                          "bundle-app.sh no longer installs $APP/\(path), which an update must carry")
        }
    }

    func testTheReleaseAssetTheUpdaterLooksForIsTheOneReleaseShips() throws {
        let release = try source("scripts/release.sh")
        XCTAssertTrue(release.contains("DMG=\"dist/AgentSpace-$VERSION.dmg\""),
                      "release.sh stopped producing dist/AgentSpace-<version>.dmg")
        XCTAssertEqual(AgentSpaceIdentity.archiveName(for: "0.1.19"), "AgentSpace-0.1.19.dmg")
    }

    func testTheBundleIdentifierCheckedInAnUpdateIsTheOneTheBundleSigns() throws {
        let bundle = try source("scripts/bundle-app.sh")
        XCTAssertTrue(bundle.contains("sign \"$APP\"                                  \"\(AgentSpaceIdentity.bundleIdentifier)\"")
                      || bundle.contains("\"\(AgentSpaceIdentity.bundleIdentifier)\""),
                      "bundle-app.sh no longer signs the app as \(AgentSpaceIdentity.bundleIdentifier)")
    }

    /// The channel is only as good as its address: a repository string that does
    /// not match the remote would have the app poll someone else's releases.
    func testTheConfiguredRepositoryIsThisCheckoutSRemote() throws {
        let config = try source(".git/config")
        XCTAssertTrue(config.contains("misswell/AgentSpace"),
                      "this checkout's remote does not mention \(AgentSpaceIdentity.githubRepository)")
    }
}

private extension String {
    func matchingGroups(in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: self) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (1..<match.numberOfRanges).compactMap {
            Range(match.range(at: $0), in: text).map { String(text[$0]) }
        }
    }
}
