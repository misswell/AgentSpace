import Foundation
import CoreVideo
import os
import AgentSpaceCore

/// One viewer's side of a frame stream.
///
/// The client owns three things the worker cannot see: whether the frames it was
/// sent actually reached the display, what the local pipeline charged for them,
/// and when to stop believing a stream that has gone quiet. That last one is the
/// reason a heartbeat exists — a desktop that is not changing publishes nothing,
/// so silence alone proves nothing, and only the *absence of heartbeats* says the
/// worker is gone while a picture is still on screen.
final class FrameClient: ObservableObject {
    enum State: Equatable { case idle, connecting, streaming, reconnecting, stopped, failed(String) }

    @Published private(set) var state: State = .idle
    @Published private(set) var surfaceSize: CGSize = .zero
    @Published private(set) var lastError: AgentSpaceError?
    /// What the overlay says about a stream that will not come up. Kept separate
    /// from `lastError` because the two audiences are different: the error carries
    /// the protocol's own words for Diagnostics and the log, and the notice is the
    /// one thing a person looking at a black window can act on.
    @Published private(set) var streamNotice: FrameStreamNotice = .none
    /// One line per connection, on the same channel as the frame signposts, so a
    /// stream that "felt slow" can be answered with what it actually did.
    private static let log = Logger(FrameSignpost.log)

    let space: AgentAccount
    let target: CaptureTarget
    private let maxFPS: Int
    private var targetWidth: Int
    private var targetHeight: Int
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var stopped = false
    private var running = false
    private var streamID: UUID?
    private var socket: FrameSocket?
    private var mapping: SharedFrameMapping?
    private var sequence = FrameSequenceValidator()
    private var reconnect = FrameReconnectState()
    /// Consecutive connections that died on an untrustworthy mapping, behind the
    /// same lock as `stopped` — `start` resets it on the main thread while the
    /// reconnect loop increments it on `queue`, and a count that only sometimes
    /// agrees with itself is worse than no count.
    private var recovery = FrameStreamRecovery()
    private var renderStats = FrameRenderStats()
    private var renderRate = RateMeter()
    private var latency = FrameLatency()
    private var configureWork: DispatchWorkItem?
    private lazy var videoDecoder = VideoFrameDecoder { [weak self] buffer in self?.handleVideoFrame?(buffer) }
    var handleSharedFrame: ((SharedFrameMapping, FrameHeader, SharedFrameNotice, SharedFrameSlotHeader, [SharedPatchDescriptor], @escaping (TimeInterval) -> Void) -> SurfaceApplyOutcome)?
    var handleVideoFrame: ((CVPixelBuffer) -> Void)?
    var resetSurface: (() -> Void)?

    init(space: AgentAccount, target: CaptureTarget, maxFPS: Int = 15, targetWidth: Int = 0, targetHeight: Int = 0) {
        self.space = space; self.target = target; self.maxFPS = maxFPS
        self.targetWidth = targetWidth; self.targetHeight = targetHeight
        self.queue = DispatchQueue(label: BundleIdentifiers.app + ".frame-client.\(UUID().uuidString)", qos: .userInitiated)
    }

    func start() {
        lock.lock(); guard !running else { lock.unlock(); return }; stopped = false; running = true; recovery = FrameStreamRecovery(); lock.unlock()
        publishNotice(.none)
        publishState(.connecting)
        queue.async { [weak self] in self?.runReconnectLoop() }
    }

    func stop() {
        configureWork?.cancel()
        lock.lock(); stopped = true; running = false; let socket = self.socket; let id = streamID; self.socket = nil; streamID = nil; mapping = nil; recovery = FrameStreamRecovery(); lock.unlock()
        try? socket?.sendLine(FrameClientCommand(kind: .close))
        // Shutdown without waiting: the read thread is parked in `read` until the
        // worker hangs up, and the worker hangs up because it read the line above.
        // If the line never arrives, this is what stops the wait becoming the
        // timeout instead of the answer.
        socket?.abort()
        if let id { closeControlStream(id) }
        publishState(.stopped)
        publishNotice(.none)
    }

    /// Debounces live view resizing. A dimension change deliberately reopens
    /// the stream because the shared-memory region is immutable for a session.
    func configure(width: Int, height: Int) {
        let width = max(1, width), height = max(1, height)
        configureWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let materiallyChanged = abs(self.targetWidth - width) >= 16 || abs(self.targetHeight - height) >= 16
            guard materiallyChanged, !self.stopped else { self.lock.unlock(); return }
            self.targetWidth = width; self.targetHeight = height
            let socket = self.socket
            self.lock.unlock()
            try? socket?.sendLine(FrameClientCommand(kind: .close))
        }
        configureWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func runReconnectLoop() {
        let delays: [TimeInterval] = [0.5, 1, 2, 5]
        var attempt = 0
        while !isStopped {
            do {
                try openAndRead(); attempt = 0
            } catch let fault as SharedFrameMappingFault {
                // The buffer itself is what this connection could not lay out, so
                // there is no baseline to ask for on it: the next frame written
                // into a mapping whose geometry is in question is a picture built
                // from the wrong offsets. End the connection, say which two numbers
                // disagreed to the log, and let the handshake choose a descriptor
                // both ends measured the same way.
                noteDisconnected()
                Self.log.error("\(fault.logLine, privacy: .public)")
                publishNotice(noteMappingFault())
            } catch let error as AgentSpaceError {
                noteDisconnected(); publishError(error)
            } catch let error as FrameSocketFailure {
                noteDisconnected(); publishError(error.frameError)
            } catch {
                noteDisconnected(); publishError(AgentSpaceError(code: .workerOffline, message: "frame stream failed: \(error)"))
            }
            guard !isStopped else { break }
            publishState(.reconnecting)
            Thread.sleep(forTimeInterval: delays[min(attempt, delays.count - 1)]); attempt += 1
        }
    }

    private func openAndRead() throws {
        let connection = SpaceConnection(space: space)
        guard let token = connection.token else { throw AgentSpaceError(code: .unauthorized, message: "the frame session token is missing") }
        lock.lock(); let requestedWidth = targetWidth, requestedHeight = targetHeight; lock.unlock()
        let response = try connection.client.call(method: Method.frameOpen, params: .obj([
            "target": target.jsonValue, "maxFPS": .int(maxFPS),
            "targetPixelWidth": .int(requestedWidth), "targetPixelHeight": .int(requestedHeight),
            "preferredMode": .string("auto"),
        ]), token: token)
        if let error = response.error { throw error }
        guard let rawID = response.result?["streamID"]?.stringValue, let id = UUID(uuidString: rawID),
              let path = response.result?["frameSocketPath"]?.stringValue else { throw AgentSpaceError(code: .internalError, message: "frame.open returned no stream endpoint") }
        var controlStreamOpen = true
        defer { if controlStreamOpen { closeControlStream(id) } }
        let socket = try FrameSocketClient.connect(path: path)
        try socket.sendLine(FrameHello(protocolVersion: agentSpaceProtocolVersion, spaceID: space.id, streamID: id, token: token, clientPID: getpid(), capabilities: [.sharedBGRA, .h264]))
        let ack = try JSONDecoder().decode(FrameHelloAck.self, from: socket.readLine())
        _ = reconnect.acceptHandshake(workerInstanceID: ack.workerInstanceID, sessionGeneration: ack.sessionGeneration)
        let mapping = try SharedFrameMapping(fd: socket.receiveFileDescriptor())
        lock.lock(); self.socket = socket; self.mapping = mapping; self.streamID = id; lock.unlock()
        publishState(.streaming)
        defer {
            lock.lock(); self.socket = nil; self.mapping = nil; if streamID == id { streamID = nil }; lock.unlock()
            socket.close()
            closeControlStream(id); controlStreamOpen = false
            sequence.reset(); reconnect.disconnected()
            logConnection()
            DispatchQueue.main.async { self.resetSurface?() }
        }
        try read(socket: socket, mapping: mapping)
    }

    /// The frame loop. Throws on anything that ends the stream — including its
    /// own silence, which is why the socket has an idle policy: a worker that
    /// died mid-stream leaves the last picture on screen and looks exactly like
    /// a desktop that stopped changing, and only the missing heartbeat tells them
    /// apart.
    private func read(socket: FrameSocket, mapping: SharedFrameMapping) throws {
        while !isStopped {
            let (header, payload) = try socket.readFrame()
            let receivedAt = UInt64(FrameClock.uptime() * 1_000_000_000)
            renderStats.framesReceived &+= 1
            if header.isHeartbeat {
                renderStats.heartbeatsReceived &+= 1
                continue
            }
            switch header.codec {
            case .sharedBGRA:
                let notice = try SharedFrameNotice(decoding: payload)
                let (slot, patches) = try mapping.frame(notice: notice, header: header)
                let slotIndex = Int(notice.slotIndex)
                switch sequence.accept(generation: notice.surfaceGeneration, sequence: header.sequence, baseSequence: notice.baseSequence, kind: notice.frameKind) {
                case .requestFullFrame:
                    renderStats.sequenceGaps &+= 1
                    try feedback(socket, slot: slotIndex, sequence: header.sequence, acceptance: .needsBaseline)
                    continue
                case .ignoredDuplicate:
                    try feedback(socket, slot: slotIndex, sequence: header.sequence, acceptance: .duplicate)
                    continue
                case .accepted:
                    let handling = FrameSignpost.begin("FrameReceive")
                    let outcome = handleSharedFrame?(mapping, header, notice, slot, patches) { [weak self] presentedAt in
                        // Metal finishes on its own queue. The hop back to this
                        // one is what keeps every number here single-threaded —
                        // and the stamp is the display taking the pixels, not the
                        // upload returning, which is the difference between a
                        // latency figure and a flattering one.
                        guard let self else { return }
                        self.queue.async { self.notePresented(header: header, receivedAt: receivedAt, at: presentedAt) }
                    } ?? .refused
                    FrameSignpost.end(handling)
                    noteApplied(outcome: outcome)
                    try feedback(socket, slot: slotIndex, sequence: header.sequence, acceptance: .applied(outcome))
                    noteSlotAcknowledged(slotIndex)
                    if outcome != .refused { publishSize(CGSize(width: Int(header.width), height: Int(header.height))) }
                }
            case .h264:
                let handling = FrameSignpost.begin("H264Decode")
                try videoDecoder.decode(payload)
                FrameSignpost.end(handling)
                // H.264 has no slot to refuse, and the decoder's callback cannot be
                // tied back to this frame's stamps, so it counts as arrived and
                // decoded without feeding the latency windows. The BGRA path —
                // which is what a stream spends nearly all of its time on — does.
                noteApplied(outcome: .uploaded)
                publishSize(CGSize(width: Int(header.width), height: Int(header.height)))
            case .jpeg:
                // JPEG is retained only for old-client compatibility and is
                // never negotiated by this production frame client.
                continue
            }
        }
    }

    /// The one place a slot is handed back. Every frame is acknowledged, used or
    /// not: a viewer that refuses a frame and keeps the slot would park the
    /// stream, because the baseline that fixes it has nowhere to be written.
    private func feedback(_ socket: FrameSocket, slot: Int, sequence next: UInt64, acceptance: FrameAcceptance) throws {
        for command in FrameSlotFeedback.commands(slot: slot, sequence: next, acceptance: acceptance) {
            try socket.sendLine(command)
        }
    }

    private func noteApplied(outcome: SurfaceApplyOutcome) {
        renderRate.record(FrameClock.uptime())
        switch outcome {
        case .uploaded: renderStats.framesRendered &+= 1
        case .uploadedWithoutPresent, .refused: renderStats.framesDropped &+= 1
        }
    }

    /// The frame's whole chain: the moment the source produced it, the moment the
    /// socket delivered it, and the moment the display took it. All three are host
    /// uptime, so the subtraction is a measurement rather than a comparison of
    /// clocks — and the last one is Metal's completion callback, not the call that
    /// queued the draw.
    private func notePresented(header: FrameHeader, receivedAt: UInt64, at presentedAt: TimeInterval) {
        let presented = UInt64(max(0, presentedAt) * 1_000_000_000)
        latency.record(receiveToRendered: Int64(presented) - Int64(receivedAt))
        latency.record(captureToRendered: Int64(presented) - Int64(header.timestampNanoseconds))
    }

    /// The connection's summary, logged where the frame timeline already lives.
    /// These numbers stay out of the window: a person reading a frozen picture
    /// needs a reason and a next step, not a percentile.
    private func logConnection() {
        let now = FrameClock.uptime()
        var value = renderStats
        value.renderFPS = renderRate.current(at: now)
        value.receiveToRenderP50 = latency.receiveToRender[50] ?? 0
        value.receiveToRenderP95 = latency.receiveToRender[95] ?? 0
        value.endToEndP50 = latency.captureToRender[50] ?? 0
        value.endToEndP95 = latency.captureToRender[95] ?? 0
        renderStats = value
        guard value.framesReceived > 0 else { return }
        let label: String
        switch target {
        case .display(let id): label = "display:\(id.map(String.init) ?? "main")"
        case .window(let identity): label = "window:\(identity.windowID)"
        }
        Self.log.notice("frame stream \(label, privacy: .public) ended: received=\(value.framesReceived) rendered=\(value.framesRendered) slots=\(value.sharedFramesPerSlot) dropped=\(value.framesDropped) heartbeats=\(value.heartbeatsReceived) gaps=\(value.sequenceGaps) reconnects=\(value.socketReconnects) endToEnd p50=\(String(format: "%.1f", value.endToEndP50))ms p95=\(String(format: "%.1f", value.endToEndP95))ms")
    }

    /// A stream is over. Counted here rather than in `FrameReconnectState`
    /// because "the socket closed" and "the viewer gave up" are different events
    /// for anyone reading the log above.
    private func noteDisconnected() { renderStats.socketReconnects &+= 1 }

    /// One more frame read out of slot `n` and acknowledged on the line above.
    /// See `FrameRenderStats.sharedFramesPerSlot` — this is the count that answers
    /// "does the second slot work" with two numbers instead of one good frame.
    private func noteSlotAcknowledged(_ slot: Int) {
        guard slot >= 0 else { return }
        while renderStats.sharedFramesPerSlot.count <= slot { renderStats.sharedFramesPerSlot.append(0) }
        renderStats.sharedFramesPerSlot[slot] &+= 1
    }

    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    private func closeControlStream(_ id: UUID) {
        let connection = SpaceConnection(space: space)
        _ = try? connection.client.call(method: Method.frameClose, params: .obj(["streamID": .string(id.uuidString)]), token: connection.token)
    }
    private func publishState(_ value: State) { DispatchQueue.main.async { self.state = value } }
    private func publishSize(_ value: CGSize) {
        // Pixels arrived, so whatever the mapping count was carrying up to here is
        // history. Without this, a stream that had three bad seconds and then
        // recovered would go on reporting itself unrecoverable while on screen.
        lock.lock(); recovery.noteStreaming(); lock.unlock()
        DispatchQueue.main.async { self.surfaceSize = value; self.lastError = nil; self.streamNotice = .none }
    }
    private func publishError(_ value: AgentSpaceError) { DispatchQueue.main.async { self.lastError = value } }
    private func publishNotice(_ value: FrameStreamNotice) { DispatchQueue.main.async { self.streamNotice = value } }

    /// One more connection that could not read its buffer. Returns what the window
    /// should now say, which is the same fact the reconnect loop is acting on: the
    /// count describes the stream, and the wording follows from it.
    private func noteMappingFault() -> FrameStreamNotice {
        lock.lock(); defer { lock.unlock() }
        return recovery.noteMappingFault()
    }
}
