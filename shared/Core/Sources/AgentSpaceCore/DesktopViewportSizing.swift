/// The desktop occupies only the space between the viewer's controls. Match
/// that rectangle to the remote display so the entire desktop fills it without
/// cropping or unused bars.
public enum DesktopViewportSizing {
    public static func contentSize(
        proposedWidth: Double,
        controlsHeight: Double,
        titlebarHeight: Double,
        maximumFrameHeight: Double,
        displayWidth: Double,
        displayHeight: Double
    ) -> (width: Double, height: Double) {
        guard proposedWidth > 0, displayWidth > 0, displayHeight > 0 else {
            return (proposedWidth, controlsHeight)
        }
        let ratio = displayWidth / displayHeight
        let availableViewportHeight = max(1, maximumFrameHeight - titlebarHeight - controlsHeight)
        let width = min(proposedWidth, availableViewportHeight * ratio)
        return (width, controlsHeight + width / ratio)
    }
}
