import CoreGraphics

/// The desktop occupies only the space between the viewer's controls. Match
/// that rectangle to the remote display so the entire desktop fills it without
/// cropping or unused bars.
public enum DesktopViewportSizing {
    /// The content size that shows the whole remote display at its own aspect.
    ///
    /// The result never has a viewport smaller than `minimumViewportWidth` or
    /// `minimumViewportHeight`, and never taller than the screen leaves room
    /// for: the aspect is held by whichever dimension has room to give. It
    /// returns `nil` when no size satisfies all three — a display whose shape
    /// this screen cannot show at the viewer's own minimum — so the caller
    /// leaves the window alone instead of trading two impossible sizes back and
    /// forth (§381).
    public static func contentSize(
        proposedWidth: Double,
        controlsHeight: Double,
        titlebarHeight: Double,
        maximumFrameHeight: Double,
        displayWidth: Double,
        displayHeight: Double,
        minimumViewportWidth: Double = 0,
        minimumViewportHeight: Double = 0,
        maximumWidth: Double = .greatestFiniteMagnitude
    ) -> (width: Double, height: Double)? {
        guard proposedWidth > 0, displayWidth > 0, displayHeight > 0 else {
            return (proposedWidth, controlsHeight)
        }
        let ratio = displayWidth / displayHeight
        let availableViewportHeight = max(1, maximumFrameHeight - titlebarHeight - controlsHeight)
        // Every width the aspect allows is one whose viewport is at least the
        // content's minimum *and* one the screen has room for.
        let widest = min(availableViewportHeight * ratio, maximumWidth)
        let narrowest = max(minimumViewportHeight * ratio, minimumViewportWidth)
        guard narrowest <= widest + 0.5 else { return nil }
        let width = min(max(proposedWidth, narrowest), widest)
        return (width, controlsHeight + width / ratio)
    }

    /// A window frame brought back inside the visible screen area.
    ///
    /// A frame saved in preferences can name a position the window can no
    /// longer be reached from: with the title strip off the screen there is
    /// nothing left to drag. macOS constrains a *drag* for exactly that reason;
    /// a frame restored from preferences has to be constrained here. The size
    /// shrinks only when the saved size no longer fits the screen at all.
    public static func onScreenFrame(_ frame: CGRect, visibleArea: CGRect) -> CGRect {
        guard visibleArea.width > 0, visibleArea.height > 0 else { return frame }
        let width = min(frame.width, visibleArea.width)
        let height = min(frame.height, visibleArea.height)
        let x = min(max(frame.minX, visibleArea.minX), max(visibleArea.minX, visibleArea.maxX - width))
        let y = min(max(frame.minY, visibleArea.minY), max(visibleArea.minY, visibleArea.maxY - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
