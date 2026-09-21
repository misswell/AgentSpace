import Darwin
import Foundation

/// The wall clock every frame timeline shares: host uptime in seconds. Both
/// ends of a frame socket run on the same Mac, so these stamps are comparable
/// across the process boundary without a clock negotiation.
public enum FrameClock {
    public static func uptime() -> TimeInterval {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}

public enum FrameSocketFailure: Error, Equatable {
    /// The peer is gone: the socket reported end-of-stream or an error.
    case disconnected
    /// Nothing arrived within the idle policy's stale window. Distinct from
    /// `disconnected` because the reason to act differs — a stale socket still
    /// looks open, and only the silence says it is not carrying a stream.
    case stale
    /// The peer stopped reading, so a write could not finish within its
    /// timeout. Framing is now half-written, so the connection cannot be
    /// reused for another frame.
    case sendTimeout
    case protocolError(String)
}

extension FrameSocketFailure {
    /// The same failure in the shape the product uses everywhere: a code a
    /// console can show and a remediation line that says what happens next.
    ///
    /// `stale` deliberately reports as offline-but-recoverable. The worker is
    /// probably still running; what died is the stream, and a viewer that said
    /// "the agent is gone" would be sending the user to the wrong page.
    public var frameError: AgentSpaceError {
        switch self {
        case .disconnected:
            return AgentSpaceError(code: .workerOffline, message: "the frame stream closed.")
        case .stale:
            return AgentSpaceError(code: .workerOffline, message: "the frame stream sent neither a frame nor a heartbeat.")
        case .sendTimeout:
            return AgentSpaceError(code: .workerOffline, message: "the frame stream stopped reading.")
        case .protocolError(let reason):
            return AgentSpaceError(code: .internalError, message: "frame protocol error: \(reason)")
        }
    }
}

/// The one socket transport both ends of a frame stream use.
///
/// It exists so that neither side can wait forever on the other. A worker that
/// blocks in `write` behind a viewer that stopped reading stalls every stream
/// that shares its queue; a viewer that blocks in `read` behind a worker that
/// died mid-frame keeps showing its last picture and calls that online. Both
/// are fixed here rather than at the call site because the fix is the same
/// primitive: put a deadline on the syscall, and treat "deadline passed" as
/// the connection being over.
public final class FrameSocket {
    public let fd: Int32
    private let writeLock = NSLock()
    private let livenessLock = NSLock()
    private var liveness: FrameStreamLiveness
    private var fdReleased = false
    /// Guards `closed`/`fdReleased` for readers that must not take `writeLock`:
    /// a thread aborting a connection from a watchdog cannot wait for a write
    /// that is parked in the kernel, because the write is only released *by*
    /// the abort.
    private let stateLock = NSLock()
    public private(set) var closed = false
    /// Set once a write has returned without finishing, which is also the
    /// moment the byte stream stopped being aligned to frames.
    private(set) var sendIncomplete = false

    public init(fd: Int32, policy: FrameIdlePolicy = .init(), sendTimeout: TimeInterval = 1, receiveTimeout: TimeInterval = 1) {
        self.fd = fd
        liveness = FrameStreamLiveness(policy: policy, at: FrameClock.uptime())
        apply(timeout: sendTimeout, option: SO_SNDTIMEO)
        apply(timeout: receiveTimeout, option: SO_RCVTIMEO)
    }

    deinit {
        abort()
        releaseFD()
    }

    private func apply(timeout: TimeInterval, option: Int32) {
        guard timeout > 0 else { return }
        var value = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, option, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    public var idlePolicy: FrameIdlePolicy { livenessLock.lock(); defer { livenessLock.unlock() }; return liveness.policy }

    public func noteActivity(at now: TimeInterval = FrameClock.uptime()) {
        livenessLock.lock(); liveness.noteActivity(at: now); livenessLock.unlock()
    }

    /// True when the peer has sent nothing — frame or heartbeat — for longer
    /// than the policy allows. A still desktop never triggers it, because the
    /// worker's heartbeat is also activity.
    public func isStale(at now: TimeInterval = FrameClock.uptime()) -> Bool {
        livenessLock.lock(); defer { livenessLock.unlock() }; return liveness.isStale(at: now)
    }

    public func heartbeatDue(at now: TimeInterval = FrameClock.uptime()) -> Bool {
        livenessLock.lock(); defer { livenessLock.unlock() }; return liveness.heartbeatDue(at: now)
    }

    public func noteHeartbeatSent(at now: TimeInterval = FrameClock.uptime()) {
        livenessLock.lock(); liveness.noteHeartbeatSent(at: now); livenessLock.unlock()
    }

    // MARK: Reading

    /// Reads one complete frame, waiting no longer than the receive timeout per
    /// syscall and no longer than the idle policy overall.
    public func readFrame() throws -> (header: FrameHeader, payload: Data) {
        let headerData = try readExactly(FrameHeader.byteCount)
        let header = try FrameHeader(decoding: headerData)
        guard header.payloadSize > 0 else { return (header, Data()) }
        let payload = try readExactly(Int(header.payloadSize))
        return (header, payload)
    }

    public func readExactly(_ count: Int) throws -> Data {
        var data = Data()
        data.reserveCapacity(count)
        var scratch = [UInt8](repeating: 0, count: 8 * 1024)
        while data.count < count {
            let received = scratch.withUnsafeMutableBytes { pointer in
                Darwin.read(fd, pointer.baseAddress, min(pointer.count, count - data.count))
            }
            if received > 0 {
                noteActivity()
                data.append(contentsOf: scratch[0..<received])
                continue
            }
            if received == 0 { throw FrameSocketFailure.disconnected }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK || errno == ETIMEDOUT {
                if isStale() { throw FrameSocketFailure.stale }
                continue
            }
            throw FrameSocketFailure.disconnected
        }
        return data
    }

    /// Reads one newline-delimited control line, used before framing starts.
    public func readLine(limit: Int = 16 * 1024) throws -> Data {
        var data = Data()
        var byte: UInt8 = 0
        while data.count < limit {
            let count = Darwin.read(fd, &byte, 1)
            if count == 1 {
                noteActivity()
                if byte == 0x0a { return data }
                data.append(byte)
                continue
            }
            if count == 0 { throw FrameSocketFailure.disconnected }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK || errno == ETIMEDOUT {
                if isStale() { throw FrameSocketFailure.stale }
                continue
            }
            throw FrameSocketFailure.disconnected
        }
        throw FrameSocketFailure.protocolError("frame control line exceeded \(limit) bytes")
    }

    // MARK: Writing

    public func sendLine<T: Encodable>(_ value: T) throws {
        try writeAll(FrameTransportCoding.line(value))
    }

    public func sendFrame(header: FrameHeader, payload: Data) throws {
        try writeAll(header.encoded() + payload)
    }

    /// Writes every byte, or explains why the connection is over.
    ///
    /// A timeout is not retried: the partial bytes already went out, so the
    /// peer is now mid-frame and the next thing written to this socket would be
    /// read as the rest of it. The only safe follow-up is to close and let the
    /// client reconnect.
    public func writeAll(_ data: Data) throws {
        writeLock.lock(); defer { writeLock.unlock() }
        guard !isDead else { throw FrameSocketFailure.disconnected }
        try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
                if written > 0 { offset += written; continue }
                if written < 0 && errno == EINTR { continue }
                if written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == ETIMEDOUT) {
                    sendIncomplete = true
                    throw FrameSocketFailure.sendTimeout
                }
                markDead()
                throw FrameSocketFailure.disconnected
            }
        }
    }

    // MARK: Descriptor passing

    /// Passes a shared-memory descriptor alongside a one-byte marker, so the
    /// byte a client is already waiting for also says "the fd is in this
    /// message".
    public func sendFileDescriptor(_ descriptor: Int32) throws {
        writeLock.lock(); defer { writeLock.unlock() }
        guard !isDead, !sendIncomplete else { throw FrameSocketFailure.disconnected }
        var marker: UInt8 = 0x46
        let alignment = MemoryLayout<size_t>.size
        let headerSize = MemoryLayout<cmsghdr>.size
        let dataSize = MemoryLayout<Int32>.size
        let controlSize = ((headerSize + dataSize + alignment - 1) / alignment) * alignment
        var control = [UInt8](repeating: 0, count: controlSize)
        let sent: Int = withUnsafeMutablePointer(to: &marker) { markerPointer in
            var vector = iovec(iov_base: UnsafeMutableRawPointer(markerPointer), iov_len: 1)
            return withUnsafeMutablePointer(to: &vector) { vectorPointer in
                control.withUnsafeMutableBytes { bytes in
                    guard let base = bytes.baseAddress else { return -1 }
                    let header = base.assumingMemoryBound(to: cmsghdr.self)
                    header.pointee.cmsg_len = socklen_t(headerSize + dataSize)
                    header.pointee.cmsg_level = SOL_SOCKET
                    header.pointee.cmsg_type = SCM_RIGHTS
                    base.advanced(by: headerSize).assumingMemoryBound(to: Int32.self).pointee = descriptor
                    var message = msghdr(msg_name: nil, msg_namelen: 0, msg_iov: vectorPointer, msg_iovlen: 1,
                                         msg_control: base, msg_controllen: socklen_t(controlSize), msg_flags: 0)
                    return sendmsg(fd, &message, 0)
                }
            }
        }
        guard sent == 1 else { markDead(); throw FrameSocketFailure.disconnected }
    }

    public func receiveFileDescriptor() throws -> Int32 {
        var marker: UInt8 = 0
        let headerSize = MemoryLayout<cmsghdr>.size
        let dataSize = MemoryLayout<Int32>.size
        let alignment = MemoryLayout<size_t>.size
        var control = [UInt8](repeating: 0, count: ((headerSize + dataSize + alignment - 1) / alignment) * alignment)
        let received: Int = withUnsafeMutablePointer(to: &marker) { markerPointer in
            var vector = iovec(iov_base: UnsafeMutableRawPointer(markerPointer), iov_len: 1)
            return withUnsafeMutablePointer(to: &vector) { vectorPointer in
                control.withUnsafeMutableBytes { bytes in
                    var message = msghdr(msg_name: nil, msg_namelen: 0, msg_iov: vectorPointer, msg_iovlen: 1,
                                         msg_control: bytes.baseAddress, msg_controllen: socklen_t(bytes.count), msg_flags: 0)
                    return recvmsg(fd, &message, 0)
                }
            }
        }
        if received > 0 { noteActivity() }
        guard received == 1, marker == 0x46 else { throw FrameSocketFailure.protocolError("frame server did not pass shared memory") }
        return control.withUnsafeBytes { bytes in
            bytes.baseAddress!.advanced(by: headerSize).assumingMemoryBound(to: Int32.self).pointee
        }
    }

    public func close() {
        writeLock.lock(); defer { writeLock.unlock() }
        markDead()
        releaseFD()
    }

    /// Marks the socket dead and wakes anything parked on it **without**
    /// releasing the descriptor.
    ///
    /// Only the thread that owns the fd — the one that accepted or connected it
    /// — may close it. A publisher asked to stop while it is still inside
    /// `writeAll` would otherwise pull the descriptor out from under its own
    /// blocked syscall, and a recycled fd number handed to the next `open` is
    /// far worse than a descriptor that lives until its owner releases it.
    public func abort() {
        markDead()
        stateLock.lock(); let released = fdReleased; stateLock.unlock()
        guard !released else { return }
        shutdown(fd, SHUT_RDWR)
    }

    /// True once either side has declared the connection over.
    public var isDead: Bool {
        stateLock.lock(); defer { stateLock.unlock() }; return closed
    }

    private func markDead() {
        stateLock.lock(); closed = true; stateLock.unlock()
    }

    private func releaseFD() {
        stateLock.lock()
        guard !fdReleased else { stateLock.unlock(); return }
        fdReleased = true
        stateLock.unlock()
        Darwin.close(fd)
    }
}

/// Client-side connect, with the same deadlines the server side gets.
public enum FrameSocketClient {
    public static func connect(path: String, policy: FrameIdlePolicy = .init()) throws -> FrameSocket {
        guard RuntimePaths.socketPathFits(path) else {
            throw AgentSpaceError(code: .internalError, message: "frame socket path is too long")
        }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw AgentSpaceError(code: .workerOffline, message: "could not create frame socket") }
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 104) { chars in
                for (index, byte) in bytes.enumerated() { chars[index] = CChar(bitPattern: byte) }
                chars[bytes.count] = 0
            }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(descriptor)
            throw AgentSpaceError(code: .workerOffline, message: "could not connect to frame socket: \(message)")
        }
        return FrameSocket(fd: descriptor, policy: policy)
    }
}
