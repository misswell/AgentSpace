import Foundation

/// Display geometry in the two coordinate spaces AgentSpace has to keep
/// straight, plus the conversion between them.
///
/// The contract (plan §15): **an agent always speaks in points.** Screenshots
/// come back in pixels on a Retina display, and a model that reads a pixel
/// coordinate out of an image and posts it as a point misses every target by a
/// factor of `scale`. So the scale is carried explicitly in every screenshot
/// reply and the conversion lives here, once, tested.
public struct DisplayGeometry: Codable, Equatable, Sendable {
    /// Width in points — the space input coordinates live in.
    public var width: Int
    /// Height in points.
    public var height: Int
    /// Width in pixels — what a screenshot of this display measures.
    public var pixelWidth: Int
    /// Height in pixels.
    public var pixelHeight: Int
    /// Backing scale factor: `pixelWidth / width`. 1 or 2 in practice.
    public var scale: Int

    public init(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, scale: Int) {
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.scale = scale
    }

    /// Derive from a CoreGraphics display mode.
    ///
    /// Measured on macOS 27.0: `CGDisplayPixelsWide()` returns the **point**
    /// width of a Retina display (1920 here), while
    /// `CGDisplayCopyDisplayMode().pixelWidth` returns the real backing-store
    /// width (3840). Deriving the scale from `CGDisplayPixelsWide()` therefore
    /// yields 1 and silently halves every coordinate. Only `pixelWidth` is
    /// usable, and the probe asserts this at runtime.
    public init(modeWidth: Int, modePixelWidth: Int, boundsWidth: Int, boundsHeight: Int) {
        let w = boundsWidth
        let h = boundsHeight
        let s: Int
        if modeWidth > 0, modePixelWidth > 0 {
            s = max(1, Int((Double(modePixelWidth) / Double(modeWidth)).rounded()))
        } else {
            s = 1
        }
        self.init(
            width: w,
            height: h,
            pixelWidth: w * s,
            pixelHeight: h * s,
            scale: s)
    }

    /// Convert a screenshot pixel coordinate to the point an input API wants.
    public func point(fromPixel pixel: Int) -> Int {
        guard scale > 0 else { return pixel }
        return Int((Double(pixel) / Double(scale)).rounded())
    }

    /// Convert a point to the pixel it lands on in a screenshot.
    public func pixel(fromPoint point: Int) -> Int { point * scale }

    /// Is this point inside the display? Used to reject `INVALID_COORDINATE`
    /// before any event is constructed.
    public func contains(point: (x: Double, y: Double)) -> Bool {
        guard point.x.isFinite, point.y.isFinite else { return false }
        return point.x >= 0 && point.y >= 0
            && point.x < Double(width) && point.y < Double(height)
    }
}

/// Coordinate validation shared by the worker and the CLI, so a bad coordinate
/// is rejected at the edge *and* at the trust boundary (plan §56: never trust
/// the client).
public enum CoordinateRules {
    /// Coordinates outside this bound are a mistake, not a very large monitor.
    /// Chosen well above any real multi-display arrangement so it never rejects
    /// a legitimate point, and low enough to catch a pixel/point mix-up or a
    /// garbage value from a model.
    public static let maxCoordinate: Double = 100_000

    public static func validate(x: Double, y: Double, geometry: DisplayGeometry?) -> AgentSpaceError? {
        guard x.isFinite, y.isFinite else {
            return AgentSpaceError(
                code: .invalidCoordinate,
                message: "coordinate is not a finite number (x=\(x), y=\(y))")
        }
        guard abs(x) <= maxCoordinate, abs(y) <= maxCoordinate else {
            return AgentSpaceError(
                code: .invalidCoordinate,
                message: "coordinate (\(x), \(y)) is outside the plausible range ±\(Int(maxCoordinate))")
        }
        guard x >= 0, y >= 0 else {
            return AgentSpaceError(
                code: .invalidCoordinate,
                message: "coordinate (\(x), \(y)) is negative; AgentSpace coordinates start at the top-left of the main display")
        }
        if let geometry, !geometry.contains(point: (x, y)) {
            return AgentSpaceError(
                code: .invalidCoordinate,
                message: "coordinate (\(x), \(y)) is off the main display (\(geometry.width)x\(geometry.height) points). Screenshot pixels must be divided by scale=\(geometry.scale) first.")
        }
        return nil
    }
}
