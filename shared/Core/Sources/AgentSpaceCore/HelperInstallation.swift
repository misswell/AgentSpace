import Foundation
import Security
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

    /// The LaunchDaemon plist inside the app bundle. The file name routes
    /// through `BundleIdentifiers.helperPlist` so the §58 single-source rule
    /// holds for this path too.
    public static var launchDaemonPlist: URL? {
        guard let bundle = containingAppBundle else { return nil }
        return bundle.appendingPathComponent(
            "Contents/Library/LaunchDaemons/" + BundleIdentifiers.helperPlist)
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

    // MARK: - Binary identity

    /// The CDHash of the *running* code, as the kernel sees it.
    ///
    /// This is the hash of the loaded image, not of the file on disk — which is
    /// exactly the distinction the reinstall prompt needs: after an app rebuild
    /// the file is new while launchd's long-lived daemon process is still the
    /// old image, and only the live CDHash tells those apart.
    public static func currentProcessCDHash() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        // The signing information lives on the static code of the running
        // image — the code directory as loaded, not a re-read of the file.
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        return cdHash(of: staticCode)
    }

    /// The CDHash a file *would* run with — the on-disk code directory.
    public static func fileCDHash(_ url: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        return cdHash(of: staticCode)
    }

    private static func cdHash(of code: SecStaticCode) -> String? {
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, [], &information) == errSecSuccess,
              let info = information as? [String: Any],
              let data = (info[kSecCodeInfoUnique as String] as? NSData) as Data?
        else { return nil }
        return data.map { String(format: "%02x", $0) }.joined()
    }

    /// Whether the answering helper is an older build than the one in this bundle.
    ///
    /// A helper that predates the `selfCDHash` field reports nothing — and a
    /// silent field is precisely an old binary, so unknown means stale. When the
    /// bundle carries no helper to compare against, no verdict is claimed.
    public static func isHelperStale(reportedCDHash: String?, expectedCDHash: String?) -> Bool {
        guard let expected = expectedCDHash else { return false }
        guard let reported = reportedCDHash else { return true }
        return reported != expected
    }

    /// Everything known about the helper, in one value, so the app, the CLI and
    /// `doctor` cannot disagree about whether it is installed.
    public struct State {
        public var plistInBundle: URL?
        public var binaryInBundle: URL?
        public var isThisProcessTheApp: Bool
        public var appServiceStatus: SMAppService.Status
        public var ping: HelperResponse?
        /// Answering, but with an older binary than this bundle carries —
        /// launchd kept the previous daemon alive across an app update.
        public var isStaleBinary: Bool

        public init(plistInBundle: URL? = nil, binaryInBundle: URL? = nil,
                    isThisProcessTheApp: Bool = false,
                    appServiceStatus: SMAppService.Status = .notFound,
                    ping: HelperResponse? = nil, isStaleBinary: Bool = false) {
            self.plistInBundle = plistInBundle
            self.binaryInBundle = binaryInBundle
            self.isThisProcessTheApp = isThisProcessTheApp
            self.appServiceStatus = appServiceStatus
            self.ping = ping
            self.isStaleBinary = isStaleBinary
        }

        public var isReachable: Bool { ping?.ok == true }

        public var helperVersionIfKnown: String? {
            ping?.result?["helperVersion"]?.stringValue
        }

        /// One line for the UI.
        public var summary: String {
            if isReachable {
                if isStaleBinary {
                    return NSLocalizedString("installed and answering, but running an older build", comment: "")
                }
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
            if isReachable {
                // A current helper has nothing to fix; a stale one needs the
                // in-app reinstall — launchd will not swap a running daemon by
                // itself, and re-registering is a no-op while it lives.
                return isStaleBinary ? NSLocalizedString("The app keeps a “Reinstall Helper” button in Doctor for exactly this: it stops the old daemon and registers the one inside this app.", comment: "") : nil
            }
            if plistInBundle == nil {
                return NSLocalizedString("Run scripts/bundle-app.sh to produce a complete AgentSpace.app, then open it and choose “Install Helper”.", comment: "")
            }
            if isThisProcessTheApp, appServiceStatus == .requiresApproval {
                return NSLocalizedString("System Settings → General → Login Items & Extensions → allow the AgentSpace background item, then run the Doctor check again.", comment: "")
            }
            if isThisProcessTheApp, appServiceStatus == .enabled {
                return NSLocalizedString("It is registered but silent, which usually means a code-signature mismatch: the daemon refuses callers that do not satisfy its requirement and records the refusal. Use Export Diagnostics in the app to collect the log.", comment: "")
            }
            return NSLocalizedString("Open the AgentSpace app and choose “Install Helper”. macOS will ask for your password, because only an administrator can add a LaunchDaemon.", comment: "")
        }
    }

    public static func inspect(ping: Bool = true) -> State {
        let response = ping ? reachesHelper() : nil
        let binary = helperBinary
        // Only a helper that actually answered can be judged stale; comparing
        // hashes with nothing on the other side would invent a verdict.
        let stale = response?.ok == true && isHelperStale(
            reportedCDHash: response?.result?["selfCDHash"]?.stringValue,
            expectedCDHash: binary.flatMap { fileCDHash($0) })
        return State(
            plistInBundle: launchDaemonPlist,
            binaryInBundle: binary,
            isThisProcessTheApp: Bundle.main.bundleURL.pathExtension == "app",
            appServiceStatus: appServiceStatus,
            ping: response,
            isStaleBinary: stale)
    }
}
