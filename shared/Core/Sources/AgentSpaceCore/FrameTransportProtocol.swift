import Foundation

public struct FrameClientCommand: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case acknowledge, requestFull, close }
    public var kind: Kind
    public var slotIndex: Int?
    public var sequence: UInt64?

    public init(kind: Kind, slotIndex: Int? = nil, sequence: UInt64? = nil) {
        self.kind = kind; self.slotIndex = slotIndex; self.sequence = sequence
    }
}

public enum FrameTransportCoding {
    public static func line<T: Encodable>(_ value: T) throws -> Data {
        var data = try JSONEncoder().encode(value); data.append(0x0a); return data
    }
}
