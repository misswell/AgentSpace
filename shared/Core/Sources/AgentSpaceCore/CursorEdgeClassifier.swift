import Foundation

/// Which resize shape a pointer position against a window's border should show.
public enum CursorEdgeShape: Equatable, Sendable {
    /// Not on any window's resize border: keep whatever shape is already drawn.
    case none
    case leftRight
    case upDown
    case northWestSouthEast
    case northEastSouthWest
}

/// Classifies a pointer position against window frames as a resize cursor.
///
/// **Why this exists.** The worker publishes the session cursor's shape through
/// public AppKit (`CursorStateProvider`), but the resize cursors are drawn by
/// the system from a private representation: `NSCursor.current.image` comes
/// back empty for exactly the shapes a person needs most — the arrows that say
/// "this border moves". Once the viewer hides the cursor that the captured
/// picture paints (the trailing-ghost fix), an unpublished shape is *no* shape,
/// which is the report of 「移动到窗口边缘，没有调整大小鼠标」.
///
/// This classifier is the honest fallback: when the shape read fails, ask
/// where the pointer is. A point hugging the border of the window under it is
/// what macOS shows a resize arrow for, and which border (or pair of borders,
/// for a corner) names the arrow. It runs only when the real read failed, so
/// every cursor AppKit *can* describe still comes from the app that set it —
/// this never overrides a published shape.
///
/// Coordinates are one global space: `CGEvent` locations and `kCGWindowBounds`
/// frames are both top-left-origin global points, so no conversion happens
/// here. Frames are front-to-back; the shape is decided by the first window
/// that contains the point, which is the one the pointer is on.
public enum CursorEdgeClassifier {
    /// How close to a single border counts as "on the resize border". macOS
    /// installs its own resize zones of roughly this width.
    public static let edgeMargin: Double = 5
    /// How close to two borders at once counts as the corner, which wins over
    /// either single border because a corner is the more specific answer.
    public static let cornerMargin: Double = 10

    /// A window's frame in the same global top-left space as the point.
    public struct WindowFrame: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
    }

    /// The shape for `pointX, pointY` against `windowFrames` (front first).
    public static func shape(pointX: Double, pointY: Double,
                             windowFrames: [WindowFrame],
                             edgeMargin: Double = CursorEdgeClassifier.edgeMargin,
                             cornerMargin: Double = CursorEdgeClassifier.cornerMargin) -> CursorEdgeShape {
        guard let frame = windowFrames.first(where: { window in
            window.width > 0 && window.height > 0
                && pointX >= window.x && pointX < window.x + window.width
                && pointY >= window.y && pointY < window.y + window.height
        }) else { return .none }
        let fromLeft = pointX - frame.x
        let fromRight = frame.x + frame.width - pointX
        let fromTop = pointY - frame.y
        let fromBottom = frame.y + frame.height - pointY
        let onLeft = fromLeft <= cornerMargin
        let onRight = fromRight <= cornerMargin
        let onTop = fromTop <= cornerMargin
        let onBottom = fromBottom <= cornerMargin
        // A corner is two borders within the wider margin; the diagonal follows
        // the axis the corner sits on, which is what the system's own arrows do.
        if onLeft && onTop || onRight && onBottom { return .northWestSouthEast }
        if onRight && onTop || onLeft && onBottom { return .northEastSouthWest }
        let nearLeft = fromLeft <= edgeMargin
        let nearRight = fromRight <= edgeMargin
        let nearTop = fromTop <= edgeMargin
        let nearBottom = fromBottom <= edgeMargin
        if nearLeft || nearRight { return .leftRight }
        if nearTop || nearBottom { return .upDown }
        return .none
    }
}
