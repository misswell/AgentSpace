import Foundation

/// One display the Desktop Viewer can capture and address with pointer input.
/// Its origin is in the session's global display-point coordinate space.
public struct ViewerDisplay: Equatable, Sendable {
    public let id: UInt32
    public let originX: Double
    public let originY: Double
    public let geometry: DisplayGeometry

    public init(id: UInt32, originX: Double, originY: Double, geometry: DisplayGeometry) {
        self.id = id
        self.originX = originX
        self.originY = originY
        self.geometry = geometry
    }

    public var isRetina: Bool { geometry.scale >= 2 }

    public func globalPoint(x: Double, y: Double) -> (x: Double, y: Double) {
        (originX + x, originY + y)
    }

    public func localPoint(x: Double, y: Double) -> (x: Double, y: Double) {
        (x - originX, y - originY)
    }

    /// Prefer the sharpest real backing store, then a larger useful canvas.
    /// A missing 2× screen is a missing requirement, not an upscale request.
    public static func preferredRetina(in displays: [ViewerDisplay]) -> ViewerDisplay? {
        displays.filter(\.isRetina).max {
            if $0.geometry.scale != $1.geometry.scale { return $0.geometry.scale < $1.geometry.scale }
            let first = $0.geometry.pixelWidth * $0.geometry.pixelHeight
            let second = $1.geometry.pixelWidth * $1.geometry.pixelHeight
            if first != second { return first < second }
            return $0.id > $1.id
        }
    }
}
