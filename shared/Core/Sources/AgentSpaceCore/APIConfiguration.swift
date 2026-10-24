import Foundation

/// Whether the API service is enabled, and where it listens.
///
/// Persisted separately from the network configuration: the plan requires the
/// two to start and stop independently, and a single file would make
/// "disable the API but keep the tunnel" a rewrite of both.
public struct APIConfiguration: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// `loopback` or `virtualNetwork`. Stored as a string so an unknown value
    /// from a newer build is a refusal rather than a crash.
    public var bindMode: String
    public var port: Int
    public var updatedAt: Date

    /// Loopback by default. It is the one address that exists on every Mac with
    /// no network at all — no Wi-Fi, no cable, no VPN — so the API works on a
    /// plane or in a Faraday cage, and it never listens on a physical interface
    /// by accident. A virtual address is opt-in and must be present on an
    /// interface before the listener will start (§398).
    public init(enabled: Bool, bindMode: String = "loopback", port: Int = VirtualNetworkValidator.defaultPort, updatedAt: Date = Date()) {
        self.enabled = enabled
        self.bindMode = bindMode
        self.port = port
        self.updatedAt = updatedAt
    }

    public static func path(paths: VirtualNetworkPaths = VirtualNetworkPaths()) -> String {
        paths.directory + "/api.json"
    }

    public static func load(paths: VirtualNetworkPaths = VirtualNetworkPaths()) -> APIConfiguration? {
        guard let data = FileManager.default.contents(atPath: path(paths: paths)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(APIConfiguration.self, from: data)
    }

    public func save(paths: VirtualNetworkPaths = VirtualNetworkPaths()) throws {
        try FileManager.default.createDirectory(
            atPath: paths.directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(
            to: URL(fileURLWithPath: APIConfiguration.path(paths: paths)), options: .atomic)
    }

    /// The listener this configuration describes, or nil when it cannot be
    /// described at all (an unknown bind mode is not silently treated as
    /// loopback: that would expose a service on a different interface than the
    /// one a person configured). The network configuration is optional because
    /// loopback mode — the default — needs no network at all; only the opt-in
    /// virtual-address mode needs a configured address to bind.
    public func policy(network: VirtualNetworkConfig?) -> APIListenPolicy? {
        switch bindMode {
        case "loopback":
            return .loopback(port: port)
        case "virtualNetwork":
            guard let network else { return nil }
            return .virtualNetwork(network.local, port: port)
        default:
            return nil
        }
    }
}
