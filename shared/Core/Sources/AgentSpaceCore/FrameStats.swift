import Foundation

public struct FrameStats: Codable, Equatable, Sendable {
    public var framesCaptured: UInt64 = 0
    public var framesPublished: UInt64 = 0
    public var framesDropped: UInt64 = 0
    public var framesMerged: UInt64 = 0
    public var fullFrames: UInt64 = 0
    public var deltaFrames: UInt64 = 0
    public var modeSwitchCount: UInt64 = 0
    public var socketReconnects: UInt64 = 0
    public var sharedBytes: UInt64 = 0
    public var videoBytes: UInt64 = 0
    public var dirtyRatio: Double = 0

    public init() {}
}
