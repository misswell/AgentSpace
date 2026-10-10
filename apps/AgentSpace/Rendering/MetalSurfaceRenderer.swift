import AppKit
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
    private let pipeline: MTLRenderPipelineState
    private var texture: MTLTexture?
    private var textureCache: CVMetalTextureCache?
    private var width = 0, height = 0
    private static let pipelineLock = NSLock()
    private static var pipelines: [UInt64: MTLRenderPipelineState] = [:]
    /// Presents in flight. Two, because that is one being drawn and one waiting;
    /// a third means the GPU is slower than the stream and the extra work is
    /// latency that will never be paid back.
    private let budget = InFlightBudget(capacity: 2)

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let pipeline = Self.pipeline(for: device) else { return nil }
        self.device = device; self.queue = queue; self.pipeline = pipeline
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        layer = CAMetalLayer(); layer.device = device; layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true; layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
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
        // A layout pass that changes nothing must not touch the layer: writing
        // `drawableSize` is what tells the window server to hand out a new pair of
        // drawables, and a viewer laid out once per frame would rebuild its backing
        // store 60 times a second for a window that has not moved.
        guard size != appliedSize || scale != appliedScale else { return }
        appliedSize = size; appliedScale = scale
        layer.contentsScale = scale
        layer.frame = CGRect(origin: .zero, size: size)
        layer.drawableSize = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
    }

    private var appliedSize = CGSize.zero
    private var appliedScale: CGFloat = 0

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
        guard let drawable = layer.nextDrawable(), let command = queue.makeCommandBuffer() else {
            budget.end(); FrameSignpost.end(interval); return false
        }
        let destination = layer.drawableSize
        let scale = min(destination.width / CGFloat(width), destination.height / CGFloat(height))
        let fittedWidth = CGFloat(width) * scale, fittedHeight = CGFloat(height) * scale
        var fitted = SIMD4<Float>(Float((destination.width - fittedWidth) / 2),
                                  Float((destination.height - fittedHeight) / 2),
                                  Float(fittedWidth), Float(fittedHeight))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            budget.end(); FrameSignpost.end(interval); return false
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&fitted, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        command.present(drawable)
        command.addCompletedHandler { [budget] _ in
            budget.end()
            FrameSignpost.end(interval)
            presented(FrameClock.uptime())
        }
        command.commit()
        return true
    }

    private static func pipeline(for device: MTLDevice) -> MTLRenderPipelineState? {
        pipelineLock.lock()
        defer { pipelineLock.unlock() }
        if let existing = pipelines[device.registryID] { return existing }
        guard let library = try? device.makeLibrary(source: MetalSurfaceShader.source, options: nil),
              let vertex = library.makeFunction(name: "surfaceVertex"),
              let fragment = library.makeFunction(name: "surfaceFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        pipelines[device.registryID] = pipeline
        return pipeline
    }
}
