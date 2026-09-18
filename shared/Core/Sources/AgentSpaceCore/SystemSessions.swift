import Foundation
import Darwin

/// Which accounts currently have live sessions on this machine.
///
/// The discriminator for plan §39: after a reboot the agent account exists but
/// nobody has logged into it, and the UI must show **Needs Login** — not
/// "offline", which would suggest that waiting or retrying could bring the
/// Space back. The difference is observable without any private API: a logged
/// in user (even switched away by fast user switching) owns running processes
/// — Finder, Dock, their launchd — while a never-logged-in account owns none.
///
/// `utmpx` was considered first and rejected empirically: modern macOS does not
/// populate it for GUI logins, so it reported *this* console session as absent.
public enum SystemSessions {
    /// True when at least one process is owned by `uid`.
    ///
    /// Deliberately cheap and permission-free: `sysctl(KERN_PROC_ALL)` is
    /// readable by any process, so the GUI can ask about the *agent's* uid
    /// without running anything as that user or as root.
    public static func hasLiveProcesses(uid: uid_t) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return false }
        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, 3, &procs, &size, nil, 0) == 0 else { return false }
        // The list can change between the two sysctls; trust only whole records
        // that came back with a live process slot.
        for entry in procs.prefix(size / MemoryLayout<kinfo_proc>.stride) where entry.kp_proc.p_stat != 0 {
            if entry.kp_eproc.e_ucred.cr_uid == uid { return true }
        }
        return false
    }
}
