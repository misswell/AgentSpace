// Live acceptance for the single-Retina-desktop layout: the worker makes the
// session's real 2× display its main display while a `retinaDesktop` frame
// stream is open, and restores the saved arrangement when the last one closes.
// This probe is the reader the stream needs (an unacknowledged stream parks
// itself after one second) and the witness for the session's display facts.
//
//   swiftc -O -o /tmp/retina-verify/retina-probe tests/probes/RetinaDesktopProbe.swift \
//     $(find shared/Core/Sources/AgentSpaceCore -name '*.swift') \
//     -framework CoreGraphics -framework Foundation
//
//   retina-probe <root> <space-id> <token-hex> facts
//   retina-probe <root> <space-id> <token-hex> open-close <seconds>
//       frame.open → facts → ACK frames → frame.close → facts (graceful path)
//   retina-probe <root> <space-id> <token-hex> open-hold <seconds>
//       frame.open → facts → ACK frames → exit without frame.close, so the
//       connection's death is what releases the layout (abnormal-client path;
//       pair it with kill -9 of the worker for the interrupted-worker path)
//   retina-probe <root> <space-id> <token-hex> input
//       input.sock: hello → humanAcquire → two `.desktop` moves (in- and out-
//       of-bounds for the CURRENT main display) → one click → one guaranteed
//       out-of-bounds move (proof the ack channel reports refusals at all)

import Foundation
import CoreGraphics
import AgentSpaceCore

let arguments = CommandLine.arguments
guard arguments.count >= 5, let spaceID = UUID(uuidString: arguments[2]) else {
    FileHandle.standardError.write(Data("usage: probe <root> <space-id> <token-hex> <facts|open-close|open-hold|input> [seconds]\n".utf8))
    exit(64)
}
let root = arguments[1]
let token = SessionToken(hex: arguments[3])
let command = arguments[4]
let holdSeconds = arguments.count > 5 ? (Double(arguments[5]) ?? 5) : 5
let paths = RuntimePaths(spaceID: spaceID, root: root)
let client = WorkerClient(socketPath: paths.socketPath)
let markerPath = paths.directory + "/retina-desktop-layout.json"

func displayFacts(_ label: String) {
    var ids = [CGDirectDisplayID](repeating: 0, count: 32)
    var count: UInt32 = 0
    CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count)
    let main = CGMainDisplayID()
    var active = 0
    for id in ids.prefix(Int(count)) where CGDisplayIsActive(id) != 0 { active += 1 }
    print("FACTS[\(label)] main=\(main) active=\(active) online=\(count)")
    for id in ids.prefix(Int(count)) {
        let bounds = CGDisplayBounds(id)
        let mode = CGDisplayCopyDisplayMode(id)
        let pixels = "\(mode?.pixelWidth ?? 0)x\(mode?.pixelHeight ?? 0)"
        let scale = (mode?.width ?? 0) > 0
            ? String(format: "%.2f", Double(mode?.pixelWidth ?? 0) / Double(mode!.width))
            : "?"
        print("DISPLAY \(id) main=\(id == main ? 1 : 0) active=\(CGDisplayIsActive(id) != 0 ? 1 : 0)"
            + " origin=(\(Int(bounds.origin.x)),\(Int(bounds.origin.y)))"
            + " pts=\(Int(bounds.width))x\(Int(bounds.height))"
            + " px=\(pixels) scale=\(scale)"
            + " mirrorSource=\(CGDisplayMirrorsDisplay(id))")
    }
    if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] {
        for window in list where window["kCGWindowBundleID"] as? String == "com.apple.dock" {
            guard let frame = window["kCGWindowBounds"] as? [String: CGFloat],
                  let x = frame["X"], let y = frame["Y"],
                  let width = frame["Width"], let height = frame["Height"] else { continue }
            print("DOCK window layer=\(window["kCGWindowLayer"] ?? -1)"
                + " frame=(\(Int(x)),\(Int(y)) \(Int(width))x\(Int(height)))")
        }
    }
    print("MARKER \(FileManager.default.fileExists(atPath: markerPath) ? "present" : "absent")")
}

guard command != "facts" else { displayFacts("only"); exit(0) }

if command == "modes" {
    var ids = [CGDirectDisplayID](repeating: 0, count: 32)
    var count: UInt32 = 0
    CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count)
    for id in ids.prefix(Int(count)) {
        let all = CGDisplayCopyAllDisplayModes(id, nil) as? [CGDisplayMode] ?? []
        let current = CGDisplayCopyDisplayMode(id)
        let summary = all.map { "\($0.width)x\($0.height)/\($0.pixelWidth)x\($0.pixelHeight)" }.joined(separator: " ")
        print("MODES \(id) mirrored=\(CGDisplayMirrorsDisplay(id)) count=\(all.count)"
            + " current=\(current.map { "\($0.width)x\($0.height)/\($0.pixelWidth)x\($0.pixelHeight)" } ?? "nil")")
        print("  all: \(summary.isEmpty ? "(none)" : summary)")
    }
    exit(0)
}

if command == "input" {
    displayFacts("input")
    let socket = try InputSocketTransport.connect(path: paths.inputSocketPath)
    try socket.send(kind: .hello,
        payload: InputHello(spaceID: spaceID, token: token, clientLabel: "retina-desktop probe").encoded(),
        sequence: 0)
    let greeting = try socket.readPacket()
    guard greeting.kind == .helloAck else {
        print("INPUT handshake answered \(greeting.kind)"); exit(1)
    }
    let capabilities = try InputHelloAck(decoding: greeting.payload)
    print("INPUT hello ok capabilities=[\(capabilities.capabilities.names.joined(separator: ","))]")
    try socket.send(kind: .humanAcquire, payload: Data(), sequence: 1)

    func drainAcks(_ seconds: Double) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, let packet = try? socket.readPacketWithTimeout(remainingUntil: deadline) {
            if packet.kind == .ack, let ack = try? InputAck(decoding: packet.payload) {
                print("ACK seq \(ack.sequence): \(ack.status)\(ack.message.map { " — \($0)" } ?? "")")
            } else if packet.kind == .cursor, let cursor = try? CursorState(decoding: packet.payload) {
                print("CURSOR (\(Int(cursor.x)),\(Int(cursor.y)))")
            }
        }
    }

    func move(_ sequence: UInt64, _ x: Double, _ y: Double, label: String) {
        let packet = InputPointerPacket(target: .desktop, x: x, y: y)
        try? socket.send(kind: .pointerMove, payload: packet.encoded(), sequence: sequence)
        print("MOVE \(label) (\(x),\(y)) sent as seq \(sequence)")
        Thread.sleep(forTimeInterval: 0.4)
        drainAcks(0.8)
    }
    func click(_ sequence: UInt64, _ x: Double, _ y: Double) {
        var down = InputPointerPacket(target: .desktop, x: x, y: y, button: .left, clickCount: 1)
        down.clickCount = 1
        try? socket.send(kind: .pointerDown, payload: down.encoded(), sequence: sequence)
        try? socket.send(kind: .pointerUp, payload: down.encoded(), sequence: sequence + 1)
        print("CLICK (\(x),\(y)) down seq \(sequence) up seq \(sequence + 1)")
        Thread.sleep(forTimeInterval: 0.4)
        drainAcks(0.8)
    }

    // The current main display decides what is in bounds; the facts above say
    // which geometry that was. In-bounds travel is silent; a refusal — the
    // first of a run — always comes back as an ack.
    move(2, 1400, 900, label: "in-bounds")
    move(3, 1600, 900, label: "probe-bounds")
    click(4, 1450, 940)
    move(6, 9999, 9999, label: "sanity-refusal")
    try socket.send(kind: .humanRelease, payload: Data(), sequence: 7)
    drainAcks(0.8)
    exit(0)
}

let response = try? client.call(method: Method.frameOpen, params: .obj([
    "target": .obj(["kind": .string("retinaDesktop")]),
    "maxFPS": .int(15),
    "targetPixelWidth": .int(0), "targetPixelHeight": .int(0),
    "preferredMode": .string("auto"),
]), token: token.hex, timeout: 30)
guard let response, response.error == nil,
      let streamIDText = response.result?["streamID"]?.stringValue,
      let streamID = UUID(uuidString: streamIDText),
      let frameSocketPath = response.result?["frameSocketPath"]?.stringValue else {
    let failure = response?.error.map { "\($0.code.rawValue): \($0.message)" } ?? "no reply fields"
    print("OPEN failed: \(failure)")
    exit(1)
}
print("OPEN ok stream=\(streamID)")
displayFacts("after-open")

let frameSocket = try FrameSocketClient.connect(path: frameSocketPath)
try frameSocket.sendLine(FrameHello(protocolVersion: agentSpaceProtocolVersion,
    spaceID: spaceID, streamID: streamID, token: token.hex, clientPID: getpid(),
    capabilities: [.sharedBGRA, .h264]))
_ = try JSONDecoder().decode(FrameHelloAck.self, from: frameSocket.readLine())
let mapping = try SharedFrameMapping(fd: frameSocket.receiveFileDescriptor())

var firstFramePrinted = false
let deadline = Date().addingTimeInterval(holdSeconds)
while Date() < deadline {
    do {
        let (header, payload) = try frameSocket.readFrame()
        if header.isHeartbeat { continue }
        if !firstFramePrinted {
            firstFramePrinted = true
            print("FRAME first=\(header.width)x\(header.height) codec=\(header.codec)")
        }
        guard header.codec == .sharedBGRA else { continue }
        let notice = try SharedFrameNotice(decoding: payload)
        for acknowledgement in FrameSlotFeedback.commands(slot: Int(notice.slotIndex),
            sequence: header.sequence, acceptance: .applied(.uploaded)) {
            try frameSocket.sendLine(acknowledgement)
        }
    } catch {
        print("READ ended: \(error)")
        break
    }
}

if command == "open-close" {
    let close = try? client.call(method: Method.frameClose,
        params: .obj(["streamID": .string(streamID.uuidString)]), token: token.hex, timeout: 10)
    print("CLOSE \(close?.error == nil ? "ok" : "failed")")
}
_ = mapping
displayFacts(command == "open-close" ? "after-close" : "before-exit")
