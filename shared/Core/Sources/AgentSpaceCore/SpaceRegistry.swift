import Foundation

/// Environment overrides, so tests and development builds can run a whole
/// parallel installation without touching the real one.
public enum AgentSpaceEnvironment {
    /// Overrides `RuntimePaths.root`. Set by tests and by `--root` on the CLI.
    public static var rootOverride: String? {
        ProcessInfo.processInfo.environment["AGENTSPACE_ROOT"]
    }

    public static var socketTimeoutSeconds: Double {
        if let raw = ProcessInfo.processInfo.environment["AGENTSPACE_TIMEOUT"],
           let value = Double(raw), value > 0 {
            return value
        }
        return 60
    }

    public static func paths(spaceID: UUID, socketPath: String? = nil) -> RuntimePaths {
        RuntimePaths(spaceID: spaceID, root: rootOverride ?? RuntimePaths.root, socketPath: socketPath)
    }
}

/// The set of Spaces this machine knows about. Plan §26/§29.
///
/// Persisted as one JSON file under the shared root. Written by the app (via
/// the privileged helper) and read by the CLI and MCP, so all three agree on
/// what exists without any of them being the owner.
public struct SpaceRegistry: Codable, Sendable {
    public var spaces: [AgentSpace]

    public init(spaces: [AgentSpace] = []) {
        self.spaces = spaces
    }

    public static func path(root: String) -> String {
        root + "/Spaces/index.json"
    }

    /// Files produced by quarantine: `index.json.corrupt-<timestamp>`.
    /// Doctor checks these so a corrupt registry is diagnosed, not discovered.
    public static func corruptRegistryFiles(root: String? = nil) -> [String] {
        let resolvedRoot = root ?? AgentSpaceEnvironment.rootOverride ?? RuntimePaths.root
        let directory = resolvedRoot + "/Spaces"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return names.filter { $0.hasPrefix("index.json.corrupt-") }
            .sorted()
            .map { directory + "/\($0)" }
    }

    /// Move a corrupt `index.json` aside, preserving its bytes. Never throws:
    /// if even the quarantine fails (permissions, read-only volume), loading
    /// still returns an empty registry — degrading to the old behavior is
    /// better than crashing the caller.
    ///
    /// The name carries a random suffix in addition to the timestamp because
    /// the ISO stamp only resolves to seconds, and two corruptions in the same
    /// second would otherwise collide — the first test of this very function
    /// caught exactly that, with one generation of evidence silently lost to a
    /// failed move the `try?` hid.
    static func quarantine(path: String, data: Data) {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let directory = (path as NSString).deletingLastPathComponent
        // Retry with a fresh suffix until the destination is unused; a handful
        // of tries is beyond any plausible collision rate.
        for _ in 0..<8 {
            let suffix = String(UUID().uuidString.prefix(8)).lowercased()
            let destination = directory + "/index.json.corrupt-\(stamp)-\(suffix)"
            do {
                try FileManager.default.moveItem(atPath: path, toPath: destination)
                return
            } catch CocoaError.fileWriteFileExists {
                continue
            } catch {
                return
            }
        }
    }

    // MARK: Load / save

    public static func load(root: String? = nil) -> SpaceRegistry {
        let resolvedRoot = root ?? AgentSpaceEnvironment.rootOverride ?? RuntimePaths.root
        let path = SpaceRegistry.path(root: resolvedRoot)
        guard let data = FileManager.default.contents(atPath: path) else {
            return SpaceRegistry()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let registry = try? decoder.decode(SpaceRegistry.self, from: data) else {
            // An undecodable registry must not be *silently* treated as "no
            // Spaces" — that would make every Space look deleted, and the next
            // save would overwrite the only evidence of what existed. So the
            // corrupt file is quarantined beside itself: the empty registry is
            // still returned (the app must keep working), but the original
            // bytes survive under a name that says what happened, and
            // `corruptRegistryFiles` lets doctor surface it.
            Self.quarantine(path: path, data: data)
            return SpaceRegistry(spaces: [])
        }
        return registry
    }

    public func save(root: String? = nil) throws {
        let resolvedRoot = root ?? AgentSpaceEnvironment.rootOverride ?? RuntimePaths.root
        let directory = resolvedRoot + "/Spaces"
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: SpaceRegistry.path(root: resolvedRoot)),
                       options: .atomic)
    }

    // MARK: Lookup

    /// Resolve a user-supplied reference: exact UUID, exact name, or a
    /// case-insensitive name match. Ambiguity is an error, never a guess.
    public func resolve(_ reference: String) -> Result<AgentSpace, AgentSpaceError> {
        if let uuid = UUID(uuidString: reference),
           let match = spaces.first(where: { $0.id == uuid }) {
            return .success(match)
        }
        if let exact = spaces.first(where: { $0.name == reference }) {
            return .success(exact)
        }
        let insensitive = spaces.filter { $0.name.caseInsensitiveCompare(reference) == .orderedSame }
        if insensitive.count == 1 { return .success(insensitive[0]) }
        if insensitive.count > 1 {
            return .failure(AgentSpaceError(
                code: .badRequest,
                message: "'\(reference)' matches \(insensitive.count) Spaces. Use the Space UUID instead: \(insensitive.map { $0.id.uuidString }.joined(separator: ", "))"))
        }
        if spaces.isEmpty {
            return .failure(AgentSpaceError(
                code: .sessionNotReady,
                message: "no AgentSpace exists yet. Create one in the AgentSpace app, or run `agentspace doctor` to see what this machine still needs."))
        }
        return .failure(AgentSpaceError(
            code: .sessionNotReady,
            message: "no AgentSpace named '\(reference)'. Known Spaces: \(spaces.map(\.name).joined(separator: ", "))"))
    }

    public func first() -> AgentSpace? { spaces.first }

    public mutating func upsert(_ space: AgentSpace) {
        if let index = spaces.firstIndex(where: { $0.id == space.id }) {
            spaces[index] = space
        } else {
            spaces.append(space)
        }
    }

    public mutating func remove(id: UUID) {
        spaces.removeAll { $0.id == id }
    }
}
