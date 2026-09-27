// Offscreen visual contract for the viewer's Metal fragment path. Run with:
// swiftc -parse-as-library apps/AgentSpace/Rendering/MetalSurfaceShader.swift \
//   tests/probes/MetalSurfaceProbe.swift -o /tmp/agentspace-metal-probe -framework Metal
// /tmp/agentspace-metal-probe
import Metal

@main
struct MetalSurfaceProbe {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { fatalError("Metal device unavailable") }
        let library = try device.makeLibrary(source: MetalSurfaceShader.source, options: nil)
        let pipelineDescription = MTLRenderPipelineDescriptor()
        pipelineDescription.vertexFunction = library.makeFunction(name: "surfaceVertex")
        pipelineDescription.fragmentFunction = library.makeFunction(name: "surfaceFragment")
        pipelineDescription.colorAttachments[0].pixelFormat = .bgra8Unorm
        let pipeline = try device.makeRenderPipelineState(descriptor: pipelineDescription)

        let sourceDescription = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 2, height: 2, mipmapped: false)
        sourceDescription.usage = [.shaderRead]
        sourceDescription.storageMode = .shared
        guard let source = device.makeTexture(descriptor: sourceDescription) else { fatalError("source texture") }
        // BGRA rows: red, green / blue, white. The first row must remain at
        // the top when the fragment samples Metal directly.
        let pixels: [UInt8] = [0, 0, 255, 255, 0, 255, 0, 255,
                               255, 0, 0, 255, 255, 255, 255, 255]
        pixels.withUnsafeBytes { bytes in
            source.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0,
                           withBytes: bytes.baseAddress!, bytesPerRow: 8)
        }

        func render(width: Int, height: Int, fitted: SIMD4<Float>) -> [UInt8] {
            let description = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            description.usage = [.renderTarget]
            description.storageMode = .shared
            guard let output = device.makeTexture(descriptor: description),
                  let command = queue.makeCommandBuffer() else { fatalError("output texture") }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = output
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { fatalError("encoder") }
            var fitted = fitted
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(source, index: 0)
            encoder.setFragmentBytes(&fitted, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            guard command.status == .completed else { fatalError("GPU command failed") }
            var result = [UInt8](repeating: 0, count: width * height * 4)
            result.withUnsafeMutableBytes { bytes in
                output.getBytes(bytes.baseAddress!, bytesPerRow: width * 4,
                                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            }
            return result
        }

        let square = render(width: 2, height: 2, fitted: SIMD4<Float>(0, 0, 2, 2))
        guard square == pixels else { fatalError("cursor colors or vertical direction changed: \(square)") }
        let letterboxed = render(width: 4, height: 2, fitted: SIMD4<Float>(1, 0, 2, 2))
        guard Array(letterboxed[0..<4]) == [0, 0, 0, 255],
              Array(letterboxed[4..<12]) == Array(pixels[0..<8]),
              Array(letterboxed[12..<16]) == [0, 0, 0, 255] else {
            fatalError("aspect-fit bars or image pixels changed: \(letterboxed)")
        }
        print("Metal surface: orientation, BGRA color, and aspect bars passed")
    }
}
