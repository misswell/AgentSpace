import Foundation

/// Turning a wheel delta counted in **lines** into a movement of a scroll bar,
/// whose value is a fraction of the scrollable range rather than a distance.
///
/// This exists because a scroll bar exposes no per-line increment: measured on
/// a live TextEdit scroll area, an `AXScrollBar` offers only `AXValue`,
/// `AXEnabled`, `AXOrientation` and friends — no `AXValueIncrement`, no knob
/// size. The scroll *area* does report both `AXSize` (the viewport) and
/// `AXContentSize` (the whole document), which is enough to place one line
/// without inventing a pixel count.
public enum ScrollMechanics {
    /// Lines assumed to fit in the viewport when the app does not say. Twenty
    /// is what a default text view shows at the system font size, and the
    /// number only sets the *feel* of one wheel notch — the range is exact.
    public static let linesPerViewport = 20.0

    /// Fraction of the scrollable range one line covers, or `nil` when there is
    /// nothing to scroll: a viewport that already fits the content has no
    /// range, and dividing by it would report an infinite step.
    public static func fractionPerLine(viewport: Double, content: Double) -> Double? {
        let range = content - viewport
        guard viewport > 0, content > 0, range > 0 else { return nil }
        return (viewport / linesPerViewport) / range
    }

    /// Where the bar should end up after `lines`.
    ///
    /// Positive `lines` scrolls toward the top, which is where the fraction
    /// decreases — the same sign the wheel event uses, so the two paths agree.
    public static func value(current: Double, lines: Double,
                             viewport: Double, content: Double) -> Double? {
        guard let perLine = fractionPerLine(viewport: viewport, content: content) else { return nil }
        return min(1, max(0, current - lines * perLine))
    }
}
