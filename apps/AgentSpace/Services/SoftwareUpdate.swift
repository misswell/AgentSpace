import AppKit
import AgentSpaceCore
import AgentSpaceUpdaterSupport
import Foundation

/// The version the release channel's tag names, not `AppModel.displayVersion` —
/// the build number in that string is this repo's commit count and means nothing
/// to a published release.
private func marketingVersion() -> String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? agentSpaceVersion
}

/// A package that has been unpacked from a verified archive and is ready to be
/// swapped in.
struct VerifiedUpdatePackage: Sendable {
    let applicationURL: URL
    let workingDirectory: URL
}

/// The online update channel: GitHub's latest AgentSpace release.
///
/// Two network paths, one trust path. Metadata (version, asset, and the SHA-256
/// GitHub stored for that asset) always comes from GitHub; only the archive
/// bytes may come from a mirror. Everything that decides whether this is
/// AgentSpace — digest, signature, developer team, designated requirement,
/// Gatekeeper — runs on the unpacked bundle before anything is terminated, so a
/// refused update costs a download and nothing else.
@MainActor
final class SoftwareUpdater: ObservableObject {
    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/\(AgentSpaceIdentity.githubRepository)/releases/latest")!
    static let latestReleasePageURL = URL(
        string: "https://github.com/\(AgentSpaceIdentity.githubRepository)/releases/latest")!
    static let mirrorHostDefaultsKey = "updateDownloadMirrorHost"

    @Published private(set) var state: SoftwareUpdateState = .idle
    let currentVersion: String

    private let session: URLSession
    private let applicationURL: URL
    private var hasCheckedAutomatically = false

    init(
        currentVersion: String = marketingVersion(),
        session: URLSession = .shared,
        applicationURL: URL = Bundle.main.bundleURL
    ) {
        self.currentVersion = currentVersion
        self.session = session
        self.applicationURL = applicationURL
    }



    /// Where an in-place update is possible, and why it is not where it isn't.
    /// Checked before any download so the copy that cannot be replaced is named
    /// while it is still free to quit and be replaced by hand.
    var installObstruction: String? {
        let location = UpdateInstallation.classify(applicationURL: applicationURL)
        return UpdateInstallation.obstruction(
            for: location,
            applicationURL: applicationURL,
            isParentWritable: FileManager.default.isWritableFile(
                atPath: applicationURL.deletingLastPathComponent().path)
        )
    }

    var canInstallUpdates: Bool { installObstruction == nil }

    /// Where this copy lives, in the sentence the Update tab opens with.
    var applicationDirectory: String { applicationURL.deletingLastPathComponent().path }

    func checkForUpdates(automatic: Bool = false) async {
        guard !state.isBusy else { return }
        if automatic {
            guard SoftwareUpdater.permittedAutomaticCheck, !hasCheckedAutomatically else { return }
            hasCheckedAutomatically = true
        }
        state = .checking
        do {
            let release = try await fetchLatestRelease()
            state = release.isNewer(than: currentVersion) ? .available(release) : .upToDate
        } catch {
            // A check nobody asked for does not get to show an error banner. It
            // still goes to the update log, where a failed check is findable.
            if automatic {
                UpdateDiagnostics.log("Automatic check failed: \(String(describing: error))")
                state = .idle
            } else {
                state = .failed(SoftwareUpdateFailure(error))
            }
        }
    }

    /// An instance pointed at a non-default registry is a development or gate
    /// run, not the owner's app. It must not make outbound requests or leave an
    /// "update available" mark on screen — `scripts/gui-verify.sh` launches one
    /// per run, and an uncontrolled network call in a gate is a flake factory.
    static var permittedAutomaticCheck: Bool {
        AgentSpaceEnvironment.rootOverride == nil
    }

    func downloadAndInstall() async {
        guard case .available(let release) = state else { return }
        guard installObstruction == nil else {
            state = .failed(SoftwareUpdateFailure(
                SoftwareUpdateError.installationUnavailable(applicationURL.path)))
            return
        }
        state = .downloading(release)
        do {
            let downloadURL = try await download(release: release)
            defer { try? FileManager.default.removeItem(at: downloadURL) }
            state = .installing(release)
            let package = try await Task.detached(priority: .userInitiated) {
                try UpdatePackageValidator.prepare(downloadURL: downloadURL, release: release)
            }.value
            defer { try? FileManager.default.removeItem(at: package.workingDirectory) }
            try launchInstaller(for: package)
            NSApp.terminate(nil)
        } catch {
            // The user-facing message groups several distinct checks, so the
            // exact reason goes to the log a failed update can be read from.
            UpdateDiagnostics.log("Update failed: \(String(describing: error))")
            state = .failed(SoftwareUpdateFailure(error))
        }
    }

    func reset() { state = .idle }

    // MARK: - Release metadata

    private func fetchLatestRelease() async throws -> SoftwareRelease {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AgentSpace/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200:
            return try SoftwareRelease.decodeGitHubResponse(data)
        // The anonymous API limit is per shared IP, so a full household can
        // exhaust it. The public release page still carries the asset links and
        // GitHub's stored digests.
        case 403:
            return try await fetchLatestReleaseFromWeb()
        default:
            throw SoftwareUpdateError.invalidResponse
        }
    }

    private func fetchLatestReleaseFromWeb() async throws -> SoftwareRelease {
        var latestRequest = URLRequest(url: Self.latestReleasePageURL)
        latestRequest.setValue("AgentSpace/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        latestRequest.timeoutInterval = 20
        let (_, latestResponse) = try await session.data(for: latestRequest)
        guard (latestResponse as? HTTPURLResponse)?.statusCode == 200,
              let finalURL = latestResponse.url,
              let tagName = finalURL.pathComponents.last,
              !tagName.isEmpty, tagName != "latest" else {
            throw SoftwareUpdateError.invalidResponse
        }
        guard let assetsURL = URL(string: "https://github.com/\(AgentSpaceIdentity.githubRepository)"
            + "/releases/expanded_assets/\(tagName)") else {
            throw SoftwareUpdateError.invalidResponse
        }
        var assetsRequest = URLRequest(url: assetsURL)
        assetsRequest.setValue("AgentSpace/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        assetsRequest.timeoutInterval = 20
        let (assetsData, assetsResponse) = try await session.data(for: assetsRequest)
        guard (assetsResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw SoftwareUpdateError.invalidResponse
        }
        return try SoftwareRelease.decodeGitHubAssetsHTML(assetsData, tagName: tagName)
    }

    // MARK: - Archive bytes

    private func download(release: SoftwareRelease) async throws -> URL {
        let preferredHost = UserDefaults.standard.string(forKey: Self.mirrorHostDefaultsKey)
        var lastError: any Error = SoftwareUpdateError.invalidResponse
        for source in UpdateSources.sources(for: release.archiveURL, preferredHost: preferredHost) {
            try Task.checkCancellation()
            var request = URLRequest(url: source)
            // A stalled mirror must not prevent the direct attempt; an active
            // transfer keeps receiving past this interval.
            request.timeoutInterval = 15
            request.setValue("AgentSpace", forHTTPHeaderField: "User-Agent")
            do {
                let (file, response) = try await session.download(for: request)
                do {
                    try Task.checkCancellation()
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        throw SoftwareUpdateError.invalidResponse
                    }
                    let digest = try await Task.detached(priority: .utility) {
                        try ArchiveDigest.sha256(of: file)
                    }.value
                    guard digest == release.sha256 else { throw SoftwareUpdateError.digestMismatch }
                    try Task.checkCancellation()
                    remember(source: source)
                    return file
                } catch {
                    try? FileManager.default.removeItem(at: file)
                    throw error
                }
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw error
                }
                try Task.checkCancellation()
                lastError = error
                UpdateDiagnostics.log("Source \(source.host ?? "unknown") failed: \(error)")
            }
        }
        throw lastError
    }

    /// Remember only a mirror that both worked and is built in. A successful
    /// direct download clears the preference, so a changed network re-runs the
    /// default order instead of sticking to a mirror that has since gone away.
    private func remember(source: URL) {
        let defaults = UserDefaults.standard
        if UpdateSources.isBuiltinMirror(source.host) {
            defaults.set(source.host, forKey: Self.mirrorHostDefaultsKey)
        } else {
            defaults.removeObject(forKey: Self.mirrorHostDefaultsKey)
        }
    }

    // MARK: - Install

    private func launchInstaller(for package: VerifiedUpdatePackage) throws {
        guard let bundledUpdater = UpdaterLaunchPlan.updaterURL(in: applicationURL)
            .takeIfExecutable() else {
            throw SoftwareUpdateError.updaterHelperMissing
        }
        // The updater runs from a copy: the bundle it lives in is the thing being
        // replaced, and a binary cannot be deleted out from under itself.
        let helperDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentSpaceUpdater-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: helperDirectory, withIntermediateDirectories: true)
        let helperURL = helperDirectory.appendingPathComponent(AgentSpaceIdentity.updaterExecutableName)
        try FileManager.default.copyItem(at: bundledUpdater, to: helperURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)

        let process = Process()
        process.executableURL = helperURL
        process.arguments = UpdaterLaunchPlan.arguments(UpdaterLaunchPlan.Arguments(
            parentPID: ProcessInfo.processInfo.processIdentifier,
            sourceApplication: package.applicationURL,
            destinationApplication: applicationURL,
            stagingDirectory: package.workingDirectory,
            helperDirectory: helperDirectory,
            logURL: UpdaterLaunchPlan.logURL(
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        ))
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}

private extension URL {
    func takeIfExecutable() -> URL? {
        FileManager.default.isExecutableFile(atPath: path) ? self : nil
    }
}

/// Unpacks a downloaded DMG and proves the AgentSpace inside it is ours.
enum UpdatePackageValidator {
    static func prepare(downloadURL: URL, release: SoftwareRelease) throws -> VerifiedUpdatePackage {
        guard try ArchiveDigest.sha256(of: downloadURL) == release.sha256 else {
            throw SoftwareUpdateError.digestMismatch
        }
        let fileManager = FileManager.default
        let workingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("AgentSpaceUpdate-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        do {
            let stagedApplication = workingDirectory
                .appendingPathComponent(AgentSpaceIdentity.appBundleName, isDirectory: true)
            let mounted = try mount(downloadURL, into: workingDirectory)
            defer { detach(mounted) }
            let candidate = mounted.appendingPathComponent(
                AgentSpaceIdentity.appBundleName, isDirectory: true)
            try verify(candidate, release: release)
            // ditto, not cp: it is the copy that preserves resource forks,
            // symlinks and the signature bytes that the verification just proved.
            try run("/usr/bin/ditto", [candidate.path, stagedApplication.path])
            stripQuarantine(from: stagedApplication)
            return VerifiedUpdatePackage(
                applicationURL: stagedApplication, workingDirectory: workingDirectory)
        } catch {
            try? fileManager.removeItem(at: workingDirectory)
            throw error
        }
    }

    /// The DMG is downloaded, so macOS may have marked it quarantined. Mounting a
    /// quarantined image is what triggers a Gatekeeper prompt mid-update; the
    /// bytes have already matched GitHub's SHA-256 and every check below runs on
    /// what is inside, so the attribute is dropped rather than acted on.
    private static func mount(_ archiveURL: URL, into workingDirectory: URL) throws -> URL {
        stripQuarantine(from: archiveURL)
        let mountPoint = workingDirectory.appendingPathComponent("Volume", isDirectory: true)
        try FileManager.default.createDirectory(
            at: mountPoint, withIntermediateDirectories: true)
        do {
            try run("/usr/bin/hdiutil", [
                "attach", "-readonly", "-nobrowse", "-quiet",
                "-mountpoint", mountPoint.path, archiveURL.path,
            ])
        } catch {
            throw SoftwareUpdateError.archiveMountFailed
        }
        return mountPoint
    }

    private static func detach(_ mountPoint: URL) {
        _ = try? run("/usr/bin/hdiutil", ["detach", "-quiet", "-force", mountPoint.path])
    }

    private static func verify(_ applicationURL: URL, release: SoftwareRelease) throws {
        guard let bundle = Bundle(url: applicationURL),
              AgentSpaceIdentity.isKnownBundleIdentifier(bundle.bundleIdentifier),
              bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
                == AgentSpaceIdentity.executableName else {
            throw SoftwareUpdateError.invalidApplication
        }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard version.flatMap(SoftwareVersion.init) == release.version else {
            throw SoftwareUpdateError.versionMismatch
        }
        // The worker and the updater are inside the bundle the helper and the app
        // both reach through relative paths. An archive that ships without them
        // would install an app that cannot attach an account or update again.
        for relative in AgentSpaceIdentity.nestedCodePaths {
            guard FileManager.default.fileExists(
                atPath: applicationURL.appendingPathComponent(relative).path) else {
                throw SoftwareUpdateError.invalidApplication
            }
        }
        let shortVersion = release.version.description
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", applicationURL.path])
        let signature = try run("/usr/bin/codesign", ["--display", "--verbose=4", applicationURL.path])
        guard signature.contains("TeamIdentifier=\(AgentSpaceIdentity.developerTeamIdentifier)") else {
            throw SoftwareUpdateError.wrongDeveloperTeam
        }
        // Privacy grants are recorded against the designated requirement of the
        // app that was granted. An update keeps every grant — Accessibility and
        // Screen Recording for the worker, the helper's caller check — exactly
        // when it satisfies the running app's requirement, so compare semantics
        // rather than text: two builds of the same app can carry requirements
        // that differ in wording and mean the same thing.
        let runningRequirement = try designatedRequirement(of: Bundle.main.bundleURL)
        guard !runningRequirement.isEmpty, satisfies(runningRequirement, at: applicationURL) else {
            throw SoftwareUpdateError.identityMismatch
        }
        do {
            try run("/usr/sbin/spctl", ["--assess", "--type", "execute", applicationURL.path])
        } catch {
            throw SoftwareUpdateError.gatekeeperRejected
        }
        UpdateDiagnostics.log("Verified \(shortVersion) from \(release.archiveURL.host ?? "")")
    }

    static func designatedRequirement(of bundleURL: URL) throws -> String {
        CodesignRequirement.parse(from: try run(
            "/usr/bin/codesign", ["--display", "-r-", bundleURL.path]))
    }

    /// Whether the code at `bundleURL` satisfies `requirement` — the same test
    /// macOS runs against the requirement stored with a privacy grant.
    static func satisfies(_ requirement: String, at bundleURL: URL) -> Bool {
        guard !requirement.isEmpty else { return false }
        return (try? run("/usr/bin/codesign", [
            "--verify", "--strict", "-R", "=\(requirement)", bundleURL.path,
        ])) != nil
    }

    private static func stripQuarantine(from url: URL) {
        _ = try? run("/usr/bin/xattr", ["-d", "com.apple.quarantine", url.path])
    }

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            if executable == "/usr/bin/codesign" { throw SoftwareUpdateError.invalidSignature }
            throw SoftwareUpdateError.commandFailed(
                output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }
}

/// A second record of what the update channel decided, kept where a user can
/// find it without a terminal: the same log folder the Advanced tab reveals.
enum UpdateDiagnostics {
    static func log(_ message: String) {
        let url = UpdaterLaunchPlan.logURL(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] app: \(message)\n"
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: url, options: .atomic)
        }
    }
}
