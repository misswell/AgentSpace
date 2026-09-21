import CoreGraphics
import Foundation
import AgentSpaceCore

/// The live displays of this Aqua session, in the shape Core's
/// `DisplayScaleSelection` decides with.
///
/// The pixel size comes from `CGDisplayCopyDisplayMode().pixelWidth` and the
/// point size from `mode.width`, because `CGDisplayPixelsWide()` returns points
/// on a scaled Retina panel — measured on macOS 27.0, where it answered 1920 for
/// a 3840-pixel display. Deriving a scale from it yields 1 and silently halves
/// every capture, so it is not used here (see `Geometry.DisplayGeometry`).
enum DisplayScales {
    static func candidates() -> [DisplayScaleSelection.Candidate] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return displays.filter { CGDisplayIsActive($0) != 0 }.compactMap(candidate)
    }

    static func candidate(_ display: CGDirectDisplayID) -> DisplayScaleSelection.Candidate? {
        guard let mode = CGDisplayCopyDisplayMode(display) else { return nil }
        return DisplayScaleSelection.Candidate(
            bounds: CGDisplayBounds(display), pixelWidth: mode.pixelWidth, pointWidth: mode.width)
    }

    static func pixelsPerPoint(of display: CGDirectDisplayID) -> Int {
        guard let mode = CGDisplayCopyDisplayMode(display) else { return 1 }
        return max(1, mode.pixelWidth / max(1, mode.width))
    }

    /// Pixels per point for a window: the display holding most of it decides,
    /// and a window touching no active display keeps the main display's scale
    /// rather than assuming Retina.
    static func pixelsPerPoint(for frame: CGRect) -> Int {
        DisplayScaleSelection.pixelsPerPoint(
            windowFrame: frame, in: candidates(), fallback: pixelsPerPoint(of: CGMainDisplayID()))
    }
}
