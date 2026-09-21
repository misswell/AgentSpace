import Foundation

public struct SharedFrameNotice: Equatable, Sendable {
    public static let byteCount = 32
    public var surfaceGeneration: UInt64
    public var slotIndex: UInt16
    public var frameKind: SharedFrameKind
    public var patchCount: UInt16
    public var baseSequence: UInt64
    /// The writer's *logical* region size — `SharedFrameGeometry.regionSize`, the
    /// number the layout is computed from. This is deliberately not what `fstat`
    /// reports for the same object: Darwin may round a POSIX shm object up, so the
    /// mapping a viewer ends up with can be larger than this and still be the
    /// right one. Comparing the two is what made a healthy stream look corrupt.
    public var mappingSize: UInt32

    public init(surfaceGeneration: UInt64, slotIndex: UInt16, frameKind: SharedFrameKind, patchCount: UInt16, baseSequence: UInt64, mappingSize: UInt32) {
        self.surfaceGeneration = surfaceGeneration; self.slotIndex = slotIndex; self.frameKind = frameKind
        self.patchCount = patchCount; self.baseSequence = baseSequence; self.mappingSize = mappingSize
    }

    public func encoded() -> Data {
        var data = Data()
        func add<T: FixedWidthInteger>(_ value: T) { var big = value.bigEndian; withUnsafeBytes(of: &big) { data.append(contentsOf: $0) } }
        add(surfaceGeneration); add(slotIndex); add(frameKind.rawValue); add(patchCount); add(UInt16(0)); add(baseSequence); add(mappingSize); add(UInt32(0))
        return data
    }

    public init(decoding data: Data) throws {
        guard data.count == Self.byteCount else { throw AgentSpaceError(code: .badRequest, message: "invalid shared frame notice") }
        func integer<T: FixedWidthInteger>(_ offset: Int, _ type: T.Type) -> T { data[offset..<(offset + MemoryLayout<T>.size)].reduce(T.zero) { ($0 << 8) | T($1) } }
        guard let kind = SharedFrameKind(rawValue: integer(10, UInt16.self)) else { throw AgentSpaceError(code: .badRequest, message: "invalid shared frame notice kind") }
        self.init(surfaceGeneration: integer(0, UInt64.self), slotIndex: integer(8, UInt16.self), frameKind: kind, patchCount: integer(12, UInt16.self), baseSequence: integer(16, UInt64.self), mappingSize: integer(24, UInt32.self))
    }
}

public enum FrameSequenceDecision: Equatable, Sendable { case accepted, ignoredDuplicate, requestFullFrame }

public struct FrameSequenceValidator: Sendable {
    public private(set) var generation: UInt64?
    public private(set) var sequence: UInt64 = 0
    public init() {}

    public mutating func accept(generation: UInt64, sequence next: UInt64, baseSequence: UInt64, kind: SharedFrameKind) -> FrameSequenceDecision {
        if next <= sequence, self.generation == generation { return .ignoredDuplicate }
        if kind == .fullBGRA {
            self.generation = generation; sequence = next; return .accepted
        }
        guard self.generation == generation, sequence == baseSequence else { return .requestFullFrame }
        sequence = next; return .accepted
    }

    public mutating func reset() { generation = nil; sequence = 0 }
}
