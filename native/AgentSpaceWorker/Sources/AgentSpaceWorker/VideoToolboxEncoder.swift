import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox
import AgentSpaceCore

/// Low-latency H.264 encoder. Payloads carry parameter sets with each IDR so a
/// reconnected viewer can build a decoder without out-of-band codec state.
final class VideoToolboxEncoder {
    private var session: VTCompressionSession?
    private let output: (Data, UInt64) -> Void
    private let lock = NSLock()
    private var frameInFlight = false

    init(output: @escaping (Data, UInt64) -> Void) {
        self.output = output
    }

    /// VT requires its callback refcon at creation. Swift cannot update that
    /// argument afterwards, so recreate once with the now-fully-initialized self.
    func activate(width: Int, height: Int, fps: Int) throws {
        invalidate()
        var created: VTCompressionSession?
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        guard VTCompressionSessionCreate(allocator: kCFAllocatorDefault, width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_H264, encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: { refcon, _, status, flags, sample in
            guard let refcon else { return }
            let encoder = Unmanaged<VideoToolboxEncoder>.fromOpaque(refcon).takeUnretainedValue()
            if status == noErr, !flags.contains(.frameDropped), let sample { encoder.emit(sample) }
            encoder.finishFrame()
        }, refcon: opaque, compressionSessionOut: &created) == noErr, let created else { throw AgentSpaceError(code: .internalError, message: "VideoToolbox H.264 encoder could not be activated") }
        session = created
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: max(1, fps * 2) as CFNumber)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ColorPrimaries, value: kCVImageBufferColorPrimaries_ITU_R_709_2)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_TransferFunction, value: kCVImageBufferTransferFunction_ITU_R_709_2)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_YCbCrMatrix, value: kCVImageBufferYCbCrMatrix_ITU_R_709_2)
        VTCompressionSessionPrepareToEncodeFrames(created)
    }

    func encode(_ buffer: CVPixelBuffer, timestamp: UInt64, forceKeyFrame: Bool) {
        guard let session else { return }
        lock.lock()
        guard !frameInFlight else { lock.unlock(); return }
        frameInFlight = true
        lock.unlock()
        let time = CMTime(value: CMTimeValue(timestamp), timescale: 1_000_000_000)
        let properties: CFDictionary? = forceKeyFrame ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        if VTCompressionSessionEncodeFrame(session, imageBuffer: buffer, presentationTimeStamp: time, duration: .invalid, frameProperties: properties, sourceFrameRefcon: nil, infoFlagsOut: nil) != noErr {
            lock.lock(); frameInFlight = false; lock.unlock()
        }
    }

    func invalidate() { if let session { VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid); VTCompressionSessionInvalidate(session) }; session = nil }
    deinit { invalidate() }

    private func emit(_ sample: CMSampleBuffer) {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
        let key = !(attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
        var payload = Data([0x41, 0x53, 0x48, 0x32, key ? 1 : 0, 0, 0, 0])
        var parameterSets: [Data] = []
        if key, let format = CMSampleBufferGetFormatDescription(sample) {
            var count = 0
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
            for index in 0..<count {
                var pointer: UnsafePointer<UInt8>?, size = 0
                if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: index, parameterSetPointerOut: &pointer, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr, let pointer { parameterSets.append(Data(bytes: pointer, count: size)) }
            }
        }
        payload[5] = UInt8(min(255, parameterSets.count))
        for parameter in parameterSets { payload.appendUInt32(UInt32(parameter.count)); payload.append(parameter) }
        var length = 0, pointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == kCMBlockBufferNoErr, let pointer else { return }
        payload.appendUInt32(UInt32(length)); payload.append(Data(bytes: pointer, count: length))
        output(payload, UInt64(max(0, CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))) * 1_000_000_000))
    }

    private func finishFrame() { lock.lock(); frameInFlight = false; lock.unlock() }
}

private extension Data {
    mutating func appendUInt32(_ value: UInt32) { var big = value.bigEndian; Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) } }
}
