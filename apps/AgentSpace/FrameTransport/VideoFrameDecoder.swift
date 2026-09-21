import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox
import AgentSpaceCore

/// H.264 decoder seam used by adaptive mode. Shared BGRA remains the default;
/// the decoder intentionally owns no image/NSImage conversion.
final class VideoFrameDecoder {
    private var session: VTDecompressionSession?
    private var format: CMVideoFormatDescription?
    private let output: (CVPixelBuffer) -> Void

    init(output: @escaping (CVPixelBuffer) -> Void) { self.output = output }

    func decode(_ payload: Data) throws {
        var reader = VideoPacketReader(payload)
        guard try reader.bytes(4) == Data([0x41, 0x53, 0x48, 0x32]) else { throw AgentSpaceError(code: .badRequest, message: "invalid H.264 frame packet") }
        _ = try reader.byte()
        let parameterCount = Int(try reader.byte()); _ = try reader.bytes(2)
        var parameters: [Data] = []
        for _ in 0..<parameterCount { parameters.append(try reader.bytes(Int(try reader.uint32()))) }
        if !parameters.isEmpty { try configure(parameterSets: parameters) }
        let sampleData = try reader.bytes(Int(try reader.uint32()))
        guard let format, let session else { throw AgentSpaceError(code: .badRequest, message: "H.264 stream has no decoder configuration") }
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: sampleData.count, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: sampleData.count, flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr, let block else { throw AgentSpaceError(code: .internalError, message: "could not allocate H.264 sample") }
        sampleData.withUnsafeBytes { if let base = $0.baseAddress { CMBlockBufferReplaceDataBytes(with: base, blockBuffer: block, offsetIntoDestination: 0, dataLength: sampleData.count) } }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid)
        var size = sampleData.count, sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr, let sample else { throw AgentSpaceError(code: .internalError, message: "could not create H.264 sample") }
        var flags = VTDecodeInfoFlags()
        let status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: VTDecodeFrameFlags(rawValue: 1), frameRefcon: nil, infoFlagsOut: &flags)
        guard status == noErr else { throw AgentSpaceError(code: .internalError, message: "VideoToolbox decode failed (\(status))") }
    }

    private func configure(parameterSets: [Data]) throws {
        guard parameterSets.count >= 2 else { throw AgentSpaceError(code: .badRequest, message: "H.264 keyframe is missing SPS/PPS") }
        invalidate()
        var description: CMFormatDescription?
        let stable = parameterSets.map { $0 as NSData }
        let pointers = stable.map { $0.bytes.assumingMemoryBound(to: UInt8.self) }
        let sizes = stable.map(\.length)
        let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault, parameterSetCount: pointers.count, parameterSetPointers: pointers, parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &description)
        guard status == noErr, let video = description else { throw AgentSpaceError(code: .badRequest, message: "invalid H.264 parameter sets") }
        format = video
        let attributes: CFDictionary = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA, kCVPixelBufferMetalCompatibilityKey: true] as CFDictionary
        var created: VTDecompressionSession?
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        var callback = VTDecompressionOutputCallbackRecord(decompressionOutputCallback: { refcon, _, status, _, image, _, _ in
            guard status == noErr, let refcon, let image else { return }
            Unmanaged<VideoFrameDecoder>.fromOpaque(refcon).takeUnretainedValue().output(image)
        }, decompressionOutputRefCon: opaque)
        guard VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: video, decoderSpecification: nil, imageBufferAttributes: attributes, outputCallback: &callback, decompressionSessionOut: &created) == noErr, let created else { throw AgentSpaceError(code: .internalError, message: "could not create H.264 decoder") }
        session = created
    }
    func invalidate() { if let session { VTDecompressionSessionInvalidate(session) }; session = nil }
    deinit { invalidate() }
}

private struct VideoPacketReader {
    let data: Data; var offset = 0
    init(_ data: Data) { self.data = data }
    mutating func byte() throws -> UInt8 { guard offset < data.count else { throw truncated() }; defer { offset += 1 }; return data[offset] }
    mutating func uint32() throws -> UInt32 { let value = try bytes(4); return value.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } }
    mutating func bytes(_ count: Int) throws -> Data { guard count >= 0, offset + count <= data.count else { throw truncated() }; defer { offset += count }; return data[offset..<(offset + count)] }
    private func truncated() -> AgentSpaceError { AgentSpaceError(code: .badRequest, message: "truncated H.264 frame packet") }
}
