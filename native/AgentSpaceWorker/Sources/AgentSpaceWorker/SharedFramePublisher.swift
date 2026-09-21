import CoreVideo
import Foundation
import AgentSpaceCore

final class SharedFramePublisher {
    typealias Sender = (FrameHeader, Data) -> Bool

    let streamID: UUID
    private let queue: DispatchQueue
    private let latest = LatestFrameBuffer<CapturedSurface>()
    private let damage = DirtyRegionAccumulator()
    private var region: SharedFrameRegion?
    private var dimensions: (Int, Int)?
    private var freeSlots = [true, true]
    private var slotSequences: [UInt64?] = [nil, nil]
    private var sender: Sender?
    private var disconnectSender: (() -> Void)?
    private var publishSequence: UInt64 = 0
    private var baselineSequence: UInt64 = 0
    private var forceFull = true
    private(set) var stats = FrameStats()
    var mappingBytes: Int { queue.sync { region?.size ?? 0 } }

    init(streamID: UUID) {
        self.streamID = streamID
        self.queue = DispatchQueue(label: BundleIdentifiers.worker + ".frame-publisher.\(streamID.uuidString)")
    }

    func prepare(width: Int, height: Int) throws {
        try queue.sync {
            region = try SharedFrameRegion(width: width, height: height, surfaceGeneration: (region?.surfaceGeneration ?? 0) &+ 1)
            dimensions = (width, height); freeSlots = [true, true]; slotSequences = [nil, nil]; forceFull = true; baselineSequence = 0
        }
    }

    func receive(_ surface: CapturedSurface) {
        queue.async { [weak self] in
            guard let self else { return }
            // Keep the pixels and their damage metadata on one serial timeline.
            // Otherwise a newer buffer can be paired with an older frame's rects.
            let replaced = self.latest.storeReplacing(surface)
            self.damage.merge(surface.dirtyRects, frameWidth: UInt32(surface.width), frameHeight: UInt32(surface.height))
            self.stats.framesCaptured &+= 1
            if replaced { self.stats.framesDropped &+= 1; self.stats.framesMerged &+= 1 }
            let full = max(1, surface.width * surface.height)
            self.stats.dirtyRatio = min(1, Double(surface.dirtyRects.reduce(UInt64(0)) { $0 + $1.area }) / Double(full))
            self.publishIfPossible()
        }
    }

    func attach(sender: @escaping Sender, onDisconnect: @escaping () -> Void) throws -> (fd: Int32, size: Int, generation: UInt64) {
        try queue.sync {
            self.sender = sender; self.disconnectSender = onDisconnect; self.forceFull = true
            guard region != nil else { throw AgentSpaceError(code: .previewNotRunning, message: "shared frame region is not ready") }
            return (region!.fd, region!.size, region!.surfaceGeneration)
        }
    }

    func detach() { queue.sync { sender = nil; disconnectSender = nil; freeSlots = [true, true]; slotSequences = [nil, nil]; forceFull = true } }
    func invalidateConnection() {
        queue.async {
            self.disconnectSender?()
            self.sender = nil; self.disconnectSender = nil
            self.freeSlots = [true, true]; self.slotSequences = [nil, nil]; self.forceFull = true
        }
    }
    func requestFull() { queue.async { self.forceFull = true; self.publishIfPossible() } }
    func acknowledge(slot: Int, sequence: UInt64) {
        queue.async {
            guard self.freeSlots.indices.contains(slot), self.slotSequences[slot] == sequence else { return }
            self.freeSlots[slot] = true; self.slotSequences[slot] = nil; self.publishIfPossible()
        }
    }

    func sendVideo(_ data: Data, width: Int, height: Int, timestamp: UInt64) {
        queue.sync {
            guard let sender = self.sender else { return }
            self.publishSequence &+= 1
            let header = FrameHeader(streamID: self.streamID, sequence: self.publishSequence, timestampNanoseconds: timestamp, codec: .h264, width: UInt32(width), height: UInt32(height), payloadSize: UInt32(data.count))
            if sender(header, data) { self.stats.framesPublished &+= 1; self.stats.videoBytes &+= UInt64(data.count) }
        }
    }

    private func ensureRegion(for surface: CapturedSurface) throws {
        if dimensions?.0 == surface.width, dimensions?.1 == surface.height, region != nil { return }
        let nextGeneration = (region?.surfaceGeneration ?? 0) &+ 1
        region = try SharedFrameRegion(width: surface.width, height: surface.height, surfaceGeneration: nextGeneration)
        dimensions = (surface.width, surface.height); freeSlots = [true, true]; slotSequences = [nil, nil]; forceFull = true; baselineSequence = 0
    }

    private func publishIfPossible() {
        guard let sender, let slot = freeSlots.firstIndex(of: true), let surface = latest.take() else { return }
        do { try ensureRegion(for: surface) } catch { latest.store(surface); return }
        guard let region else { return }
        let accumulated = damage.take()
        let rects: [DirtyRect]
        let kind: SharedFrameKind
        if forceFull || baselineSequence == 0 {
            rects = [.init(x: 0, y: 0, width: UInt32(surface.width), height: UInt32(surface.height))]; kind = .fullBGRA
        } else {
            switch accumulated {
            case .none: return
            case .fullFrame: rects = [.init(x: 0, y: 0, width: UInt32(surface.width), height: UInt32(surface.height))]; kind = .fullBGRA
            case .regions(let regions): rects = regions; kind = .deltaBGRA
            }
        }
        guard write(surface: surface, rects: rects, kind: kind, slot: slot, region: region) else { return }
        publishSequence &+= 1
        let base = kind == .fullBGRA ? 0 : baselineSequence
        let notice = SharedFrameNotice(surfaceGeneration: region.surfaceGeneration, slotIndex: UInt16(slot), frameKind: kind, patchCount: UInt16(rects.count), baseSequence: base, mappingSize: UInt32(region.size))
        let header = FrameHeader(streamID: streamID, sequence: publishSequence, timestampNanoseconds: surface.timestampNanoseconds, codec: .sharedBGRA, width: UInt32(surface.width), height: UInt32(surface.height), payloadSize: UInt32(SharedFrameNotice.byteCount))
        if sender(header, notice.encoded()) {
            freeSlots[slot] = false; slotSequences[slot] = publishSequence; baselineSequence = publishSequence; forceFull = false
            stats.framesPublished &+= 1; stats.sharedBytes &+= UInt64(rects.reduce(0) { $0 + Int($1.width * $1.height * 4) })
            if kind == .fullBGRA { stats.fullFrames &+= 1 } else { stats.deltaFrames &+= 1 }
        }
    }

    private func write(surface: CapturedSurface, rects: [DirtyRect], kind: SharedFrameKind, slot: Int, region: SharedFrameRegion) -> Bool {
        CVPixelBufferLockBaseAddress(surface.pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(surface.pixelBuffer, .readOnly) }
        guard let source = CVPixelBufferGetBaseAddress(surface.pixelBuffer) else { return false }
        let sourceRow = CVPixelBufferGetBytesPerRow(surface.pixelBuffer)
        let slotBase = region.slotPointer(slot)
        var payloadOffset = SharedFrameLayout.slotMetadataSize
        var descriptors: [SharedPatchDescriptor] = []
        for rect in rects.prefix(SharedFrameLayout.maximumPatchCount) {
            let rowBytes = Int(rect.width) * 4, length = rowBytes * Int(rect.height)
            guard payloadOffset + length <= SharedFrameLayout.slotSize(payloadCapacity: region.payloadCapacity) else { return false }
            let destination = slotBase.advanced(by: payloadOffset)
            for row in 0..<Int(rect.height) {
                memcpy(destination.advanced(by: row * rowBytes), source.advanced(by: (Int(rect.y) + row) * sourceRow + Int(rect.x) * 4), rowBytes)
            }
            descriptors.append(.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height, bytesPerRow: UInt32(rowBytes), payloadOffset: UInt32(SharedFrameLayout.slotOffset(slot, payloadCapacity: region.payloadCapacity) + payloadOffset), payloadLength: UInt32(length)))
            payloadOffset += length
        }
        let header = SharedFrameSlotHeader(surfaceGeneration: region.surfaceGeneration, sequence: publishSequence &+ 1, baseSequence: kind == .fullBGRA ? 0 : baselineSequence, timestampNanoseconds: surface.timestampNanoseconds, width: UInt32(surface.width), height: UInt32(surface.height), frameKind: kind, patchCount: UInt16(descriptors.count), payloadSize: UInt32(payloadOffset - SharedFrameLayout.slotMetadataSize))
        header.encoded().copyBytes(to: slotBase.assumingMemoryBound(to: UInt8.self), count: SharedFrameSlotHeader.byteCount)
        for (index, descriptor) in descriptors.enumerated() {
            descriptor.encoded().copyBytes(to: slotBase.advanced(by: SharedFrameSlotHeader.byteCount + index * SharedPatchDescriptor.byteCount).assumingMemoryBound(to: UInt8.self), count: SharedPatchDescriptor.byteCount)
        }
        return true
    }
}
