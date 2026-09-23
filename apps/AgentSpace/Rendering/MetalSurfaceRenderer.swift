import AppKit
import CoreImage
import Metal
import CoreVideo
import QuartzCore
import AgentSpaceCore

/// Persistent BGRA texture renderer. Full and delta updates both write into the
/// same texture; only the patch rectangles cross from shared memory to Metal.
final class MetalSurfaceRenderer {
    let layer: CAMetalLayer
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let context: CIContext
    private var texture: MTLTexture?
    private var textureCache: CVMetalTextureCache?
    private var width = 0, height = 0
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    /// Presents in flight. Two, because that is one being drawn and one waiting;
    /// a third means the GPU is slower than the stream and the extra work is
    /// latency that will never be paid back.
    private let budget = InFlightBudget(capacity: 2)

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device; self.queue = queue; self.context = CIContext(mtlDevice: device)
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        layer = CAMetalLayer(); layer.device = device; layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false; layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        // Two drawables, and presents not tied to a transaction.
        //
        // The count is a latency decision rather than a tuning knob: a layer with
        // three or more in flight lets the compositor hold frames it has already
        // been handed, which is invisible at 5 FPS and is exactly the extra frame
        // of lag a person notices at 60. Two is the minimum that still lets this
        // renderer build the next frame while the compositor takes the last one.
        layer.maximumDrawableCount = 2
        // `presentsWithTransaction` exists for synchronising a layer with a
        // transaction the caller is already inside; nothing here is, and leaving
        // it on makes every present wait for a transaction commit that never
        // comes — the classic "why is my Metal view one frame behind" answer.
        layer.presentsWithTransaction = false
        layer.backgroundColor = NSColor.black.cgColor
    }

    /// A decoded H.264 frame. `true` means Metal owns the picture now; the frame
    /// may still not have been put on screen if the GPU was busy, which is the
    /// right trade — the decoder has already advanced, so the next frame is built
    /// from this one either way.
    func applyVideo(_ pixelBuffer: CVPixelBuffer) -> Bool {
        guard let textureCache else { return false }
        var wrapped: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .bgra8Unorm, CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer), 0, &wrapped) == kCVReturnSuccess,
              let wrapped, let metal = CVMetalTextureGetTexture(wrapped) else { return false }
        width = metal.width; height = metal.height
        _ = present(metal)
        return true
    }

    func clear() {
        texture = nil; width = 0; height = 0
        budget.reset()
        layer.backgroundColor = NSColor.black.cgColor
        layer.setNeedsDisplay()
    }

    func resize(_ size: CGSize, scale: CGFloat) {
        layer.contentsScale = scale
        layer.frame = CGRect(origin: .zero, size: size)
        layer.drawableSize = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
    }

    /// Puts one shared-memory frame into the texture and, when the GPU has room,
    /// on screen. The answer is what the worker gets told about the slot;
    /// `presented` fires later, on Metal's queue, with the moment the display
    /// actually took the pixels — which is the only honest end-to-end stamp.
    func apply(mapping: SharedFrameMapping, slot: SharedFrameSlotHeader, patches: [SharedPatchDescriptor],
               presented: @escaping (TimeInterval) -> Void = { _ in }) -> SurfaceApplyOutcome {
        if texture == nil || width != Int(slot.width) || height != Int(slot.height) || slot.frameKind == .fullBGRA {
            if texture == nil || width != Int(slot.width) || height != Int(slot.height) {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(slot.width), height: Int(slot.height), mipmapped: false)
                descriptor.usage = [.shaderRead, .renderTarget]
                guard let newTexture = device.makeTexture(descriptor: descriptor) else { return .refused }
                texture = newTexture; width = Int(slot.width); height = Int(slot.height)
            }
        }
        guard let texture else { return .refused }
        let upload = FrameSignpost.begin("MetalUpload")
        defer { FrameSignpost.end(upload) }
        for patch in patches {
            let offset = Int(patch.payloadOffset), length = Int(patch.payloadLength)
            guard offset >= 0, length >= 0, offset + length <= mapping.mappedCapacity else { return .refused }
            texture.replace(region: MTLRegionMake2D(Int(patch.x), Int(patch.y), Int(patch.width), Int(patch.height)), mipmapLevel: 0, withBytes: mapping.pointer.advanced(by: offset), bytesPerRow: Int(patch.bytesPerRow))
        }
        // Returning from that loop is the point at which the slot stopped being
        // read, so the acknowledge below is safe. See `SurfaceApplyOutcome`.
        //
        // A frame that found no room is not a frame that failed: the texture
        // holds these pixels, and the next draw shows something newer than what
        // was dropped. So the slot goes back without a baseline request.
        return present(texture, presented: presented) ? .uploaded : .uploadedWithoutPresent
    }

    /// Draws, commits and returns. The old code waited for completion here, which
    /// turned a slow GPU into a blocked frame thread — the backlog then lived in
    /// the caller instead of in the two frames this budget allows. The permit is
    /// released by Metal's own completion callback, so the bound is real rather
    /// than advisory, and that same callback is when the pixels were on screen.
    @discardableResult
    private func present(_ texture: MTLTexture, presented: @escaping (TimeInterval) -> Void = { _ in }) -> Bool {
        guard budget.begin() else { return false }
        let interval = FrameSignpost.begin("MetalPresent")
        guard let drawable = layer.nextDrawable(), let command = queue.makeCommandBuffer(), var image = CIImage(mtlTexture: texture, options: [.colorSpace: colorSpace]) else {
            budget.end(); FrameSignpost.end(interval); return false
        }
        let destination = CGRect(origin: .zero, size: layer.drawableSize)
        // `CIImage(mtlTexture:)` reads row 0 of a texture as its *bottom* row, while
        // every writer here — the capture, the shared region, the CPU fallback —
        // puts row 0 at the *top*, because that is what a screen is. Unflipped, the
        // desktop draws with its menu bar along the bottom of the window, and the
        // two render paths disagree with each other, since
        // `CALayer.contents = CGImage` needs no such flip.
        //
        // Written as a matrix rather than composed with `translatedBy`, because
        // `translatedBy` prepends: `scale(1,-1).translatedBy(0,h)` is
        // `y -> -(y+h)`, which moves the picture below the drawable and shows
        // nothing at all. `d: -1, ty: h` is the flip that was meant — `y -> h-y`.
        image = image.transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(height)))
        let scale = min(destination.width / CGFloat(width), destination.height / CGFloat(height))
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = (destination.width - image.extent.width) / 2, dy = (destination.height - image.extent.height) / 2
        image = image.transformed(by: CGAffineTransform(translationX: dx, y: dy))
        context.render(image, to: drawable.texture, commandBuffer: command, bounds: destination, colorSpace: colorSpace)
        command.present(drawable)
        command.addCompletedHandler { [budget] _ in
            budget.end()
            FrameSignpost.end(interval)
            presented(FrameClock.uptime())
        }
        command.commit()
        return true
    }
}
