import Foundation
import AgentSpaceCore

#if canImport(Darwin)
import Darwin
#endif

/// Puts one alias address on `lo0`, and takes it off again.
///
/// Root-only by the kernel's own rules (an unprivileged caller gets EPERM —
/// the same fact §399 row 1355 measured for utun, and §400 row 1363 for
/// binding an unassigned 127.x). Implemented with the socket ioctls the
/// `ifconfig` command itself uses, so the privileged helper runs no shell, no
/// external tool and no path handling — the shape every other operation in
/// this daemon keeps.
///
/// The address never reaches this type unvalidated: `HelperValidation` has
/// already refused everything outside 127.100.0.0/16. That range check is
/// repeated here only because defence in depth on a root path is cheap.
enum LoopbackAliasRunner {

    static let interfaceName = "lo0"

    // `sys/sockio.h` defines these as `_IOW(...)` macros, which the Swift
    // importer does not materialize; the values are the header's own, spelled
    // out for exactly these two requests:
    //   SIOCAIFADDR = _IOW('i', 26, struct ifaliasreq)  /* 64-byte request */
    //   SIOCDIFADDR = _IOW('i', 25, struct ifreq)       /* 32-byte request */
    private static let addAliasRequest: UInt32 = 0x8040_691a
    private static let deleteAliasRequest: UInt32 = 0x8020_6919

    /// Returns nil when the interface now holds the desired state, or a
    /// failure text for the reply. Adding an address that is already present
    /// and removing one that is already gone are both successes: the caller
    /// asked for a state, not an action.
    static func apply(address: String, add: Bool) -> String? {
        guard let parsed = AgentSpaceCore.IPv4Address(address) else {
            return "\(address) is not a dotted-quad IPv4 address"
        }
        let raw = parsed.rawValue
        guard (raw >> 24) & 0xff == 127, (raw >> 16) & 0xff == 100 else {
            return "\(address) is outside 127.100.0.0/16"
        }

        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            return "socket() failed: \(String(cString: strerror(errno)))"
        }
        defer { close(fd) }

        // The request layouts, byte for byte, as the kernel reads them:
        // ifaliasreq { char[16] name; sockaddr addr; sockaddr broadaddr; sockaddr mask; }
        // ifreq      { char[16] name; sockaddr addr; }
        // A sockaddr_in is 16 bytes: len, family, 2 bytes port, 4 bytes
        // address, 8 bytes zero.
        var request = [UInt8](repeating: 0, count: add ? 64 : 32)
        let name = Array(interfaceName.utf8)
        for (index, byte) in name.enumerated() where index < 15 {
            request[index] = byte
        }
        request.replaceSubrange(16..<32, with: sockaddrBytes(raw))
        if add {
            // A /32 alias: every alias is its own host address, which is
            // exactly how `ifconfig lo0 alias` sets it.
            request.replaceSubrange(32..<48, with: sockaddrBytes(raw))
            request.replaceSubrange(48..<64, with: sockaddrBytes(0xffff_ffff))
        }

        let command: UInt = add ? UInt(addAliasRequest) : UInt(deleteAliasRequest)
        let result = request.withUnsafeMutableBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return -1 }
            return ioctl(fd, command, base)
        }
        guard result == 0 else {
            let code = errno
            if add, code == EEXIST { return nil }
            if !add, code == EADDRNOTAVAIL { return nil }
            return "ioctl \(add ? "SIOCAIFADDR" : "SIOCDIFADDR") failed: \(String(cString: strerror(code)))"
        }
        return nil
    }

    /// One IPv4 `sockaddr_in`, as sixteen bytes in network layout.
    private static func sockaddrBytes(_ address: UInt32) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = UInt8(MemoryLayout<sockaddr_in>.size)
        bytes[1] = UInt8(AF_INET)
        bytes[4] = UInt8((address >> 24) & 0xff)
        bytes[5] = UInt8((address >> 16) & 0xff)
        bytes[6] = UInt8((address >> 8) & 0xff)
        bytes[7] = UInt8(address & 0xff)
        return bytes
    }
}
