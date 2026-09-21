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

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device; self.queue = queue; self.context = CIContext(mtlDevice: device)
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        layer = CAMetalLayer(); layer.device = device; layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false; layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer.backgroundColor = NSColor.black.cgColor
    }

    func applyVideo(_ pixelBuffer: CVPixelBuffer) -> Bool {
        guard let textureCache else { return false }
        var wrapped: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .bgra8Unorm, CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer), 0, &wrapped) == kCVReturnSuccess,
              let wrapped, let metal = CVMetalTextureGetTexture(wrapped) else { return false }
        width = metal.width; height = metal.height; render(metal)
        return true
    }

    func clear() {
        texture = nil; width = 0; height = 0
        layer.backgroundColor = NSColor.black.cgColor
        layer.setNeedsDisplay()
    }

    func resize(_ size: CGSize, scale: CGFloat) {
        layer.contentsScale = scale
        layer.frame = CGRect(origin: .zero, size: size)
        layer.drawableSize = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
    }

    func apply(mapping: SharedFrameMapping, slot: SharedFrameSlotHeader, patches: [SharedPatchDescriptor]) -> Bool {
        if texture == nil || width != Int(slot.width) || height != Int(slot.height) || slot.frameKind == .fullBGRA {
            if texture == nil || width != Int(slot.width) || height != Int(slot.height) {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(slot.width), height: Int(slot.height), mipmapped: false)
                descriptor.usage = [.shaderRead, .renderTarget]
                guard let newTexture = device.makeTexture(descriptor: descriptor) else { return false }
                texture = newTexture; width = Int(slot.width); height = Int(slot.height)
            }
        }
        guard let texture else { return false }
        for patch in patches {
            let offset = Int(patch.payloadOffset), length = Int(patch.payloadLength)
            guard offset >= 0, length >= 0, offset + length <= mapping.size else { return false }
            texture.replace(region: MTLRegionMake2D(Int(patch.x), Int(patch.y), Int(patch.width), Int(patch.height)), mipmapLevel: 0, withBytes: mapping.pointer.advanced(by: offset), bytesPerRow: Int(patch.bytesPerRow))
        }
        render(texture)
        return true
    }

    private func render(_ texture: MTLTexture) {
        guard let drawable = layer.nextDrawable(), let command = queue.makeCommandBuffer(), var image = CIImage(mtlTexture: texture, options: [.colorSpace: colorSpace]) else { return }
        let destination = CGRect(origin: .zero, size: layer.drawableSize)
        let scale = min(destination.width / CGFloat(width), destination.height / CGFloat(height))
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = (destination.width - image.extent.width) / 2, dy = (destination.height - image.extent.height) / 2
        image = image.transformed(by: CGAffineTransform(translationX: dx, y: dy))
        context.render(image, to: drawable.texture, commandBuffer: command, bounds: destination, colorSpace: colorSpace)
        command.present(drawable); command.commit(); command.waitUntilCompleted()
    }
}
