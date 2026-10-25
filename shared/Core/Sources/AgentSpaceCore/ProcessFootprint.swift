import Foundation

/// Physical memory footprint for a process, and the sum over a set — the
/// number Activity Monitor's Memory column shows, and the honest answer to
/// "how much more RAM does this Mac really have to find for this agent"
/// (§407).
///
/// ## Why footprint and not RSS
///
/// The resource card's `memoryBytes` is a sum of resident sizes from `ps`,
/// which counts every shared page once per process that maps it: the dyld
/// cache and the system frameworks are resident exactly once on the machine
/// but appear in every process's row. `ri_phys_footprint` is Apple's own
/// accounting instead — private anonymous pages plus this process's compressed
/// pages at their compressed size — so shared clean pages cost nothing and an
/// idle agent shrinks to what the compressor really holds for it. The two
/// figures are deliberately shown side by side; neither replaces the other.
///
/// ## The syscall, pinned by measurement rather than memory
///
/// `libproc` has no Swift module, so the one entry point needed is declared by
/// hand, the same way `SharedFrameRegion` declares `shm_open`. Facts from
/// `<sys/resource.h>` and from measuring on this machine (2026-10-25):
/// `ri_phys_footprint` sits at byte offset 72 — word 9 — at the same offset in
/// every `rusage_info_v*` from v1 on; flavor 4 (`RUSAGE_INFO_V4`) returns 0 on
/// success; and a process may read rusage for every pid its own uid owns with
/// no privilege — 405 of 405 calls succeeded as uid 503, and word 9 matched
/// `vmmap --summary`'s "Physical footprint" line exactly (ZCode Helper
/// (Renderer), 158.6 MB both ways). The whole 405-pid walk costs under a
/// millisecond, so the status poll's `resources` sample carries it without
/// breaking §53's near-zero idle CPU.
public enum ProcessFootprint {

    /// `sizeof(rusage_info_v4)` = 16 bytes of uuid + 35 UInt64 fields = 296.
    private static let infoWords = 37
    /// Byte offset 72 ÷ 8: the ninth word is `ri_phys_footprint`.
    private static let footprintWord = 9

    @_silgen_name("proc_pid_rusage")
    private static func proc_pid_rusage(_ pid: Int32, _ flavor: Int32, _ buffer: UnsafeMutableRawPointer) -> Int32

    /// The footprint of one pid, or nil when the call was refused. A pid that
    /// exited between the `ps` snapshot and here is normal table churn, not an
    /// error — the caller treats it as "this one did not answer".
    public static func bytes(pid: pid_t) -> UInt64? {
        var buffer = [UInt64](repeating: 0, count: infoWords)
        let result = buffer.withUnsafeMutableBytes { raw in
            proc_pid_rusage(pid, 4, raw.baseAddress!)
        }
        guard result == 0 else { return nil }
        return buffer[footprintWord]
    }

    /// Sum over pids. An empty set is a measured zero. A non-empty set where
    /// every call failed is `nil`: "we could not look" must not display as
    /// "0 bytes". Mixed success sums what answered — a lower bound under
    /// churn, like every other figure in the resources card.
    public static func sum(pids: [pid_t]) -> UInt64? {
        if pids.isEmpty { return 0 }
        var total: UInt64 = 0
        var answered = 0
        for pid in pids {
            if let bytes = bytes(pid: pid) {
                total += bytes
                answered += 1
            }
        }
        return answered == 0 ? nil : total
    }
}
