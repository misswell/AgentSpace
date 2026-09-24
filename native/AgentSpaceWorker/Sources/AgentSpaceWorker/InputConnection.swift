import Darwin
import Foundation
import CoreGraphics
import AgentSpaceCore

/// One client's side of the fast input channel, as the worker sees it.
///
/// The ordering inside this type is the product's safety rule, expressed as
/// code: prove the peer, then for *every* packet re-ask the session verdict,
/// the desktop readiness and the human lease before a single event is built.
/// Only then is the packet turned into input and posted.
///
/// The one thing this type deliberately does not do is wait. Travel is state:
/// the newest position is the only one that matters, so a `move` is posted the
/// moment it is read and its acknowledgement is sampled (see `InputAckPolicy`).
/// A press is different — it is an event with an order — and it is acknowledged
/// every time, because a client that never learns its press was refused is a
/// client that will not know to restore the local cursor.
final class InputConnection {
    private let fd: Int32
    private let context: WorkerContext
    private let operations: Operations
    private let lease: InputLeaseManager
    private var socket: InputSocketTransport?
    private var capabilities: InputCapabilities = []
    private var sequence: UInt64 = 0
    /// The highest sequence already answered. Advanced by `ackPolicy`, so a
    /// sampled answer is still an answer for the purpose of the next interval.
    private var acknowledged: UInt64 = 0
    private var ackPolicy = InputAckPolicy()
    /// The last refusal this connection reported, so a *new* reason is always
    /// delivered and a repeated one is throttled. Reset by any packet the
    /// session accepts: a refusal after a success is a new transition.
    private var lastRefusalStatus: InputAckStatus?
    private var cursorPublisher: CursorStateProvider?
    private var stopped = false
    /// The window frames a drag's phases resolve against, keyed by identity. Held
    /// here rather than per packet so a gesture that moves its own window keeps
    /// its original coordinate basis — the same rule the RPC path implements with
    /// `WindowDragFrameStore`, moved onto the channel that now carries the drag.
    private let gestureFrames = GestureFrameStore<WindowIdentity>()

    init(fd: Int32, context: WorkerContext, operations: Operations, lease: InputLeaseManager) {
        self.fd = fd; self.context = context; self.operations = operations; self.lease = lease
    }

    func stop() {
        stopped = true
        cursorPublisher?.stop()
        socket?.close()
    }

    // MARK: - Session

    func pump() {
        let socket: InputSocketTransport
        do {
            socket = try InputSocketTransport(fd: fd)
        } catch {
            close()
            return
        }
        self.socket = socket
        // The cursor provider exists *before* the handshake is answered, because
        // whether this session can read its own cursor is one of the things the
        // handshake has to report — and the answer is only trustworthy once the
        // provider has actually read two of them.
        let provider = CursorStateProvider(context: context) { [weak socket] state in
            try? socket?.send(kind: .cursor, payload: state.encoded(), sequence: state.sequence)
        }
        provider.onShapesProved = { [weak self] in
            guard let self else { return }
            // The promise was not available when the handshake was answered, so it
            // is announced when it becomes true. A viewer that hears it may stop
            // painting the cursor the frames carry; one that never hears it keeps
            // the cursor it already has, which is the state nothing is lost in.
            self.capabilities.insert(.cursorShapes)
            self.announceCapabilities()
        }
        cursorPublisher = provider
        provider.start()
        // The handshake has its own deadline: a connection that opens and then
        // says nothing is a connection holding a worker queue slot.
        do {
            guard let hello = try socket.readHello(timeout: 5) else { close(); return }
            guard accept(hello) else { close(); return }
        } catch {
            Log.input.error("input channel handshake failed: \(error)")
            close()
            return
        }
        // Past here the connection is established, so silence means a client that
        // has stopped sending — not a client that never proved itself.
        while !stopped {
            guard let packet = try? socket.readPacket() else { break }
            if packet.header.kind == .bye || packet.header.kind == .ping { if packet.header.kind == .bye { break } else { continue } }
            handle(packet)
        }
        close()
    }

    private func close() {
        cursorPublisher?.stop(); cursorPublisher = nil
        socket?.close(); socket = nil
        // A client that vanishes mid-drag must not leave a coordinate basis
        // behind for the next gesture to resolve against.
        releaseAllGestures()
    }

    /// Only the frames are forgotten; the events themselves were posted by the
    /// press that started them, and the window server resolves the release from
    /// whatever the client sends next. Forgetting the basis is what matters.
    private func releaseAllGestures() { gestureFrames.endAll() }

    /// Prove the peer exactly the way a frame connection does, and answer with
    /// what this worker can do.
    private func accept(_ hello: InputHello) -> Bool {
        var peerUID: uid_t = 0, peerGID: gid_t = 0
        guard getpeereid(fd, &peerUID, &peerGID) == 0 else {
            Log.input.error("input channel: could not read the peer uid")
            return false
        }
        let expectedUID: uid_t
        if let user = context.mainUser, let record = getpwnam(user) {
            expectedUID = record.pointee.pw_uid
        } else if context.paths.root != RuntimePaths.root {
            // Throwaway roots used by tests have no root-authored space.json, so
            // the same-user case is the only peer that can exist. The production
            // root always names the controller and never reaches this branch.
            expectedUID = getuid()
        } else {
            Log.input.error("input channel: refusing a peer because the controller identity is unknown")
            return false
        }
        guard peerUID == expectedUID else {
            Log.input.error("input channel: refused uid \(peerUID), expected \(expectedUID)")
            return false
        }
        guard hello.protocolVersion == UInt16(agentSpaceProtocolVersion) else {
            Log.input.error("input channel: protocol mismatch (\(hello.protocolVersion) vs \(agentSpaceProtocolVersion))")
            return false
        }
        guard hello.spaceID == context.spaceID else {
            Log.input.error("input channel: refused a connection for another account")
            return false
        }
        // The token is compared in constant time against the one on disk, which is
        // the same check `worker.sock` applies — the fast channel is not a way
        // around it.
        guard context.token.matches(hello.tokenHex) else {
            Log.input.error("input channel: bad or missing session token")
            return false
        }
        capabilities = hello.capabilities.intersection(.current)
        // `cursorShapes` is advertised only when this session has *proved* it can
        // read its own cursor — the viewer turns the capture's embedded cursor off
        // on the strength of this bit, and a bit that lies produces a desktop with
        // no pointer at all. The proof is a runtime measurement rather than an
        // assumption (see `CursorStateProvider`), so at handshake time it may not
        // exist yet; `announceCapabilities` sends it the moment it does.
        capabilities.remove(.cursorShapes)
        if cursorPublisher?.shapesAvailable == true { capabilities.insert(.cursorShapes) }
        guard (try? socket?.send(kind: .helloAck, payload: helloAck().encoded(), sequence: 0)) != nil else { return false }
        Log.input.info("input channel: connection from pid \(hello.clientPID) cap=[\(capabilities.names.joined(separator: ","))]")
        return true
    }

    private func helloAck() -> InputHelloAck {
        InputHelloAck(capabilities: capabilities,
                      workerInstanceID: operations.frames.workerInstanceID,
                      sessionGeneration: operations.frames.sessionGeneration,
                      workerLabel: "agentspace-worker \(Operations.workerVersion)")
    }

    /// Re-announce the capabilities mid-connection. Sent as a second `helloAck`,
    /// which is the one packet whose shape already means "these are the facts
    /// about this connection" — a new kind would be a new thing for every client
    /// to learn, for a case that happens once per connection.
    private func announceCapabilities() {
        Log.input.info("input channel: capabilities now [\(capabilities.names.joined(separator: ","))]")
        try? socket?.send(kind: .helloAck, payload: helloAck().encoded(), sequence: sequence)
    }

    // MARK: - Packets

    private func handle(_ packet: InputPacket) {
        let receivedAt = InputClock.now()
        sequence = packet.header.sequence
        if let refusal = gate(packet) {
            // A refusal has to reach the client, because the alternative is a
            // viewer drawing a cursor it moved locally into a session that never
            // heard about it. But a *repeating* refusal is the same sentence, and
            // a client refused 500 times in a row already knows — measured on a
            // console session, answering every one of them filled the socket
            // buffer until the worker's own write blocked. The first is always
            // sent; the rest are sampled.
            if ackPolicy.shouldAcknowledge(kind: packet.header.kind, after: &acknowledged,
                                           sequence: packet.header.sequence,
                                           refusal: refusal.status, previousRefusal: lastRefusalStatus) {
                sendAck(sequence: packet.header.sequence, status: refusal.status, x: 0, y: 0,
                        receivedAt: receivedAt, postedAt: 0, message: refusal.message)
            }
            lastRefusalStatus = refusal.status
            return
        }
        do {
            let applied = try apply(packet)
            lastRefusalStatus = nil
            if ackPolicy.shouldAcknowledge(kind: packet.header.kind, after: &acknowledged,
                                           sequence: packet.header.sequence,
                                           refusal: nil, previousRefusal: nil) {
                sendAck(sequence: packet.header.sequence, status: .ok,
                        x: applied?.x ?? 0, y: applied?.y ?? 0,
                        receivedAt: receivedAt, postedAt: applied?.postedAt ?? InputClock.now())
            }
        } catch let error as AgentSpaceError {
            // A packet that reached the worker and failed is a refusal too, and
            // the same rule applies: a new reason is reported, a repeated one is
            // throttled.
            let status = InputAckStatus.forError(error.code)
            if ackPolicy.shouldAcknowledge(kind: packet.header.kind, after: &acknowledged,
                                           sequence: packet.header.sequence,
                                           refusal: status, previousRefusal: lastRefusalStatus) {
                sendAck(sequence: packet.header.sequence, status: status,
                        x: 0, y: 0, receivedAt: receivedAt, postedAt: 0, message: error.message)
            }
            lastRefusalStatus = status
        } catch {
            sendAck(sequence: packet.header.sequence, status: .internalError,
                    x: 0, y: 0, receivedAt: receivedAt, postedAt: 0, message: "\(error)")
        }
    }

    private struct Refusal {
        var status: InputAckStatus
        var message: String
    }

    /// Everything that must be true before an event exists. The order is the
    /// `input` RPC's order, on purpose: the fast channel is a faster path to the
    /// same rules, never a way around one of them.
    private func gate(_ packet: InputPacket) -> Refusal? {
        let direction = InputPacketDirection.clientToWorker
        guard direction.permits(packet.header.kind) else {
            return Refusal(status: .invalidPacket, message: "worker does not accept \(packet.header.kind) from a client")
        }
        switch context.sessionVerdict() {
        case .usable:
            break
        case .isConsole:
            Log.input.error("input channel: refused input, this session is on the console")
            return Refusal(status: .refusedSession,
                           message: "refusing to inject input: the '\(context.spaceName)' session is currently on the console, so events would land on the user's own screen.")
        case .indeterminate:
            Log.input.error("input channel: refused input, session state could not be determined")
            return Refusal(status: .refusedSession,
                           message: "refusing to inject input: this session's console state could not be determined. AgentSpace fails closed rather than risk posting events onto the user's screen.")
        case .noWindowServer:
            return Refusal(status: .refusedSession,
                           message: "refusing to inject input: this session has no window server.")
        }
        let readiness = context.desktopReadiness()
        if let error = DesktopReadinessCheck.refusal(readiness, spaceName: context.spaceName) {
            Log.input.error("input channel: refused input, desktop not ready (\(readiness.summary))")
            return Refusal(status: .refusedDesktopNotReady, message: error.message)
        }
        // The human lease gates *automation*, not the person: a client that has
        // taken the lease may keep driving, while an agent's own `input` call
        // during it is refused by the RPC path. A second human client is held off
        // by the lease only for pointer travel, which is the same rule the
        // Fusion proxy applied through `deliversHover`.
        if packet.header.kind == .pointerMove, !lease.deliversHover() {
            // Travel with no button held and nobody in control: the cursor is
            // crossing somebody else's picture. Not an error — the client is
            // told "not applied" without a message, because a proxy whose hover
            // was skipped must not paint an error over a working window.
            return Refusal(status: .refusedLease, message: "")
        }
        guard AccessibilityBridge.trusted() else {
            return Refusal(status: .refusedAccessibility,
                           message: "Accessibility is not granted to agentspace-worker in this session, so synthetic input cannot be delivered.")
        }
        return nil
    }

    private struct Applied {
        var x: Double
        var y: Double
        var postedAt: UInt64
    }

    /// Turn one validated packet into an event.
    private func apply(_ packet: InputPacket) throws -> Applied? {
        switch packet.header.kind {
        case .pointerMove, .pointerDown, .pointerUp:
            let pointer = try InputPointerPacket(decoding: packet.payload)
            let point = try resolve(pointer.target, x: pointer.x, y: pointer.y)
            let action: InputAction
            switch packet.header.kind {
            case .pointerMove:
                action = .move(x: point.x, y: point.y)
            case .pointerDown:
                action = .pointerDown(x: point.x, y: point.y, button: pointer.button,
                                      clickCount: Int(pointer.clickCount), modifiers: pointer.modifiers)
                if case .window(let identity) = pointer.target, let frame = windowFrame(identity) {
                    gestureFrames.begin(identity, frame: frame)
                }
            default:
                action = .pointerUp(x: point.x, y: point.y, button: pointer.button,
                                    clickCount: Int(pointer.clickCount), modifiers: pointer.modifiers)
                if case .window(let identity) = pointer.target { gestureFrames.end(identity) }
            }
            try perform(action, target: pointer.target)
            return Applied(x: point.x, y: point.y, postedAt: InputClock.now())

        case .pointerDrag:
            let drag = try InputDragPacket(decoding: packet.payload)
            let from = try resolveDrag(drag.target, x: drag.fromX, y: drag.fromY)
            let to = try resolve(drag.target, x: drag.toX, y: drag.toY)
            try perform(.pointerDrag(fromX: from.x, fromY: from.y, toX: to.x, toY: to.y,
                                     button: drag.button, modifiers: drag.modifiers), target: drag.target)
            return Applied(x: to.x, y: to.y, postedAt: InputClock.now())

        case .scroll:
            let scroll = try InputScrollPacket(decoding: packet.payload)
            let point = try resolve(scroll.target, x: scroll.x, y: scroll.y)
            try perform(.scroll(x: point.x, y: point.y, dx: Int(scroll.dx), dy: Int(scroll.dy)), target: scroll.target)
            return Applied(x: point.x, y: point.y, postedAt: InputClock.now())

        case .key:
            guard let combo = packet.payload.stringValue else { throw AgentSpaceError(code: .invalidAction, message: "key packet carries no combination") }
            try perform(.key(combo: combo), target: .desktop)
            return nil

        case .type:
            guard let text = packet.payload.stringValue else { throw AgentSpaceError(code: .invalidAction, message: "type packet carries no text") }
            guard text.count <= InputLimits.maxTypeLength else {
                throw AgentSpaceError(code: .invalidAction, message: "text longer than \(InputLimits.maxTypeLength) characters")
            }
            try perform(.type(text: text), target: .desktop)
            return nil

        case .humanAcquire:
            lease.claimHuman()
            broadcastLease(holder: packet.header.sequence == 0 ? 0 : Int32(getpid()))
            return nil

        case .humanRelease:
            lease.releaseHuman()
            broadcastLease(holder: 0)
            return nil

        default:
            throw AgentSpaceError(code: .methodNotFound, message: "unsupported packet \(packet.header.kind)")
        }
    }

    /// Coordinates arrive as display points (desktop) or window fractions
    /// (Fusion). A window target's fractions resolve against the frame the
    /// gesture is bound to, falling back to the window's current frame — which is
    /// what makes a pointer *move* into a window that has moved since still land
    /// where the person is pointing.
    private func resolve(_ target: InputTarget, x: Double, y: Double) throws -> (x: Double, y: Double) {
        switch target {
        case .desktop:
            let point = try target.resolve(x: x, y: y, canvas: nil)
            try validate(point)
            return point
        case .retinaDisplay:
            // Resolved per packet on purpose: the role "the session's Retina
            // display" is what the viewer means, and a raw display id goes stale
            // across sleep and re-enumeration (§336 row 965).
            guard let display = ScreenCapture.retinaViewerDisplay() else {
                throw AgentSpaceError(code: .invalidTarget,
                    message: "no Retina display is available in this session")
            }
            if let error = CoordinateRules.validate(x: x, y: y, geometry: display.geometry) {
                throw error
            }
            return display.globalPoint(x: x, y: y)
        case .display(let id):
            guard let display = ScreenCapture.viewerDisplays().first(where: { $0.id == id }),
                  display.isRetina else {
                throw AgentSpaceError(code: .invalidTarget,
                    message: "the requested Retina display is no longer available")
            }
            if let error = CoordinateRules.validate(x: x, y: y, geometry: display.geometry) {
                throw error
            }
            return display.globalPoint(x: x, y: y)
        case .window(let identity):
            let frame = try gestureFrames.frame(for: identity) ?? currentWindow(identity).frame
            return try target.resolve(x: x, y: y, canvas: InputCanvas(frame: frame))
        }
    }

    /// A drag's start is always resolved against the gesture's own basis: the
    /// press named a window at a moment, and the gesture is usually what moves it.
    private func resolveDrag(_ target: InputTarget, x: Double, y: Double) throws -> (x: Double, y: Double) {
        switch target {
        case .desktop:
            let point = try target.resolve(x: x, y: y, canvas: nil)
            try validate(point)
            return point
        case .display, .retinaDisplay:
            return try resolve(target, x: x, y: y)
        case .window(let identity):
            let frame = try gestureFrames.frame(for: identity) ?? currentWindow(identity).frame
            return try target.resolve(x: x, y: y, canvas: InputCanvas(frame: frame))
        }
    }

    private func windowFrame(_ identity: WindowIdentity) -> CGRectValue? {
        try? currentWindow(identity).frame
    }

    private func currentWindow(_ identity: WindowIdentity) throws -> RemoteWindow {
        do {
            return try operations.windowCatalog.window(matching: identity)
        } catch {
            throw AgentSpaceError(
                code: .invalidTarget,
                message: "window \(identity.windowID) of pid \(identity.pid) is no longer on screen")
        }
    }

    private func validate(_ point: (x: Double, y: Double)) throws {
        let geometry = ScreenCapture.mainDisplayGeometry()
        if let error = CoordinateRules.validate(x: point.x, y: point.y, geometry: geometry) {
            throw AgentSpaceError(code: error.code, message: error.message)
        }
    }

    /// Post one action, with the two guards the RPC path applies and the fast
    /// channel must not skip: a window action needs its window raised once at the
    /// start of the gesture (never per point), and every action is still an
    /// event posted into this session's own stream.
    private func perform(_ action: InputAction, target: InputTarget) throws {
        if case .window(let identity) = target {
            // Raising on every point of a drag is what `isDragContinuation`
            // exists to avoid: AX latency per point, and a window that is moving
            // can be reordered by the raise itself. The press and the activation
            // happen once; the rest of the gesture just posts.
            let needsActivation = !action.isDragContinuation
            if needsActivation {
                let window = try currentWindow(identity)
                try WindowInputRouter.activate(window: window)
            }
        }
        _ = try InputSynthesizer.perform(action)
    }

    private func sendAck(sequence: UInt64, status: InputAckStatus, x: Double, y: Double,
                         receivedAt: UInt64, postedAt: UInt64, message: String? = nil) {
        let ack = InputAck(sequence: sequence, status: status, appliedX: x, appliedY: y,
                           workerReceiveNs: receivedAt, cgEventPostedNs: postedAt, message: message)
        try? socket?.send(kind: .ack, payload: ack.encoded(), sequence: sequence)
    }

    private func broadcastLease(holder: Int32) {
        let state = InputLeaseState(owner: holder == 0 ? .free : .human, holderPID: holder,
                                    remainingMilliseconds: UInt32(max(0, lease.remaining()) * 1000))
        try? socket?.send(kind: .lease, payload: state.encoded(), sequence: sequence)
    }
}

extension GestureFrameStore {
    /// Forget every frame in the store. Used when a connection ends: the next
    /// gesture must not resolve against a basis a previous client established.
    func endAll() {
        for key in allKeys() { end(key) }
    }
}

private extension Data {
    var stringValue: String? { String(data: self, encoding: .utf8) }
}
