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

    public init(enabled: Bool, bindMode: String = "virtualNetwork", port: Int = VirtualNetworkValidator.defaultPort, updatedAt: Date = Date()) {
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
    /// one a person configured).
    public func policy(network: VirtualNetworkConfig) -> APIListenPolicy? {
        switch bindMode {
        case "loopback":
            return .loopback(port: port)
        case "virtualNetwork":
            return .virtualNetwork(network.local, port: port)
        default:
            return nil
        }
    }
}

/// What the system says about the AgentSpace network extension.
///
/// Read from `systemextensionsctl list`, which is the only public way to see
/// whether the extension is activated. Deliberately reports the raw state rather
/// than a boolean: "activated waiting for user" is the state a person must act
/// on, and collapsing it into "not installed" would send them to reinstall a
/// bundle that is already correct.
public struct SystemExtensionProbe {
    public enum State: Equatable, Sendable {
        case unknown
        case notInstalled
        case waitingForUser
        case enabled
        case terminated(String)

        public var isUsable: Bool {
            if case .enabled = self { return true }
            return false
        }
    }

    public let state: State
    public let detail: String

    /// Whether the extension can carry traffic right now. `waitingForUser` is
    /// not usable: the bundle is installed but macOS has not been told to run
    /// it, and saying "installed" would send a person looking for the wrong fix.
    public var isUsable: Bool { state.isUsable }

    public init(state: State, detail: String) {
        self.state = state
        self.detail = detail
    }

    public static let extensionIdentifier = "com.agentspace.AgentSpace.Tunnel"

    public static func installedState(identifier: String = extensionIdentifier) -> SystemExtensionProbe {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/systemextensionsctl")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return SystemExtensionProbe(state: .unknown, detail: "could not run systemextensionsctl: \(error)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else {
            return SystemExtensionProbe(state: .unknown, detail: "systemextensionsctl produced no readable output")
        }
        return parse(text, identifier: identifier)
    }

    public static func parse(_ text: String, identifier: String = extensionIdentifier) -> SystemExtensionProbe {
        guard let line = text.split(separator: "\n").first(where: { $0.contains(identifier) }) else {
            return SystemExtensionProbe(
                state: .notInstalled,
                detail: "the AgentSpace network extension is not installed. The app installs it when the virtual network is turned on.")
        }
        let lower = line.lowercased()
        if lower.contains("waiting for user") {
            return SystemExtensionProbe(
                state: .waitingForUser,
                detail: "the extension is installed and waiting for approval: open System Settings → General → Login Items & Extensions → Network Extensions and allow AgentSpace.")
        }
        if lower.contains("activated enabled") {
            return SystemExtensionProbe(state: .enabled, detail: "the extension is activated and enabled")
        }
        if lower.contains("terminated") {
            return SystemExtensionProbe(
                state: .terminated(line.trimmingCharacters(in: .whitespaces)),
                detail: "the extension is installed but not running: \(line.trimmingCharacters(in: .whitespaces))")
        }
        return SystemExtensionProbe(
            state: .unknown,
            detail: "the extension's state could not be interpreted from: \(line.trimmingCharacters(in: .whitespaces))")
    }
}
