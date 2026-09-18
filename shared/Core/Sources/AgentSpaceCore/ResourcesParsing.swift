import Foundation

/// Parsing for the per-uid resource sample (plan §30).
///
/// Extracted from the worker's `Resources.sample` as a pure function so the
/// text-parsing contract — the part that has historically been untested — can
/// be pinned directly: one `ps -axo uid=,rss=,pcpu=` line per process, uid in
/// column 1, RSS in kilobytes in column 2, CPU percent in column 3. Malformed
/// lines are skipped, not fatal, because a partial answer that keeps updating
/// is more useful than a resource card that dies on one odd process.
public enum ResourcesParsing {

    /// The accumulated numbers for one Space's uid.
    public struct Totals: Equatable, Sendable {
        public var cpuPercent: Double
        public var memoryBytes: UInt64
        public var processCount: Int

        public init(cpuPercent: Double = 0, memoryBytes: UInt64 = 0, processCount: Int = 0) {
            self.cpuPercent = cpuPercent
            self.memoryBytes = memoryBytes
            self.processCount = processCount
        }
    }

    /// Sum every ps line whose uid matches. Lines for other uids are ignored;
    /// lines that do not parse (headers, truncated output) are skipped.
    public static func accumulate(_ output: String, uid: uid_t) -> Totals {
        var totals = Totals()
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3, let lineUID = uid_t(fields[0]), lineUID == uid else { continue }
            guard let rssKilobytes = UInt64(fields[1]), let cpu = Double(fields[2]) else { continue }
            totals.processCount += 1
            totals.memoryBytes += rssKilobytes * 1024
            totals.cpuPercent += cpu
        }
        return totals
    }
}
