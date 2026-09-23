/// What size a capture buffer has to be, given the subject and the box it was
/// asked to fit in.
///
/// A viewer can only name the box: it knows its own window, and it does not know
/// the shape of the desktop or remote window being captured. ScreenCaptureKit then
/// scales a picture *into* the buffer it is handed without distorting it, so a box
/// shaped unlike its subject comes back with the picture floating between black
/// pillars — and the only size either end of a stream is told about is the buffer's.
/// A viewer that reads the whole buffer as its subject therefore translates a click
/// at the picture's left edge to a point *inside* the desktop: measured on a 1920×1080
/// desktop in a 1512×641 point window, 236 points of the screen away from what it was
/// aimed at, growing linearly from zero at the centre.
///
/// So the request is a budget and the subject's aspect is the constraint, and the
/// two are reconciled here rather than inside a capture call because the choice is
/// pure geometry — and because both ends of a stream have to agree that a buffer
/// holds exactly its subject, which is only true if the buffer is sized that way.
public enum CaptureSizing {
    /// The buffer to build.
    ///
    /// `naturalWidth × naturalHeight` is the subject's own pixel size. The target
    /// is the box the caller wants the picture to fit in, where zero means "not
    /// specified", so a one-dimensional request still means what it says: scale
    /// the subject by that one dimension.
    public static func resolved(naturalWidth: Int, naturalHeight: Int,
                                targetWidth: Int, targetHeight: Int) -> (width: Int, height: Int) {
        let naturalWidth = max(1, naturalWidth)
        let naturalHeight = max(1, naturalHeight)
        if targetWidth > 0, targetHeight > 0 {
            // Fit, not fill: the result never asks the capture for more pixels than
            // the caller's box can hold in either dimension. `rounded` rather than
            // truncation because a box that already has the subject's shape must come
            // back as that box, and 1920 × (1280 ÷ 1920) is 1279.9999 in binary.
            let scale = min(Double(targetWidth) / Double(naturalWidth),
                            Double(targetHeight) / Double(naturalHeight))
            return (max(1, Int((Double(naturalWidth) * scale).rounded())),
                    max(1, Int((Double(naturalHeight) * scale).rounded())))
        }
        if targetWidth > 0 {
            return (targetWidth, max(1, naturalHeight * targetWidth / naturalWidth))
        }
        if targetHeight > 0 {
            return (max(1, naturalWidth * targetHeight / naturalHeight), targetHeight)
        }
        return (naturalWidth, naturalHeight)
    }

    /// A resolved buffer size, and whether a ceiling reduced it.
    public struct Plan: Equatable, Sendable {
        public let width: Int
        public let height: Int
        /// True when `SharedFrameGeometry.maximumPixels` cut the size down. Said
        /// out loud rather than folded into the numbers because a softer picture
        /// and a deliberate one look identical once only the size is reported.
        public let capped: Bool

        public init(width: Int, height: Int, capped: Bool) {
            self.width = width; self.height = height; self.capped = capped
        }

        public var pixels: Int { width * height }
    }

    /// The buffer to build, held to the largest size one stream may hold.
    ///
    /// The subject's own pixel size is the ceiling for quality — an upscale can
    /// be asked for, but nothing above it is detail. The budget is the ceiling
    /// for survival: a mapping the manager would refuse, or one that leaves no
    /// room for a second surface, is not a picture anyone can use. So the fit
    /// happens first (the aspect is the subject's) and the ceiling second, where
    /// it scales both axes by the same factor so the buffer keeps that aspect.
    ///
    /// `maximumPixels` is not reachable by any single display today, which is the
    /// point of measuring rather than guessing: it is a bound the code can prove
    /// instead of a number that felt large.
    public static func planned(naturalWidth: Int, naturalHeight: Int,
                               targetWidth: Int, targetHeight: Int) -> Plan {
        let (width, height) = resolved(naturalWidth: naturalWidth, naturalHeight: naturalHeight,
                                      targetWidth: targetWidth, targetHeight: targetHeight)
        let pixels = width * height
        guard pixels > SharedFrameGeometry.maximumPixels else {
            return Plan(width: width, height: height, capped: false)
        }
        let scale = (Double(SharedFrameGeometry.maximumPixels) / Double(pixels)).squareRoot()
        return Plan(width: max(1, Int((Double(width) * scale).rounded())),
                    height: max(1, Int((Double(height) * scale).rounded())),
                    capped: true)
    }
}
