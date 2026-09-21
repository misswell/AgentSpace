import Darwin
import Foundation
import AgentSpaceCore

final class FrameServer {
    /// How long a frame may sit in the kernel buffer before the worker calls the
    /// viewer dead. Above the ~16 ms a frame wants, below the second at which a
    /// frozen window stops being a hiccup and starts being a stall.
    static let sendTimeout: TimeInterval = 1

    private let context: WorkerContext
    private let manager: FrameManager
    private let allowSameUserPeer: Bool
    private var listenFD: Int32 = -1
    private let queue = DispatchQueue(label: BundleIdentifiers.worker + ".frame-server", attributes: .concurrent)

    init(context: WorkerContext, manager: FrameManager) {
        self.context = context; self.manager = manager
        // Throwaway roots used by tests/development have no root-authored
        // space.json. The production root must always name the controller.
        self.allowSameUserPeer = context.paths.root != RuntimePaths.root
    }

    func bind() throws {
        let path = context.paths.frameSocketPath
        guard RuntimePaths.socketPathFits(path) else { throw AgentSpaceError(code: .internalError, message: "frame socket path exceeds sockaddr_un") }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentSpaceError(code: .internalError, message: "could not create frame socket") }
        var address = sockaddr_un(); address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size); address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in pointer.withMemoryRebound(to: CChar.self, capacity: 104) { chars in for (i, byte) in bytes.enumerated() { chars[i] = CChar(bitPattern: byte) }; chars[bytes.count] = 0 } }
        let result = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard result == 0, listen(fd, 16) == 0 else { let message = String(cString: strerror(errno)); Darwin.close(fd); throw AgentSpaceError(code: .internalError, message: "could not bind frame socket: \(message)") }
        guard chmod(path, 0o660) == 0 else { Darwin.close(fd); unlink(path); throw AgentSpaceError(code: .internalError, message: "could not restrict frame socket") }
        if let mainUser = context.mainUser, ACLRunner.apply("user:\(mainUser) allow read,write", to: path) != 0 { Darwin.close(fd); unlink(path); throw AgentSpaceError(code: .internalError, message: "could not grant controller access to frame socket") }
        listenFD = fd
    }

    func start() { queue.async { [weak self] in self?.acceptLoop() } }
    func stop() { if listenFD >= 0 { shutdown(listenFD, SHUT_RDWR); Darwin.close(listenFD); listenFD = -1 }; unlink(context.paths.frameSocketPath) }

    private func acceptLoop() {
        while listenFD >= 0 {
            let client = accept(listenFD, nil, nil)
            if client < 0 { if errno == EINTR { continue }; break }
            // One block per viewer, and each viewer drives a publisher of its own.
            // That is what keeps a frozen Fusion window from holding up Desktop:
            // nothing is shared across connections except the capture, which
            // never waits for a viewer.
            queue.async { [weak self] in self?.handle(client) }
        }
    }

    private func handle(_ fd: Int32) {
        // Every send carries the deadline above. The *read* side deliberately
        // carries none: a still desktop is a viewer that sends nothing for
        // minutes and is perfectly alive, so a read timeout on this side would be
        // a false positive. Judgment of silence flows the other way — the viewer
        // watches for the worker's heartbeats, because a silent worker is the one
        // that would leave a picture on screen pretending to be current.
        let socket = FrameSocket(fd: fd, sendTimeout: Self.sendTimeout, receiveTimeout: 0)
        defer { socket.close() }
        guard let line = try? socket.readLine(),
              let hello = try? JSONDecoder().decode(FrameHello.self, from: line),
              let publisher = manager.publisher(hello.streamID) else { return }
        var peerUID: uid_t = 0, peerGID: gid_t = 0
        guard getpeereid(fd, &peerUID, &peerGID) == 0 else { return }
        let expectedUID: uid_t
        if let user = context.mainUser, let record = getpwnam(user) {
            expectedUID = record.pointee.pw_uid
        } else if allowSameUserPeer {
            expectedUID = getuid()
        } else {
            return
        }
        let expectation = FrameHandshakeExpectation(spaceID: context.spaceID, streamID: publisher.streamID, token: context.token.hex, protocolVersion: agentSpaceProtocolVersion, peerUID: expectedUID, workerInstanceID: manager.workerInstanceID, sessionGeneration: manager.sessionGeneration)
        guard (try? expectation.validate(hello, actualPeerUID: peerUID)) != nil else { return }
        let ack = FrameHelloAck(workerInstanceID: manager.workerInstanceID, sessionGeneration: manager.sessionGeneration, supportedFrameModes: [.sharedBGRA, .h264])
        guard (try? socket.sendLine(ack)) != nil else { return }
        let mapping: (fd: Int32, size: Int, generation: UInt64)
        do {
            mapping = try publisher.shared.attach(sender: { [weak self, weak socket] header, payload in
                guard let socket, self?.context.sessionVerdict() == .usable else { return false }
                return (try? socket.sendFrame(header: header, payload: payload)) != nil
            }, onDisconnect: { [weak socket] in
                // `abort`, not `close`: this runs on the publisher queue, and the
                // descriptor belongs to this method. Shutdown wakes the blocked
                // read below; the `defer` above is what releases it.
                socket?.abort()
            })
        } catch { return }
        guard (try? socket.sendFileDescriptor(mapping.fd)) != nil else { publisher.shared.detach(); return }
        publisher.shared.requestFull()
        defer { publisher.shared.detach() }
        while let commandLine = try? socket.readLine(),
              let command = try? JSONDecoder().decode(FrameClientCommand.self, from: commandLine) {
            switch command.kind {
            case .acknowledge:
                if let slot = command.slotIndex, let sequence = command.sequence { publisher.shared.acknowledge(slot: slot, sequence: sequence) }
            case .requestFull: publisher.shared.requestFull()
            case .close: return
            }
        }
    }
}
