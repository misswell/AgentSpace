import Foundation

/// Only target identity and coordinates differ between the two viewer hosts.
public enum ViewerInputSurface: Equatable, Sendable {
    case desktop(DisplayGeometry)
    case window(WindowIdentity, CGRectValue)

    public var target: InputTarget {
        switch self {
        case .desktop: return .desktop
        case .window(let identity, _): return .window(identity)
        }
    }

    public func point(u: Double, v: Double) -> (x: Double, y: Double) {
        switch self {
        case .desktop(let geometry):
            return PreviewMapping.displayPoint(u: u, v: v,
                displayWidth: geometry.width, displayHeight: geometry.height)
        case .window: return (u, v)
        }
    }

    public func cursorPoint(x: Double, y: Double) -> (x: Double, y: Double) {
        switch self {
        case .desktop: return (x, y)
        case .window(_, let frame): return (x - frame.x, y - frame.y)
        }
    }
}
