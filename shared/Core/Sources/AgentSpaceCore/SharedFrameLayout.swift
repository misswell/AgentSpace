import Foundation

public enum SharedFrameKind: UInt16, Codable, Sendable { case fullBGRA = 1, deltaBGRA = 2 }

public struct SharedFrameSlotHeader: Equatable, Sendable {
    public static let magic: UInt32 = 0x41535348 // ASSH
    public static let version: UInt16 = 1
    public static let byteCount = 64

    public var surfaceGeneration: UInt64
    public var sequence: UInt64
    public var baseSequence: UInt64
    public var timestampNanoseconds: UInt64
    public var width: UInt32
    public var height: UInt32
    public var frameKind: SharedFrameKind
    public var patchCount: UInt16
    public var payloadSize: UInt32

    public init(surfaceGeneration: UInt64, sequence: UInt64, baseSequence: UInt64, timestampNanoseconds: UInt64, width: UInt32, height: UInt32, frameKind: SharedFrameKind, patchCount: UInt16, payloadSize: UInt32) {
        self.surfaceGeneration = surfaceGeneration; self.sequence = sequence; self.baseSequence = baseSequence
        self.timestampNanoseconds = timestampNanoseconds; self.width = width; self.height = height
        self.frameKind = frameKind; self.patchCount = patchCount; self.payloadSize = payloadSize
    }

    public func encoded() -> Data {
        var data = Data(); data.appendBE(Self.magic); data.appendBE(Self.version); data.appendBE(frameKind.rawValue)
        data.appendBE(surfaceGeneration); data.appendBE(sequence); data.appendBE(baseSequence); data.appendBE(timestampNanoseconds)
        data.appendBE(width); data.appendBE(height); data.appendBE(patchCount); data.appendBE(UInt16(0)); data.appendBE(payloadSize)
        data.append(Data(repeating: 0, count: Self.byteCount - data.count)); return data
    }

    public init(decoding data: Data) throws {
        guard data.count == Self.byteCount else { throw AgentSpaceError(code: .badRequest, message: "invalid shared frame slot header size") }
        var reader = SharedFrameReader(data)
        guard try reader.integer(UInt32.self) == Self.magic else { throw AgentSpaceError(code: .badRequest, message: "invalid shared frame magic") }
        guard try reader.integer(UInt16.self) == Self.version else { throw AgentSpaceError(code: .protocolMismatch, message: "unsupported shared frame version") }
        guard let kind = SharedFrameKind(rawValue: try reader.integer(UInt16.self)) else { throw AgentSpaceError(code: .badRequest, message: "invalid shared frame kind") }
        self.init(surfaceGeneration: try reader.integer(UInt64.self), sequence: try reader.integer(UInt64.self), baseSequence: try reader.integer(UInt64.self), timestampNanoseconds: try reader.integer(UInt64.self), width: try reader.integer(UInt32.self), height: try reader.integer(UInt32.self), frameKind: kind, patchCount: try reader.integer(UInt16.self), payloadSize: { _ = try? reader.integer(UInt16.self); return (try? reader.integer(UInt32.self)) ?? 0 }())
    }
}

public struct SharedPatchDescriptor: Equatable, Sendable {
    public static let byteCount = 32
    public var x, y, width, height, bytesPerRow, payloadOffset, payloadLength: UInt32

    public init(x: UInt32, y: UInt32, width: UInt32, height: UInt32, bytesPerRow: UInt32, payloadOffset: UInt32, payloadLength: UInt32) {
        self.x = x; self.y = y; self.width = width; self.height = height; self.bytesPerRow = bytesPerRow
        self.payloadOffset = payloadOffset; self.payloadLength = payloadLength
    }

    public func encoded() -> Data {
        var data = Data(); [x, y, width, height, bytesPerRow, payloadOffset, payloadLength, 0].forEach { data.appendBE($0) }; return data
    }

    public init(decoding data: Data) throws {
        guard data.count == Self.byteCount else { throw AgentSpaceError(code: .badRequest, message: "invalid patch descriptor size") }
        var reader = SharedFrameReader(data)
        self.init(x: try reader.integer(UInt32.self), y: try reader.integer(UInt32.self), width: try reader.integer(UInt32.self), height: try reader.integer(UInt32.self), bytesPerRow: try reader.integer(UInt32.self), payloadOffset: try reader.integer(UInt32.self), payloadLength: try reader.integer(UInt32.self))
    }
}

public enum SharedFrameLayout {
    public static let slotCount = 2
    public static let maximumPatchCount = 64
    public static let descriptorAreaSize = maximumPatchCount * SharedPatchDescriptor.byteCount
    public static let slotMetadataSize = SharedFrameSlotHeader.byteCount + descriptorAreaSize

    public static func slotSize(payloadCapacity: Int) -> Int { slotMetadataSize + payloadCapacity }
    public static func regionSize(payloadCapacity: Int) -> Int { slotCount * slotSize(payloadCapacity: payloadCapacity) }
    public static func slotOffset(_ slot: Int, payloadCapacity: Int) -> Int { slot * slotSize(payloadCapacity: payloadCapacity) }

    /// The inverse of `regionSize(payloadCapacity:)`.
    ///
    /// This is how a viewer recovers the layout of a region it did not allocate:
    /// the size it can read off the descriptor is the number the writer asked for
    /// *rounded up* by the kernel, so deriving a layout from it puts slot 1 at an
    /// offset the writer never wrote. The writer's own number travels in every
    /// notice, and this is what turns it back into a capacity.
    public static func payloadCapacity(forRegionSize size: Int) -> Int? {
        guard size % slotCount == 0 else { return nil }
        let capacity = (size / slotCount) - slotMetadataSize
        return capacity >= 0 ? capacity : nil
    }

    public static func validate(header: SharedFrameSlotHeader, patches: [SharedPatchDescriptor], regionSize: Int) throws {
        guard patches.count == Int(header.patchCount), patches.count <= maximumPatchCount else { throw AgentSpaceError(code: .badRequest, message: "shared frame patch count mismatch") }
        for patch in patches {
            guard patch.width > 0, patch.height > 0,
                  UInt64(patch.x) + UInt64(patch.width) <= UInt64(header.width),
                  UInt64(patch.y) + UInt64(patch.height) <= UInt64(header.height),
                  UInt64(patch.bytesPerRow) >= UInt64(patch.width) * 4,
                  UInt64(patch.payloadOffset) + UInt64(patch.payloadLength) <= UInt64(regionSize),
                  UInt64(patch.payloadLength) >= UInt64(patch.bytesPerRow) * UInt64(patch.height)
            else { throw AgentSpaceError(code: .badRequest, message: "shared frame patch is outside its surface or mapping") }
        }
    }
}

private extension Data {
    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        var big = value.bigEndian; Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) }
    }
}

private struct SharedFrameReader {
    let data: Data; var offset = 0
    init(_ data: Data) { self.data = data }
    mutating func integer<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let size = MemoryLayout<T>.size
        guard offset + size <= data.count else { throw AgentSpaceError(code: .badRequest, message: "truncated shared frame metadata") }
        defer { offset += size }
        return data[offset..<(offset + size)].reduce(T.zero) { ($0 << 8) | T($1) }
    }
}
