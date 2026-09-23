import CoreVideo
import Foundation
import AgentSpaceCore

/// Turns captured surfaces into acknowledged frames on one connection.
///
/// Everything that can decide anything happens on `queue`, which is what makes
/// the two-slot protocol safe: a slot is only ever marked free by an ACK that
/// names both the slot and the sequence written into it, and the write, the
/// notice and the slot bookkeeping are one step on one serial timeline.
///
/// Slot ownership, stated as the rule the code follows: a slot may be written
/// again only after the viewer has acknowledged it exactly — same slot, same
/// sequence. The single exception is a connection that has already been
/// terminated, at which point the whole mapping is dead and the viewer must
/// reconnect and be given a baseline. There is deliberately no third case: a
/// slot whose ACK is late is not reclaimed while its connection lives, because
/// the only thing that proves the viewer has finished reading is the ACK, and
/// overwriting on a timeout races the reader inside shared memory.
final class SharedFramePublisher {
    typealias Sender = (FrameHeader, Data) -> Bool

    let streamID: UUID
    private let queue: DispatchQueue
    private let latest = LatestFrameBuffer<CapturedSurface>()
    private let damage = DirtyRegionAccumulator()
    private var region: SharedFrameRegion?
    /// Bumped for every mapping this stream has made, including one it lost. The
    /// count cannot come from the region itself: a region reallocated after a
    /// failure would otherwise hand out the same generation a viewer may still be
    /// holding, and "same generation" is what tells a reader to keep its pixels.
    private var generation: UInt64 = 0
    private var dimensions: (Int, Int)?
    /// Whether the capture feeding this mapping was cut by the pixel ceiling.
    ///
    /// Recorded when the capture starts rather than recomputed here: only the
    /// capture knows what it asked a subject for and what it was given, and a
    /// reader of `frame.stats` needs both to tell a soft picture that was asked
    /// for from one that was trimmed.
    private var captureCapped = false
    /// The size this stream needs and could not get a mapping for.
    ///
    /// Held so the next reconnect can ask again. Retrying per captured frame
    /// would turn a full memory pool into a syscall storm sixty times a second on
    /// the capture thread; a client that comes back is the only event that makes
    /// another attempt worth making.
    private var unavailableAt: (Int, Int)?
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
    /// otherwise park the stream forever: no ACK, no free slot, no frame — and
    /// the answer is to end the connection, not to write over its reads.
    private var awaitingAcknowledgement: [(slot: Int, sequence: UInt64, sentAt: TimeInterval)] = []
    /// Whether the viewer watching this stream has a decodable H.264 sequence.
    /// Owned by this queue because `sendVideo` is the only thing that can answer
    /// it, and the answer is a socket result.
    private var keyFrame = FrameKeyFrameState()
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

    /// The mapping the first frame will be drawn into.
    ///
    /// Throws the allocation failure rather than a plain internal error, because
    /// the one caller that can report it to a client converts it at the socket
    /// boundary — and the typed form is what `frame.open` records as this
    /// worker's most recent refusal.
    func prepare(width: Int, height: Int) throws {
        try queue.sync { try self.allocate(width: width, height: height) }
    }

    /// What the capture's own sizing decided, reported beside the size it
    /// produced. See `FrameStats.captureCapped`.
    func noteCaptureCapped(_ value: Bool) {
        queue.sync { captureCapped = value }
    }

    /// Create the mapping a surface of this size needs, resetting everything that
    /// was measured against the old one. Must already be on `queue`.
    ///
    /// A refusal is recorded before it is thrown, so both callers — the stream open,
    /// and a reconnect after a size the last mapping could not hold — report the same
    /// way, and so a stream that cannot be started still answers `frame.stats` with
    /// the call and the errno instead of only a log line nobody can query.
    private func allocate(width: Int, height: Int) throws {
        do {
            generation &+= 1
            region = try SharedFrameRegion(width: width, height: height, surfaceGeneration: generation)
        } catch let failure as SharedFrameAllocationError {
            // The log gets the whole story — call, errno name, size. What it never
            // gets is the name's token: the name is random, so a record carrying it
            // would identify nothing while carrying its length names the bug.
            Log.capture.error("frame stream \(streamID) \(failure.message)")
            stats.allocationFailure = failure.failure
            unavailableAt = (width, height)
            throw failure
        }
        dimensions = (width, height); unavailableAt = nil
        freeSlots = [true, true]; slotSequences = [nil, nil]; forceFull = true; baselineSequence = 0
        keyFrame.require()
    }

    /// Whether this surface still fits the mapping the connection was handed — and
    /// if not, why that connection is now over.
    ///
    /// A size change used to be answered by allocating a new region right here and
    /// carrying on. That was the second bug: the viewer holds the descriptor
    /// `attach` returned, and nothing re-sends a new one, so the worker wrote frame
    /// B into buffer B while the viewer kept reading buffer A and decoded B's
    /// metadata through A's layout — which reads as corrupt pixels, not as an
    /// error. One connection, one mapping. The way to change the mapping is to end
    /// the connection; the client's own reconnect reaches `attach` again, and
    /// `unavailableAt` is what makes that attempt size the buffer for the capture
    /// the stream has now, with a fresh generation and a full baseline.
    private func ensureRegion(for surface: CapturedSurface) -> Bool {
        guard region != nil, let dimensions else { return false }
        if dimensions.0 == surface.width, dimensions.1 == surface.height { return true }
        Log.capture.info("frame stream \(streamID) is capturing \(surface.width)x\(surface.height) into a mapping for \(dimensions.0)x\(dimensions.1); ending the connection so the next one gets its own buffer")
        unavailableAt = (surface.width, surface.height)
        region = nil
        self.dimensions = nil
        connectionLost()
        return false
    }

    func receive(_ surface: CapturedSurface) {
        queue.async { [weak self] in
            guard let self else { return }
            // Keep the pixels and their damage metadata on one serial timeline.
            // Otherwise a newer buffer can be paired with an older frame's rects.
            let now = FrameClock.uptime()
            let replaced = self.latest.storeReplacing(surface)
            self.damage.merge(surface.dirtyRects, frameWidth: UInt32(surface.width), frameHeight: UInt32(surface.height))
            if replaced { self.stats.framesDropped &+= 1; self.stats.framesMerged &+= 1 }
            self.publishIfPossible(capturedAt: now)
        }
    }

    /// A surface arrived from the capture, whichever path its pixels take next.
    ///
    /// This counter used to sit inside `receive`, which is only the shared-pixel
    /// path, so a stream that switched to H.264 kept publishing, kept being
    /// acknowledged, and reported `framesCaptured` and `captureFPS` frozen at the
    /// last delta frame. The capture rate belongs to the capture, so the router
    /// records it before it chooses a path — and hands over the damage ratio it
    /// already measured rather than deriving it a second time.
    func noteCaptured(damageRatio: Double) {
        queue.async {
            self.captureRate.record(FrameClock.uptime())
            self.stats.framesCaptured &+= 1
            self.stats.dirtyRatio = self.stats.dirtyRatio == 0 ? damageRatio : (0.8 * self.stats.dirtyRatio + 0.2 * damageRatio)
        }
    }

    func attach(sender: @escaping Sender, onDisconnect: @escaping () -> Void) throws -> (fd: Int32, size: Int, generation: UInt64) {
        try queue.sync {
            // A stream that lost its mapping to a refusal asks the kernel again
            // here, on the one path a client can drive. The failure is thrown
            // rather than swallowed so the peer is told there is no picture, and
            // `unavailableAt` stays set so the next attempt asks once more.
            if region == nil, let size = unavailableAt {
                try allocate(width: size.0, height: size.1)
            }
            guard region != nil else { throw AgentSpaceError(code: .previewNotRunning, message: "shared frame region is not ready") }
            self.sender = sender; self.disconnectSender = onDisconnect; self.forceFull = true
            self.awaitingAcknowledgement.removeAll()
            self.startWatchdog()
            return (region!.fd, region!.size, region!.surfaceGeneration)
        }
    }

    func detach() {
        queue.sync {
            sender = nil; disconnectSender = nil
            freeSlots = [true, true]; slotSequences = [nil, nil]; forceFull = true
            awaitingAcknowledgement.removeAll()
            keyFrame.require()
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
            self.keyFrame.require()
            self.timer?.cancel(); self.timer = nil
        }
    }

    func requestFull() { queue.async { self.forceFull = true; self.publishIfPossible(capturedAt: FrameClock.uptime()) } }

    /// What the next video frame has to be. The router asks this instead of
    /// remembering: the answer depends on a socket result, and a second copy of
    /// it in another object is a second place to be wrong.
    var needsKeyFrame: Bool { queue.sync { keyFrame.forceKeyFrame } }

    /// The viewer cannot be continued from an ordinary frame — it is new, or it
    /// has spent a stretch of time on shared pixels.
    func requireKeyFrame() { queue.async { self.keyFrame.require() } }

    /// A captured frame that never reached either path. An encoder still working
    /// on the previous frame is the common case, and a frame that quietly
    /// vanished is exactly what `framesDropped` exists to make visible.
    func noteFrameDropped() { queue.async { self.stats.framesDropped &+= 1 } }

    /// The only path by which a slot comes back: an acknowledgement that names
    /// both the slot and the sequence written into it. A late or wrong ACK is
    /// ignored rather than trusted, because accepting one would let the next
    /// frame land on pixels the viewer is still reading.
    func acknowledge(slot: Int, sequence: UInt64) {
        queue.async {
            guard self.freeSlots.indices.contains(slot), self.slotSequences[slot] == sequence else { return }
            self.freeSlots[slot] = true; self.slotSequences[slot] = nil
            self.awaitingAcknowledgement.removeAll { $0.slot == slot && $0.sequence == sequence }
            self.publishIfPossible(capturedAt: FrameClock.uptime())
        }
    }

    /// Send an encoded sample. The return value says whether the viewer got it,
    /// and the key frame bookkeeping below is decided by exactly that: a payload
    /// that never reached a socket has not given anyone a decodable sequence.
    @discardableResult
    func sendVideo(_ data: Data, width: Int, height: Int, capturedAt: UInt64, isKeyFrame: Bool) -> Bool {
        queue.sync {
            guard let sender = self.sender else {
                keyFrame.noteOutput(isKeyFrame: isKeyFrame, delivered: false)
                return false
            }
            self.publishSequence &+= 1
            let now = FrameClock.uptime()
            let header = FrameHeader(streamID: self.streamID, sequence: self.publishSequence, timestampNanoseconds: capturedAt, codec: .h264, width: UInt32(width), height: UInt32(height), payloadSize: UInt32(data.count))
            let send = FrameSignpost.begin("FrameSend")
            let delivered = sender(header, data)
            FrameSignpost.end(send)
            // Decided by the send, not by the submission that led to it: a key
            // frame the socket refused is one the viewer does not have, and the
            // next one still has to be forced.
            keyFrame.noteOutput(isKeyFrame: isKeyFrame, delivered: delivered)
            if delivered {
                self.notePublished(at: now, capturedAt: capturedAt, bytes: UInt64(data.count), full: false, video: true)
            } else {
                self.connectionLost()
            }
            return delivered
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
            value.captureWidth = dimensions?.0
            value.captureHeight = dimensions?.1
            // Only answered once there is a capture to describe: a stream that
            // never got a mapping has no resolution, and "false" would read as
            // "measured, not capped".
            value.captureCapped = dimensions == nil ? nil : captureCapped
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
        expireAcknowledgements(before: now - liveness.policy.staleAfter)
        // Expiring an acknowledgement ends the connection, and a dead
        // connection has no one to send a heartbeat to.
        guard sender != nil else { return }
        guard liveness.heartbeatDue(at: now) else { return }
        let header = FrameHeader.heartbeat(streamID: streamID, timestampNanoseconds: UInt64(now * 1_000_000_000))
        if sender?(header, Data()) == true {
            liveness.noteHeartbeatSent(at: now)
            stats.heartbeatsSent &+= 1
        } else {
            connectionLost()
        }
    }

    /// A viewer that has not given a slot back within the stale window has not
    /// read anything off the socket for that long, which makes it a lost viewer
    /// rather than a slow one.
    ///
    /// So the slots are not reclaimed. Freeing one here would let the worker
    /// write over pixels a disconnected client may still be reading — the one
    /// race the two-slot protocol exists to prevent, and the ACK is the only
    /// evidence that the read finished. Ending the connection instead makes the
    /// whole mapping dead at once: the client reconnects, handshakes again, and
    /// is given a baseline it cannot be missing.
    private func expireAcknowledgements(before deadline: TimeInterval) {
        let expired = awaitingAcknowledgement.filter { $0.sentAt < deadline }
        guard !expired.isEmpty else { return }
        stats.unacknowledgedDrops &+= UInt64(expired.count)
        connectionLost()
    }

    private func connectionLost() {
        stats.socketReconnects &+= 1
        disconnectSender?()
        sender = nil; disconnectSender = nil
        freeSlots = [true, true]; slotSequences = [nil, nil]; forceFull = true
        awaitingAcknowledgement.removeAll()
        // Whoever reconnects has not seen a key frame from this connection, and
        // a decoder with neither SPS/PPS nor an IDR cannot be resumed into.
        keyFrame.require()
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

    /// Times the machine was asked for an H.264 encoder and could not produce
    /// one. Without it a stream that has always been on deltas is
    /// indistinguishable from one that tried to switch and failed.
    func noteEncoderFailure() { queue.async { self.stats.videoEncoderFailures &+= 1 } }

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

    private func publishIfPossible(capturedAt: TimeInterval) {
        guard let sender, let slot = freeSlots.firstIndex(of: true), let surface = latest.take() else { return }
        guard ensureRegion(for: surface) else { return }
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
            guard payloadOffset + length <= region.geometry.slotSize else { return false }
            let destination = slotBase.advanced(by: payloadOffset)
            for row in 0..<Int(rect.height) {
                memcpy(destination.advanced(by: row * rowBytes), source.advanced(by: (Int(rect.y) + row) * sourceRow + Int(rect.x) * 4), rowBytes)
            }
            descriptors.append(.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height, bytesPerRow: UInt32(rowBytes), payloadOffset: UInt32(region.geometry.slotOffset(slot) + payloadOffset), payloadLength: UInt32(length)))
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
