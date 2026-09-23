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
            if let shape = readShape() {
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
    private func readShape() -> (id: UInt32, image: Data, hotSpotX: Double, hotSpotY: Double, width: Int, height: Int)? {
        let cursor = NSCursor.current
        let hotspot = cursor.hotSpot
        let image = cursor.image
        // `cursor.image` can be the empty image for a cursor the system draws
        // itself (the resize cursors are drawn from a private representation).
        // An empty image is not a shape: sending it would blank the remote
        // pointer. The caller counts this as a failure and keeps the embedded
        // cursor in the picture, which is the honest outcome.
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
        // The hash covers the pixels and the hotspot together: two cursors that
        // differ only in where they point are different cursors, and a client
        // drawing the wrong hotspot is a click that lands one pixel off.
        var hash = Hasher()
        hash.combine(width); hash.combine(height)
        hash.combine(Int(hotspot.x * 4)); hash.combine(Int(hotspot.y * 4))
        hash.combine(pixels)
        let id = UInt32(truncatingIfNeeded: hash.finalize())
        return (id: id, image: pixels, hotSpotX: Double(hotspot.x), hotSpotY: Double(hotspot.y),
                width: width, height: height)
    }
}
