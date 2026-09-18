import Foundation
import os
import AgentSpaceCore

/// One client connection. Owns the fd and every write to it.
///
/// Framing is one JSON object per line, one request per connection, exactly as
/// `docs/protocol.md` specifies. Requests are capped before buffering so a
/// hostile peer cannot make the worker allocate without bound.
final class Connection {
    let fd: Int32
    private(set) var peerGone = false

    init(fd: Int32) { self.fd = fd }

    /// Read one `\n`-terminated request.
    ///
    /// Returns nil on EOF before a newline. Throws `BAD_REQUEST` if the line
    /// exceeds the cap — thrown *while* reading, so the memory is never spent.
    func readLine() throws -> Data? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if n == 0 { return buffer.isEmpty ? nil : buffer }
            for i in 0..<n {
                if chunk[i] == Framing.newline { return buffer }
                buffer.append(chunk[i])
                if buffer.count > Framing.maxRequestBytes {
                    throw AgentSpaceError(
                        code: .badRequest,
                        message: "request exceeds \(Framing.maxRequestBytes) bytes")
                }
            }
        }
    }

    @discardableResult
    func send(_ response: RPCResponse) -> Bool {
        guard let data = try? RPCCodec.encodeLine(response) else {
            let fallback = #"{"id":"","ok":false,"error":{"code":"INTERNAL_ERROR","message":"failed to encode response","recoverable":false}}"#
            return writeAll(Data(fallback.utf8) + Data([Framing.newline]))
        }
        return writeAll(data)
    }

    @discardableResult
    private func writeAll(_ data: Data) -> Bool {
        guard !peerGone else { return false }
        var sent = 0
        let total = data.count
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress else { return true }
            while sent < total {
                let n = write(fd, base.advanced(by: sent), total - sent)
                if n > 0 { sent += n; continue }
                if n < 0 && errno == EINTR { continue }
                peerGone = true
                return false
            }
            return true
        }
    }

    func close() { _ = Darwin.close(fd) }
}

/// Structured logging through `OSLog` with the subsystem and categories the
/// plan names (§37).
///
/// Everything funnels through `Redaction.scrubString` first. `OSLog`'s own
/// privacy annotations cannot help a message that was already interpolated into
/// a plain `String`, so the redaction has to happen before the call, and it does
/// — in one place, so a new log line cannot forget it.
enum Log {
    static let subsystem = "com.agentspace.app"

    static let app = Logger(category: "app")
    static let helper = Logger(category: "helper")
    static let worker = Logger(category: "worker")
    static let ipc = Logger(category: "ipc")
    static let session = Logger(category: "session")
    static let input = Logger(category: "input")
    static let capture = Logger(category: "capture")
    static let mcp = Logger(category: "mcp")

    /// Captures lines instead of emitting them. Set by tests; nil in production.
    static var sink: ((String, String, String) -> Void)?
    private static let sinkLock = NSLock()

    static func setSink(_ newValue: ((String, String, String) -> Void)?) {
        sinkLock.lock(); defer { sinkLock.unlock() }
        sink = newValue
    }

    struct Logger {
        let category: String

        func info(_ message: String) { emit(level: .default, message) }
        func error(_ message: String) { emit(level: .error, message) }
        func debug(_ message: String) { emit(level: .debug, message) }

        private func emit(level: OSLogType, _ message: String) {
            let line = Redaction.scrubString(message)
            Log.sinkLock.lock()
            let captured = Log.sink
            Log.sinkLock.unlock()
            if let captured {
                captured(Log.subsystem, category, line)
                return
            }
            os_log(level, log: Log.handle(subsystem: Log.subsystem, category: category),
                   "%{public}s", line)
        }
    }

    private static var handles: [String: OSLog] = [:]
    private static let handlesLock = NSLock()

    private static func handle(subsystem: String, category: String) -> OSLog {
        handlesLock.lock(); defer { handlesLock.unlock() }
        let key = subsystem + "/" + category
        if let existing = handles[key] { return existing }
        let created = OSLog(subsystem: subsystem, category: category)
        handles[key] = created
        return created
    }
}
