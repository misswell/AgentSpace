import Foundation
import CoreGraphics

/// The binary input channel's fixed-width framing.
///
/// Pointer travel is *state*, and a state update that costs a socket connect, a
/// JSON encode and a synchronous reply has already lost: the GUI's own input
/// path sent one `move` per mouse event over the JSON RPC transport, each one
/// opening its own connection, so a hand moving at 500 Hz queued position
/// updates behind a request/reply latency that was measured at p95 3.98 ms per
/// call (§327 row 894). The desktop viewer's 5 FPS capture made that invisible
/// for a while — 200 ms per frame hides a 4 ms round trip — but it is the wrong
/// shape for the feature the product is: a pointer that follows the hand.
///
/// So this is the other transport: one long-lived connection per Space, fixed
/// binary records, no reply in the hot path, and an explicit capability
/// negotiation so a worker or app from an older build is spoken to in the old
/// language rather than misunderstood.
///
/// Layout, all integers network byte order so the two ends cannot disagree
/// about the meaning of a byte:
///
/// ```text
/// header 32 bytes: magic "ASFI" | version | kind | sequence | timestamp | payloadSize | flags
/// payload: fixed struct per kind, then an optional byte tail (text, cursor image)
/// ```
public enum InputPacketKind: UInt16, CaseIterable, Sendable {
    /// Client → worker: the handshake. Carries the session token.
    case hello = 1
    /// Worker → client: accepted, and what this worker can do.
    case helloAck = 2
    case pointerMove = 10
    case pointerDown = 11
    case pointerDrag = 12
    case pointerUp = 13
    case scroll = 14
    /// A named key combination (`cmd+shift+t`), resolved by the same
    /// `KeyCombo` parser the RPC path uses.
    case key = 15
    /// Literal text, one grapheme cluster per event on the posting side.
    case type = 16
    /// The person took control of a surface: pause automation now instead of
    /// waiting for the five-second lease to be re-taken by the next gesture.
    case humanAcquire = 20
    /// The person left the surface: automation may resume immediately.
    case humanRelease = 21
    /// Worker → client: what happened to one client packet.
    case ack = 30
    /// Worker → client: where the session's pointer is now, and its shape when
    /// it changed.
    case cursor = 31
    /// Worker → client: who holds the human lease.
    case lease = 32
    case ping = 40
    case bye = 41
}

/// Which end is allowed to send which kind. A worker that answered a `cursor`
/// packet, or a client that believed a `ack`, would each be reading a byte
/// stream it did not frame — so the direction is checked rather than assumed.
public enum InputPacketDirection: Sendable {
    case clientToWorker
    case workerToClient

    public func permits(_ kind: InputPacketKind) -> Bool {
        switch kind {
        case .hello, .pointerMove, .pointerDown, .pointerDrag, .pointerUp,
             .scroll, .key, .type, .humanAcquire, .humanRelease, .ping, .bye:
            return self == .clientToWorker
        case .helloAck, .ack, .cursor, .lease:
            return self == .workerToClient
        }
    }
}

/// The header every packet starts with. Fixed at 32 bytes.
public struct InputPacketHeader: Equatable, Sendable {
    public static let magic: UInt32 = 0x41534649 // "ASFI"
    public static let version: UInt16 = 1
    public static let byteCount = 32
    /// A cursor sprite is the largest thing that crosses this socket: 128×128
    /// BGRA is 64 KB, and the text kinds are bounded far below that. The ceiling
    /// exists so a hostile or broken peer cannot make the worker allocate.
    public static let maxPayloadBytes = 1 << 20

    public var kind: InputPacketKind
    public var sequence: UInt64
    public var timestampNanoseconds: UInt64
    public var flags: UInt32

    public init(kind: InputPacketKind, sequence: UInt64 = 0, timestampNanoseconds: UInt64 = InputClock.now(), flags: UInt32 = 0) {
        self.kind = kind; self.sequence = sequence; self.timestampNanoseconds = timestampNanoseconds; self.flags = flags
    }

    public func encoded(payloadSize: Int) -> Data {
        var writer = BinaryWriter(capacity: Self.byteCount)
        writer.append(Self.magic)
        writer.append(Self.version)
        writer.append(kind.rawValue)
        writer.append(sequence)
        writer.append(timestampNanoseconds)
        writer.append(UInt32(payloadSize))
        writer.append(flags)
        return writer.data
    }

    public init(decoding data: Data) throws {
        guard data.count == Self.byteCount else {
            throw AgentSpaceError(code: .badRequest, message: "input header must be exactly \(Self.byteCount) bytes")
        }
        var reader = BinaryReader(data)
        guard try reader.integer(UInt32.self) == Self.magic else {
            throw AgentSpaceError(code: .badRequest, message: "invalid input packet magic")
        }
        guard try reader.integer(UInt16.self) == Self.version else {
            throw AgentSpaceError(code: .protocolMismatch, message: "unsupported input packet version; update AgentSpace so both ends come from one build")
        }
        guard let kind = InputPacketKind(rawValue: try reader.integer(UInt16.self)) else {
            throw AgentSpaceError(code: .badRequest, message: "unknown input packet kind")
        }
        let sequence = try reader.integer(UInt64.self)
        let timestamp = try reader.integer(UInt64.self)
        let payloadSize = try reader.integer(UInt32.self)
        guard payloadSize <= Self.maxPayloadBytes else {
            throw AgentSpaceError(code: .badRequest, message: "input packet payload is \(payloadSize) bytes, over the \(Self.maxPayloadBytes)-byte ceiling")
        }
        self.init(kind: kind, sequence: sequence, timestampNanoseconds: timestamp,
                  flags: try reader.integer(UInt32.self))
        self.payloadSize = payloadSize
    }

    /// Read by the socket layer, which needs it to know how many bytes follow.
    public internal(set) var payloadSize: UInt32 = 0
}

/// Host uptime in nanoseconds: the one clock both ends of a local socket share,
/// which is what makes a client→worker latency a subtraction instead of a
/// comparison of two clocks.
public enum InputClock {
    public static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
}

// MARK: - Binary coding

/// Big-endian writer used by every fixed struct in this file.
public struct BinaryWriter {
    public private(set) var data: Data
    public init(capacity: Int = 64) { data = Data(capacity: capacity) }

    public mutating func append(_ value: UInt8) { data.append(value) }
    public mutating func append(_ value: Int32) { data.appendBigEndian(UInt32(bitPattern: value)) }
    public mutating func append(_ value: UInt32) { data.appendBigEndian(value) }
    public mutating func append(_ value: UInt64) { data.appendBigEndian(value) }
    public mutating func append(_ value: UInt16) { data.appendBigEndian(value) }
    public mutating func append(_ value: Int16) { data.appendBigEndian(UInt16(bitPattern: value)) }
    public mutating func append(_ value: Double) { data.appendBigEndian(value.bitPattern) }
    public mutating func append(_ value: UUID) { withUnsafeBytes(of: value.uuid) { data.append(contentsOf: $0) } }
    public mutating func append(_ bytes: [UInt8]) { data.append(contentsOf: bytes) }
    public mutating func append(_ tail: Data) { data.append(tail) }
}

/// Big-endian reader. Every read is bounds-checked: these bytes arrive over a
/// socket another user can write to.
public struct BinaryReader {
    public let data: Data
    public private(set) var offset = 0

    public init(_ data: Data) { self.data = data }

    public var remaining: Int { data.count - offset }

    public mutating func byte() throws -> UInt8 {
        guard offset < data.count else { throw truncated() }
        defer { offset += 1 }
        return data[offset]
    }

    public mutating func bytes(count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= data.count else { throw truncated() }
        defer { offset += count }
        return Array(data[offset..<(offset + count)])
    }

    public mutating func tail() -> Data { defer { offset = data.count }; return data[offset...] }

    public mutating func integer<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let raw = try bytes(count: MemoryLayout<T>.size)
        return raw.reduce(T.zero) { ($0 << 8) | T($1) }
    }

    public mutating func int16() throws -> Int16 { Int16(bitPattern: try integer(UInt16.self)) }
    public mutating func int32() throws -> Int32 { Int32(bitPattern: try integer(UInt32.self)) }
    public mutating func double() throws -> Double { Double(bitPattern: try integer(UInt64.self)) }
    public mutating func uuid() throws -> UUID {
        let raw = try bytes(count: 16)
        return UUID(uuid: (raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
                           raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]))
    }

    private func truncated() -> AgentSpaceError {
        AgentSpaceError(code: .badRequest, message: "truncated input packet")
    }
}

extension Data {
    /// Appends a fixed-width integer in network byte order. Named differently
    /// from `FrameHeader`'s file-private twin so the two encoders stay
    /// independent: a change made for one wire should not silently move the
    /// other's bytes.
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var big = value.bigEndian
        Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) }
    }
}

// MARK: - Capabilities

/// What one end can do. Negotiated once, at `hello`/`helloAck`, and never
/// assumed: the fallback for every bit here is the behaviour the previous
/// release already had, so a mixed pair of builds degrades to 0.1.37 instead of
/// misunderstanding a field.
public struct InputCapabilities: OptionSet, Sendable, Equatable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// Absolute display points, as the desktop viewer sends them.
    public static let absolutePointer = InputCapabilities(rawValue: 1 << 0)
    /// Window-relative fractions, resolved by the worker against the window's
    /// current frame, as every Fusion proxy sends them.
    public static let windowPointer = InputCapabilities(rawValue: 1 << 1)
    public static let scroll = InputCapabilities(rawValue: 1 << 2)
    public static let keyboard = InputCapabilities(rawValue: 1 << 3)
    /// Explicit `humanAcquire` / `humanRelease`, so a person entering a surface
    /// pauses automation immediately and leaving it resumes immediately.
    public static let leaseControl = InputCapabilities(rawValue: 1 << 4)
    /// The worker publishes the session pointer's position on this socket.
    public static let cursorPosition = InputCapabilities(rawValue: 1 << 5)
    /// …and its shape, which is what allows the viewer to turn the capture's own
    /// cursor off and draw one sprite instead. Only advertised after the worker
    /// has proved to itself that it can read a cursor in its session.
    public static let cursorShapes = InputCapabilities(rawValue: 1 << 6)
    /// Immediate press phases (`pointerDown` before any drag threshold).
    public static let pressPhases = InputCapabilities(rawValue: 1 << 7)
    /// Per-packet apply timestamps in the ack, for the latency instrument.
    public static let applyTimestamps = InputCapabilities(rawValue: 1 << 8)

    /// Everything this build speaks. The wire is additive, so this is also the
    /// set a peer is compared against.
    public static let current: InputCapabilities = [
        .absolutePointer, .windowPointer, .scroll, .keyboard,
        .leaseControl, .cursorPosition, .pressPhases, .applyTimestamps,
    ]

    public var names: [String] {
        var out: [String] = []
        if contains(.absolutePointer) { out.append("absolutePointer") }
        if contains(.windowPointer) { out.append("windowPointer") }
        if contains(.scroll) { out.append("scroll") }
        if contains(.keyboard) { out.append("keyboard") }
        if contains(.leaseControl) { out.append("leaseControl") }
        if contains(.cursorPosition) { out.append("cursorPosition") }
        if contains(.cursorShapes) { out.append("cursorShapes") }
        if contains(.pressPhases) { out.append("pressPhases") }
        if contains(.applyTimestamps) { out.append("applyTimestamps") }
        return out
    }
}

// MARK: - Acknowledgement

/// Why a packet was not applied. The numbering is the wire's; the mapping onto
/// the product's error codes is `errorCode`.
public enum InputAckStatus: Int16, Sendable, Equatable {
    case ok = 0
    case refusedSession = 1
    case refusedDesktopNotReady = 2
    case refusedAccessibility = 3
    case refusedLease = 4
    case invalidPacket = 5
    case invalidTarget = 6
    case invalidCoordinate = 7
    case unsupported = 8
    case internalError = 9

    public var isRefusal: Bool { self != .ok }

    public var agentSpaceCode: AgentSpaceErrorCode {
        switch self {
        case .ok, .internalError: return .internalError
        case .refusedSession: return .sessionIsConsole
        case .refusedDesktopNotReady: return .sessionNotReady
        case .refusedAccessibility: return .accessibilityDenied
        case .refusedLease: return .inputBusyByHuman
        case .invalidPacket, .invalidTarget: return .badRequest
        case .invalidCoordinate: return .invalidCoordinate
        case .unsupported: return .methodNotFound
        }
    }

    public static func forError(_ code: AgentSpaceErrorCode) -> InputAckStatus {
        switch code {
        case .sessionIsConsole: return .refusedSession
        case .sessionNotReady: return .refusedDesktopNotReady
        case .accessibilityDenied: return .refusedAccessibility
        case .inputBusyByHuman: return .refusedLease
        case .invalidCoordinate: return .invalidCoordinate
        case .invalidTarget: return .invalidTarget
        case .badRequest, .invalidAction: return .invalidPacket
        case .methodNotFound, .protocolMismatch: return .unsupported
        default: return .internalError
        }
    }
}

/// What happened to one client packet.
///
/// Ordinary travel is answered only every so often (`InputAckPolicy`), so an
/// ack's `sequence` is the newest packet the worker has applied by that point,
/// not necessarily the one that carried the visible change.
public struct InputAck: Equatable, Sendable {
    public var sequence: UInt64
    public var status: InputAckStatus
    /// The worker's position for the pointer after this packet, in the display
    /// points the desktop viewer speaks. A client that predicted the position
    /// locally compares against this and corrects only when it disagrees.
    public var appliedX: Double
    public var appliedY: Double
    /// Worker-side stamps, in the same host-uptime clock the client uses.
    public var workerReceiveNs: UInt64
    public var cgEventPostedNs: UInt64
    /// Present on refusals: the worker's own words, the same ones the RPC path
    /// would have returned.
    public var message: String?

    public init(sequence: UInt64, status: InputAckStatus, appliedX: Double = 0, appliedY: Double = 0,
                workerReceiveNs: UInt64 = 0, cgEventPostedNs: UInt64 = 0, message: String? = nil) {
        self.sequence = sequence; self.status = status; self.appliedX = appliedX; self.appliedY = appliedY
        self.workerReceiveNs = workerReceiveNs; self.cgEventPostedNs = cgEventPostedNs; self.message = message
    }

    public init(decoding payload: Data) throws {
        var reader = BinaryReader(payload)
        sequence = try reader.integer(UInt64.self)
        guard let status = InputAckStatus(rawValue: try reader.int16()) else {
            throw AgentSpaceError(code: .badRequest, message: "unknown input ack status")
        }
        self.status = status
        _ = try reader.integer(UInt16.self) // reserved, for a future error-code field
        appliedX = try reader.double()
        appliedY = try reader.double()
        workerReceiveNs = try reader.integer(UInt64.self)
        cgEventPostedNs = try reader.integer(UInt64.self)
        let tail = reader.tail()
        message = tail.isEmpty ? nil : String(data: tail, encoding: .utf8)
    }

    public func encoded() -> Data {
        var writer = BinaryWriter(capacity: 44)
        writer.append(sequence)
        writer.append(status.rawValue)
        writer.append(UInt16(0))
        writer.append(appliedX)
        writer.append(appliedY)
        writer.append(workerReceiveNs)
        writer.append(cgEventPostedNs)
        if let message, !message.isEmpty { writer.append(Data(message.utf8)) }
        return writer.data
    }
}

// MARK: - Cursor

/// Where the session's pointer is now, and what it looks like.
///
/// The point of separating this from the frames is arithmetic, not taste: the
/// remote cursor used to be painted *into* the capture, so its newest position
/// could never be younger than the newest frame — 200 ms at the viewer's old
/// 5 FPS default. Position updates are tiny and can arrive at display rate;
/// shape images are kilobytes and change only when the cursor does.
public struct CursorState: Equatable, Sendable {
    public var sequence: UInt64
    public var x: Double
    public var y: Double
    /// A stable identity for the shape: equal ids mean "same sprite", which is
    /// what keeps the image off the wire while the pointer moves.
    public var shapeID: UInt32
    public var hotSpotX: Double
    public var hotSpotY: Double
    public var width: Int
    public var height: Int
    /// BGRA, `width * 4` bytes per row, present only when the shape changed.
    public var image: Data?

    public init(sequence: UInt64, x: Double, y: Double, shapeID: UInt32 = 0,
                hotSpotX: Double = 0, hotSpotY: Double = 0,
                width: Int = 0, height: Int = 0, image: Data? = nil) {
        self.sequence = sequence; self.x = x; self.y = y; self.shapeID = shapeID
        self.hotSpotX = hotSpotX; self.hotSpotY = hotSpotY
        self.width = width; self.height = height; self.image = image
    }

    /// Whether this packet carries a sprite the receiver should cache.
    public var hasImage: Bool { image != nil && width > 0 && height > 0 }

    public init(decoding payload: Data) throws {
        var reader = BinaryReader(payload)
        sequence = try reader.integer(UInt64.self)
        x = try reader.double()
        y = try reader.double()
        shapeID = try reader.integer(UInt32.self)
        hotSpotX = try reader.double()
        hotSpotY = try reader.double()
        width = Int(try reader.integer(UInt32.self))
        height = Int(try reader.integer(UInt32.self))
        let flags = try reader.integer(UInt32.self)
        if flags & 1 == 1 {
            let count = Int(try reader.integer(UInt32.self))
            guard count == width * height * 4, count > 0 else {
                throw AgentSpaceError(code: .badRequest, message: "cursor image does not match its stated size")
            }
            image = Data(try reader.bytes(count: count))
        }
        guard width >= 0, height >= 0, width <= 512, height <= 512 else {
            throw AgentSpaceError(code: .badRequest, message: "cursor image is larger than any real cursor")
        }
    }

    public func encoded() -> Data {
        var writer = BinaryWriter(capacity: 64 + (image?.count ?? 0))
        writer.append(sequence)
        writer.append(x)
        writer.append(y)
        writer.append(shapeID)
        writer.append(hotSpotX)
        writer.append(hotSpotY)
        writer.append(UInt32(width))
        writer.append(UInt32(height))
        if let image, width > 0, height > 0 {
            writer.append(UInt32(1))
            writer.append(UInt32(image.count))
            writer.append(image)
        } else {
            writer.append(UInt32(0))
        }
        return writer.data
    }
}

/// Who owns the session's input right now.
public struct InputLeaseState: Equatable, Sendable {
    public enum Owner: UInt8, Sendable {
        /// Nobody is holding it; automation may post.
        case free = 0
        /// A person is holding it, so automation is refused.
        case human = 1
    }

    public var owner: Owner
    /// The client that took it, so a viewer can tell its own lease from a
    /// sibling window's.
    public var holderPID: Int32
    public var remainingMilliseconds: UInt32

    public init(owner: Owner, holderPID: Int32 = 0, remainingMilliseconds: UInt32 = 0) {
        self.owner = owner; self.holderPID = holderPID; self.remainingMilliseconds = remainingMilliseconds
    }

    public init(decoding payload: Data) throws {
        var reader = BinaryReader(payload)
        guard let owner = Owner(rawValue: try reader.byte()) else {
            throw AgentSpaceError(code: .badRequest, message: "unknown lease owner")
        }
        self.owner = owner
        holderPID = try reader.int32()
        remainingMilliseconds = try reader.integer(UInt32.self)
    }

    public func encoded() -> Data {
        var writer = BinaryWriter(capacity: 9)
        writer.append(owner.rawValue)
        writer.append(holderPID)
        writer.append(remainingMilliseconds)
        return writer.data
    }
}

// MARK: - Handshake

public struct InputHello: Equatable, Sendable {
    public var protocolVersion: UInt16
    public var capabilities: InputCapabilities
    public var clientPID: Int32
    public var spaceID: UUID
    public var token: [UInt8]
    /// Free text for the log only: which surface opened this connection.
    public var clientLabel: String?

    public init(protocolVersion: UInt16 = UInt16(agentSpaceProtocolVersion), capabilities: InputCapabilities = .current,
                clientPID: Int32 = Int32(getpid()), spaceID: UUID, token: SessionToken, clientLabel: String? = nil) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.clientPID = clientPID
        self.spaceID = spaceID
        self.token = Self.tokenBytes(token)
        self.clientLabel = clientLabel
    }

    public static func tokenBytes(_ token: SessionToken) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = token.hex.startIndex
        while index < token.hex.endIndex, let next = token.hex.index(index, offsetBy: 2, limitedBy: token.hex.endIndex) {
            if let byte = UInt8(token.hex[index..<next], radix: 16) { bytes.append(byte) }
            index = next
        }
        return bytes
    }

    public var tokenHex: String { token.map { String(format: "%02x", $0) }.joined() }

    public init(decoding payload: Data) throws {
        var reader = BinaryReader(payload)
        protocolVersion = try reader.integer(UInt16.self)
        capabilities = InputCapabilities(rawValue: try reader.integer(UInt32.self))
        clientPID = try reader.int32()
        spaceID = try reader.uuid()
        token = try reader.bytes(count: SessionToken.byteCount)
        let tail = reader.tail()
        clientLabel = tail.isEmpty ? nil : String(data: tail, encoding: .utf8)
    }

    public func encoded() -> Data {
        var writer = BinaryWriter(capacity: 64)
        writer.append(protocolVersion)
        writer.append(capabilities.rawValue)
        writer.append(clientPID)
        writer.append(spaceID)
        writer.append(token)
        if let clientLabel { writer.append(Data(clientLabel.utf8)) }
        return writer.data
    }
}

public struct InputHelloAck: Equatable, Sendable {
    public var protocolVersion: UInt16
    public var capabilities: InputCapabilities
    public var workerInstanceID: UUID
    public var sessionGeneration: UInt64
    /// The worker's own words for a client that asked for something it cannot
    /// do, so a mixed pair of builds is diagnosable from the log.
    public var workerLabel: String?

    public init(protocolVersion: UInt16 = UInt16(agentSpaceProtocolVersion), capabilities: InputCapabilities,
                workerInstanceID: UUID, sessionGeneration: UInt64, workerLabel: String? = nil) {
        self.protocolVersion = protocolVersion; self.capabilities = capabilities
        self.workerInstanceID = workerInstanceID; self.sessionGeneration = sessionGeneration
        self.workerLabel = workerLabel
    }

    public init(decoding payload: Data) throws {
        var reader = BinaryReader(payload)
        protocolVersion = try reader.integer(UInt16.self)
        capabilities = InputCapabilities(rawValue: try reader.integer(UInt32.self))
        workerInstanceID = try reader.uuid()
        sessionGeneration = try reader.integer(UInt64.self)
        let tail = reader.tail()
        workerLabel = tail.isEmpty ? nil : String(data: tail, encoding: .utf8)
    }

    public func encoded() -> Data {
        var writer = BinaryWriter(capacity: 40)
        writer.append(protocolVersion)
        writer.append(capabilities.rawValue)
        writer.append(workerInstanceID)
        writer.append(sessionGeneration)
        if let workerLabel { writer.append(Data(workerLabel.utf8)) }
        return writer.data
    }
}

// MARK: - Pointer payloads

/// One pointer packet. The same struct serves move, down and up; the kind in
/// the header says which fields matter.
///
/// `clickCount` is additive on the wire and defaults to 1, so a press that
/// carries a double-click means what it means locally: `NSEvent.clickCount` is
/// what makes the second press of a double-click a double-click on the remote
/// side, and without it macOS sees two unrelated clicks.
public struct InputPointerPacket: Equatable, Sendable {
    public static let clickCountDefault: UInt8 = 1

    public var target: InputTarget
    public var x: Double
    public var y: Double
    public var button: MouseButton
    public var clickCount: UInt8
    public var modifiers: [Modifier]

    public init(target: InputTarget, x: Double, y: Double, button: MouseButton = .left,
                clickCount: Int = 1, modifiers: [Modifier] = []) {
        self.target = target; self.x = x; self.y = y; self.button = button
        self.clickCount = UInt8(min(255, max(1, clickCount)))
        self.modifiers = modifiers
    }

    public init(decoding payload: Data) throws {
        var reader = BinaryReader(payload)
        target = try InputTarget(decoding: &reader)
        x = try reader.double()
        y = try reader.double()
        guard let button = MouseButton(wireCode: try reader.byte()) else {
            throw AgentSpaceError(code: .badRequest, message: "unknown mouse button")
        }
        self.button = button
        let count = try reader.byte()
        clickCount = count == 0 ? Self.clickCountDefault : count
        modifiers = Modifier.wireMask(decoding: try reader.integer(UInt16.self))
    }

    public func encoded() -> Data {
        var writer = BinaryWriter(capacity: 48)
        target.encode(into: &writer)
        writer.append(x)
        writer.append(y)
        writer.append(button.wireCode)
        writer.append(clickCount)
        writer.append(Modifier.wireMask(of: modifiers))
        return writer.data
    }
}

public struct InputDragPacket: Equatable, Sendable {
    public var target: InputTarget
    public var fromX: Double
    public var fromY: Double
    public var toX: Double
    public var toY: Double
    public var button: MouseButton
    public var modifiers: [Modifier]

    public init(target: InputTarget, fromX: Double, fromY: Double, toX: Double, toY: Double,
                button: MouseButton = .left, modifiers: [Modifier] = []) {
        self.target = target; self.fromX = fromX; self.fromY = fromY; self.toX = toX; self.toY = toY
        self.button = button; self.modifiers = modifiers
    }

    public init(decoding payload: Data) throws {
        var reader = BinaryReader(payload)
        target = try InputTarget(decoding: &reader)
        fromX = try reader.double()
        fromY = try reader.double()
        toX = try reader.double()
        toY = try reader.double()
        guard let button = MouseButton(wireCode: try reader.byte()) else {
            throw AgentSpaceError(code: .badRequest, message: "unknown mouse button")
        }
        self.button = button
        modifiers = Modifier.wireMask(decoding: try reader.integer(UInt16.self))
    }

    public func encoded() -> Data {
        var writer = BinaryWriter(capacity: 64)
        target.encode(into: &writer)
        writer.append(fromX); writer.append(fromY); writer.append(toX); writer.append(toY)
        writer.append(button.wireCode)
        writer.append(Modifier.wireMask(of: modifiers))
        return writer.data
    }
}

public struct InputScrollPacket: Equatable, Sendable {
    public var target: InputTarget
    public var x: Double
    public var y: Double
    public var dx: Int32
    public var dy: Int32

    public init(target: InputTarget, x: Double, y: Double, dx: Int32, dy: Int32) {
        self.target = target; self.x = x; self.y = y; self.dx = dx; self.dy = dy
    }

    public init(decoding payload: Data) throws {
        var reader = BinaryReader(payload)
        target = try InputTarget(decoding: &reader)
        x = try reader.double(); y = try reader.double()
        dx = try reader.int32(); dy = try reader.int32()
    }

    public func encoded() -> Data {
        var writer = BinaryWriter(capacity: 48)
        target.encode(into: &writer)
        writer.append(x); writer.append(y); writer.append(dx); writer.append(dy)
        return writer.data
    }
}

// MARK: - Modifier wire encoding

extension Modifier {
    /// Bit positions, stable for the life of the protocol.
    public var wireBit: UInt16 {
        switch self {
        case .cmd: return 1 << 0
        case .ctrl: return 1 << 1
        case .alt: return 1 << 2
        case .shift: return 1 << 3
        case .fn: return 1 << 4
        }
    }

    public static let wireOrder: [Modifier] = [.cmd, .ctrl, .alt, .shift, .fn]

    public static func wireMask(of modifiers: [Modifier]) -> UInt16 {
        modifiers.reduce(UInt16(0)) { $0 | $1.wireBit }
    }

    public static func wireMask(decoding mask: UInt16) -> [Modifier] {
        wireOrder.filter { mask & $0.wireBit != 0 }
    }
}

extension MouseButton {
    /// `CGMouseButton` already numbers these; the wire keeps that order.
    public var wireCode: UInt8 {
        switch self {
        case .left: return 0
        case .right: return 1
        case .middle: return 2
        }
    }

    public init?(wireCode: UInt8) {
        switch wireCode {
        case 0: self = .left
        case 1: self = .right
        case 2: self = .middle
        default: return nil
        }
    }
}
