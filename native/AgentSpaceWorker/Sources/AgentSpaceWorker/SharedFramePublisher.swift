import CoreVideo
import Foundation
import AgentSpaceCore

/// Turns captured surfaces into acknowledged frames on one connection.
///
/// Everything that can decide anything happens on `queue`, which is what makes
/// the two-slot protocol safe: a slot is only ever marked free by an ACK that
/// names both the slot and the sequence written into it, and the write, the
/// notice and the slot bookkeeping are one step on one serial timeline.
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
    private var liveness = FrameStreamLiveness(policy: .init(), at: FrameClock.uptime())
    /// Slots the viewer has been told about and has not given back, with the
    /// moment each was sent. A viewer that dies holding both slots would
    /// otherwise park the stream forever: no ACK, no free slot, no frame.
    private var awaitingAcknowledgement: [(slot: Int, sequence: UInt64, sentAt: TimeInterval)] = []
    private var timer: DispatchSourceTimer?
    private var captureRate = RateMeter()
    private var publishRate = RateMeter()
    private var latency = FrameLatency()
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
            let now = FrameClock.uptime()
            let replaced = self.latest.storeReplacing(surface)
            self.damage.merge(surface.dirtyRects, frameWidth: UInt32(surface.width), frameHeight: UInt32(surface.height))
            self.captureRate.record(now)
            self.stats.framesCaptured &+= 1
            if replaced { self.stats.framesDropped &+= 1; self.stats.framesMerged &+= 1 }
            let full = max(1, surface.width * surface.height)
            let ratio = min(1, Double(surface.dirtyRects.reduce(UInt64(0)) { $0 + $1.area }) / Double(full))
            self.stats.dirtyRatio = self.stats.dirtyRatio == 0 ? ratio : (0.8 * self.stats.dirtyRatio + 0.2 * ratio)
            self.publishIfPossible(capturedAt: now)
        }
    }

    func attach(sender: @escaping Sender, onDisconnect: @escaping () -> Void) throws -> (fd: Int32, size: Int, generation: UInt64) {
        try queue.sync {
            self.sender = sender; self.disconnectSender = onDisconnect; self.forceFull = true
            self.awaitingAcknowledgement.removeAll()
            self.startWatchdog()
            guard region != nil else { throw AgentSpaceError(code: .previewNotRunning, message: "shared frame region is not ready") }
            return (region!.fd, region!.size, region!.surfaceGeneration)
        }
    }

    func detach() {
        queue.sync {
            sender = nil; disconnectSender = nil
            freeSlots = [true, true]; slotSequences = [nil, nil]; forceFull = true
            awaitingAcknowledgement.removeAll()
            timer?.cancel(); timer = nil
        }
    }

    /// Ends the connection a viewer is reading from, leaving the stream itself
    /// ready to be attached again. Used when the socket says nothing more can
    /// arrive, and when the capture says nothing more will.
    func invalidateConnection() {
        queue.async {
            self.disconnectSender?()
            self.sender = nil; self.disconnectSender = nil
            self.freeSlots = [true, true]; self.slotSequences = [nil, nil]; self.forceFull = true
            self.awaitingAcknowledgement.removeAll()
            self.timer?.cancel(); self.timer = nil
        }
    }

    func requestFull() { queue.async { self.forceFull = true; self.publishIfPossible(capturedAt: FrameClock.uptime()) } }

    func acknowledge(slot: Int, sequence: UInt64) {
        queue.async {
            guard self.freeSlots.indices.contains(slot), self.slotSequences[slot] == sequence else { return }
            self.freeSlots[slot] = true; self.slotSequences[slot] = nil
            self.awaitingAcknowledgement.removeAll { $0.slot == slot && $0.sequence == sequence }
            self.publishIfPossible(capturedAt: FrameClock.uptime())
        }
    }

    func sendVideo(_ data: Data, width: Int, height: Int, capturedAt: UInt64) {
        queue.sync {
            guard let sender = self.sender else { return }
            self.publishSequence &+= 1
            let now = FrameClock.uptime()
            let header = FrameHeader(streamID: self.streamID, sequence: self.publishSequence, timestampNanoseconds: capturedAt, codec: .h264, width: UInt32(width), height: UInt32(height), payloadSize: UInt32(data.count))
            let send = FrameSignpost.begin("FrameSend")
            let delivered = sender(header, data)
            FrameSignpost.end(send)
            if delivered {
                self.notePublished(at: now, capturedAt: capturedAt, bytes: UInt64(data.count), full: false, video: true)
            } else {
                self.connectionLost()
            }
        }
    }

    /// The report a `frame.stats` call answers with. Rates and percentiles are
    /// computed here because this is the only place that owns the timeline they
    /// are measured on.
    func snapshot() -> FrameStats {
        queue.sync {
            var value = stats
            let now = FrameClock.uptime()
            value.captureFPS = captureRate.current(at: now)
            value.publishFPS = publishRate.current(at: now)
            value.captureToPublishP50 = latency.captureToPublish[50] ?? 0
            value.captureToPublishP95 = latency.captureToPublish[95] ?? 0
            value.mappingBytes = region?.size ?? 0
            value.fullFrameRatio = value.framesPublished > 0
                ? Double(value.fullFrames) / Double(value.framesPublished) : 0
            value.pendingDamageArea = pendingDamageArea()
            return value
        }
    }

    private func pendingDamageArea() -> UInt64 { damage.pendingArea() }

    private func notePublished(at now: TimeInterval, capturedAt: UInt64, bytes: UInt64, full: Bool, video: Bool) {
        liveness.noteActivity(at: now)
        publishRate.record(now)
        stats.framesPublished &+= 1
        if video { stats.videoBytes &+= bytes } else { stats.sharedBytes &+= bytes }
        if full { stats.fullFrames &+= 1 } else { stats.deltaFrames &+= 1 }
        latency.record(captureToPublished: Int64(now * 1_000_000_000) - Int64(capturedAt))
    }

    // MARK: Watchdog

    /// One timer, two duties, both of which are "the peer said nothing".
    ///
    /// A static desktop legitimately produces no frames, so silence on its own
    /// proves nothing; that is what the heartbeat is for. The slot deadline is a
    /// different silence: a frame went out and the viewer never gave the slot
    /// back, which only happens when the viewer stopped reading — and both slots
    /// parked like that stops the stream while the socket still looks healthy.
    private func startWatchdog() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + 1, repeating: 1)
        source.setEventHandler { [weak self] in self?.tick() }
        timer = source
        source.resume()
    }

    private func tick() {
        guard sender != nil else { return }
        let now = FrameClock.uptime()
        expireAcknowledgements(before: now - liveness.policy.staleAfter, at: now)
        guard liveness.heartbeatDue(at: now) else { return }
        let header = FrameHeader.heartbeat(streamID: streamID, timestampNanoseconds: UInt64(now * 1_000_000_000))
        if sender?(header, Data()) == true {
            liveness.noteHeartbeatSent(at: now)
            stats.heartbeatsSent &+= 1
        } else {
            connectionLost()
        }
    }

    private func expireAcknowledgements(before deadline: TimeInterval, at now: TimeInterval) {
        let expired = awaitingAcknowledgement.filter { $0.sentAt < deadline }
        guard !expired.isEmpty else { return }
        awaitingAcknowledgement.removeAll { $0.sentAt < deadline }
        for entry in expired where slotSequences[entry.slot] == entry.sequence {
            freeSlots[entry.slot] = true
            slotSequences[entry.slot] = nil
            stats.unacknowledgedDrops &+= 1
        }
        // A viewer that never answered has probably missed more than this one
        // frame, so the stream resumes from a baseline rather than a delta built
        // on pixels nobody is holding.
        forceFull = true
        publishIfPossible(capturedAt: now)
    }

    private func connectionLost() {
        stats.socketReconnects &+= 1
        disconnectSender?()
        sender = nil; disconnectSender = nil
        freeSlots = [true, true]; slotSequences = [nil, nil]; forceFull = true
        awaitingAcknowledgement.removeAll()
        timer?.cancel(); timer = nil
    }

    /// A capture that ended by itself takes its socket with it.
    func captureEnded(_ termination: CaptureEngine.Termination) {
        queue.async {
            self.stats.captureTerminations &+= 1
            guard case .failed = termination else { return }
            self.connectionLost()
        }
    }

    func noteModeSwitch() { queue.async { self.stats.modeSwitchCount &+= 1 } }

    func setFrameMode(_ mode: FrameDeliveryMode) { queue.async { self.stats.frameMode = mode.rawValue } }

    /// Which side of the encoder line the stream is on, counted in both
    /// directions: a static desktop that reports activations is a bug, and so is
    /// one that activates an encoder for every window on the desktop.
    func noteEncoder(active: Bool) {
        queue.async {
            guard self.stats.encoderActive != active else { return }
            self.stats.encoderActive = active
            if active { self.stats.videoEncoderActivations &+= 1 } else { self.stats.videoEncoderInvalidations &+= 1 }
        }
    }

    private func ensureRegion(for surface: CapturedSurface) throws {
        if dimensions?.0 == surface.width, dimensions?.1 == surface.height, region != nil { return }
        let nextGeneration = (region?.surfaceGeneration ?? 0) &+ 1
        region = try SharedFrameRegion(width: surface.width, height: surface.height, surfaceGeneration: nextGeneration)
        dimensions = (surface.width, surface.height); freeSlots = [true, true]; slotSequences = [nil, nil]; forceFull = true; baselineSequence = 0
    }

    private func publishIfPossible(capturedAt: TimeInterval) {
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
        let copy = FrameSignpost.begin("SharedCopy")
        let written = write(surface: surface, rects: rects, kind: kind, slot: slot, region: region)
        FrameSignpost.end(copy)
        guard written else { return }
        publishSequence &+= 1
        let base = kind == .fullBGRA ? 0 : baselineSequence
        let notice = SharedFrameNotice(surfaceGeneration: region.surfaceGeneration, slotIndex: UInt16(slot), frameKind: kind, patchCount: UInt16(rects.count), baseSequence: base, mappingSize: UInt32(region.size))
        let header = FrameHeader(streamID: streamID, sequence: publishSequence, timestampNanoseconds: surface.timestampNanoseconds, codec: .sharedBGRA, width: UInt32(surface.width), height: UInt32(surface.height), payloadSize: UInt32(SharedFrameNotice.byteCount))
        let bytes = UInt64(rects.reduce(0) { $0 + Int($1.width * $1.height * 4) })
        let send = FrameSignpost.begin("FrameSend")
        let delivered = sender(header, notice.encoded())
        FrameSignpost.end(send)
        if delivered {
            let now = FrameClock.uptime()
            freeSlots[slot] = false; slotSequences[slot] = publishSequence; baselineSequence = publishSequence; forceFull = false
            awaitingAcknowledgement.append((slot: slot, sequence: publishSequence, sentAt: now))
            notePublished(at: now, capturedAt: surface.timestampNanoseconds, bytes: bytes, full: kind == .fullBGRA, video: false)
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
