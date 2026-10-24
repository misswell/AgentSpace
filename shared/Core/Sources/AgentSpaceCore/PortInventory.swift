import Foundation

/// One TCP socket this account is listening on.
public struct ListeningPort: Equatable, Sendable, Codable {
    /// The numeric bind address exactly as `lsof -n` printed it: `127.0.0.1`,
    /// `0.0.0.0`, `*`, `[::1]`, `[fe80::1%en0]`, …
    public let address: String
    public let port: UInt16
    public let process: String?
    public let pid: Int?

    public init(address: String, port: UInt16, process: String? = nil, pid: Int? = nil) {
        self.address = address
        self.port = port
        self.process = process
        self.pid = pid
    }

    /// Whether a connection to `127.0.0.1:<port>` can reach this socket —
    /// i.e. whether the port can be mapped for use with no network at all. A
    /// service bound only to a physical interface's address is reachable
    /// through that interface, not through loopback, and the mapped alias
    /// would refuse.
    public var coversLoopback: Bool {
        switch address {
        case "127.0.0.1", "0.0.0.0", "*", "[::]", "::":
            return true
        default:
            return false
        }
    }
}

/// Lists the TCP ports this account's own processes are listening on.
///
/// Runs `/usr/sbin/lsof` as the calling user, which is what makes the answer
/// *this account's* ports without any privilege: lsof without root only
/// attributes the calling user's own files, so other users' listeners do not
/// appear as rows at all. Read-only; nothing is written, opened or signalled.
public enum PortInventory {

    public static let lsofPath = "/usr/sbin/lsof"

    /// Parse the output of `lsof -nP -iTCP -sTCP:LISTEN`. Only rows whose NAME
    /// column ends in `(LISTEN)`; one row per distinct (process, address,
    /// port) so a server with several file descriptors on one port appears
    /// once.
    public static func parse(lsofOutput text: String) -> [ListeningPort] {
        var seen = Set<String>()
        var ports: [ListeningPort] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            // COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME (LISTEN)
            guard fields.count >= 10, fields[0] != "COMMAND",
                  fields[9].hasSuffix("(LISTEN)") else { continue }
            guard let (address, port) = parseEndpoint(String(fields[8])) else { continue }
            let key = "\(fields[1])|\(address)|\(port)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            ports.append(ListeningPort(
                address: address,
                port: port,
                process: String(fields[0]),
                pid: Int(fields[1])))
        }
        return ports.sorted { ($0.port, $0.address) < ($1.port, $1.address) }
    }

    /// `host:port` as lsof prints it, IPv6 in brackets, `*` for wildcard.
    /// Returns nil for anything without a parsable port — `*:*` rows are
    /// sockets lsof could not attribute a port to, not listeners.
    static func parseEndpoint(_ text: String) -> (address: String, port: UInt16)? {
        if let opening = text.firstIndex(of: "[") {
            guard let closing = text[opening...].firstIndex(of: "]"),
                  let colon = text.index(closing, offsetBy: 1, limitedBy: text.endIndex),
                  text[colon] == ":" else { return nil }
            let address = String(text[opening...closing])
            let portText = String(text[text.index(after: colon)...])
            guard let port = UInt16(portText), port != 0 else { return nil }
            return (address, port)
        }
        guard let colon = text.lastIndex(of: ":") else { return nil }
        let address = String(text[..<colon])
        let portText = String(text[text.index(after: colon)...])
        guard let port = UInt16(portText), port != 0, !address.isEmpty else { return nil }
        return (address, port)
    }

    /// The live answer for this account. A failure to run lsof is an empty
    /// list; the callers that matter (the forwarder's ownership gate) treat
    /// "no evidence" as "not owned" and refuse, which is the safe direction.
    public static func collect(lsofPath: String = PortInventory.lsofPath) -> [ListeningPort] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: lsofPath)
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return parse(lsofOutput: text)
    }
}
