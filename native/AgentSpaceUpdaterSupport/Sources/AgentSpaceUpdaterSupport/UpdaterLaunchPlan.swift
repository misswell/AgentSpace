import Foundation

/// The contract between the running app and the updater it launches, and the
/// paths both sides derive from it.
///
/// Living in the shared target is the point: the GUI builds the argument vector,
/// the updater reads it, and a test can assert the two agree without launching
/// either. An updater that mis-reads one argument would install over the wrong
/// path, which is the one failure mode here that costs the user their app.
public enum UpdaterLaunchPlan {
    public struct Arguments: Equatable {
        public let parentPID: pid_t
        /// The verified application inside the staging directory.
        public let sourceApplication: URL
        /// The application to replace.
        public let destinationApplication: URL
        /// Unpacked archive; the updater deletes it when it finishes.
        public let stagingDirectory: URL
        /// The copy of the updater itself, which cannot delete a running binary.
        public let helperDirectory: URL
        public let logURL: URL

        public init(
            parentPID: pid_t,
            sourceApplication: URL,
            destinationApplication: URL,
            stagingDirectory: URL,
            helperDirectory: URL,
            logURL: URL
        ) {
            self.parentPID = parentPID
            self.sourceApplication = sourceApplication
            self.destinationApplication = destinationApplication
            self.stagingDirectory = stagingDirectory
            self.helperDirectory = helperDirectory
            self.logURL = logURL
        }
    }

    public static func arguments(_ arguments: Arguments) -> [String] {
        [
            String(arguments.parentPID),
            arguments.sourceApplication.path,
            arguments.destinationApplication.path,
            arguments.stagingDirectory.path,
            arguments.helperDirectory.path,
            arguments.logURL.path,
        ]
    }

    /// `nil` unless this is exactly the vector `arguments(_:)` produces.
    public static func parse(_ values: [String]) -> Arguments? {
        guard values.count == 7,
              let parentPID = pid_t(values[1]), parentPID > 0 else { return nil }
        return Arguments(
            parentPID: parentPID,
            sourceApplication: URL(fileURLWithPath: values[2]),
            destinationApplication: URL(fileURLWithPath: values[3]),
            stagingDirectory: URL(fileURLWithPath: values[4]),
            helperDirectory: URL(fileURLWithPath: values[5]),
            logURL: URL(fileURLWithPath: values[6])
        )
    }

    /// The updater is a plain command-line tool nested in the bundle next to the
    /// CLI, which is where `scripts/bundle-app.sh` puts helpers that are not the
    /// main binary.
    public static func updaterURL(in applicationURL: URL) -> URL {
        applicationURL
            .appendingPathComponent("Contents/Helpers", isDirectory: true)
            .appendingPathComponent(AgentSpaceIdentity.updaterExecutableName)
    }

    /// Relaunching the executable directly rather than through LaunchServices:
    /// the record for a path that was just replaced is exactly as stale as it
    /// sounds, and `open` would also hand the relaunched app this process's
    /// environment — including a test harness's `AGENTSPACE_ROOT` (§300).
    public static func directExecutableURL(
        for application: URL,
        executableName: String = AgentSpaceIdentity.executableName
    ) -> URL {
        application
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent(executableName)
    }

    /// The scratch names in the destination's own directory. Both are dot-prefixed
    /// so a half-finished update is invisible in Finder but still findable by a
    /// `ls -a` when diagnosing one.
    public static func incomingApplicationURL(
        replacing destination: URL,
        token: String = UUID().uuidString
    ) -> URL {
        destination.deletingLastPathComponent()
            .appendingPathComponent(".AgentSpace-update-\(token).app")
    }

    public static func backupApplicationURL(
        replacing destination: URL,
        token: String = UUID().uuidString
    ) -> URL {
        destination.deletingLastPathComponent()
            .appendingPathComponent(".AgentSpace-backup-\(token).app")
    }

    public static func logURL(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Logs/AgentSpace", isDirectory: true)
            .appendingPathComponent("update.log")
    }
}

/// Whether this running copy can be replaced in place.
public enum UpdateInstallLocation: Equatable {
    /// `/Applications/AgentSpace.app` — the supported case.
    case applicationsDirectory
    /// Gatekeeper moved a quarantined copy to a randomized read-only path.
    case translocated
    /// Anywhere else: a build folder, `dist/`, Downloads.
    case elsewhere
}

public enum UpdateInstallation {
    /// Where a running copy may be replaced.
    ///
    /// Restricted to `/Applications` on purpose. An in-place replacement is the
    /// one operation in this app that destroys a bundle, and the developer's own
    /// `dist/AgentSpace.app` is a notarized artifact that a silently successful
    /// "update" would overwrite with GitHub's bytes.
    public static func classify(applicationURL: URL) -> UpdateInstallLocation {
        let standardized = applicationURL.standardizedFileURL.path
        if standardized.contains("/AppTranslocation/") { return .translocated }
        for parent in ["/Applications", "/System/Volumes/Data/Applications"] {
            if standardized == parent + "/" + AgentSpaceIdentity.appBundleName {
                return .applicationsDirectory
            }
        }
        return .elsewhere
    }

    /// Why an update cannot be applied here, in the words the UI shows. `nil`
    /// means the location is fine; writability is checked separately because
    /// only the caller's filesystem knows the answer.
    public static func obstruction(
        for location: UpdateInstallLocation,
        applicationURL: URL,
        isParentWritable: Bool
    ) -> String? {
        switch location {
        case .translocated:
            return applicationURL.path
        case .elsewhere:
            return applicationURL.path
        case .applicationsDirectory:
            return isParentWritable ? nil : applicationURL.deletingLastPathComponent().path
        }
    }
}
