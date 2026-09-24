import AppKit
import Foundation
import os
import AgentSpaceCore

/// The app's side of the fast input channel.
///
/// One connection per account, shared by the desktop viewer and every Fusion
/// proxy of that account. That sharing is the point: a Space has one session,
/// one pointer and one human lease, so a second socket would only be a second
/// queue competing for the same events — and a Fusion window that blocked on its
/// own connection must not be able to delay the desktop's.
///
/// What it is not: a replacement for `WorkerClient`. Status, screenshots, window
/// lists, app launches and every other low-frequency call stay on the JSON RPC
/// transport, because those are request/reply by nature and the old path is
/// correct for them. Only the pointer, the keys and the lease move here.
@MainActor
final class InputClient: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case ready
        /// The worker refused or went away. `reason` is the worker's own words.
        case unavailable(String)

        var isReady: Bool { self == .ready }
    }

    /// Where the agent's pointer is, as the worker reports it, and the shape it
    /// draws there. Published so the viewer can draw a sprite locally without
    /// waiting for the next frame.
    struct CursorPresentation: Equatable {
        var x: Double
        var y: Double
        var shapeID: UInt32
        var hotSpotX: Double
        var hotSpotY: Double
        var size: CGSize
        var image: Data?
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var remoteCursor: CursorPresentation?
    /// True while the *person using this app* holds the human lease on this
    /// account. Published so a viewer can show that automation is paused rather
    /// than silently dropping an agent's input on the floor.
    @Published private(set) var humanLeaseHeld = false
    /// What the worker said it can do, after the handshake.
    @Published private(set) var capabilities: InputCapabilities = []
    /// The last refusal that has not been superseded. Cleared by the next
    /// success, so a viewer does not keep displaying an error that has stopped
    /// being true.
    @Published private(set) var lastRefusal: AgentSpaceError?

    let space: AgentAccount
    private let workQueues = InputChannelWorkQueues(label: BundleIdentifiers.app + ".input-client")
    private var socket: InputSocketTransport?
    private var sequence: UInt64 = 0
    private var readerRunning = false
    private var stopped = false
    /// The highest packet whose *application* the worker has confirmed, and the
    /// position it reported. A viewer that predicted a position locally compares
    /// these; the difference is the correction, and it is only applied when it
    /// is big enough to be a correction rather than rounding.
    private var lastAck: (sequence: UInt64, x: Double, y: Double)?
    /// Latency samples, client-event → worker-applied, for the instrument §34
    /// asks for. Bounded: a running window of the last 512 packets.
    private var latency = InputLatencyWindows()
    private var connectAttempts = 0
    private var cursorShapeCache: [UInt32: Data] = [:]

    init(space: AgentAccount) {
        self.space = space
    }

    /// Open the channel. Idempotent: a second call while a connection is live
    /// does nothing, so a viewer that appears twice cannot open two sockets.
    func connect() {
        guard socket == nil, !stopped else { return }
        let space = self.space
        let paths = AgentSpaceEnvironment.paths(for: space)
        guard paths.inputSocketPathFits else {
            publish(.unavailable("the input socket path is too long for a unix socket"))
            return
        }
        publish(.connecting)
        workQueues.write { [weak self] in
            guard let self else { return }
            do {
                let connection = try InputSocketTransport.connect(path: paths.inputSocketPath)
                guard let token = TokenStore.read(from: paths.tokenPath) else {
                    throw AgentSpaceError(code: .unauthorized, message: "the session token is missing for '\(space.name)'")
                }
                let hello = InputHello(spaceID: space.id, token: token,
                                       clientLabel: "AgentSpace \(agentSpaceVersion)")
                try connection.send(kind: .hello, payload: hello.encoded(), sequence: 0)
                let packet = try connection.readPacket()
                guard packet.kind == .helloAck else {
                    throw AgentSpaceError(code: .protocolMismatch,
                                          message: "the worker answered the input handshake with \(packet.kind)")
                }
                let ack = try InputHelloAck(decoding: packet.payload)
                Task { @MainActor in self.install(connection: connection, ack: ack) }
            } catch {
                let message = (error as? AgentSpaceError)?.message ?? "\(error)"
                Task { @MainActor in
                    guard !self.stopped else { return }
                    self.noteFailure(message)
                    self.scheduleReconnect()
                }
            }
        }
    }

    func disconnect() {
        stopped = true
        let connection = socket
        connection?.abort() // Wake the blocking reader before releasing the socket.
        workQueues.write { connection?.close() }
        socket = nil
        readerRunning = false
        publish(.idle)
        remoteCursor = nil
        humanLeaseHeld = false
    }

    /// Re-arm after a `disconnect`, so reopening a viewer that was closed in
    /// the same session connects again rather than staying silently dead.
    func restart() {
        stopped = false
        connect()
    }

    // MARK: - Sending

    /// Pointer travel. Fire-and-forget by design: the newest position wins, and
    /// a `move` that is still waiting for a reply is a `move` that has already
    /// been overtaken.
    func move(to point: (x: Double, y: Double), target: InputTarget, phase: PointerPhase = .move) {
        var packet = InputPointerPacket(target: target, x: point.x, y: point.y)
        packet.clickCount = 1
        sendForKind(phase.kind, payload: packet.encoded(), trackLatency: false)
    }

    func pointerDown(at point: (x: Double, y: Double), target: InputTarget,
                     button: MouseButton, clickCount: Int, modifiers: [Modifier]) {
        let packet = InputPointerPacket(target: target, x: point.x, y: point.y, button: button,
                                        clickCount: clickCount, modifiers: modifiers)
        sendForKind(.pointerDown, payload: packet.encoded(), trackLatency: true)
    }

    func pointerUp(at point: (x: Double, y: Double), target: InputTarget,
                   button: MouseButton, clickCount: Int, modifiers: [Modifier]) {
        let packet = InputPointerPacket(target: target, x: point.x, y: point.y, button: button,
                                        clickCount: clickCount, modifiers: modifiers)
        sendForKind(.pointerUp, payload: packet.encoded(), trackLatency: true)
    }

    func pointerDrag(from: (x: Double, y: Double), to: (x: Double, y: Double), target: InputTarget,
                     button: MouseButton, modifiers: [Modifier]) {
        let packet = InputDragPacket(target: target, fromX: from.x, fromY: from.y,
                                     toX: to.x, toY: to.y, button: button, modifiers: modifiers)
        sendForKind(.pointerDrag, payload: packet.encoded(), trackLatency: true)
    }

    func scroll(at point: (x: Double, y: Double), target: InputTarget, dx: Int, dy: Int) {
        let packet = InputScrollPacket(target: target, x: point.x, y: point.y,
                                       dx: Int32(dx), dy: Int32(dy))
        sendForKind(.scroll, payload: packet.encoded(), trackLatency: true)
    }

    func key(_ combo: String) {
        sendForKind(.key, payload: Data(combo.utf8), trackLatency: true)
    }

    func type(_ text: String) {
        sendForKind(.type, payload: Data(text.utf8), trackLatency: true)
    }

    /// Tell the worker a person has taken this surface. The lease is what pauses
    /// automation, and taking it *here* — when the pointer enters a captured
    /// surface, not when the first press finally arrives — is the difference
    /// between an agent pausing and an agent clicking on top of the person.
    func acquireHuman() {
        guard socket != nil else { return }
        sendForKind(.humanAcquire, payload: Data(), trackLatency: false)
        humanLeaseHeld = true
    }

    /// The person left. Automation resumes now rather than when the five-second
    /// fail-safe would have expired — the lease still guards a client that dies
    /// without releasing, it just stops being the normal way out.
    func releaseHuman() {
        guard socket != nil else { return }
        sendForKind(.humanRelease, payload: Data(), trackLatency: false)
        humanLeaseHeld = false
    }

    /// What the worker last confirmed for a position, or `nil` if it has not
    /// confirmed one yet. A viewer compares its prediction against this and
    /// corrects only a real disagreement.
    var confirmedPosition: (x: Double, y: Double)? {
        guard let lastAck, lastAck.x != 0 || lastAck.y != 0 else { return nil }
        return (x: lastAck.x, y: lastAck.y)
    }

    enum PointerPhase: Equatable {
        case move, down, drag, up
        var kind: InputPacketKind {
            switch self {
            case .move: return .pointerMove
            case .down: return .pointerDown
            case .drag: return .pointerDrag
            case .up: return .pointerUp
            }
        }
    }

    private func sendForKind(_ kind: InputPacketKind, payload: Data, trackLatency: Bool) {
        guard let socket, !socket.isDead else { return }
        sequence &+= 1
        let sent = sequence
        if trackLatency { latency.noteSent(sequence: sent, at: InputClock.now()) }
        workQueues.write {
            do {
                try socket.send(kind: kind, payload: payload, sequence: sent)
            } catch {
                Task { @MainActor in self.noteFailure("the input channel stopped accepting packets") }
            }
        }
    }

    // MARK: - Receiving

    private func install(connection: InputSocketTransport, ack: InputHelloAck) {
        guard !stopped else { connection.close(); return }
        socket = connection
        capabilities = ack.capabilities
        connectAttempts = 0
        publish(.ready)
        lastRefusal = nil
        guard !readerRunning else { return }
        readerRunning = true
        workQueues.read { [weak self] in self?.readLoop(connection) }
    }

    private func readLoop(_ connection: InputSocketTransport) {
        while !stopped, !connection.isDead {
            do {
                let packet = try connection.readPacket()
                Task { @MainActor in self.handle(packet) }
            } catch {
                break
            }
        }
        Task { @MainActor in
            guard self.socket === connection else { return }
            self.socket = nil
            self.readerRunning = false
            guard !self.stopped else { return }
            self.noteFailure("the input channel closed")
            self.scheduleReconnect()
        }
    }

    private func handle(_ packet: InputPacket) {
        switch packet.kind {
        case .helloAck:
            // A second handshake answer, which is how the worker announces a
            // capability that only became true after the first one — the cursor
            // shape channel is proved by reading two cursors in its own session,
            // and that proof may not exist yet when the connection opens. Taking
            // it as "the facts about this connection have changed" is what lets
            // the viewer start drawing the agent's cursor the moment it can, and
            // never a moment before.
            guard let ack = try? InputHelloAck(decoding: packet.payload) else { return }
            if ack.capabilities != capabilities {
                capabilities = ack.capabilities
                InputLatencyLog.shared.noteCapabilities(ack.capabilities)
            }

        case .ack:
            guard let ack = try? InputAck(decoding: packet.payload) else { return }
            if let received = latency.noteAcked(sequence: ack.sequence, workerPostedAt: ack.cgEventPostedNs) {
                InputLatencyLog.shared.record(roundTripNanoseconds: received)
            }
            switch ack.status {
            case .ok:
                lastAck = (sequence: ack.sequence, x: ack.appliedX, y: ack.appliedY)
                lastRefusal = nil
            case .refusedLease:
                // Travel skipped because nobody holds the lease. Not an error:
                // it is the pointer crossing a picture.
                break
            default:
                lastRefusal = AgentSpaceError(
                    code: ack.status.agentSpaceCode,
                    message: ack.message ?? "the worker refused an input packet (\(ack.status))")
            }

        case .cursor:
            guard let state = try? CursorState(decoding: packet.payload) else { return }
            if let image = state.image, state.width > 0, state.height > 0 {
                cursorShapeCache[state.shapeID] = image
                if cursorShapeCache.count > 24 { cursorShapeCache.removeAll(keepingCapacity: true) }
            }
            let cached = state.image ?? cursorShapeCache[state.shapeID]
            remoteCursor = CursorPresentation(
                x: state.x, y: state.y, shapeID: state.shapeID,
                hotSpotX: state.hotSpotX, hotSpotY: state.hotSpotY,
                size: CGSize(width: state.width, height: state.height),
                image: state.hasImage ? state.image : cached)

        case .lease:
            guard let lease = try? InputLeaseState(decoding: packet.payload) else { return }
            humanLeaseHeld = lease.owner == .human

        default:
            break
        }
    }

    private func scheduleReconnect() {
        guard !stopped else { return }
        connectAttempts += 1
        let delay = min(5.0, 0.5 * Double(connectAttempts))
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !self.stopped, self.socket == nil else { return }
            self.connect()
        }
    }

    private func publish(_ value: State) { state = value }

    private func noteFailure(_ message: String) {
        publish(.unavailable(message))
        humanLeaseHeld = false
    }
}

/// A bounded window of client→worker round trips.
///
/// The number that matters is not the socket write, which is a few microseconds
/// on a local unix socket, but the whole trip: the client handed a packet to the
/// kernel, and the worker had built and posted a `CGEvent`. Both ends stamp with
/// the same host clock, so the difference is a measurement.
struct InputLatencyWindows {
    private var sent: [UInt64: UInt64] = [:]
    private var order: [UInt64] = []
    private static let windowSize = 512

    mutating func noteSent(sequence: UInt64, at time: UInt64) {
        sent[sequence] = time
        order.append(sequence)
        while order.count > Self.windowSize {
            let oldest = order.removeFirst()
            sent[oldest] = nil
        }
    }

    /// The round trip for a sequence whose application has been confirmed, or
    /// nil when the sample no longer exists (an ack about a sampled move can
    /// arrive long after the packet left the window).
    mutating func noteAcked(sequence: UInt64, workerPostedAt: UInt64) -> UInt64? {
        guard let sentAt = sent.removeValue(forKey: sequence) else { return nil }
        if let index = order.firstIndex(of: sequence) { order.remove(at: index) }
        guard workerPostedAt > 0 else { return nil }
        return workerPostedAt > sentAt ? workerPostedAt - sentAt : 0
    }
}

/// One log line per connection summarizing the input latency the person actually
/// experienced, in the shape the frame timeline already uses.
///
/// Kept off the window on purpose: a person moving a mouse does not need a
/// percentile, and the number is only meaningful next to the operation that
/// produced it — which is what `docs/validation.md` records.
final class InputLatencyLog {
    static let shared = InputLatencyLog()

    /// The same channel the frame timeline uses, so a latency question can be
    /// answered from one log stream instead of two.
    private static let log = Logger(FrameSignpost.log)

    private let lock = NSLock()
    private var lastCapabilities: InputCapabilities?

    /// One line when the capability set changes, because "the cursor appears
    /// without the desktop blinking" and "the cursor never appeared" are two
    /// reports that look identical from the outside.
    func noteCapabilities(_ capabilities: InputCapabilities) {
        lock.lock()
        let changed = lastCapabilities != capabilities
        lastCapabilities = capabilities
        lock.unlock()
        guard changed else { return }
        Self.log.notice("input channel capabilities: [\(capabilities.names.joined(separator: ","), privacy: .public)]")
    }
    private var samples: [UInt64] = []
    private var lastReport = Date.distantPast

    func record(roundTripNanoseconds: UInt64) {
        lock.lock()
        samples.append(roundTripNanoseconds)
        if samples.count > 4096 { samples.removeFirst(samples.count - 4096) }
        let due = Date().timeIntervalSince(lastReport) > 30
        let snapshot = due ? samples : []
        if due { lastReport = Date(); samples.removeAll(keepingCapacity: true) }
        lock.unlock()
        guard due, !snapshot.isEmpty else { return }
        let sorted = snapshot.sorted()
        func percentile(_ p: Double) -> Double {
            let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))
            return Double(sorted[index]) / 1_000_000
        }
        Self.log.notice("input latency (client→worker posted CGEvent): n=\(sorted.count, privacy: .public) p50=\(String(format: "%.2f", percentile(0.5)), privacy: .public)ms p95=\(String(format: "%.2f", percentile(0.95)), privacy: .public)ms p99=\(String(format: "%.2f", percentile(0.99)), privacy: .public)ms")
    }
}
