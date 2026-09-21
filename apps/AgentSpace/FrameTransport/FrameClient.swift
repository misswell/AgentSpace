import Foundation
import CoreVideo
import AgentSpaceCore

final class FrameClient: ObservableObject {
    enum State: Equatable { case idle, connecting, streaming, reconnecting, stopped, failed(String) }

    @Published private(set) var state: State = .idle
    @Published private(set) var surfaceSize: CGSize = .zero
    @Published private(set) var lastError: AgentSpaceError?

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
    private var socket: FrameSocketConnection?
    private var mapping: SharedFrameMapping?
    private var sequence = FrameSequenceValidator()
    private var reconnect = FrameReconnectState()
    private var configureWork: DispatchWorkItem?
    private lazy var videoDecoder = VideoFrameDecoder { [weak self] buffer in self?.handleVideoFrame?(buffer) }
    var handleSharedFrame: ((SharedFrameMapping, FrameHeader, SharedFrameNotice, SharedFrameSlotHeader, [SharedPatchDescriptor]) -> Bool)?
    var handleVideoFrame: ((CVPixelBuffer) -> Void)?
    var resetSurface: (() -> Void)?

    init(space: AgentAccount, target: CaptureTarget, maxFPS: Int = 15, targetWidth: Int = 0, targetHeight: Int = 0) {
        self.space = space; self.target = target; self.maxFPS = maxFPS
        self.targetWidth = targetWidth; self.targetHeight = targetHeight
        self.queue = DispatchQueue(label: BundleIdentifiers.app + ".frame-client.\(UUID().uuidString)", qos: .userInitiated)
    }

    func start() {
        lock.lock(); guard !running else { lock.unlock(); return }; stopped = false; running = true; lock.unlock()
        publishState(.connecting)
        queue.async { [weak self] in self?.runReconnectLoop() }
    }

    func stop() {
        configureWork?.cancel()
        lock.lock(); stopped = true; running = false; let socket = self.socket; let id = streamID; self.socket = nil; streamID = nil; mapping = nil; lock.unlock()
        try? socket?.sendLine(FrameClientCommand(kind: .close))
        if let id { closeControlStream(id) }
        publishState(.stopped)
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
            } catch let error as AgentSpaceError {
                publishError(error)
            } catch {
                publishError(AgentSpaceError(code: .workerOffline, message: "frame stream failed: \(error)"))
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
        let socket = try FrameSocketConnection(path: path)
        try socket.sendLine(FrameHello(protocolVersion: agentSpaceProtocolVersion, spaceID: space.id, streamID: id, token: token, clientPID: getpid(), capabilities: [.sharedBGRA, .h264]))
        let ack = try JSONDecoder().decode(FrameHelloAck.self, from: socket.readLine())
        _ = reconnect.acceptHandshake(workerInstanceID: ack.workerInstanceID, sessionGeneration: ack.sessionGeneration)
        let mapping = try SharedFrameMapping(fd: socket.receiveFileDescriptor())
        lock.lock(); self.socket = socket; self.mapping = mapping; self.streamID = id; lock.unlock()
        publishState(.streaming)
        defer {
            lock.lock(); self.socket = nil; self.mapping = nil; if streamID == id { streamID = nil }; lock.unlock()
            closeControlStream(id); controlStreamOpen = false
            sequence.reset(); reconnect.disconnected()
            DispatchQueue.main.async { self.resetSurface?() }
        }
        while !isStopped {
            let header = try FrameHeader(decoding: socket.readExactly(FrameHeader.byteCount))
            let payload = try socket.readExactly(Int(header.payloadSize))
            switch header.codec {
            case .sharedBGRA:
                let notice = try SharedFrameNotice(decoding: payload)
                let (slot, patches) = try mapping.frame(notice: notice, header: header)
                let decision = sequence.accept(generation: notice.surfaceGeneration, sequence: header.sequence, baseSequence: notice.baseSequence, kind: notice.frameKind)
                if decision == .requestFullFrame { try socket.sendLine(FrameClientCommand(kind: .requestFull)); continue }
                if decision == .ignoredDuplicate { try socket.sendLine(FrameClientCommand(kind: .acknowledge, slotIndex: Int(notice.slotIndex), sequence: header.sequence)); continue }
                let consumed = handleSharedFrame?(mapping, header, notice, slot, patches) ?? false
                if consumed {
                    publishSize(CGSize(width: Int(header.width), height: Int(header.height)))
                    try socket.sendLine(FrameClientCommand(kind: .acknowledge, slotIndex: Int(notice.slotIndex), sequence: header.sequence))
                } else {
                    // Release the slot even when local rendering fails. Holding it
                    // while requesting a baseline can permanently exhaust both slots.
                    try socket.sendLine(FrameClientCommand(kind: .acknowledge, slotIndex: Int(notice.slotIndex), sequence: header.sequence))
                    try socket.sendLine(FrameClientCommand(kind: .requestFull))
                }
            case .h264:
                try videoDecoder.decode(payload)
                publishSize(CGSize(width: Int(header.width), height: Int(header.height)))
            case .jpeg:
                // JPEG is retained only for old-client compatibility and is
                // never negotiated by this production frame client.
                continue
            }
        }
    }

    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    private func closeControlStream(_ id: UUID) {
        let connection = SpaceConnection(space: space)
        _ = try? connection.client.call(method: Method.frameClose, params: .obj(["streamID": .string(id.uuidString)]), token: connection.token)
    }
    private func publishState(_ value: State) { DispatchQueue.main.async { self.state = value } }
    private func publishSize(_ value: CGSize) { DispatchQueue.main.async { self.surfaceSize = value; self.lastError = nil } }
    private func publishError(_ value: AgentSpaceError) { DispatchQueue.main.async { self.lastError = value } }
}
