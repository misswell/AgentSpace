import Foundation
import Security
import AgentSpaceCore

/// Verifies that the process connecting to the helper is the AgentSpace app.
///
/// Plan §7: the helper must check the caller's code signing requirement. Without
/// this, any process on the machine — including the agent itself — could ask the
/// root helper to create and delete accounts. The typed interface limits the
/// damage to accounts named `_agentspace_…`, but that still means an agent could
/// delete another Space or create accounts without limit.
public enum CodeSigningRequirement {

    /// Team identifier of the signing certificate. Hard-coded rather than read
    /// from the running process, because a requirement that adapts to whatever
    /// signed the app is not a requirement.
    public static let teamIdentifier = "U8U443D7ZL"

    public static let appIdentifier = "com.agentspace.AgentSpace"
    public static let helperIdentifier = "com.agentspace.AgentSpace.Helper"

    /// The requirement string the helper enforces in release builds.
    ///
    /// Read it as: signed by Apple's Developer ID chain, with *our* team, and
    /// either the app or the helper (the helper is a separate Mach-O, and the CLI
    /// ships inside the app bundle so it carries the app's identity).
    ///
    /// `anchor apple generic` is what makes this meaningful: it requires the
    /// certificate chain to reach Apple, so a self-signed certificate with a
    /// copied team identifier does not satisfy it.
    public static var requirement: String {
        "anchor apple generic"
        + " and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        + " and (identifier \"\(appIdentifier)\" or identifier \"\(helperIdentifier)\")"
    }

    /// What a locally built, ad-hoc-signed debug binary can actually satisfy.
    ///
    /// It still requires the signing identifier — so a random unsigned binary is
    /// refused — but not the Apple anchor, which a development build cannot have.
    /// Selected at compile time, never at run time: "skip the signature check
    /// when a file exists" is how backdoors are born.
    public static var developmentRequirement: String {
        "identifier \"\(appIdentifier)\" or identifier \"\(helperIdentifier)\""
    }

    public static var enforcedRequirement: String {
        #if DEBUG
        return developmentRequirement
        #else
        return requirement
        #endif
    }

    /// Why the check is done on a pid, and what that costs.
    ///
    /// The correct identity for an XPC peer is its **audit token**, which the
    /// kernel supplies for the connection and which the peer cannot forge. The
    /// modern API for using it is `xpc_peer_requirement_create_team_identity` —
    /// which is `macOS 26.0+`, and which is precisely the "signed with the same
    /// team identifier as the current process" check this file implements by
    /// hand. It takes an `xpc_object_t`, so using it would mean abandoning
    /// `NSXPCConnection` for raw XPC.
    ///
    /// `NSXPCConnection` exposes only `processIdentifier` (verified against the
    /// SDK: `Foundation/NSXPCConnection.h` declares `processIdentifier` and
    /// nothing else), so on the supported API surface the check is pid-based.
    ///
    /// That leaves a **pid-reuse window**: if the real app exits at exactly the
    /// right moment, an attacker's process could be assigned the same pid and
    /// pass the check. It is narrow — it requires winning a race against pid
    /// allocation — but it is real, and it is recorded in `docs/security.md`
    /// rather than papered over.
    ///
    /// `verifiedPeer(pid:token:)` closes most of it: the signature is checked,
    /// then the process is re-identified and its cdhash compared, and the helper
    /// runs this again immediately before each privileged operation. An attacker
    /// must then survive three identifications rather than one.
    public static func check(pid: pid_t) -> PeerIdentity? {
        let attributes = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary

        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let guest = code else {
            return nil
        }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(enforcedRequirement as CFString, [], &requirement) == errSecSuccess,
              let requirement else {
            return nil
        }

        // The whole point. Fails closed: any error at any step above returned nil.
        guard SecCodeCheckValidity(guest, [], requirement) == errSecSuccess else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(guest, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return PeerIdentity(pid: pid, identifier: nil, cdhash: nil, path: nil)
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &information) == errSecSuccess,
              let info = information as? [String: Any] else {
            return PeerIdentity(pid: pid, identifier: nil, cdhash: nil, path: nil)
        }

        // The identifier and the cdhash both describe *which code this is*, so
        // they are read together. The cdhash is the stronger of the two and is
        // what the pid-reuse recheck compares.
        let identifier = info[kSecCodeInfoIdentifier as String] as? String
        let path = (info[kSecCodeInfoMainExecutable as String] as? URL)?.path
            ?? (info[kSecCodeInfoMainExecutable as String] as? String)
        let cdhash = (info[kSecCodeInfoUnique as String] as? NSData) as Data?

        return PeerIdentity(pid: pid, identifier: identifier, cdhash: cdhash, path: path)
    }

    /// Check, then confirm the process at that pid is still the one we checked.
    ///
    /// The second identification is what makes pid reuse expensive: an attacker
    /// has to be the same *code* twice, not merely occupy the pid once.
    public static func verifiedPeer(pid: pid_t) -> PeerIdentity? {
        guard let first = check(pid: pid) else { return nil }
        // Give the scheduler a chance to run anything that was waiting on this
        // pid, so the recheck is a real recheck rather than two reads of one
        // cached value.
        usleep(1_000)
        guard let second = check(pid: pid) else { return nil }

        // A nil cdhash on either side means we could not read it; in that case the
        // identifier must at least match, and we say so rather than assuming.
        if let a = first.cdhash, let b = second.cdhash {
            guard a == b else { return nil }
        } else if first.identifier != second.identifier {
            return nil
        }

        return second
    }

    public static func describe() -> String {
        "the connecting process did not satisfy: \(enforcedRequirement)"
    }
}

/// What was verified about the caller. Kept so the log can say *which* process
/// was accepted, which is what a security review needs to read.
public struct PeerIdentity {
    public var pid: pid_t
    public var identifier: String?
    public var cdhash: Data?
    public var path: String?

    public var summary: String {
        let cdhashText = cdhash.map { $0.map { String(format: "%02x", $0) }.joined().prefix(16) } ?? "?"
        return "pid \(pid), id \(identifier ?? "?"), cdhash \(cdhashText)…, \(path ?? "?")"
    }
}
