import Foundation
import NetworkExtension
import os

/// The tunnel provider.
///
/// It does three things, in this order, and it fails rather than approximating
/// any of them:
///
/// 1. read the configuration this Mac was given (address, peer list, private
///    key) from the provider configuration, which is the only channel macOS
///    gives a system extension;
/// 2. apply the network settings — **this Mac's address** and a precise host
///    route per peer, never the pool;
/// 3. start wireguard-go against the utun file descriptor the provider hands it.
///
/// The tunnel does not start unless all three succeed. A half-configured tunnel
/// that reports "connected" is worse than no tunnel: a client would send traffic
/// into it and wait for an answer that can never arrive.
final class TunnelProvider: NEPacketTunnelProvider {
    private var handle: Int32 = 0
    private let log = Logger(subsystem: "com.misswell.AgentSpace.Tunnel", category: "tunnel")

    override func startTunnel(options: [String: NSObject]?) async throws {
        guard let protocolConfiguration = protocolConfiguration as? NETunnelProviderProtocol,
              let providerConfiguration = protocolConfiguration.providerConfiguration,
              let uapi = providerConfiguration["uapi"] as? String,
              !uapi.isEmpty else {
            // No configuration means the app started the tunnel without giving
            // it anything. Refuse rather than come up with no peers.
            throw NSError(
                domain: "com.misswell.AgentSpace.Tunnel", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "the tunnel was started without a configuration; nothing was applied"])
        }

        guard let localAddress = providerConfiguration["address"] as? String,
              isIPv4(localAddress) else {
            throw NSError(
                domain: "com.misswell.AgentSpace.Tunnel", code: 2,
                userInfo: [NSLocalizedDescriptionKey:
                    "the tunnel configuration has no valid local address"])
        }

        let mtu = providerConfiguration["mtu"] as? Int ?? 1420
        // The app sends the exact host routes, already computed and validated by
        // AgentSpaceCore. The extension does not re-derive them: two places that
        // decide routing are two places that can disagree, and the one inside a
        // system extension is the harder one to inspect.
        let routes = (providerConfiguration["routes"] as? [String] ?? []).filter(isIPv4)
        guard !routes.isEmpty else {
            throw NSError(
                domain: "com.misswell.AgentSpace.Tunnel", code: 4,
                userInfo: [NSLocalizedDescriptionKey:
                    "the tunnel configuration has no routes; a tunnel that routes nothing would report connected and carry nothing"])
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: localAddress)
        settings.mtu = NSNumber(value: mtu)
        let ipv4 = NEIPv4Settings(
            addresses: [localAddress],
            subnetMasks: ["255.255.255.255"])
        // A /32 host route per peer. Never a pool route: a physical LAN sharing
        // the range keeps working, and only the virtual addresses enter the
        // tunnel.
        ipv4.includedRoutes = routes.map {
            NEIPv4Route(destinationAddress: $0, subnetMask: "255.255.255.255")
        }
        settings.ipv4Settings = ipv4
        try await setTunnelNetworkSettings(settings)

        let descriptor = tunnelFileDescriptor()
        guard descriptor > 0 else {
            throw NSError(
                domain: "com.misswell.AgentSpace.Tunnel", code: 3,
                userInfo: [NSLocalizedDescriptionKey:
                    "no tun file descriptor: the tunnel interface was not created"])
        }

        let started = uapi.withCString { settingsPointer in
            wgTurnOn(settingsPointer, descriptor)
        }
        guard started > 0 else {
            // WireGuard reports failure as a negative code. It is worth surfacing
            // verbatim: `-1` is a bad configuration, and a caller that only sees
            // "failed to start" cannot tell a wrong key from a taken port.
            throw NSError(
                domain: "com.misswell.AgentSpace.Tunnel", code: Int(started),
                userInfo: [NSLocalizedDescriptionKey:
                    "wireguard-go refused the configuration (code \(started))"])
        }
        handle = started

        // Read and discard packets. wireguard-go writes into the descriptor
        // itself, so nothing here forwards traffic; this loop must run or the
        // provider's flow stalls, which is why it starts and is never awaited.
        pump()
        log.info("tunnel up: \(localAddress, privacy: .public), \(routes.count) route(s), wireguard-go started")
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        if handle > 0 {
            wgTurnOff(handle)
            handle = 0
        }
        log.info("tunnel stopped: reason \(reason.rawValue, privacy: .public)")
    }

    /// The utun descriptor NetworkExtension created for this provider.
    ///
    /// Found in C: `sys/kern_control.h`'s structures are not importable into
    /// Swift on this SDK, so `CTLIOCGINFO` cannot be called from here at all.
    private func tunnelFileDescriptor() -> Int32 {
        agentspace_tunnel_fd()
    }

    /// Drain the packet flow.
    ///
    /// wireguard-go owns the descriptor and does the encryption, so these packets
    /// are already-decrypted inbound traffic that has nowhere to go inside a
    /// system extension. Reading them is what keeps the flow healthy; the
    /// alternative — never reading — fills the queue and stalls the interface.
    /// Strict dotted quad. The extension cannot link AgentSpaceCore (that would
    /// pull the whole protocol and the GUI's expectations into a system
    /// extension), so the one parse it needs lives here.
    private func isIPv4(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy {
            !$0.isEmpty && $0.count <= 3 && $0.allSatisfy(\.isNumber) && UInt8($0).map { _ in true } ?? false
        }
    }

    private func pump() {
        packetFlow.readPackets { [weak self] packets, _ in
            _ = packets
            self?.pump()
        }
    }
}
