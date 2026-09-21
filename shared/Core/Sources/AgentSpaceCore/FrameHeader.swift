import Foundation

public enum FrameCodec: UInt8, Codable, Sendable {
    case jpeg = 1
    case h264 = 2
    case sharedBGRA = 3
}

/// The header's one reserved byte. A heartbeat is a header with an empty
/// payload rather than a new codec: a peer that predates it reads a zero-length
/// frame and stays compatible, while a peer that understands it can tell "the
/// desktop is still" apart from "the worker is gone" — which is exactly the
/// distinction a static capture cannot make by itself.
public struct FrameHeaderFlags: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let heartbeat = FrameHeaderFlags(rawValue: 1 << 0)
}

/// Fixed-width framing for the binary capture channel. Integer fields are
/// network byte order so a future non-Swift client can decode them verbatim.
public struct FrameHeader: Equatable, Sendable {
    public static let magic: UInt32 = 0x41534652 // ASFR
    public static let version: UInt16 = 1
    public static let byteCount = 52

    public var streamID: UUID
    public var sequence: UInt64
    public var timestampNanoseconds: UInt64
    public var codec: FrameCodec
    public var flags: FrameHeaderFlags
    public var width: UInt32
    public var height: UInt32
    public var payloadSize: UInt32

    public var isHeartbeat: Bool { flags.contains(.heartbeat) }

    public init(
        streamID: UUID,
        sequence: UInt64,
        timestampNanoseconds: UInt64,
        codec: FrameCodec,
        width: UInt32,
        height: UInt32,
        payloadSize: UInt32,
        flags: FrameHeaderFlags = []
    ) {
        self.streamID = streamID
        self.sequence = sequence
        self.timestampNanoseconds = timestampNanoseconds
        self.codec = codec
        self.flags = flags
        self.width = width
        self.height = height
        self.payloadSize = payloadSize
    }

    /// A liveness signal for a stream that has produced no pixels recently. It
    /// advances no sequence: consumers validate frames by sequence, and a
    /// heartbeat that consumed one would look like a gap.
    public static func heartbeat(streamID: UUID, timestampNanoseconds: UInt64) -> FrameHeader {
        FrameHeader(streamID: streamID, sequence: 0, timestampNanoseconds: timestampNanoseconds,
                    codec: .sharedBGRA, width: 0, height: 0, payloadSize: 0, flags: .heartbeat)
    }

    public func encoded() -> Data {
        var data = Data()
        data.appendInteger(Self.magic)
        data.appendInteger(Self.version)
        data.append(codec.rawValue)
        data.append(flags.rawValue)
        withUnsafeBytes(of: streamID.uuid) { data.append(contentsOf: $0) }
        data.appendInteger(sequence)
        data.appendInteger(timestampNanoseconds)
        data.appendInteger(width)
        data.appendInteger(height)
        data.appendInteger(payloadSize)
        return data
    }

    public init(decoding data: Data) throws {
        guard data.count == Self.byteCount else {
            throw AgentSpaceError(code: .badRequest, message: "frame header must be exactly \(Self.byteCount) bytes")
        }
        var reader = FrameHeaderReader(data)
        guard try reader.integer(UInt32.self) == Self.magic else {
            throw AgentSpaceError(code: .badRequest, message: "invalid frame header magic")
        }
        guard try reader.integer(UInt16.self) == Self.version else {
            throw AgentSpaceError(code: .protocolMismatch, message: "unsupported frame header version")
        }
        guard let codec = FrameCodec(rawValue: try reader.byte()) else {
            throw AgentSpaceError(code: .badRequest, message: "unknown frame codec")
        }
        let flagsByte = try reader.byte()
        let uuidBytes = try reader.bytes(count: 16)
        let tuple: uuid_t = (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15])
        self.init(
            streamID: UUID(uuid: tuple),
            sequence: try reader.integer(UInt64.self),
            timestampNanoseconds: try reader.integer(UInt64.self),
            codec: codec,
            width: try reader.integer(UInt32.self),
            height: try reader.integer(UInt32.self),
            payloadSize: try reader.integer(UInt32.self),
            flags: FrameHeaderFlags(rawValue: flagsByte))
    }
}

private extension Data {
    mutating func appendInteger<T: FixedWidthInteger>(_ value: T) {
        var big = value.bigEndian
        Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) }
    }
}

private struct FrameHeaderReader {
    let data: Data
    var offset = 0

    init(_ data: Data) { self.data = data }

    mutating func byte() throws -> UInt8 {
        guard offset < data.count else { throw truncated() }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func bytes(count: Int) throws -> [UInt8] {
        guard offset + count <= data.count else { throw truncated() }
        defer { offset += count }
        return Array(data[offset..<(offset + count)])
    }

    mutating func integer<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let raw = try bytes(count: MemoryLayout<T>.size)
        return raw.reduce(T.zero) { ($0 << 8) | T($1) }
    }

    private func truncated() -> AgentSpaceError {
        AgentSpaceError(code: .badRequest, message: "truncated frame header")
    }
}
