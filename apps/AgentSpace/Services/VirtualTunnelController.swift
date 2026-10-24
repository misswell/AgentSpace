import Foundation
import NetworkExtension
import AgentSpaceCore

/// Starts and stops the packet tunnel, and reports whether it is actually up.
///
/// A vendor's packet-tunnel configuration lives in `NETunnelProviderManager`,
/// which macOS owns: the app asks for a configuration by name, fills in the
/// provider bundle and the per-provider payload, and asks it to connect. The
/// extension then reads that payload — which is the only channel between the two
/// processes.
///
/// Everything here reports what macOS says, never what was requested. A
/// configuration that exists is not a tunnel that is up; the two are separate
/// facts and conflating them is how a settings page shows green over a dead
/// interface.
@MainActor
final class VirtualTunnelController: ObservableObject {

    enum Status: Equatable {
        case stopped
        case starting
        case connected
        case waitingForExtension
        case failed(String)

        var isConnected: Bool { self == .connected }
    }

    static let configurationName = "AgentSpace Virtual Network"

    @Published private(set) var status: Status = .stopped
    @Published private(set) var detail: String = ""
    @Published private(set) var assignedAddress: String?

    private var manager: NETunnelProviderManager?

    /// Load the system's configuration for this provider, if there is one.
    func refresh() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            manager = managers.first {
                $0.protocolConfiguration?.serverAddress == Self.configurationName
                    || ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                        .providerBundleIdentifier == BundleIdentifiers.tunnel
            }
            guard let manager else {
                status = .stopped
                detail = NSLocalizedString("The virtual network is not set up yet.", comment: "")
                return
            }
            switch manager.connection.status {
            case .connected:
                status = .connected
            case .connecting, .reasserting:
                status = .starting
            case .disconnected, .invalid:
                status = .stopped
            case .disconnecting:
                status = .stopped
            @unknown default:
                status = .stopped
            }
            assignedAddress = (manager.protocolConfiguration as? NETunnelProviderProtocol)?
                .providerConfiguration?["address"] as? String
            detail = statusText(manager.connection.status)
        } catch {
            status = .failed("\(error)")
            detail = NSLocalizedString("AgentSpace could not read the tunnel configuration from macOS.", comment: "")
        }
    }

    /// Bring the tunnel up from a committed configuration.
    ///
    /// The provider payload is built here, from the same `AgentSpaceCore` types
    /// the CLI and the API use, so there is one answer to "what is our address and
    /// which routes do we install".
    func connect(configuration: VirtualNetworkConfig, identity: VirtualNodeIdentity) async {
        guard let tunnel = configuration.tunnelConfiguration(identity: identity) else {
            status = .failed(NSLocalizedString(
                "This Mac has no usable tunnel key, so the network cannot be joined.", comment: ""))
            detail = status.failureText
            return
        }
        let problems = tunnel.problems()
        guard problems.isEmpty else {
            status = .failed(problems.joined(separator: " "))
            detail = problems.joined(separator: " ")
            return
        }

        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let manager = managers.first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                    .providerBundleIdentifier == BundleIdentifiers.tunnel
            } ?? NETunnelProviderManager()

            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = BundleIdentifiers.tunnel
            proto.serverAddress = Self.configurationName
            proto.providerConfiguration = [
                "uapi": tunnel.uapiConfiguration(replacePeers: true),
                "address": configuration.local.description,
                "routes": configuration.hostRoutes.map(\.description),
                "mtu": tunnel.mtu,
            ]
            manager.protocolConfiguration = proto
            manager.localizedDescription = Self.configurationName
            manager.isEnabled = true
            // Not on demand: this tunnel exists to be driven by a person and by
            // the API, and a rule that reconnects it whenever any network appears
            // would fight a user who deliberately stopped it.
            manager.isOnDemandEnabled = false

            try await manager.saveToPreferences()
            // macOS documents that a save may leave the manager stale; reloading
            // before connecting is what the VPN sample code does, and connecting a
            // stale manager silently does nothing.
            try await manager.loadFromPreferences()
            try manager.connection.startVPNTunnel()

            self.manager = manager
            self.assignedAddress = configuration.local.description
            status = .starting
            detail = NSLocalizedString("Starting the encrypted tunnel…", comment: "")
        } catch {
            let text = "\(error)"
            // NEVPNError 5 is "no provider" on a machine where the extension has
            // not been approved. Naming it is the difference between a fixable
            // step and an unexplained failure.
            if text.contains("NEVPNErrorDomain Code=5") || text.contains("configuration is invalid") {
                status = .waitingForExtension
            } else {
                status = .failed(text)
            }
            detail = status.failureText
        }
    }

    /// Stop the tunnel. The configuration is left in place, so the next start is
    /// immediate and does not need a person's approval again.
    func disconnect() {
        manager?.connection.stopVPNTunnel()
        status = .stopped
        detail = NSLocalizedString("The virtual network is stopped.", comment: "")
    }

    private func statusText(_ status: NEVPNStatus) -> String {
        switch status {
        case .connected:
            return NSLocalizedString("Connected. This Mac is reachable at its virtual address.", comment: "")
        case .connecting, .reasserting:
            return NSLocalizedString("Connecting…", comment: "")
        case .disconnected:
            return NSLocalizedString("Not connected.", comment: "")
        case .disconnecting:
            return NSLocalizedString("Disconnecting…", comment: "")
        case .invalid:
            return NSLocalizedString("macOS has no tunnel configuration for AgentSpace.", comment: "")
        @unknown default:
            return NSLocalizedString("The tunnel's state is unknown.", comment: "")
        }
    }
}

extension VirtualTunnelController.Status {
    var failureText: String {
        if case .failed(let text) = self { return text }
        if self == .waitingForExtension {
            return NSLocalizedString(
                "The tunnel needs its system extension. Allow AgentSpace under System Settings → General → Login Items & Extensions → Network Extensions, then connect again.",
                comment: "")
        }
        if self == .starting {
            return NSLocalizedString("The tunnel is starting.", comment: "")
        }
        if self == .connected {
            return NSLocalizedString("The tunnel is up.", comment: "")
        }
        return NSLocalizedString("The tunnel is stopped.", comment: "")
    }
}
