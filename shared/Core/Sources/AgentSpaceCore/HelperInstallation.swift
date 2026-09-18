import Foundation
import ServiceManagement

/// Where the privileged helper is, and whether it can be reached.
///
/// `SMAppService.status` answers this question only for the **main bundle's own**
/// helper. That is fine inside the app and wrong everywhere else: the CLI lives at
/// `AgentSpace.app/Contents/Helpers/agentspace`, so for the CLI process
/// `Bundle.main` is `Contents/Helpers` and `SMAppService.daemon(plistName:)`
/// reports `.notFound` — on a machine where the helper is installed and working.
///
/// That produced a `doctor` warning that could not be cleared. Rather than special
/// case it in the check, the resolution lives here: find the app bundle that
/// contains this executable, look for the helper inside it, and then ask the only
/// question that cannot be wrong — *does it answer?*
public enum HelperInstallation {

    /// The `.app` bundle containing this executable, if there is one.
    ///
    /// Walks up from the executable path rather than trusting `Bundle.main`,
    /// because for a helper binary in `Contents/Helpers` or
    /// `Contents/Library/LaunchDaemons`, `Bundle.main` is the wrong thing.
    public static var containingAppBundle: URL? {
        let executable = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        var directory = executable.standardizedFileURL.deletingLastPathComponent()
        // Bounded: an app bundle is never more than a few levels up, and an
        // unbounded walk from "/" would be silly.
        for _ in 0..<6 {
            if directory.pathExtension == "app" { return directory }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        return nil
    }

    /// The LaunchDaemon plist inside the app bundle.
    public static var launchDaemonPlist: URL? {
        guard let bundle = containingAppBundle else { return nil }
        return bundle.appendingPathComponent(
            "Contents/Library/LaunchDaemons/com.agentspace.AgentSpace.Helper.plist")
    }

    public static var helperBinary: URL? {
        guard let bundle = containingAppBundle else { return nil }
        return bundle.appendingPathComponent(
            "Contents/Library/LaunchDaemons/agentspace-helper")
    }

    /// `SMAppService`'s own view. Only meaningful when this process *is* the app,
    /// which is why it is reported separately from `reachesHelper`.
    public static var appServiceStatus: SMAppService.Status {
        SMAppService.daemon(plistName: BundleIdentifiers.helperPlist).status
    }

    /// The question that matters: does the helper answer right now?
    ///
    /// A ping is ground truth in a way that a status enum is not — it proves the
    /// LaunchDaemon is loaded, listening on the expected Mach service, and willing
    /// to talk to this process, which also means the code-signature check passed.
    public static func reachesHelper(timeout: TimeInterval = 5) -> HelperResponse? {
        HelperClient.ping(timeout: timeout)
    }

    /// Everything known about the helper, in one value, so the app, the CLI and
    /// `doctor` cannot disagree about whether it is installed.
    public struct State {
        public var plistInBundle: URL?
        public var binaryInBundle: URL?
        public var isThisProcessTheApp: Bool
        public var appServiceStatus: SMAppService.Status
        public var ping: HelperResponse?

        public var isReachable: Bool { ping?.ok == true }

        public var helperVersionIfKnown: String? {
            ping?.result?["helperVersion"]?.stringValue
        }

        /// One line for the UI.
        public var summary: String {
            if isReachable {
                return helperVersionIfKnown.map {
                    String(format: NSLocalizedString("installed and answering (version %@)", comment: ""), $0)
                } ?? NSLocalizedString("installed and answering", comment: "")
            }
            if plistInBundle == nil {
                return NSLocalizedString("not in this build", comment: "")
            }
            if isThisProcessTheApp {
                switch appServiceStatus {
                case .requiresApproval: return NSLocalizedString("waiting for approval in System Settings", comment: "")
                case .enabled: return NSLocalizedString("registered but not answering", comment: "")
                case .notRegistered: return NSLocalizedString("not registered yet", comment: "")
                case .notFound: return NSLocalizedString("not in this build", comment: "")
                @unknown default: return NSLocalizedString("unknown state", comment: "")
                }
            }
            return NSLocalizedString("not answering", comment: "")
        }

        /// What to do about it. `nil` when there is nothing to do.
        public var fix: String? {
            if isReachable { return nil }
            if plistInBundle == nil {
                return NSLocalizedString("Run scripts/bundle-app.sh to produce a complete AgentSpace.app, then open it and choose “Install Helper”.", comment: "")
            }
            if isThisProcessTheApp, appServiceStatus == .requiresApproval {
                return NSLocalizedString("System Settings → General → Login Items & Extensions → allow the AgentSpace background item, then run `agentspace doctor` again.", comment: "")
            }
            if isThisProcessTheApp, appServiceStatus == .enabled {
                return String(format: NSLocalizedString("It is registered but silent, which usually means a code-signature mismatch: the daemon refuses callers that do not satisfy its requirement and logs the refusal. Check with:\nlog show --predicate 'subsystem == \"%@\" AND category == \"helper\"' --last 5m", comment: ""), BundleIdentifiers.logSubsystem)
            }
            return NSLocalizedString("Open the AgentSpace app and choose “Install Helper”. macOS will ask for your password, because only an administrator can add a LaunchDaemon.", comment: "")
        }
    }

    public static func inspect(ping: Bool = true) -> State {
        State(
            plistInBundle: launchDaemonPlist,
            binaryInBundle: helperBinary,
            isThisProcessTheApp: Bundle.main.bundleURL.pathExtension == "app",
            appServiceStatus: appServiceStatus,
            ping: ping ? reachesHelper() : nil)
    }
}
