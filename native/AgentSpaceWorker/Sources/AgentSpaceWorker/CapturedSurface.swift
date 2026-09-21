import CoreVideo
import Foundation
import AgentSpaceCore

struct CapturedSurface {
    let pixelBuffer: CVPixelBuffer
    let sequence: UInt64
    let width: Int
    let height: Int
    let dirtyRects: [DirtyRect]
    let timestampNanoseconds: UInt64
}
