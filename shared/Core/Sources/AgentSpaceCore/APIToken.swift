import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// API access is a separate credential from the Worker's session token, with
/// separate scopes. One token type for both would mean a screenshot client and
/// an input client are the same principal, and the whole point of the scope list
/// is that they are not.
public enum APIScope: String, Codable, Sendable, CaseIterable, Comparable {
    /// Lists and status: what is connected, is it usable.
    case read
    /// Screenshots and window lists: seeing the desktop.
    case observe
    /// Input, launch, quit: driving the desktop.
    case control
    /// `exec`. Off unless a token is explicitly granted it.
    case exec

    public static func < (lhs: APIScope, rhs: APIScope) -> Bool {
        order(lhs) < order(rhs)
    }

    private static func order(_ scope: APIScope) -> Int {
        switch scope {
        case .read: return 0
        case .observe: return 1
        case .control: return 2
        case .exec: return 3
        }
    }

    /// Scopes imply the read-only ones below them: a token that may drive a
    /// desktop can obviously look at it, and forcing people to tick four boxes
    /// to do one job is how scope lists get ignored.
    public static func expand(_ scopes: Set<APIScope>) -> Set<APIScope> {
        var result = scopes
        if scopes.contains(.exec) { result.insert(.control) }
        if result.contains(.control) { result.insert(.observe) }
        if result.contains(.observe) { result.insert(.read) }
        return result
    }

    public var displayName: String {
        switch self {
        case .read: return "read"
        case .observe: return "observe"
        case .control: return "control"
        case .exec: return "exec"
        }
    }
}

public struct APITokenRecord: Codable, Equatable, Sendable, Identifiable {
    /// Short, public identifier — what a person sees in a list and what a log
    /// line may contain. Never the secret.
    public var id: String
    public var name: String
    /// SHA-256 of the secret, hex. The secret itself is shown once, at creation,
    /// and never stored.
    public var digest: String
    public var scopes: [APIScope]
    public var createdAt: Date
    public var lastUsedAt: Date?
    public var revokedAt: Date?

    public var isActive: Bool { revokedAt == nil }

    public var effectiveScopes: Set<APIScope> { APIScope.expand(Set(scopes)) }

    public func allows(_ scope: APIScope) -> Bool {
        isActive && effectiveScopes.contains(scope)
    }
}

public struct APITokenList: Codable, Equatable, Sendable {
    public var tokens: [APITokenRecord]

    public init(tokens: [APITokenRecord] = []) {
        self.tokens = tokens
    }

    public func find(_ id: String) -> APITokenRecord? {
        tokens.first { $0.id == id }
    }
}

public enum APITokenStore {
    /// 32 bytes of CSPRNG output, base64url without padding. 256 bits is the
    /// plan's floor and the reason a token cannot be guessed by brute force even
    /// if the endpoint is reachable.
    public static func generateSecret() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return nil
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func digest(of secret: String) -> String {
        SHA256.hex(Data(secret.utf8))
    }

    /// Constant-time comparison of digests.
    public static func matches(secret: String, record: APITokenRecord) -> Bool {
        let candidate = Array(digest(of: secret).utf8)
        let stored = Array(record.digest.utf8)
        guard candidate.count == stored.count, !candidate.isEmpty else { return false }
        return candidate.withUnsafeBufferPointer { a in
            stored.withUnsafeBufferPointer { b in
                timingsafe_bcmp(a.baseAddress!, b.baseAddress!, a.count) == 0
            }
        }
    }

    public static func load(paths: VirtualNetworkPaths = VirtualNetworkPaths()) -> APITokenList {
        guard let data = FileManager.default.contents(atPath: paths.tokenPath) else {
            return APITokenList()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(APITokenList.self, from: data)) ?? APITokenList()
    }

    public static func save(_ list: APITokenList, paths: VirtualNetworkPaths = VirtualNetworkPaths()) throws {
        try FileManager.default.createDirectory(
            atPath: paths.directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(list)
        // 0600 from the moment it exists: this file holds token digests, and a
        // world-readable window is a window even if it is short.
        guard FileManager.default.createFile(
            atPath: paths.tokenPath, contents: data,
            attributes: [.posixPermissions: 0o600]) else {
            throw AgentSpaceError(
                code: .internalError,
                message: "could not write API token store to \(paths.tokenPath)")
        }
    }

    /// Create a token and return the secret exactly once.
    public static func create(
        name: String,
        scopes: Set<APIScope>,
        paths: VirtualNetworkPaths = VirtualNetworkPaths(),
        now: Date = Date()
    ) throws -> (record: APITokenRecord, secret: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AgentSpaceError(code: .badRequest, message: "an API token needs a name")
        }
        guard !scopes.isEmpty else {
            throw AgentSpaceError(code: .badRequest, message: "an API token needs at least one scope")
        }
        guard let secret = generateSecret() else {
            throw AgentSpaceError(code: .internalError, message: "the system CSPRNG refused to produce a token")
        }
        var list = load(paths: paths)
        let record = APITokenRecord(
            id: String(UUID().uuidString.prefix(8)).lowercased(),
            name: name,
            digest: digest(of: secret),
            scopes: APIScope.allCases.filter { scopes.contains($0) },
            createdAt: now,
            lastUsedAt: nil,
            revokedAt: nil)
        list.tokens.append(record)
        try save(list, paths: paths)
        return (record, secret)
    }

    /// Resolve a presented secret to an active record, and record the use.
    public static func authenticate(
        secret: String,
        paths: VirtualNetworkPaths = VirtualNetworkPaths(),
        now: Date = Date()
    ) -> APITokenRecord? {
        var list = load(paths: paths)
        guard let index = list.tokens.firstIndex(where: {
            $0.isActive && matches(secret: secret, record: $0)
        }) else { return nil }
        list.tokens[index].lastUsedAt = now
        try? save(list, paths: paths)
        return list.tokens[index]
    }

    @discardableResult
    public static func revoke(
        id: String,
        paths: VirtualNetworkPaths = VirtualNetworkPaths(),
        now: Date = Date()
    ) throws -> APITokenRecord? {
        var list = load(paths: paths)
        guard let index = list.tokens.firstIndex(where: { $0.id == id }) else { return nil }
        list.tokens[index].revokedAt = now
        try save(list, paths: paths)
        return list.tokens[index]
    }

    /// Rotate: revoke the old token and mint a new one with the same name and
    /// scopes. Returns the new secret once.
    public static func rotate(
        id: String,
        paths: VirtualNetworkPaths = VirtualNetworkPaths(),
        now: Date = Date()
    ) throws -> (record: APITokenRecord, secret: String)? {
        let list = load(paths: paths)
        guard let old = list.find(id), old.isActive else { return nil }
        _ = try revoke(id: id, paths: paths, now: now)
        return try create(
            name: old.name + " (rotated)",
            scopes: Set(old.scopes),
            paths: paths,
            now: now)
    }
}

/// SHA-256, because Core has no CryptoKit dependency and this is the only hash
/// the product needs.
enum SHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
        0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
        0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
        0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
        0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hex(_ data: Data) -> String {
        var h: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]
        var message = [UInt8](data)
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }

        var w = [UInt32](repeating: 0, count: 64)
        for chunk in stride(from: 0, to: message.count, by: 64) {
            for i in 0..<16 {
                let base = chunk + i * 4
                w[i] = (UInt32(message[base]) << 24) | (UInt32(message[base + 1]) << 16)
                    | (UInt32(message[base + 2]) << 8) | UInt32(message[base + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3]
            var e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let temp1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj
                hh = g; g = f; f = e
                e = d &+ temp1
                d = c; c = b; b = a
                a = temp1 &+ temp2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }

    private static func rotr(_ value: UInt32, _ amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}
