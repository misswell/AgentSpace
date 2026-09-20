import CoreGraphics
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

/// Maps a click inside the Desktop Viewer's preview image back to a display
/// point that the input API can act on.
///
/// This is the arithmetic behind plan §17: the user clicks on a picture of the
/// agent's desktop in the main app, and that click has to arrive as a real click
/// in the *other* session. Three coordinate spaces are in play:
///
/// ```
///   view point      where the user clicked, in SwiftUI points inside the view
///        ↓          fit the image, discard the letterbox
///   image fraction  how far across the captured picture the click was, 0…1
///        ↓          × the captured display's size IN POINTS
///   display point   what `agentspace click` accepts
/// ```
///
/// The fraction is the key step, and it is why this type stores the *display's
/// point* size rather than its pixel size.
///
/// A preview is normally downscaled (`--max-width`), so the image's own pixel
/// dimensions are not the framebuffer's and definitely not the display's points:
/// a 640x360 preview of a 1920x1080-point display has three different widths for
/// the same picture. Dividing the image's pixels by the backing scale — the
/// obvious-looking move — gives 320 instead of 960, a click that lands a third
/// of the way across the screen with no error to explain it.
///
/// The image always covers the whole captured display, so the click's fraction
/// across the image is the click's fraction across the display, and that
/// fraction times the display's point width is the point. The backing scale
/// never enters the calculation, and is deliberately not a parameter here.
public struct PreviewMapping: Equatable, Sendable {
    public struct Rect: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
        public func contains(x px: Double, y py: Double) -> Bool {
            px >= x && py >= y && px < x + width && py < y + height
        }
    }

    /// The preview image's size in pixels, as reported by the worker.
    public let imageWidth: Int
    public let imageHeight: Int
    /// The captured display's size in **points** — the space input lives in.
    public let displayWidth: Int
    public let displayHeight: Int
    /// The size of the view the image is drawn in, in SwiftUI points.
    public let viewWidth: Double
    public let viewHeight: Double

    public init(imageWidth: Int, imageHeight: Int,
                displayWidth: Int, displayHeight: Int,
                viewWidth: Double, viewHeight: Double) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.viewWidth = viewWidth
        self.viewHeight = viewHeight
    }

    /// Build from a screenshot result and the geometry the worker reported.
    ///
    /// Prefer this to the memberwise initialiser: it takes the display's point
    /// size from `DisplayGeometry`, which is the value the worker validated the
    /// coordinates against, so the preview and the input API cannot disagree
    /// about how big the display is.
    public static func fitting(
        imageWidth: Int,
        imageHeight: Int,
        geometry: DisplayGeometry,
        viewWidth: Double,
        viewHeight: Double
    ) -> PreviewMapping {
        PreviewMapping(
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            displayWidth: geometry.width,
            displayHeight: geometry.height,
            viewWidth: viewWidth,
            viewHeight: viewHeight)
    }

    /// The rectangle the image actually occupies once fitted into the view.
    /// `nil` when either the image or the view has no size, which happens for one
    /// frame before the first capture arrives.
    public var fittedRect: Rect? {
        guard imageWidth > 0, imageHeight > 0, viewWidth > 0, viewHeight > 0 else { return nil }
        let imageAspect = Double(imageWidth) / Double(imageHeight)
        let viewAspect = viewWidth / viewHeight
        let width: Double
        let height: Double
        if imageAspect > viewAspect {
            // Relatively wider than the view: spans it, bars top and bottom.
            width = viewWidth
            height = viewWidth / imageAspect
        } else {
            height = viewHeight
            width = viewHeight * imageAspect
        }
        return Rect(x: (viewWidth - width) / 2, y: (viewHeight - height) / 2,
                    width: width, height: height)
    }

    /// Where a click in the view lands on the display, in points.
    ///
    /// Returns `nil` for a click in the letterbox rather than clamping to the
    /// nearest edge. A click on the black bar has no meaning, and silently
    /// turning it into a click at the very edge would move the agent's pointer
    /// somewhere the user did not ask for.
    public func displayPoint(viewX: Double, viewY: Double) -> (x: Double, y: Double)? {
        guard let rect = fittedRect, rect.contains(x: viewX, y: viewY) else { return nil }
        let u = (viewX - rect.x) / rect.width
        let v = (viewY - rect.y) / rect.height
        // `floor`, not `round`: a click in the last pixel of the image is a click
        // on the last point of the display, and rounding would produce
        // `displayWidth`, which is off the screen by one and would come back as
        // INVALID_COORDINATE.
        let x = (u * Double(displayWidth)).rounded(.down)
        let y = (v * Double(displayHeight)).rounded(.down)
        return (x: min(x, Double(max(0, displayWidth - 1))),
                y: min(y, Double(max(0, displayHeight - 1))))
    }

    /// Where a point reported by an AppKit `NSView` lands on the display.
    ///
    /// AppKit view coordinates have their origin at the lower-left, while the
    /// SwiftUI preview (and the input protocol) use a top-left origin.  The
    /// conversion belongs here rather than in each event callback so a
    /// transparent `NSViewRepresentable` cannot silently invert vertical
    /// clicks when it is embedded in SwiftUI's flipped host view.
    public func displayPoint(appKitX: Double, appKitY: Double) -> (x: Double, y: Double)? {
        let topLeftY = viewHeight - appKitY
        // An AppKit event at the lower edge reports y == 0.  The equivalent
        // top-left coordinate is the last point inside the image, not the
        // half-open view boundary at y == viewHeight.
        let insideTopLeftY = topLeftY == viewHeight ? viewHeight.nextDown : topLeftY
        return displayPoint(viewX: appKitX, viewY: insideTopLeftY)
    }

    /// The inverse, for drawing an indicator at the agent's last known pointer
    /// position. Returns `nil` if the point is off the display.
    public func viewPoint(displayX: Double, displayY: Double) -> (x: Double, y: Double)? {
        guard let rect = fittedRect, displayWidth > 0, displayHeight > 0 else { return nil }
        let u = displayX / Double(displayWidth)
        let v = displayY / Double(displayHeight)
        guard u >= 0, u <= 1, v >= 0, v <= 1 else { return nil }
        return (x: rect.x + u * rect.width, y: rect.y + v * rect.height)
    }
}

/// Which display a window is really on, and how many pixels that display uses
/// per point.
///
/// A capture buffer sized in points is only correct on a 1x panel: on the Retina
/// display next to it the same request halves the resolution of everything small
/// enough to matter. With more than one display attached that choice has to be
/// made per window, which makes it a pure geometry decision — and therefore
/// testable without a WindowServer.
public enum DisplayScaleSelection {
    /// One attached display: where it sits in the global top-left space the
    /// window list uses, and its pixel-to-point ratio.
    public struct Candidate: Equatable, Sendable {
        public var bounds: CGRect
        public var pixelsPerPoint: Int

        public init(bounds: CGRect, pixelWidth: Int, pointWidth: Int) {
            self.bounds = bounds
            // A zero or negative point width is not a display; treat it as 1x
            // rather than dividing by it.
            self.pixelsPerPoint = max(1, pixelWidth / max(1, pointWidth))
        }
    }

    /// Area of the rectangle two displays and the window share. Disjoint
    /// rectangles intersect in a null rect, whose negative extents are clamped.
    public static func overlap(of frame: CGRect, on bounds: CGRect) -> CGFloat {
        let shared = frame.intersection(bounds)
        return max(0, shared.width) * max(0, shared.height)
    }

    /// The display holding the largest part of the window, or `nil` when the
    /// window touches none of them.
    ///
    /// The scan is explicit and the comparison is `>` on purpose: `max(by:)`
    /// wants an *increasing* comparator, and reading it as "bigger comes first"
    /// silently returns the smallest overlap — which is how a window that is
    /// 80% on a Retina panel came to be encoded at the 1x panel's scale.
    public static func candidate(for frame: CGRect, in candidates: [Candidate]) -> Candidate? {
        var best: Candidate?
        var bestOverlap: CGFloat = 0
        for candidate in candidates {
            let overlap = self.overlap(of: frame, on: candidate.bounds)
            if overlap > bestOverlap {
                best = candidate
                bestOverlap = overlap
            }
        }
        return best
    }

    /// Pixels per point for a window: the display it mostly occupies, and
    /// `fallback` when it occupies none of the candidates.
    public static func pixelsPerPoint(
        windowFrame: CGRect, in candidates: [Candidate], fallback: Int = 1
    ) -> Int {
        guard let best = candidate(for: windowFrame, in: candidates) else {
            return max(1, fallback)
        }
        return best.pixelsPerPoint
    }
}
