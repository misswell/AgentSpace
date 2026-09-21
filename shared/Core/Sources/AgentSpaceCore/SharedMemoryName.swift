import Foundation

/// Names for POSIX shared-memory objects, sized for the kernel that must accept them.
///
/// Do not include space or stream UUIDs here. Darwin POSIX shared-memory names
/// have a much smaller limit than UNIX-domain socket paths, and `shm_open`
/// answers an over-long one with `ENAMETOOLONG` — a failure no layout test can
/// see, because the struct it breaks on is a string in a syscall argument. The
/// first version of this path used `/agentspace-<uuid>`; at 48 bytes it made
/// every frame stream on every machine die at its first call.
///
/// `RuntimePaths.maxSocketPathBytes` (103) is `sockaddr_un.sun_path` and is a
/// different object with a different limit. The two are not interchangeable.
public enum SharedMemoryName {
    /// Measured on Darwin, not copied from a header: `shm_open` accepts a
    /// 31-byte name and rejects a 32-byte one.
    public static let darwinMaximumBytes = 31

    /// A short, unguessable name for an object that outlives its own name.
    ///
    /// The token is 24 hex characters (96 bits) instead of something readable
    /// because the object's whole life is `shm_open` → `ftruncate` → `mmap` →
    /// `shm_unlink`; after the unlink only the fd remains, and the controller
    /// receives that through SCM_RIGHTS on an authenticated socket. Names are
    /// not identities — a stream is known by its space id, stream id, worker
    /// instance id and surface generation, none of which belong here.
    public static func make() -> String {
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let name = "/as-\(token.prefix(24))"
        precondition(name.utf8.count <= darwinMaximumBytes)
        return name
    }
}
