import Foundation

public struct DirtyRect: Equatable, Hashable, Codable, Sendable {
    public var x: UInt32
    public var y: UInt32
    public var width: UInt32
    public var height: UInt32

    public init(x: UInt32, y: UInt32, width: UInt32, height: UInt32) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public var area: UInt64 { UInt64(width) * UInt64(height) }
    public var maxX: UInt64 { UInt64(x) + UInt64(width) }
    public var maxY: UInt64 { UInt64(y) + UInt64(height) }

    public func clipped(width frameWidth: UInt32, height frameHeight: UInt32) -> DirtyRect? {
        let right = min(maxX, UInt64(frameWidth)), bottom = min(maxY, UInt64(frameHeight))
        guard UInt64(x) < right, UInt64(y) < bottom else { return nil }
        return .init(x: x, y: y, width: UInt32(right - UInt64(x)), height: UInt32(bottom - UInt64(y)))
    }

    func touches(_ other: DirtyRect, distance: UInt32) -> Bool {
        let d = UInt64(distance)
        return UInt64(x) <= other.maxX + d && UInt64(other.x) <= maxX + d &&
            UInt64(y) <= other.maxY + d && UInt64(other.y) <= maxY + d
    }

    func union(_ other: DirtyRect) -> DirtyRect {
        let left = min(x, other.x), top = min(y, other.y)
        let right = max(maxX, other.maxX), bottom = max(maxY, other.maxY)
        return .init(x: left, y: top, width: UInt32(right - UInt64(left)), height: UInt32(bottom - UInt64(top)))
    }
}

public enum AccumulatedDamage: Equatable, Sendable {
    case none
    case regions([DirtyRect])
    case fullFrame(width: UInt32, height: UInt32)
}

public struct DirtyRegionPolicy: Equatable, Sendable {
    public var maximumRects: Int
    public var fullFrameThreshold: Double
    public var mergeDistance: UInt32

    public init(maximumRects: Int = 64, fullFrameThreshold: Double = 0.5, mergeDistance: UInt32 = 2) {
        self.maximumRects = maximumRects
        self.fullFrameThreshold = fullFrameThreshold
        self.mergeDistance = mergeDistance
    }
}

/// Accumulates damage while both shared-memory slots are awaiting ACK. It never
/// stores historical frames; the next publish copies these regions from the
/// newest surface.
public final class DirtyRegionAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let policy: DirtyRegionPolicy
    private var damage: AccumulatedDamage = .none

    public init(policy: DirtyRegionPolicy = .init()) { self.policy = policy }

    public func merge(_ incoming: [DirtyRect], frameWidth: UInt32, frameHeight: UInt32) {
        guard !incoming.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        if case .fullFrame = damage { return }
        var regions: [DirtyRect]
        if case .regions(let current) = damage { regions = current } else { regions = [] }
        regions.append(contentsOf: incoming.compactMap { $0.clipped(width: frameWidth, height: frameHeight) })
        var merged: [DirtyRect] = []
        for var rect in regions {
            var index = 0
            while index < merged.count {
                if rect.touches(merged[index], distance: policy.mergeDistance) {
                    rect = rect.union(merged.remove(at: index)); index = 0
                } else { index += 1 }
            }
            merged.append(rect)
        }
        let fullArea = UInt64(frameWidth) * UInt64(frameHeight)
        let area = merged.reduce(UInt64(0)) { $0 + $1.area }
        if merged.count > policy.maximumRects || (fullArea > 0 && Double(area) / Double(fullArea) >= policy.fullFrameThreshold) {
            damage = .fullFrame(width: frameWidth, height: frameHeight)
        } else {
            damage = .regions(merged)
        }
    }

    public func requireFullFrame(width: UInt32, height: UInt32) {
        lock.lock(); damage = .fullFrame(width: width, height: height); lock.unlock()
    }

    public func take() -> AccumulatedDamage {
        lock.lock(); defer { lock.unlock() }
        let result = damage; damage = .none; return result
    }

    /// Pixels waiting to be sent. Read without emptying, so a report can say how
    /// much damage has piled up behind a viewer that is not acknowledging.
    public func pendingArea() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        switch damage {
        case .none: return 0
        case .regions(let regions): return regions.reduce(0) { $0 + $1.area }
        case .fullFrame(let width, let height): return UInt64(width) * UInt64(height)
        }
    }
}
