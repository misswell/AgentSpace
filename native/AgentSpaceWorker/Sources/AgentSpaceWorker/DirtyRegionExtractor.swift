import CoreMedia
import Foundation
import ScreenCaptureKit
import AgentSpaceCore

enum DirtyRegionExtractor {
    /// ScreenCaptureKit reports rectangles in source coordinates. Map them to
    /// the configured output buffer and fall back to a full surface whenever
    /// metadata is absent or malformed.
    static func regions(from sampleBuffer: CMSampleBuffer, outputWidth: Int, outputHeight: Int) -> [DirtyRect] {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let frame = attachments.first else { return full(outputWidth, outputHeight) }
        if let statusRaw = frame[.status] as? Int,
           let status = SCFrameStatus(rawValue: statusRaw), status != .complete { return [] }
        guard let values = frame[.dirtyRects] as? [NSValue] else {
            return full(outputWidth, outputHeight)
        }
        if values.isEmpty { return [] }
        let content = (frame[.contentRect] as? NSValue)?.rectValue ?? CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)
        guard content.width > 0, content.height > 0 else { return full(outputWidth, outputHeight) }
        let sx = CGFloat(outputWidth) / content.width, sy = CGFloat(outputHeight) / content.height
        let mapped = values.compactMap { value -> DirtyRect? in
            let rect = value.rectValue
            let x = max(0, Int((rect.minX - content.minX) * sx))
            let y = max(0, Int((rect.minY - content.minY) * sy))
            let right = min(outputWidth, Int(ceil((rect.maxX - content.minX) * sx)))
            let bottom = min(outputHeight, Int(ceil((rect.maxY - content.minY) * sy)))
            guard right > x, bottom > y else { return nil }
            return DirtyRect(x: UInt32(x), y: UInt32(y), width: UInt32(right - x), height: UInt32(bottom - y))
        }
        return mapped.isEmpty ? full(outputWidth, outputHeight) : mapped
    }

    private static func full(_ width: Int, _ height: Int) -> [DirtyRect] {
        guard width > 0, height > 0 else { return [] }
        return [.init(x: 0, y: 0, width: UInt32(width), height: UInt32(height))]
    }
}
