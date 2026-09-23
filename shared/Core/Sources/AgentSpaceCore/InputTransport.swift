import Darwin
import Foundation

/// One framed packet, as the socket hands it upward.
public struct InputPacket {
    public var header: InputPacketHeader
    public var payload: Data

    public var kind: InputPacketKind { header.kind }

    public var description: String { "\(header.kind) seq \(header.sequence) (\(payload.count) bytes)" }
}

/// The byte transport both ends of the input channel use.
///
/// Shaped like `FrameSocket` and for the same reasons — a write deadline so a
/// client that has stopped reading cannot park the worker, and an idle policy so
/// a peer that has died is detectable — but with a different framing: fixed
/// records with a payload length in the header, no descriptor passing, and a
/// read side that is *not* deadline-bound while a connection is established.
/// Silence on this channel is normal; a person's hand can be still for minutes.
///
/// The one place a deadline is right is the handshake: a connection that opens
/// and never says hello is a connection holding a slot on the worker's
/// user-interactive queue, and that slot is worth more than the stranger.
public final class InputSocketTransport {
    /// How long a single write may take before the peer counts as gone. An input
    /// packet is at most a few kilobytes, so a second is two orders of magnitude
    /// above the local cost and far below a person's patience.
    public static let sendTimeout: TimeInterval = 1

    public let fd: Int32
    private let writeLock = NSLock()
    private let stateLock = NSLock()
    private var closed = false

    public init(fd: Int32, sendTimeout: TimeInterval = InputSocketTransport.sendTimeout) throws {
        self.fd = fd
        var value = timeval(tv_sec: Int(sendTimeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    deinit { close() }

    // MARK: - Writing

    /// Frame and send one packet.
    public func send(kind: InputPacketKind, payload: Data, sequence: UInt64) throws {
        let header = InputPacketHeader(kind: kind, sequence: sequence, timestampNanoseconds: InputClock.now())
        try writeAll(header.encoded(payloadSize: payload.count) + payload)
    }

    private func writeAll(_ data: Data) throws {
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
                    markDead()
                    throw FrameSocketFailure.sendTimeout
                }
                markDead()
                throw FrameSocketFailure.disconnected
            }
        }
    }

    // MARK: - Reading

    /// One framed packet, waiting as long as the peer needs. Throws on EOF or a
    /// framing error, which is what ends a connection.
    public func readPacket() throws -> InputPacket {
        let headerData = try readExactly(InputPacketHeader.byteCount)
        let header = try InputPacketHeader(decoding: headerData)
        let payload = header.payloadSize > 0 ? try readExactly(Int(header.payloadSize)) : Data()
        return InputPacket(header: header, payload: payload)
    }

    /// One packet, waiting no longer than the deadline.
    ///
    /// Exists because "the worker has nothing to say" is the *normal* state of a
    /// connection whose client's hand is still: a reader that blocked until a
    /// packet arrived could not tell a working channel from a dead one without a
    /// second source of information. Returns nil when the deadline passes first.
    public func readPacketWithTimeout(remainingUntil deadline: Date) throws -> InputPacket? {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { return nil }
        var value = timeval(tv_sec: Int(remaining), tv_usec: Int32((remaining - Double(Int(remaining))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
        defer {
            var none = timeval(tv_sec: 0, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &none, socklen_t(MemoryLayout<timeval>.size))
        }
        do {
            return try readPacket()
        } catch FrameSocketFailure.stale {
            return nil
        }
    }

    /// The handshake, with a deadline of its own: reads with a receive timeout
    /// until the first hello arrives or `timeout` passes.
    public func readHello(timeout: TimeInterval) throws -> InputHello? {
        var value = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
        defer {
            var none = timeval(tv_sec: 0, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &none, socklen_t(MemoryLayout<timeval>.size))
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let headerData: Data
            do {
                headerData = try readExactly(InputPacketHeader.byteCount)
            } catch FrameSocketFailure.stale {
                return nil
            }
            let header = try InputPacketHeader(decoding: headerData)
            let payload = header.payloadSize > 0 ? try readExactly(Int(header.payloadSize)) : Data()
            guard header.kind == .hello else {
                throw AgentSpaceError(code: .badRequest, message: "the first packet on the input channel must be hello, got \(header.kind)")
            }
            return try InputHello(decoding: payload)
        }
        return nil
    }

    private func readExactly(_ count: Int) throws -> Data {
        var data = Data(capacity: count)
        var scratch = [UInt8](repeating: 0, count: min(64 * 1024, max(1, count)))
        while data.count < count {
            let received = scratch.withUnsafeMutableBytes { pointer in
                Darwin.read(fd, pointer.baseAddress, min(pointer.count, count - data.count))
            }
            if received > 0 { data.append(contentsOf: scratch[0..<received]); continue }
            if received == 0 { throw FrameSocketFailure.disconnected }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK || errno == ETIMEDOUT {
                // Only reachable during the handshake, where the receive timeout
                // is armed: anything else is a truncated packet, which is a
                // connection that cannot be resynchronised.
                throw FrameSocketFailure.stale
            }
            throw FrameSocketFailure.disconnected
        }
        return data
    }

    // MARK: - Lifecycle

    public func close() {
        stateLock.lock()
        let already = closed
        closed = true
        stateLock.unlock()
        guard !already else { return }
        shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
    }

    /// Wakes a blocked read without releasing the descriptor, for a reader on
    /// another thread that must not close what it does not own.
    public func abort() {
        markDead()
        shutdown(fd, SHUT_RDWR)
    }

    public var isDead: Bool { stateLock.lock(); defer { stateLock.unlock() }; return closed }

    private func markDead() {
        stateLock.lock(); closed = true; stateLock.unlock()
    }
}

extension InputSocketTransport {
    /// Connect to a worker's input socket.
    public static func connect(path: String) throws -> InputSocketTransport {
        guard RuntimePaths.socketPathFits(path) else {
            throw AgentSpaceError(code: .internalError, message: "input socket path is too long")
        }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw AgentSpaceError(code: .workerOffline, message: "could not create the input socket")
        }
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
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(descriptor)
            throw AgentSpaceError(code: .workerOffline, message: "could not connect to the input socket: \(message)")
        }
        return try InputSocketTransport(fd: descriptor)
    }
}

/// How often a packet is worth an acknowledgement.
///
/// A move is state, and a reply per move is the request/reply shape this whole
/// channel exists to remove. But "no replies at all" would leave a client unable
/// to tell a working channel from a dead one, and would leave a refusal — the
/// console switched, Accessibility was revoked — invisible until the next press.
///
/// **Refusals are sampled too, and that is not an optimisation.** Measured on a
/// console session: a client sending 500 moves got one refusal per move, and the
/// worker filled the socket buffer until its own write blocked and the
/// connection died on a send timeout. The client learns nothing from the 400th
/// copy of the same sentence, so the first refusal of a run is always answered
/// and the rest are throttled — a transition is reported, a flood is not.
public struct InputAckPolicy {
    /// Every Nth ordinary packet is acknowledged even when nothing is wrong.
    public var travelSampleInterval: UInt64 = 16
    /// Refusals of the same kind are repeated at most this often. The first one
    /// is never suppressed: that is the one that tells the client something
    /// changed.
    public var refusalSampleInterval: UInt64 = 32

    public init(travelSampleInterval: UInt64 = 16, refusalSampleInterval: UInt64 = 32) {
        self.travelSampleInterval = travelSampleInterval
        self.refusalSampleInterval = refusalSampleInterval
    }

    /// Whether this packet needs an answer now, and what the answer will say.
    ///
    /// `acknowledged` is the highest sequence already answered by this
    /// connection; it is advanced here so a client can always reason about
    /// "what has the worker seen" rather than about a count. `refusal` is the
    /// status the worker is about to report, or nil when the packet was applied.
    ///
    /// **A refusal that is new is always sent; a refusal that repeats is
    /// sampled.** That distinction is the whole policy: the client has to learn
    /// the first time the session refuses it — the console switched, the grant
    /// was revoked — and learns nothing from the four hundredth copy of the same
    /// sentence, which is what the flood measurement found.
    public func shouldAcknowledge(kind: InputPacketKind, after acknowledged: inout UInt64,
                                  sequence: UInt64, refusal: InputAckStatus?,
                                  previousRefusal: InputAckStatus?) -> Bool {
        if let refusal {
            if refusal != previousRefusal {
                // A transition: the client is about to need to know.
                acknowledged = sequence
                return true
            }
            guard sequence &- acknowledged >= refusalSampleInterval else { return false }
            acknowledged = sequence
            return true
        }
        switch kind {
        case .pointerMove:
            // Sampled: the newest position wins anyway, and a stale ack about a
            // position the pointer has already left is worth less than the bytes.
            guard sequence &- acknowledged >= travelSampleInterval else { return false }
            acknowledged = sequence
            return true
        case .pointerDown, .pointerDrag, .pointerUp, .scroll, .key, .type,
             .humanAcquire, .humanRelease:
            // Every one of these has a consequence a person is about to look at,
            // so each is confirmed.
            acknowledged = sequence
            return true
        default:
            return false
        }
    }
}
