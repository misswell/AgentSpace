import Foundation

/// Diagnostics export (plan §37): a support bundle a user can hand out without
/// also handing out the keys to their Spaces.
///
/// Two independent controls, both required — either alone would be a bet:
///
/// 1. **Whitelist collection.** The collector only ever gathers doctor output,
///    registry metadata (names, usernames, uid, state) and file *existence*.
///    It never reads token files, Keychain items, input payloads, or frame
///    data, so those secrets cannot leak because they are never collected.
/// 2. **Redaction pass.** Everything still goes through `DiagnosticsRedactor`
///    before leaving the process, as defense in depth: if a future collector
///    change accidentally pulls something secret-shaped (a token pasted in a
///    doctor detail, a base64 blob), the redactor catches it at the boundary.
///
/// The redactor is a pure function precisely so this second control can be
/// tested property-style: feed it anything secret-shaped and assert nothing
/// recognizable survives.
public enum Diagnostics {

    // MARK: - Redaction

    public struct RedactionResult: Equatable {
        public var text: String
        public var redactions: Int
    }

    /// Redact secret-shaped text. Idempotent, order-independent: every pass
    /// sees the output of the previous pattern family, so a value that matches
    /// two patterns is still exactly one `<redacted …>` marker.
    public static func redact(_ input: String) -> RedactionResult {
        var count = 0
        var text = input

        // 64-hex runs are session tokens (`openssl rand -hex 32`). Commit SHAs
        // are 40 hex; shortened SHAs far shorter — nothing legitimate in a
        // diagnostics bundle is 64 hex.
        text = replacing(in: text, pattern: #"\b[0-9a-fA-F]{64}\b"#, replacement: "<redacted-token>") { count += 1 }

        // key: value secrets of any shape, whatever the key spelling.
        text = replacing(
            in: text,
            pattern: #"(?i)\b(password|passphrase|secret|token)\b(\s*[:=]\s*)(\S+)"#,
            replacement: "<redacted-$1>$2<redacted-value>") { count += 1 }

        // Inline images (screenshots) — §37 forbids full screenshots in exports.
        text = replacing(
            in: text,
            pattern: #"data:image/[a-z+]+;base64,[A-Za-z0-9+/=]+"#,
            replacement: "<redacted-image>") { count += 1 }

        // Any other very long base64-ish run: frame data, blobs. 4096 chars of
        // base64 is ~3 KB of payload — no legitimate diagnostics field.
        text = replacing(
            in: text,
            pattern: #"[A-Za-z0-9+/]{4096,}"#,
            replacement: "<redacted-blob>") { count += 1 }

        return RedactionResult(text: text, redactions: count)
    }

    private static func replacing(in text: String, pattern: String, replacement: String, _ bump: () -> Void) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return text }
        bump()
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    // MARK: - Collection

    /// Build the diagnostics text. Everything here is deliberately
    /// registry-level: states and existence, not payloads.
    public static func collect(root: String? = nil, now: Date = Date()) -> String {
        var lines: [String] = []
        lines.append("AgentSpace diagnostics — \(ISO8601DateFormatter().string(from: now))")

        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { bytes in
            String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        let release = withUnsafeBytes(of: &system.release) { bytes in
            String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        lines.append("system: \(machine) macOS(\(release)) agentspace-core 0.1.0")

        // Doctor — its checks are about states and binaries; no secrets by
        // construction, but it goes through the redactor with everything else.
        let report = Doctor.run(root: root)
        lines.append("")
        lines.append("doctor:")
        for check in report.checks {
            lines.append("  \(check.symbol) \(check.name): \(check.detail)")
        }

        // Spaces — metadata only. The username is shown deliberately: it is
        // how the user navigates the machine; it is not a credential.
        let registry = SpaceRegistry.load(root: root)
        lines.append("")
        lines.append("spaces (\(registry.spaces.count)):")
        for space in registry.spaces {
            let runtime = RuntimePaths(spaceID: space.id, root: root ?? RuntimePaths.root)
            let socket = FileManager.default.fileExists(atPath: runtime.socketPath)
            let tokenFile = FileManager.default.fileExists(atPath: runtime.tokenPath)
            lines.append(
                "  \(space.name): state=\(space.state.rawValue) uid=\(space.uid) " +
                "user=\(space.username) socket=\(socket ? "present" : "absent") " +
                "tokenFile=\(tokenFile ? "present" : "absent")")
        }

        // Quarantined registries (§22) — corruption evidence, file names only.
        let quarantined = SpaceRegistry.corruptRegistryFiles(root: root)
        if !quarantined.isEmpty {
            lines.append("")
            lines.append("quarantined registries:")
            for file in quarantined {
                lines.append("  \((file as NSString).lastPathComponent)")
            }
        }

        return redact(lines.joined(separator: "\n")).text
    }
}
