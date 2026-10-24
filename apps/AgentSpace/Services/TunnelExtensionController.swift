import Foundation
import SystemExtensions
import AgentSpaceCore

/// Installing, activating and reporting the packet-tunnel system extension.
///
/// A system extension cannot be installed by copying files: macOS decides when it
/// runs, and the first activation is a person's approval in System Settings. This
/// type drives that flow and reports the truth at each step, because the failure
/// modes are indistinguishable from the outside — "nothing happened" is what an
/// unapproved extension, a missing profile and an unsigned bundle all look like.
///
/// Measured in §398: an extension outside `/Applications` is refused outright; a
/// signed-but-unnotarized bundle answers `extension category returned error`; a
/// restricted entitlement without its provisioning profile is killed by `amfid`
/// before `main`. Each has a different fix, so each gets a different message.
@MainActor
final class TunnelExtensionController: ObservableObject {

    enum State: Equatable {
        case unknown
        case notInstalled
        case waitingForApproval
        case installed
        case failed(String)

        var isUsable: Bool {
            if case .installed = self { return true }
            return false
        }
    }

    @Published private(set) var state: State = .unknown
    @Published private(set) var detail: String = ""

    static let extensionIdentifier = BundleIdentifiers.tunnel

    /// Where macOS requires the containing app to be before it will consider an
    /// activation request at all.
    static var isInApplicationsFolder: Bool {
        Bundle.main.bundleURL.deletingLastPathComponent().path == "/Applications"
    }

    /// Ask macOS to activate the extension.
    ///
    /// Returns as soon as the request is submitted; the answer arrives through
    /// the delegate, which is why `state` is published rather than returned.
    /// A person may have to approve it in System Settings, and that can take as
    /// long as they like — waiting inside this call would freeze the settings
    /// page for the duration.
    func activate() {
        guard Self.isInApplicationsFolder else {
            state = .failed(NSLocalizedString(
                "AgentSpace must be in /Applications before macOS will install the tunnel. Move it there and try again.",
                comment: ""))
            return
        }
        guard FileManager.default.fileExists(
            atPath: Bundle.main.bundleURL
                .appendingPathComponent("Contents/Library/SystemExtensions/com.misswell.AgentSpace.Tunnel.systemextension").path) else {
            state = .failed(NSLocalizedString(
                "This build does not contain the tunnel extension, so the virtual network cannot start. A release build does.",
                comment: ""))
            return
        }
        detail = NSLocalizedString("Asking macOS to install the tunnel…", comment: "")
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: Self.extensionIdentifier, queue: .main)
        request.delegate = delegate
        OSSystemExtensionManager.shared.submitRequest(request)
        state = .waitingForApproval
    }

    func deactivate() {
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: Self.extensionIdentifier, queue: .main)
        request.delegate = delegate
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// Re-read what the system says. `systemextensionsctl` is the only public
    /// source, and it distinguishes "waiting for user" from "activated enabled" —
    /// two states that need different words in the UI.
    func refresh() {
        let probe = SystemExtensionProbe.installedState()
        detail = probe.detail
        switch probe.state {
        case .enabled: state = .installed
        case .waitingForUser: state = .waitingForApproval
        case .notInstalled: state = .notInstalled
        case .terminated(let text): state = .failed(text)
        case .unknown: state = .unknown
        }
    }

    private lazy var delegate = Delegate(owner: self)

    private final class Delegate: NSObject, OSSystemExtensionRequestDelegate {
        weak var owner: TunnelExtensionController?

        init(owner: TunnelExtensionController) {
            self.owner = owner
        }

        func request(_ request: OSSystemExtensionRequest,
                     didFinishWithResult result: OSSystemExtensionRequest.Result) {
            Task { @MainActor in
                switch result {
                case .completed:
                    owner?.state = .installed
                    owner?.detail = NSLocalizedString("The tunnel extension is installed and running.", comment: "")
                case .willCompleteAfterReboot:
                    owner?.state = .waitingForApproval
                    owner?.detail = NSLocalizedString(
                        "macOS will finish installing the tunnel after the next restart.", comment: "")
                @unknown default:
                    owner?.state = .unknown
                    owner?.detail = NSLocalizedString("macOS reported an unrecognised activation result.", comment: "")
                }
            }
        }

        func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
            Task { @MainActor in
                owner?.state = .failed(Self.explain(error))
                owner?.detail = Self.explain(error)
            }
        }

        func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
            Task { @MainActor in
                owner?.state = .waitingForApproval
                owner?.detail = NSLocalizedString(
                    "macOS is waiting for you to allow AgentSpace in System Settings → General → Login Items & Extensions → Network Extensions.",
                    comment: "")
            }
        }

        func request(_ request: OSSystemExtensionRequest,
                     actionForReplacingExtension existing: OSSystemExtensionProperties,
                     withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
            // Replace in place: the extension carries no state of its own, and the
            // configuration it runs with comes from the app each time it starts.
            .replace
        }

        /// Turn the three distinct failures into three distinct sentences.
        static func explain(_ error: Error) -> String {
            let text = "\(error)"
            if text.contains("must be in /Applications folder") || text.contains("Current location") {
                return NSLocalizedString(
                    "AgentSpace has to be in /Applications for macOS to install the tunnel.", comment: "")
            }
            if text.contains("code signature invalid") {
                return NSLocalizedString(
                    "macOS rejected the tunnel's signature. A build that is not notarized cannot install a system extension.",
                    comment: "")
            }
            if text.contains("Missing entitlement") {
                return NSLocalizedString(
                    "This build is missing the entitlement macOS requires to install a system extension, so it cannot use the virtual network.",
                    comment: "")
            }
            if text.contains("extension category returned error") {
                return NSLocalizedString(
                    "macOS refused the tunnel before it ran. This is what an unnoticed or unstamped build looks like; reinstalling a notarized AgentSpace fixes it.",
                    comment: "")
            }
            return text
        }
    }
}
