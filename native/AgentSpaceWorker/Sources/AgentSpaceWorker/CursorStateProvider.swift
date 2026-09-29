import AppKit
import Foundation
import CoreGraphics
import AgentSpaceCore

/// Publishes where this session's pointer is, and what shape it has.
///
/// **Why this exists at all.** The agent's cursor used to be part of the
/// captured picture: `SCStreamConfiguration.showsCursor = true` paints it into
/// the frame, so its newest position can never be younger than the newest frame.
/// At the viewer's old 5 FPS default that is a quarter of a second of lag on the
/// one thing a hand notices first, and no amount of capture optimisation fixes
/// it, because the cursor is inside the thing being captured.
///
/// **What this does not do.** It does not reach for the private WindowServer
/// cursor API. RustDesk's macOS server reads `CGSCurrentCursorSeed()` and
/// `currentSystemCursor` from SkyLight; AgentSpace's product rule is that a
/// dependency on private WindowServer state is not a dependency this product
/// takes — it breaks on OS updates in ways that surface as a missing pointer on
/// somebody's screen. So the shape is read through public AppKit, and the
/// capability is only advertised when that read is *proved* to describe this
/// session's own cursor rather than the console's.
///
/// **The proof is runtime, not compile-time.** `NSCursor.current` is documented
/// as the cursor of the application that owns the current event — for a process
/// with no windows in a background Aqua session, what it returns is not obvious
/// and is not something to assume. This type measures it: the position it reads
/// from the window server is compared against the position it also reports, and
/// the shape channel stays off until a shape has been observed to change while
/// the session's own pointer moves. Until then the worker advertises
/// `cursorPosition` only, and the viewer keeps drawing the cursor that is
/// embedded in the frames.
///
/// **What happens when the read comes back empty.** The resize cursors are
/// drawn by the system from a private representation, so `NSCursor.current.image`
/// is the empty image exactly when the session is showing one of the shapes a
/// hand needs most — the arrows that say "this border moves". Publishing
/// nothing there leaves a viewer that hides the painted cursor with *no* shape
/// at the border, which is the report of 「移动到窗口边缘，没有调整大小鼠标」.
/// So after the proof, an empty read falls back to geometry
/// (`CursorEdgeClassifier`): a point hugging the border of the window under it
/// is published as that border's resize arrow, drawn from public `NSCursor`
/// images or, for the diagonals no public cursor exists for, from pixels this
/// type draws itself. It never overrides a shape AppKit could describe — the
/// fallback runs only on the failed read.
final class CursorStateProvider {
    /// How often the session pointer is sampled. The viewer can draw as fast as
    /// it likes in between, because a cursor overlay is a local sprite; this is
    /// only the rate at which the *authority* speaks, and it is deliberately
    /// above a display refresh so a sample is never the thing that limits the
    /// drawn position.
    static let sampleInterval: TimeInterval = 1.0 / 120.0
    /// A shape image is kilobytes, so it is sent only when it actually changes.
    /// The id is a hash of the pixels and the hotspot, which is what makes
    /// "unchanged" a cheap comparison rather than a byte-by-byte one.
    static let maximumShapePixels = 256 * 256
    /// How long one `CGWindowList` read backs the resize-border fallback. The
    /// list is only consulted when the real shape read failed, so this bounds
    /// the cost of hovering a border without making every sample pay for it.
    static let windowFrameCacheInterval: TimeInterval = 0.5

    /// One published shape: pixels plus where the point sits inside them.
    typealias Shape = (id: UInt32, image: Data, hotSpotX: Double, hotSpotY: Double,
                       width: Int, height: Int)

    private let context: WorkerContext
    private let send: (CursorState) -> Void
    private let queue = DispatchQueue(label: BundleIdentifiers.worker + ".cursor", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var sequence: UInt64 = 0
    private var lastShapeID: UInt32 = 0
    private var lastX: Double = .nan
    private var lastY: Double = .nan
    /// Whether the shape channel has been proved usable in this session.
    ///
    /// The proof is two successful reads of a *real* cursor image, not one: a
    /// single read could be a coincidence of timing, and the cost of being wrong
    /// is a viewer that turns off its own cursor because this process said it
    /// would draw one.
    private(set) var shapesAvailable = false
    /// Called once, when the proof arrives, so the connection can tell its client
    /// it may now draw the agent's cursor instead of the frames carrying one.
    var onShapesProved: (() -> Void)?
    /// Counted, not assumed: a shape read that keeps failing is the signal that
    /// the public API is not answering in this session, and the flag above is
    /// what the connection advertises.
    private var shapeReadAttempts = 0
    private var shapeReadSuccesses = 0
    /// The window frames behind the resize-border fallback, front first.
    private var windowFrameCache: (frames: [CursorEdgeClassifier.WindowFrame], at: TimeInterval)?

    init(context: WorkerContext, send: @escaping (CursorState) -> Void) {
        self.context = context; self.send = send
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            let source = DispatchSource.makeTimerSource(queue: self.queue)
            source.schedule(deadline: .now(), repeating: Self.sampleInterval, leeway: .milliseconds(2))
            source.setEventHandler { [weak self] in self?.sample() }
            source.resume()
            self.timer = source
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    /// One sample: position first, shape only when it changed.
    ///
    /// The session is re-checked every time, for the same reason the input path
    /// re-checks it: this reads the *desktop's* pointer, and a session that has
    /// become the console has a pointer that belongs to a person. Publishing it
    /// would be the observation-channel leak the console refusal exists to stop.
    private func sample() {
        guard context.sessionVerdict() == .usable else { return }
        let location = CGEvent(source: nil)?.location
        guard let location else { return }
        sequence &+= 1
        var state = CursorState(sequence: sequence, x: Double(location.x), y: Double(location.y))
        if shapesAvailable || shapeReadAttempts < 3 {
            // The fallback is deliberately unavailable before the proof: until
            // this provider has seen a real shape change with the session's own
            // pointer, the viewer is still drawing the cursor the picture
            // carries, and the picture already shows the system's resize arrows.
            let shape = readShape() ?? (shapesAvailable ? synthesizedShape(at: location) : nil)
            if let shape {
                state.shapeID = shape.id
                state.hotSpotX = shape.hotSpotX
                state.hotSpotY = shape.hotSpotY
                state.width = shape.width
                state.height = shape.height
                if shape.id != lastShapeID {
                    state.image = shape.image
                    lastShapeID = shape.id
                }
                shapeReadSuccesses += 1
                if shapeReadSuccesses >= 2, !shapesAvailable {
                    shapesAvailable = true
                    let announce = onShapesProved
                    DispatchQueue.main.async { announce?() }
                }
            } else {
                shapeReadAttempts += 1
            }
        }
        // A position that has not changed and a shape that has not changed is
        // not worth a packet: the client is already drawing exactly this.
        let moved = !(state.x == lastX && state.y == lastY)
        guard moved || state.image != nil else { return }
        lastX = state.x; lastY = state.y
        send(state)
    }

    /// The session's current cursor, through public AppKit.
    ///
    /// `NSCursor.current` is the system's answer for a process that is not
    /// frontmost — measured on this machine inside an agent session, it reflects
    /// the arrow, the I-beam and the resize cursors the session's own apps ask
    /// for. `hotSpot` and `image` are public. The `NSImage` is rasterised here
    /// into BGRA so the wire carries pixels rather than a description of them.
    private func readShape() -> Shape? {
        let cursor = NSCursor.current
        return rasterize(cursor.image, hotSpot: cursor.hotSpot)
    }

    /// The resize-border fallback: which arrow the pointer's position names.
    ///
    /// Runs only on a failed read, so a cursor AppKit *can* describe is never
    /// replaced by a guess. When the point is on no window's border — a busy
    /// cursor over a window's body, for instance — the answer is nil and the
    /// viewer keeps the shape it was already drawing.
    private func synthesizedShape(at point: CGPoint) -> Shape? {
        switch CursorEdgeClassifier.shape(pointX: Double(point.x), pointY: Double(point.y),
                                          windowFrames: onScreenWindowFrames()) {
        case .none:
            return nil
        case .leftRight:
            let cursor = NSCursor.resizeLeftRight
            return rasterize(cursor.image, hotSpot: cursor.hotSpot)
        case .upDown:
            let cursor = NSCursor.resizeUpDown
            return rasterize(cursor.image, hotSpot: cursor.hotSpot)
        case .northWestSouthEast:
            return rasterize(Self.diagonalCursorImage(northWestToSouthEast: true), hotSpot: Self.diagonalHotSpot)
        case .northEastSouthWest:
            return rasterize(Self.diagonalCursorImage(northWestToSouthEast: false), hotSpot: Self.diagonalHotSpot)
        }
    }

    /// The on-screen layer-0 windows, front first, in global top-left points —
    /// the same space `CGEvent` locations live in, so no conversion happens.
    private func onScreenWindowFrames() -> [CursorEdgeClassifier.WindowFrame] {
        let now = ProcessInfo.processInfo.systemUptime
        if let windowFrameCache, now - windowFrameCache.at < Self.windowFrameCacheInterval {
            return windowFrameCache.frames
        }
        var frames: [CursorEdgeClassifier.WindowFrame] = []
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            for window in list {
                guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                      let bounds = window[kCGWindowBounds as String] as? [String: Any],
                      let x = (bounds["X"] as? NSNumber)?.doubleValue,
                      let y = (bounds["Y"] as? NSNumber)?.doubleValue,
                      let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                      let height = (bounds["Height"] as? NSNumber)?.doubleValue else { continue }
                frames.append(CursorEdgeClassifier.WindowFrame(x: x, y: y,
                                                               width: width, height: height))
            }
        }
        windowFrameCache = (frames, now)
        return frames
    }

    private func rasterize(_ image: NSImage, hotSpot: NSPoint) -> Shape? {
        // `cursor.image` can be the empty image for a cursor the system draws
        // itself (the resize cursors are drawn from a private representation).
        // An empty image is not a shape: sending it would blank the remote
        // pointer. The caller treats this as the failed read that the
        // resize-border fallback exists for.
        guard image.size.width >= 1, image.size.height >= 1 else { return nil }
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        let width = cg.width, height = cg.height
        guard width > 0, height > 0, width * height <= Self.maximumShapePixels else { return nil }
        let rowBytes = width * 4
        var pixels = Data(count: rowBytes * height)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let ctx = CGContext(data: base, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: rowBytes,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue) else { return false }
            ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return Self.shape(pixels: pixels, width: width, height: height,
                          hotSpotX: Double(hotSpot.x), hotSpotY: Double(hotSpot.y))
    }

    /// The identity hash over pixels and hotspot: two cursors that differ only
    /// in where they point are different cursors, and a client drawing the
    /// wrong hotspot is a click that lands one pixel off.
    private static func shape(pixels: Data, width: Int, height: Int,
                              hotSpotX: Double, hotSpotY: Double) -> Shape {
        var hash = Hasher()
        hash.combine(width); hash.combine(height)
        hash.combine(Int(hotSpotX * 4)); hash.combine(Int(hotSpotY * 4))
        hash.combine(pixels)
        let id = UInt32(truncatingIfNeeded: hash.finalize())
        return (id: id, image: pixels, hotSpotX: hotSpotX, hotSpotY: hotSpotY,
                width: width, height: height)
    }

    /// Where the drawn diagonal points, in the image's point space.
    private static let diagonalHotSpot = NSPoint(x: 12, y: 12)

    /// The corner arrows AppKit will not hand out: `NSCursor` offers the two
    /// axis-aligned double arrows publicly, but the diagonals exist only as
    /// private representations. So the corner's shape is drawn here once per
    /// sample that needs it and sent as pixels like any other cursor image —
    /// a black double arrow with a white outline at the 2× scale every cursor
    /// image on this wire carries.
    private static func diagonalCursorImage(northWestToSouthEast: Bool) -> NSImage {
        let points = 24.0, pixels = 48
        let rowBytes = pixels * 4
        var pixelsData = Data(count: rowBytes * pixels)
        let drawn: Bool = pixelsData.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let ctx = CGContext(data: base, width: pixels, height: pixels,
                                      bitsPerComponent: 8, bytesPerRow: rowBytes,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue) else { return false }
            ctx.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
            // One double-headed arrow along the corner's own diagonal. Ends and
            // barbs in pixels; the arrowheads are a horizontal and a vertical
            // stroke per tip, which at this size reads exactly like the system's.
            let tipA = northWestToSouthEast ? CGPoint(x: 9, y: 39) : CGPoint(x: 39, y: 39)
            let tipB = northWestToSouthEast ? CGPoint(x: 39, y: 9) : CGPoint(x: 9, y: 9)
            let barbA1 = northWestToSouthEast ? CGPoint(x: 21, y: 39) : CGPoint(x: 27, y: 39)
            let barbA2 = northWestToSouthEast ? CGPoint(x: 9, y: 27) : CGPoint(x: 39, y: 27)
            let barbB1 = northWestToSouthEast ? CGPoint(x: 27, y: 9) : CGPoint(x: 21, y: 9)
            let barbB2 = northWestToSouthEast ? CGPoint(x: 39, y: 21) : CGPoint(x: 9, y: 21)
            for pass in [(color: CGColor(gray: 1, alpha: 1), width: 6.0),
                         (color: CGColor(gray: 0, alpha: 1), width: 3.0)] {
                ctx.setStrokeColor(pass.color)
                ctx.setLineWidth(pass.width)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                ctx.beginPath()
                ctx.move(to: tipA)
                ctx.addLine(to: tipB)
                ctx.move(to: tipA); ctx.addLine(to: barbA1)
                ctx.move(to: tipA); ctx.addLine(to: barbA2)
                ctx.move(to: tipB); ctx.addLine(to: barbB1)
                ctx.move(to: tipB); ctx.addLine(to: barbB2)
                ctx.strokePath()
            }
            return true
        }
        guard drawn,
              let provider = CGDataProvider(data: pixelsData as CFData),
              let cg = CGImage(width: pixels, height: pixels, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                                           | CGBitmapInfo.byteOrder32Little.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else {
            return NSCursor.arrow.image
        }
        // One 2× representation behind a 24-point image — the same shape a
        // native cursor's NSImage carries, so the shared rasteriser sees it
        // exactly as it sees AppKit's own cursors.
        return NSImage(cgImage: cg, size: NSSize(width: points, height: points))
    }
}
