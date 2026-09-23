// Proves the persistent binary input channel against a real worker, on this
// machine, rather than against a mock.
//
//   swiftc -O -o /tmp/agentspace-input-probe tests/probes/InputChannelProbe.swift \
//     -I .build/debug -L .build/debug -lAgentSpaceCore \
//     -framework CoreGraphics -framework Foundation
//   /tmp/agentspace-input-probe <runtime-root> <space-id> <token-hex>
//
// What it measures, and why each number is the one that matters:
//
// 1. **one connection, N packets** — the RPC path the fast channel replaces
//    opens a socket, encodes JSON and waits for a reply per event. This opens
//    one socket and writes N framed records, timing each write.
// 2. **the per-packet write cost** — the number that has to be well under one
//    display refresh, because the pointer is what a hand compares against its
//    own motion.
// 3. **the console refusal** — run on a machine whose agent session is the
//    console (or where the session cannot be proven background), every packet
//    must come back refused. A fast channel to a session that has become the
//    console is still a refusal, and that is the property that must not be
//    traded for speed.
// 4. **the handshake's answers** — which capabilities the worker claims, so a
//    viewer knows whether it may hide its own cursor.

import Foundation
import AgentSpaceCore

let arguments = CommandLine.arguments
guard arguments.count >= 4,
      let spaceID = UUID(uuidString: arguments[2]) else {
    FileHandle.standardError.write(Data("usage: probe <runtime-root> <space-id> <token-hex>\n".utf8))
    exit(64)
}

let root = arguments[1]
let token = SessionToken(hex: arguments[3])
let paths = RuntimePaths(spaceID: spaceID, root: root)

func section(_ title: String) { print("\n== \(title) ==") }

// MARK: - 1. The RPC path, for the comparison the product's own notes quote

section("RPC path (worker.sock): one connection per call")
let rpcClient = WorkerClient(socketPath: paths.socketPath)
var rpcSamples: [Double] = []
for index in 0..<50 {
    let started = DispatchTime.now().uptimeNanoseconds
    let response = try? rpcClient.call(method: Method.input, params: .obj([
        "actions": .array([.obj(["type": .string("move"), "x": .double(400), "y": .double(400)])]),
    ]), token: token.hex, timeout: 10)
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    if index == 0 { print("first reply: \(response?.error?.code.rawValue ?? (response?.ok == true ? "ok" : "none"))") }
    rpcSamples.append(elapsed)
}
report("RPC input (new socket, JSON, reply)", rpcSamples)

// MARK: - 2. The fast channel: one socket, N packets

section("Fast channel (input.sock): one connection, N packets")
let socket: InputSocketTransport
do {
    socket = try InputSocketTransport.connect(path: paths.inputSocketPath)
} catch {
    print("could not connect to \(paths.inputSocketPath): \(error)")
    exit(3)
}
do {
    let hello = InputHello(spaceID: spaceID, token: token, clientLabel: "input-channel probe")
    try socket.send(kind: .hello, payload: hello.encoded(), sequence: 0)
    let reply = try socket.readPacket()
    guard reply.kind == .helloAck else {
        print("handshake answered with \(reply.kind) rather than helloAck")
        exit(1)
    }
    let ack = try InputHelloAck(decoding: reply.payload)
    print("handshake accepted: protocol \(ack.protocolVersion), capabilities [\(ack.capabilities.names.joined(separator: ","))]")
    print("worker \(ack.workerInstanceID), session generation \(ack.sessionGeneration)")
} catch {
    print("handshake failed: \(error)")
    exit(1)
}

// 500 moves down one connection, the same packet the desktop viewer sends.
var writeSamples: [Double] = []
for sequence in UInt64(1)...UInt64(500) {
    let packet = InputPointerPacket(target: .desktop, x: 400 + Double(sequence % 50), y: 400)
    let started = DispatchTime.now().uptimeNanoseconds
    do {
        try socket.send(kind: .pointerMove, payload: packet.encoded(), sequence: sequence)
    } catch {
        print("write \(sequence) failed: \(error)")
        break
    }
    writeSamples.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
}
report("input packet write (same socket, no reply awaited)", writeSamples)

// MARK: - 3. What the worker answers

section("Acknowledgements")
// A read with a deadline, because the point of the fast channel is that the
// worker says nothing most of the time: a drain that blocks until a packet
// arrives would hang on a healthy connection.
func drain(_ transport: InputSocketTransport, timeout: TimeInterval) -> [InputPacket] {
    var out: [InputPacket] = []
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        guard let packet = try? transport.readPacketWithTimeout(remainingUntil: deadline) else { break }
        out.append(packet)
        if out.count > 64 { break }
    }
    return out
}

// One press, which is always acknowledged, then a human acquire.
var press = InputPointerPacket(target: .desktop, x: 400, y: 400, button: .left, clickCount: 1)
press.clickCount = 1
try? socket.send(kind: .pointerDown, payload: press.encoded(), sequence: 501)
try? socket.send(kind: .pointerUp, payload: press.encoded(), sequence: 502)
try? socket.send(kind: .humanAcquire, payload: Data(), sequence: 503)

var sawAck = false
var sawLease = false
var refusal: InputAckStatus?
var cursorPackets = 0
for packet in drain(socket, timeout: 1.5) {
    switch packet.kind {
    case .ack:
        if let ack = try? InputAck(decoding: packet.payload) {
            sawAck = true
            if ack.status.isRefusal, refusal == nil { refusal = ack.status }
            print("ack seq \(ack.sequence): \(ack.status)\(ack.message.map { " — \($0)" } ?? "")")
        }
    case .lease:
        sawLease = true
        if let lease = try? InputLeaseState(decoding: packet.payload) {
            print("lease: owner=\(lease.owner) holder=\(lease.holderPID) remaining=\(lease.remainingMilliseconds)ms")
        }
    case .cursor:
        cursorPackets += 1
    default:
        print("unexpected packet \(packet.kind)")
    }
}
print("cursor packets seen: \(cursorPackets)")
print("acknowledged: \(sawAck), lease event: \(sawLease), refusal: \(refusal.map(String.init(describing:)) ?? "none")")

// MARK: - 4. Two connections at once, which a Space must allow

section("Two concurrent connections")
var second: InputSocketTransport?
do {
    let other = try InputSocketTransport.connect(path: paths.inputSocketPath)
    let hello = InputHello(spaceID: spaceID, token: token, clientLabel: "probe #2")
    try other.send(kind: .hello, payload: hello.encoded(), sequence: 0)
    let reply = try other.readPacket()
    print("second connection handshake: \(reply.kind)")
    second = other
} catch {
    print("second connection failed: \(error)")
}

// MARK: - 5. A bad token must be refused

section("Token enforcement")
do {
    let bad = try InputSocketTransport.connect(path: paths.inputSocketPath)
    var bogus = InputHello(spaceID: spaceID, token: SessionToken(hex: String(repeating: "00", count: 32)))
    bogus.clientPID = getpid()
    try bad.send(kind: .hello, payload: bogus.encoded(), sequence: 0)
    let reply = try? bad.readPacket()
    print("a wrong token got: \(reply.map { "\($0.kind)" } ?? "no reply — connection closed, which is a refusal")")
    bad.close()
} catch {
    print("bad-token connection error: \(error)")
}

second?.close()
socket.close()

func report(_ label: String, _ samples: [Double]) {
    guard !samples.isEmpty else { print("\(label): no samples"); return }
    let sorted = samples.sorted()
    func percentile(_ p: Double) -> Double {
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))
        return sorted[index]
    }
    print(String(format: "%@: n=%d p50=%.3fms p95=%.3fms p99=%.3fms max=%.3fms",
                 label, sorted.count, percentile(0.5), percentile(0.95), percentile(0.99), sorted[sorted.count - 1]))
}

// MARK: - Output

