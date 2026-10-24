import Foundation
import NetworkExtension
import SystemExtensions
import AgentSpaceCore

/// The gate's way to exercise the tunnel from inside the signed app.
///
/// macOS only accepts an activation request from a process whose bundle carries
/// `com.apple.developer.system-extension.install` **and** is covered by a
/// provisioning profile that grants it. That means the check cannot live in a
/// separate test binary — a tool signed with the same entitlement is killed by
/// `amfid` (measured: exit 137, no message) — so it lives in the app and is
/// reached through `AGENTSPACE_TUNNEL_SELFTEST`.
///
/// It prints one line per fact and exits, because it is driven by a script:
/// `activate`, `state`, or `connect`. Absent the variable nothing here runs.
enum TunnelSelfTest {

    static func run(mode: String) -> Never {
        switch mode {
        case "activate":
            activate()
        case "state":
            print(SystemExtensionProbe.installedState().detail)
            exit(SystemExtensionProbe.installedState().state.isUsable ? 0 : 1)
        case "deactivate":
            deactivate()
        case "connect":
            connect()
        default:
            print("unknown AGENTSPACE_TUNNEL_SELFTEST mode '\(mode)'")
            exit(2)
        }
    }

    private static func activate() -> Never {
        print("bundle: \(Bundle.main.bundleURL.path)")
        print("in /Applications: \(Bundle.main.bundleURL.deletingLastPathComponent().path == "/Applications")")
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: BundleIdentifiers.tunnel, queue: .main)
        let delegate = Delegate()
        request.delegate = delegate
        print("activating \(BundleIdentifiers.tunnel)")
        OSSystemExtensionManager.shared.submitRequest(request)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 180))
        print("activation produced no answer within 180s")
        exit(4)
    }

    private static func deactivate() -> Never {
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: BundleIdentifiers.tunnel, queue: .main)
        let delegate = Delegate()
        request.delegate = delegate
        print("deactivating \(BundleIdentifiers.tunnel)")
        OSSystemExtensionManager.shared.submitRequest(request)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 120))
        print("deactivation produced no answer within 120s")
        exit(4)
    }

    private static func connect() -> Never {
        guard let configuration = VirtualNetworkStore().load() else {
            print("no committed virtual-network configuration")
            exit(5)
        }
        guard let identity = VirtualNodeIdentity.loadOrGenerate() else {
            print("no node identity")
            exit(5)
        }
        guard let tunnel = configuration.tunnelConfiguration(identity: identity) else {
            print("this Mac has no usable tunnel key")
            exit(5)
        }
        print("address \(configuration.local), \(configuration.hostRoutes.count) route(s)")

        let manager = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = BundleIdentifiers.tunnel
        proto.serverAddress = "AgentSpace Virtual Network"
        proto.providerConfiguration = [
            "uapi": tunnel.uapiConfiguration(replacePeers: true),
            "address": configuration.local.description,
            "routes": configuration.hostRoutes.map(\.description),
            "mtu": tunnel.mtu,
        ]
        manager.protocolConfiguration = proto
        manager.localizedDescription = "AgentSpace Virtual Network"
        manager.isEnabled = true
        manager.isOnDemandEnabled = false

        var finished = false
        manager.saveToPreferences { error in
            if let error { print("save failed: \(error)"); exit(6) }
            manager.loadFromPreferences { _ in
                do { try manager.connection.startVPNTunnel() } catch {
                    print("start failed: \(error)"); exit(7)
                }
                print("start requested")
            }
        }
        var waited = 0.0
        while !finished && waited < 40 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
            waited += 0.5
            switch manager.connection.status {
            case .connected:
                print("connected")
                printInterface()
                finished = true
            case .invalid:
                print("macOS has no valid configuration for this tunnel")
                finished = true
            default:
                break
            }
        }
        exit(finished && manager.connection.status == .connected ? 0 : 8)
    }

    /// Print what the kernel has, not what was requested.
    private static func printInterface() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        for block in text.components(separatedBy: "\n\n") {
            if block.contains("100.64.") || block.contains("utun") {
                print(block.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    private final class Delegate: NSObject, OSSystemExtensionRequestDelegate {
        func request(_ request: OSSystemExtensionRequest,
                     didFinishWithResult result: OSSystemExtensionRequest.Result) {
            print("result: \(result == .completed ? "completed" : "willCompleteAfterReboot")")
            print(SystemExtensionProbe.installedState().detail)
            exit(result == .completed ? 0 : 3)
        }
        func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
            print("error: \(error)")
            exit(2)
        }
        func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
            print("needs approval: System Settings → General → Login Items & Extensions → Network Extensions")
        }
        func request(_ request: OSSystemExtensionRequest,
                     actionForReplacingExtension existing: OSSystemExtensionProperties,
                     withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
            print("replacing \(existing.bundleVersion) → \(ext.bundleVersion)")
            return .replace
        }
    }
}
