import Foundation
import Darwin

/// macOS file privacy: what a process may read inside an account's home *beyond*
/// what POSIX allows, and how to tell without raising a dialog nobody is watching.
///
/// Two families of TCC gate protect a home directory, and they fail differently:
///
/// * The folder gates (`Desktop`, `Documents`, `Downloads`) **prompt** the first
///   time an ungranted process reads them. In a background Aqua session that
///   dialog can sit unanswered forever, so nothing here may trigger one as a side
///   effect of a metric.
/// * Per-app data (`kTCCServiceSystemPolicyAppDataDetailed`, Photos, Messages…) is
///   consulted **per access**: a walk of `~/Library` costs one tccd round trip per
///   protected container, and denies hard when prompting is not allowed.
///
/// Full Disk Access is the one answer that covers all of it, and the probe below
/// is why it can be used from a polling path: the grant is checked silently — the
/// kernel denies the open, it does not ask — so `granted(home:)` never produces a
/// dialog. Measured on macOS 27: `isReadableFile` on a gated file returns false
/// and tccd logs `kTCCServiceSystemPolicyAllFiles` with no prompting event.
public enum FilePrivacy {

    /// Home-relative roots a walk must not enter without the grant.
    ///
    /// `Library` is skipped as a whole rather than container by container: the
    /// per-app gate is evaluated for every protected bundle directory it holds,
    /// so a fine-grained list would still cost a prompt or a denial per app.
    public static let protectedSubpaths: [String] = [
        "Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Library",
    ]

    /// Gated files to probe, most likely to exist first. All are covered by Full
    /// Disk Access and none belongs to a category with its own prompt, so
    /// checking them cannot raise a dialog the way `Documents` would.
    static let probeSubpaths: [String] = [
        "Library/Application Support/Knowledge/knowledgeC.db",
        "Library/Messages/chat.db",
        "Library/Cookies/Cookies.sqlite",
        "Library/Safari/Bookmarks",
    ]

    /// Injectable because a unit test must not read a real account's home, and a
    /// wrong answer here only ever narrows what the disk metric walks.
    public static var reader: (String) -> Bool = {
        FileManager.default.isReadableFile(atPath: $0)
    }

    static var exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }

    /// The first probe file this home actually has.
    static func probe(home: String) -> String? {
        probeSubpaths.lazy.map { home + "/" + $0 }.first(where: exists)
    }

    /// Whether this process may read the whole home of `home`'s owner.
    ///
    /// One gated file answers it: Full Disk Access is a single grant, so a process
    /// that can read any of these can read all of them. `false` also covers "could
    /// not tell" — a home with none of these files has nothing to check. That is
    /// the safe direction, since the only consumer keeps out of protected folders
    /// when the answer is no.
    public static func granted(home: String, reader: (String) -> Bool = FilePrivacy.reader) -> Bool {
        guard let probe = probe(home: home) else { return false }
        return reader(probe)
    }

    /// Make this process appear in System Settings' Full Disk Access list.
    ///
    /// There is no public request API for this grant and macOS never prompts for
    /// it — a gated read is simply denied — so the only way the worker becomes a
    /// row the user can switch on is by attempting one such read. Call this from
    /// the user's explicit authorization action, never from a poll, and only after
    /// `granted(home:)` said no: nothing here reads file contents, and when the
    /// grant is already in place this opens a file the process may already open.
    public static func registerForFullDiskAccess(home: String) {
        guard let probe = probe(home: home) else { return }
        let descriptor = Darwin.open(probe, O_RDONLY)
        if descriptor >= 0 { Darwin.close(descriptor) }
    }
}
