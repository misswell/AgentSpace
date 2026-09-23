import AppKit
import AgentSpaceCore

/// Draws the agent's own pointer over the captured picture.
///
/// This exists because a cursor that lives *inside* the video stream can never
/// be newer than the newest frame: ScreenCaptureKit paints it into the pixels, so
/// at the viewer's old 5 FPS default a hand's own pointer arrived up to 200 ms
/// after the hand moved. Drawing one sprite locally, from a position the worker
/// publishes over the input channel, decouples the two completely — the picture
/// can stay at 30 FPS while the cursor moves at the display's own rate, and
/// during the moment before the worker's answer arrives the overlay is already
/// where the hand is, because the viewer knows the position it just sent.
///
/// What it is *not* is a second source of truth: the position comes from the
/// worker whenever the worker disagrees with the prediction, and the shape image
/// comes from the worker's own read of its session cursor. The overlay is a
/// renderer, not an authority.
final class RemoteCursorOverlayLayer: CALayer {
    /// How far the drawn position may drift from the worker's before it is
    /// corrected. Below this the difference is rounding and event coalescing,
    /// and snapping on it would look like a twitch.
    static let correctionThreshold: Double = 2

    /// The last position the worker confirmed, in display points.
    private var authoritative: CGPoint?
    /// The position this client last sent, which is what the hand actually did.
    private var predicted: CGPoint?
    private var sprite: CGImage?
    private var shapeID: UInt32 = 0
    private var hotSpot = CGPoint.zero
    private var spriteSize = CGSize.zero
    /// Maps display points to this layer's coordinate space, refreshed by the
    /// owning view on layout.
    var mapping: PreviewMapping? { didSet { markNeedsLayout() } }

    override init() {
        super.init()
        isHidden = true
        contentsScale = 2
        // A cursor is a photo, not a shape: no interpolation, or a 32-pixel
        // pointer drawn into a scaled layer turns to mush.
        magnificationFilter = .nearest
        minificationFilter = .nearest
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The worker's answer. Corrects the drawn position only when it disagrees
    /// with the prediction by more than rounding — the optimistic position is
    /// what makes the pointer feel attached to the hand, so it is given up only
    /// when it is known to be wrong.
    func apply(_ presentation: InputClient.CursorPresentation) {
        let authoritativePoint = CGPoint(x: presentation.x, y: presentation.y)
        self.authoritative = authoritativePoint
        if let predicted, hypot(predicted.x - authoritativePoint.x, predicted.y - authoritativePoint.y) <= Self.correctionThreshold {
            // Close enough: keep the prediction. It is at worst one event ahead.
        } else {
            self.predicted = authoritativePoint
        }
        if presentation.shapeID != shapeID || sprite == nil {
            shapeID = presentation.shapeID
            hotSpot = CGPoint(x: presentation.hotSpotX, y: presentation.hotSpotY)
            spriteSize = presentation.size
            if let data = presentation.image {
                sprite = Self.image(from: data, width: Int(presentation.size.width), height: Int(presentation.size.height))
            }
        }
        markNeedsLayout()
    }

    /// Where the hand is, as this client last sent it. Drawn immediately: the
    /// whole point of the overlay is that it does not wait for a round trip.
    func predict(displayPoint: CGPoint) {
        predicted = displayPoint
        markNeedsLayout()
    }

    func clear() {
        predicted = nil
        authoritative = nil
        sprite = nil
        shapeID = 0
        isHidden = true
    }

    /// Position the sprite. Called on layout and on every update; setting a
    /// layer's `frame` is cheap and the alternative — a display link — would
    /// spend a callback per frame to draw the same position twice.
    override func layoutSublayers() {
        super.layoutSublayers()
        guard let mapping, let point = predicted ?? authoritative, let sprite else {
            isHidden = true
            return
        }
        guard let viewPoint = mapping.viewPoint(displayX: Double(point.x), displayY: Double(point.y)) else {
            // The pointer is off the captured display: hide rather than clamp to
            // an edge, which would show a cursor somewhere it is not.
            isHidden = true
            return
        }
        let scale = contentsScale > 0 ? contentsScale : 1
        let width = max(1, spriteSize.width / scale)
        let height = max(1, spriteSize.height / scale)
        // `viewPoint` is top-left origin; this layer's coordinate space follows
        // its host view, so the y axis is flipped once, here.
        let originY = (mapping.viewHeight - viewPoint.y) - (height - hotSpot.y / scale)
        let originX = viewPoint.x - hotSpot.x / scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = CGRect(x: originX, y: originY, width: width, height: height)
        contents = sprite
        CATransaction.commit()
        isHidden = false
    }

    /// Re-run `layoutSublayers` on the next run loop pass. `CALayer.needsLayout`
    /// is a method, not a property, and a cursor one event behind the hand is the
    /// exact defect this overlay exists to remove.
    private func markNeedsLayout() { needsLayout() }

    private static func image(from data: Data, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, data.count >= width * height * 4 else { return nil }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                                | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
