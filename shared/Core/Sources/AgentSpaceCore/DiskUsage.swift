import Foundation

/// How much disk a Space actually occupies — plan §30.
///
/// ## Allocated, not logical
///
/// Plan §30 asks for "Disk Usage", meaning the space the Space occupies on the
/// volume. Summing `fileSize` would report the *logical* length, which on APFS with
/// compression, sparse files and clones can be far larger than what is really
/// used — and would disagree with both `du` and Finder. `totalFileAllocatedSizeKey`
/// is the number of bytes the filesystem will give back when the blocks are freed,
/// which is the honest answer and the one a user can check.
///
/// ## Why it is opt-in
///
/// A Space's home holds a browser profile, an IDE's caches and whatever the agent
/// downloaded. Tens of thousands of files is normal, so this walk is genuinely
/// expensive — hundreds of milliseconds, not microseconds. Plan §53 requires the
/// app to sit near 0% CPU while idle, so nothing in the ordinary status path calls
/// this; it is a separate, explicitly-requested operation.
public enum DiskUsage {

    /// Lower bound on the bytes under `path`, and whether the walk was cut short.
    ///
    /// Returning a bound rather than throwing matters: a partial answer is still
    /// useful, and the caller can say "at least this much" instead of showing
    /// nothing or, worse, a number that is wrong without saying so.
    public struct Measurement: Equatable {
        public var bytes: UInt64
        public var truncated: Bool
        public var files: Int
        /// True when `skip` cut a root out of the walk, making `bytes` a figure
        /// for part of the home rather than for the home.
        public var skippedProtected: Bool

        public init(
            bytes: UInt64,
            truncated: Bool,
            files: Int,
            skippedProtected: Bool = false
        ) {
            self.bytes = bytes
            self.truncated = truncated
            self.files = files
            self.skippedProtected = skippedProtected
        }
    }

    /// Walk `path` and total the allocated bytes of the regular files in it.
    ///
    /// - Parameter budget: the maximum number of directory entries to visit. The
    ///   default is high enough for a realistic home and low enough that the walk
    ///   cannot become an unbounded stall if the agent has filled the disk with
    ///   node_modules. Exceeding it sets `truncated` and returns what was counted.
    /// - Parameter skip: root-relative top-level entries never to descend into.
    ///   Callers pass `FilePrivacy.protectedSubpaths` when the process has no
    ///   Full Disk Access: entering `Documents` or an app's data container is a
    ///   TCC-gated read, which either raises a prompt nobody in a background
    ///   session will answer or costs a denial per protected directory. A metric
    ///   must not spend the user's privacy decisions to produce a number.
    public static func allocatedBytes(
        under path: String,
        budget: Int = 250_000,
        skip: Set<String> = []
    ) -> Measurement {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: keys,
            // Symlinks are not followed by default, which is what we want: a link
            // into another Space's home must not make one Space's usage include
            // another's, and a link loop must not hang the walk.
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }) else {
            return Measurement(bytes: 0, truncated: false, files: 0)
        }
        // Trailing slash stripped: the comparison below is against paths relative
        // to `path`, and `standardizedFileURL` keeps that prefix stable.
        let root = URL(fileURLWithPath: path).standardizedFileURL.path

        var total: UInt64 = 0
        var files = 0
        var visited = 0
        var skippedProtected = false
        for case let url as URL in enumerator {
            visited += 1
            if visited > budget {
                return Measurement(bytes: total, truncated: true, files: files, skippedProtected: skippedProtected)
            }
            // Before any resource value is requested: asking for one is a read of
            // that entry's metadata, and for a protected root the whole subtree
            // costs one gate check per entry.
            if !skip.isEmpty, let first = relativeComponent(of: url, under: root),
               skip.contains(first) {
                enumerator.skipDescendants()
                skippedProtected = true
                continue
            }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            // Only regular files contribute. Directories report an entry size of
            // their own, and adding it would double count on filesystems where it
            // is derived from the contents.
            guard values.isRegularFile == true else { continue }
            let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
            total += UInt64(size)
            files += 1
        }
        return Measurement(bytes: total, truncated: false, files: files, skippedProtected: skippedProtected)
    }

    /// The first path component under `root`, or nil when `url` is `root` itself.
    static func relativeComponent(of url: URL, under root: String) -> String? {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return nil }
        return String(path.dropFirst(root.count + 1).prefix { $0 != "/" })
    }
}
