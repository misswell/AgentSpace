import XCTest
import Darwin
import AgentSpaceCore
@testable import AgentSpaceApp

final class RemoteViewerInputTests: XCTestCase {
    @MainActor
    func testDesktopAndWindowShareSocketAndDeliverLastHoverAndRawPress() async throws {
        let root = "/tmp/as-viewer-\(UUID().uuidString.prefix(8))"
        let account = AgentAccount(name: "InputFixture", username: "fixture", uid: getuid(), runtimeRoot: root)
        let paths = AgentSpaceEnvironment.paths(for: account)
        try FileManager.default.createDirectory(atPath: paths.directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        XCTAssertNil(TokenStore.write(SessionToken(hex: String(repeating: "a", count: 64)), to: paths.tokenPath))
        let peer = try ViewerInputPeer(path: paths.inputSocketPath)
        defer { peer.close() }
        let desktop = RemoteViewerInput(), window = RemoteViewerInput()
        defer {
            desktop.shutdown(); window.shutdown()
            InputChannelRegistry.shared.discard(account.id)
        }
        let identity = WindowIdentity(pid: 99, windowID: 42, generation: 7)
        desktop.configure(space: account, surface: .desktop(DisplayGeometry(width: 1000, height: 800,
            pixelWidth: 2000, pixelHeight: 1600, scale: 2)))
        window.configure(space: account, surface: .window(identity,
            CGRectValue(x: 100, y: 200, width: 800, height: 600)))
        try await waitUntil { desktop.cursorChannelActive && window.cursorChannelActive }
        XCTAssertTrue(desktop.cursorChannelActive); XCTAssertTrue(window.cursorChannelActive)
        desktop.setPointerRate(30); window.setPointerRate(30)
        desktop.send(.hover(u: 0.1, v: 0.1)); desktop.send(.hover(u: 0.9, v: 0.9))
        window.send(.hover(u: 0.1, v: 0.1)); window.send(.hover(u: 0.9, v: 0.9))
        // Down reaches the socket before any up, using the same controller.
        window.send(.pointerDown(u: 0.4, v: 0.5, button: .left, clickCount: 1, modifiers: []))
        try await waitUntil {
            let moves = try peer.packets.filter { $0.kind == .pointerMove }.map { try InputPointerPacket(decoding: $0.payload) }
            return peer.packets.contains { $0.kind == .pointerDown }
                && moves.contains { $0.target == .desktop && $0.x == 900 && $0.y == 720 }
        }
        let packets = peer.packets
        XCTAssertTrue(packets.contains { $0.kind == .pointerDown })
        XCTAssertFalse(packets.contains { $0.kind == .pointerUp })
        let moves = try packets.filter { $0.kind == .pointerMove }.map { try InputPointerPacket(decoding: $0.payload) }
        XCTAssertTrue(moves.contains { $0.target == .desktop && $0.x == 900 && $0.y == 720 })
        // Down intentionally resets that surface's pending hover, exactly as desktop does.
        window.send(.pointerUp(u: 0.4, v: 0.5, button: .left, clickCount: 1, modifiers: []))
        desktop.shutdown()
        window.send(.hover(u: 0.8, v: 0.8)); window.send(.hover(u: 0.9, v: 0.9))
        try await waitUntil {
            let moves = try peer.packets.filter { $0.kind == .pointerMove }.map { try InputPointerPacket(decoding: $0.payload) }
            return moves.contains { $0.target == .window(identity) && $0.x == 0.9 && $0.y == 0.9 }
        }
        let remaining = try peer.packets.filter { $0.kind == .pointerMove }.map { try InputPointerPacket(decoding: $0.payload) }
        XCTAssertTrue(remaining.contains { $0.target == .window(identity) && $0.x == 0.9 && $0.y == 0.9 },
                      "Closing the desktop must not close the application's shared channel")
        desktop.configure(space: account, surface: .desktop(DisplayGeometry(width: 1000, height: 800,
            pixelWidth: 2000, pixelHeight: 1600, scale: 2)))
        try await waitUntil { desktop.cursorChannelActive }
        desktop.send(.hover(u: 0.3, v: 0.3))
        try await waitUntil {
            let moves = try peer.packets.filter { $0.kind == .pointerMove }.map { try InputPointerPacket(decoding: $0.payload) }
            return moves.contains { $0.target == .desktop && $0.x == 300 && $0.y == 240 }
        }
        let reopened = try peer.packets.filter { $0.kind == .pointerMove }.map { try InputPointerPacket(decoding: $0.payload) }
        XCTAssertTrue(reopened.contains { $0.target == .desktop && $0.x == 300 && $0.y == 240 },
                      "A closed viewer must reattach to the existing channel when reopened")
    }

    @MainActor
    private func waitUntil(_ predicate: () throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while try !predicate(), Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private final class ViewerInputPeer {
    private let listener: Int32
    private let lock = NSLock()
    private var connection: InputSocketTransport?
    private var received: [InputPacket] = []
    var packets: [InputPacket] { lock.lock(); defer { lock.unlock() }; return received }

    init(path: String) throws {
        listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &address.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: 104) { chars in
                for (index, byte) in path.utf8.enumerated() { chars[index] = CChar(bitPattern: byte) }
                chars[path.utf8.count] = 0
            }
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0, Darwin.listen(listener, 1) == 0 else {
            Darwin.close(listener)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        DispatchQueue.global().async { [self] in
            let fd = Darwin.accept(listener, nil, nil)
            guard fd >= 0 else { return }
            do {
                let socket = try InputSocketTransport(fd: fd)
                lock.lock(); connection = socket; lock.unlock()
                _ = try socket.readPacket()
                let ack = InputHelloAck(capabilities: [.absolutePointer, .leaseControl, .cursorShapes],
                    workerInstanceID: UUID(), sessionGeneration: 1)
                try socket.send(kind: .helloAck, payload: ack.encoded(), sequence: 0)
                while true {
                    let packet = try socket.readPacket()
                    lock.lock(); received.append(packet); lock.unlock()
                }
            } catch { /* Closing a fixture wakes the reader with EOF. */ }
        }
    }

    func close() {
        lock.lock(); let socket = connection; lock.unlock()
        socket?.abort()
        Darwin.shutdown(listener, SHUT_RDWR); Darwin.close(listener)
    }
}
