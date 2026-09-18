import Foundation

/// The 256-bit session secret that guards a Space's socket. Plan §20.
///
/// The socket already lives in a directory only three principals can traverse,
/// so why a token too? Because the *agent session* can read the socket
/// directory by design — it runs as the agent user. Without a token, anything
/// that gets code execution in an AgentSpace (a browser exploit, a
/// prompt-injected shell) could drive a sibling Space's worker. The token means
/// a compromise of one Space does not become a compromise of all of them.
public struct SessionToken: Equatable, Sendable {
    /// 32 bytes = 256 bits.
    public static let byteCount = 32

    public let hex: String

    public init(hex: String) {
        self.hex = hex.lowercased()
    }

    /// Generate from the system CSPRNG. Never a fixed or derived value
    /// (plan §9 makes the same point about account passwords).
    public static func generate() -> SessionToken? {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else { return nil }
        return SessionToken(hex: bytes.map { String(format: "%02x", $0) }.joined())
    }

    public var isValidShape: Bool {
        hex.count == SessionToken.byteCount * 2 && hex.allSatisfy(\.isHexDigit)
    }

    /// Constant-time comparison.
    ///
    /// A byte-by-byte `==` on a secret leaks its prefix through timing to
    /// anyone who can open the socket repeatedly, which is exactly the
    /// adversary the token exists for. `timingsafe_bcmp` is the libSystem
    /// primitive for this.
    public func matches(_ other: String) -> Bool {
        let a = Array(hex.utf8)
        let b = Array(other.lowercased().utf8)
        guard a.count == b.count, !a.isEmpty else { return false }
        return a.withUnsafeBufferPointer { ap in
            b.withUnsafeBufferPointer { bp in
                timingsafe_bcmp(ap.baseAddress!, bp.baseAddress!, a.count) == 0
            }
        }
    }
}

/// Token storage on disk: one file per Space, mode 0600, inside the ACL'd
/// runtime directory. Never in `config.json`, never in `UserDefaults`, never in
/// a log line (plan §9 and §37).
public enum TokenStore {
    public static func write(_ token: SessionToken, to path: String) -> AgentSpaceError? {
        let fm = FileManager.default
        // 0600 from the moment it exists, not after: a create-then-chmod window
        // is a window.
        guard fm.createFile(atPath: path, contents: Data((token.hex + "\n").utf8),
                            attributes: [.posixPermissions: 0o600]) else {
            return AgentSpaceError(
                code: .internalError,
                message: "could not write session token to \(path)")
        }
        return nil
    }

    public static func read(from path: String) -> SessionToken? {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let token = SessionToken(hex: text.trimmingCharacters(in: .whitespacesAndNewlines))
        return token.isValidShape ? token : nil
    }

    /// Read the token for a Space, if it has one.
    public static func read(spaceID: UUID) -> SessionToken? {
        read(from: RuntimePaths(spaceID: spaceID).tokenPath)
    }
}

/// Redaction for anything that gets logged or exported. Plan §37: exported
/// diagnostics must not carry passwords, tokens, keychain material, typed text
/// or screenshots.
public enum Redaction {
    public static let placeholder = "<redacted>"

    /// Substrings that mark a value as secret.
    private static let secretKeys = [
        "token", "password", "passwd", "secret", "keychain",
        "authorization", "api_key", "apikey", "credential",
    ]

    public static func isSecretKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        return secretKeys.contains { lower.contains($0) }
    }

    /// Scrub a JSON-ish dictionary before it is logged.
    ///
    /// Also scrubs any *value* that looks like a 64-hex-character token, because
    /// the most likely leak is a token embedded in a message string rather than
    /// sitting under a key we happened to think of.
    public static func scrub(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let object):
            var out: [String: JSONValue] = [:]
            for (k, v) in object {
                out[k] = isSecretKey(k) ? .string(placeholder) : scrub(v)
            }
            return .object(out)
        case .array(let items):
            return .array(items.map(scrub))
        case .string(let s):
            return .string(scrubString(s))
        default:
            return value
        }
    }

    public static func scrubString(_ s: String) -> String {
        var out = s
        // 64 hex characters, optionally hyphenated in groups.
        if let regex = try? NSRegularExpression(pattern: "\\b[0-9a-fA-F]{64}\\b") {
            let range = NSRange(out.startIndex..., in: out)
            out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: placeholder)
        }
        for key in secretKeys {
            if let regex = try? NSRegularExpression(
                pattern: "(?i)\(key)\\s*[:=]\\s*\\S+") {
                let range = NSRange(out.startIndex..., in: out)
                out = regex.stringByReplacingMatches(
                    in: out, range: range, withTemplate: "\(key)=\(placeholder)")
            }
        }
        return out
    }

    /// Convenience used by the worker before writing a status line or a log.
    public static func scrubStringMap(_ map: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in map { out[k] = isSecretKey(k) ? placeholder : scrubString(v) }
        return out
    }
}
