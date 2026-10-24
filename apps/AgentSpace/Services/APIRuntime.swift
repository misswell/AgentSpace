import Foundation
import Combine
import AgentSpaceCore
import os

/// Runs the remote API listener inside the app.
///
/// §398 designed the API as app-owned — "the listener belongs to the app: it
/// needs the virtual address, the token store and the same registry the GUI
/// reads" — but no production entry point ever constructed the server, so the
/// configuration the CLI and the settings page wrote described a listener that
/// did not exist. This runtime is that entry point: while AgentSpace is open,
/// `api.json` is reconciled into a real `APIServer` every few seconds, so a
/// CLI `api enable` takes effect without a relaunch and a disable closes the
/// port. The state it publishes is what the settings page shows — the address
/// a person can actually call, not the address a file promised.
@MainActor
final class APIRuntime: ObservableObject {

    enum Phase: Equatable {
        case off
        case running(host: String, port: Int)
        case failed(String)

        var description: String {
            switch self {
            case .off:
                return NSLocalizedString("Off", comment: "")
            case .running(let host, let port):
                return "\(host):\(port) — " + NSLocalizedString("running", comment: "")
            case .failed(let reason):
                return String(
                    format: NSLocalizedString("not running: %@", comment: ""), reason)
            }
        }
    }

    @Published private(set) var phase: Phase = .off
    @Published private(set) var configuration: APIConfiguration?

    private var server: APIServer?
    private var runningPolicy: APIListenPolicy?
    private var timer: Timer?
    private var reconciling = false
    private let log = Logger(subsystem: BundleIdentifiers.logSubsystem, category: "api-runtime")

    func start() {
        guard timer == nil else { return }
        reconcile()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
    }

    /// Read the configuration file again and make the listener match it. Called
    /// on a timer, after the settings page writes the file, and after the CLI
    /// changes it (picked up on the next tick).
    func reconcile() {
        guard !reconciling else { return }
        reconciling = true
        defer { reconciling = false }

        let config = APIConfiguration.load()
        let network = VirtualNetworkStore().load()
        configuration = config

        guard let config, config.enabled else {
            phase = .off
            stopServer()
            return
        }
        guard let policy = config.policy(network: network) else {
            phase = .failed(
                NSLocalizedString(
                    "the bind mode in the configuration is unknown, or a virtual address was requested with no virtual network configured",
                    comment: ""))
            stopServer()
            return
        }

        if server != nil, runningPolicy == policy, server?.isRunning == true { return }

        stopServer()

        let service = APIAgentService()
        let snapshot = LocalNetworkProbe.snapshot()
        let apiServer = APIServer(configuration: .init(
            policy: policy,
            service: service,
            tokenPaths: VirtualNetworkPaths(),
            networkStatus: {
                Self.networkStatusJSON()
            },
            isBindAddressAvailable: { host in
                guard let address = IPv4Address(host) else { return false }
                return snapshot.addresses.contains(address)
            }))

        do {
            try apiServer.start()
            server = apiServer
            runningPolicy = policy
            phase = .running(host: policy.host, port: apiServer.boundPort)
            log.info("api listener on \(policy.host):\(apiServer.boundPort, privacy: .public)")
        } catch {
            let reason = String(describing: error)
            phase = .failed(reason)
            log.error("api listener refused: \(reason, privacy: .public)")
        }
    }

    private func stopServer() {
        server?.stop()
        server = nil
        runningPolicy = nil
    }

    /// The shape `GET /v1/network/status` answers with: what is configured and
    /// whether this Mac actually holds the virtual address right now. Static
    /// because the listener's queue calls it; it touches no instance state.
    nonisolated private static func networkStatusJSON() -> JSONValue {
        let network = VirtualNetworkStore().load()
        guard let network else { return .obj(["connected": .bool(false)]) }
        let present = LocalNetworkProbe.snapshot().addresses.contains(network.local)
        return .obj([
            "connected": .bool(present),
            "pool": .string(network.pool.description),
            "local": .string(network.local.description),
            "virtualAddressPresent": .bool(present),
        ])
    }
}
