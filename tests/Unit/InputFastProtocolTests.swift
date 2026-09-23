import XCTest
import CoreGraphics
@testable import AgentSpaceCore

/// The fast input channel's binary framing.
///
/// These are the tests that make the wire safe to change: every struct here is
/// read from bytes another process wrote, so a field that decodes differently
/// than it encodes is a corrupted click rather than a compile error.
final class InputFastProtocolTests: XCTestCase {

    func testHeaderRoundTripsEveryField() throws {
        let header = InputPacketHeader(kind: .pointerDrag, sequence: 42,
                                       timestampNanoseconds: 1_234_567_890, flags: 0xAB)
        let encoded = header.encoded(payloadSize: 96)
        XCTAssertEqual(encoded.count, InputPacketHeader.byteCount)
        let decoded = try InputPacketHeader(decoding: encoded)
        XCTAssertEqual(decoded.kind, .pointerDrag)
        XCTAssertEqual(decoded.sequence, 42)
        XCTAssertEqual(decoded.timestampNanoseconds, 1_234_567_890)
        XCTAssertEqual(decoded.flags, 0xAB)
        XCTAssertEqual(decoded.payloadSize, 96)
    }

    /// The magic is what stops a client from framing another socket's bytes as
    /// packets — the frame socket and this one carry binary records of their own.
    func testAWrongMagicIsRefusedAndNotFramedSpeculatively() {
        var encoded = InputPacketHeader(kind: .pointerMove).encoded(payloadSize: 0)
        encoded[0] = 0x00
        XCTAssertThrowsError(try InputPacketHeader(decoding: encoded)) { error in
            XCTAssertEqual((error as? AgentSpaceError)?.code, .badRequest)
        }
    }

    /// A future protocol speaks a version this build does not, and the answer is
    /// a named mismatch rather than a guess at the layout.
    func testAnUnknownVersionIsAProtocolMismatchRatherThanGarbage() {
        var encoded = InputPacketHeader(kind: .pointerMove).encoded(payloadSize: 0)
        encoded[4] = 0
        encoded[5] = 99
        XCTAssertThrowsError(try InputPacketHeader(decoding: encoded)) { error in
            XCTAssertEqual((error as? AgentSpaceError)?.code, .protocolMismatch)
        }
    }

    /// A hostile or broken peer must not be able to make the worker allocate: the
    /// declared payload size is checked before a single byte of it is read.
    func testAnOversizedPayloadIsRefusedBeforeItIsRead() {
        let header = InputPacketHeader(kind: .type)
        let tooBig = InputPacketHeader(kind: .type).encoded(payloadSize: InputPacketHeader.maxPayloadBytes + 1)
        XCTAssertThrowsError(try InputPacketHeader(decoding: tooBig))
        let absurd = InputPacketHeader(kind: .type).encoded(payloadSize: Int(UInt32.max))
        XCTAssertThrowsError(try InputPacketHeader(decoding: absurd))
    }

    func testPointerPacketRoundTripsIncludingClickCountAndModifiers() throws {
        let packet = InputPointerPacket(target: .desktop, x: 1234.5, y: 678.25,
                                       button: .right, clickCount: 3,
                                       modifiers: [.cmd, .shift, .alt])
        let decoded = try InputPointerPacket(decoding: packet.encoded())
        XCTAssertEqual(decoded.target, .desktop)
        XCTAssertEqual(decoded.x, 1234.5)
        XCTAssertEqual(decoded.y, 678.25)
        XCTAssertEqual(decoded.button, .right)
        XCTAssertEqual(decoded.clickCount, 3)
        XCTAssertEqual(decoded.modifiers, [.cmd, .alt, .shift])
    }

    /// A click count of zero on the wire is not "no clicks" — it is an older
    /// client that did not send the field, and one click is what its absence has
    /// always meant.
    func testAMissingClickCountMeansOneClick() throws {
        var writer = BinaryWriter()
        InputTarget.desktop.encode(into: &writer)
        writer.append(10.0); writer.append(20.0)
        writer.append(MouseButton.left.wireCode)
        writer.append(UInt8(0))
        writer.append(UInt16(0))
        let decoded = try InputPointerPacket(decoding: writer.data)
        XCTAssertEqual(decoded.clickCount, 1)
    }

    func testWindowTargetRoundTripsItsIdentity() throws {
        let identity = WindowIdentity(pid: 4242, windowID: 77, generation: 9)
        let packet = InputPointerPacket(target: .window(identity), x: 0.25, y: 0.75)
        let decoded = try InputPointerPacket(decoding: packet.encoded())
        XCTAssertEqual(decoded.target, .window(identity))
        XCTAssertTrue(decoded.target.isWindowRelative)
        XCTAssertEqual(decoded.x, 0.25)
    }

    func testCursorStateRoundTripsWithAndWithoutAnImage() throws {
        let withoutImage = CursorState(sequence: 5, x: 100, y: 200, shapeID: 0xDEADBEEF,
                                       hotSpotX: 1, hotSpotY: 1, width: 0, height: 0)
        let plain = try CursorState(decoding: withoutImage.encoded())
        XCTAssertEqual(plain.shapeID, 0xDEADBEEF)
        XCTAssertNil(plain.image)
        XCTAssertFalse(plain.hasImage)

        let pixels = Data(repeating: 0x7F, count: 4 * 4 * 4)
        let withImage = CursorState(sequence: 6, x: 1, y: 2, shapeID: 7,
                                    hotSpotX: 0.5, hotSpotY: 0.5, width: 4, height: 4, image: pixels)
        let decoded = try CursorState(decoding: withImage.encoded())
        XCTAssertTrue(decoded.hasImage)
        XCTAssertEqual(decoded.image, pixels)
        XCTAssertEqual(decoded.width, 4)
    }

    /// The image's own size and the pixel count it claims must agree, or a client
    /// would draw whatever the bytes happened to describe.
    func testACursorImageThatDisagreesWithItsSizeIsRefused() {
        let bad = CursorState(sequence: 1, x: 0, y: 0, shapeID: 1, width: 8, height: 8,
                              image: Data(repeating: 0, count: 10))
        XCTAssertThrowsError(try CursorState(decoding: bad.encoded()))
    }

    func testAckRoundTripsIncludingARefusalMessage() throws {
        let ack = InputAck(sequence: 900, status: .refusedSession,
                           appliedX: 10, appliedY: 20,
                           workerReceiveNs: 111, cgEventPostedNs: 222,
                           message: "the session is on the console")
        let decoded = try InputAck(decoding: ack.encoded())
        XCTAssertEqual(decoded, ack)
        XCTAssertTrue(decoded.status.isRefusal)
        XCTAssertEqual(decoded.status.agentSpaceCode, .sessionIsConsole)
    }

    func testHelloCarriesTheTokenAsBytesAndChecksOutAsHex() throws {
        let token = SessionToken(hex: String(repeating: "ab", count: 32))
        let hello = InputHello(spaceID: UUID(), token: token, clientLabel: "desktop viewer")
        XCTAssertEqual(hello.token.count, SessionToken.byteCount)
        XCTAssertEqual(hello.tokenHex, token.hex)
        let decoded = try InputHello(decoding: hello.encoded())
        XCTAssertEqual(decoded.tokenHex, token.hex)
        XCTAssertEqual(decoded.clientLabel, "desktop viewer")
        XCTAssertTrue(SessionToken(hex: decoded.tokenHex).isValidShape)
    }

    func testHelloAckRoundTripsCapabilities() throws {
        let ack = InputHelloAck(capabilities: [.absolutePointer, .leaseControl, .cursorShapes],
                                workerInstanceID: UUID(), sessionGeneration: 12345,
                                workerLabel: "agentspace-worker test")
        let decoded = try InputHelloAck(decoding: ack.encoded())
        XCTAssertEqual(decoded, ack)
        XCTAssertTrue(decoded.capabilities.contains(.cursorShapes))
        XCTAssertFalse(decoded.capabilities.contains(.scroll))
    }

    /// Every kind has exactly one direction, and a peer that sends the other
    /// end's packets is refused rather than interpreted.
    func testDirectionIsEnforcedPerKind() {
        for kind in InputPacketKind.allCases {
            let fromClient = InputPacketDirection.clientToWorker.permits(kind)
            let fromWorker = InputPacketDirection.workerToClient.permits(kind)
            XCTAssertNotEqual(fromClient, fromWorker, "\(kind) must belong to exactly one direction")
        }
        XCTAssertTrue(InputPacketDirection.clientToWorker.permits(.pointerMove))
        XCTAssertFalse(InputPacketDirection.clientToWorker.permits(.cursor))
        XCTAssertTrue(InputPacketDirection.workerToClient.permits(.cursor))
        XCTAssertFalse(InputPacketDirection.workerToClient.permits(.humanAcquire))
    }

    func testCapabilityNamesCoverEveryBitThisBuildSpeaks() {
        XCTAssertEqual(Set(InputCapabilities.current.names), Set([
            "absolutePointer", "windowPointer", "scroll", "keyboard",
            "leaseControl", "cursorPosition", "pressPhases", "applyTimestamps",
        ]))
        // `cursorShapes` is deliberately absent from `current`: a worker adds it
        // only after proving it can read a cursor in its own session.
        XCTAssertFalse(InputCapabilities.current.contains(.cursorShapes))
    }

    func testAckStatusMapsOntoTheProductsOwnErrorCodes() {
        XCTAssertEqual(InputAckStatus.refusedSession.agentSpaceCode, .sessionIsConsole)
        XCTAssertEqual(InputAckStatus.refusedLease.agentSpaceCode, .inputBusyByHuman)
        XCTAssertEqual(InputAckStatus.refusedAccessibility.agentSpaceCode, .accessibilityDenied)
        XCTAssertEqual(InputAckStatus.refusedDesktopNotReady.agentSpaceCode, .sessionNotReady)
        XCTAssertEqual(InputAckStatus.invalidCoordinate.agentSpaceCode, .invalidCoordinate)
        XCTAssertEqual(InputAckStatus.forError(.sessionIsConsole), .refusedSession)
        XCTAssertEqual(InputAckStatus.forError(.invalidTarget), .invalidTarget)
    }

    /// Travel is sampled and events are not. This is the rule that keeps the
    /// channel from becoming a request/reply per move *and* keeps a refusal
    /// invisible for at most one press.
    func testTravelIsSampledAndEventsAreAlwaysAcknowledged() {
        let policy = InputAckPolicy(travelSampleInterval: 4)
        var acknowledged: UInt64 = 0
        var travelAcks = 0
        for sequence in UInt64(1)...UInt64(16) {
            if policy.shouldAcknowledge(kind: .pointerMove, after: &acknowledged, sequence: sequence, refusal: nil, previousRefusal: nil) {
                travelAcks += 1
            }
        }
        XCTAssertEqual(travelAcks, 4, "one travel ack per sample interval")

        let second = InputAckPolicy(travelSampleInterval: 4)
        var seen: UInt64 = 0
        for kind in [InputPacketKind.pointerDown, .pointerDrag, .pointerUp, .scroll, .key, .type] {
            XCTAssertTrue(second.shouldAcknowledge(kind: kind, after: &seen, sequence: seen + 1, refusal: nil, previousRefusal: nil),
                          "\(kind) has a consequence the person is about to look at")
        }
    }

    /// A flood of refusals must not be answered packet for packet. This is not
    /// hypothetical: measured on a console session, one refusal per move filled
    /// the socket buffer until the worker's own write blocked and the connection
    /// died on a send timeout — the failure the product would see as "the input
    /// channel keeps dropping" while every packet was being answered correctly.
    func testAFloodOfRefusalsIsSampledRatherThanEchoed() {
        let policy = InputAckPolicy(refusalSampleInterval: 32)
        var acknowledged: UInt64 = 0
        var sent = 0
        // The run has already announced itself (see the transition test below),
        // so every packet here is a repeat of a refusal the client knows.
        for sequence in UInt64(1)...UInt64(500) {
            if policy.shouldAcknowledge(kind: .pointerMove, after: &acknowledged, sequence: sequence,
                                        refusal: .refusedSession, previousRefusal: .refusedSession) {
                sent += 1
            }
        }
        // One per interval across 500 packets, rather than 500 of them.
        XCTAssertEqual(sent, 500 / 32, "500 copies of one refusal become a handful of messages")
    }

    /// The *first* refusal is never suppressed: it is the transition from
    /// "working" to "the session will not accept input", and a client that missed
    /// it would keep drawing a cursor it moved locally.
    func testTheFirstRefusalOfARunIsAlwaysSent() {
        let policy = InputAckPolicy(refusalSampleInterval: 32)
        var acknowledged: UInt64 = 0
        XCTAssertTrue(policy.shouldAcknowledge(kind: .pointerMove, after: &acknowledged, sequence: 1,
                                               refusal: .refusedSession, previousRefusal: nil))
        // …and a *different* refusal afterwards is a new transition, so it goes out
        // too, however recently the last one was sent.
        XCTAssertTrue(policy.shouldAcknowledge(kind: .pointerMove, after: &acknowledged, sequence: 2,
                                               refusal: .refusedAccessibility, previousRefusal: .refusedSession))
    }

    /// A move that arrives before the interval is *not* acknowledged, which is
    /// what makes the acknowledgement rate a policy rather than a property of
    /// every packet.
    func testConsecutiveMovesInsideTheIntervalAreNotAllAcknowledged() {
        let policy = InputAckPolicy(travelSampleInterval: 8)
        var acknowledged: UInt64 = 0
        XCTAssertTrue(policy.shouldAcknowledge(kind: .pointerMove, after: &acknowledged, sequence: 8, refusal: nil, previousRefusal: nil))
        for sequence in UInt64(9)...UInt64(15) {
            XCTAssertFalse(policy.shouldAcknowledge(kind: .pointerMove, after: &acknowledged, sequence: sequence, refusal: nil, previousRefusal: nil))
        }
        XCTAssertTrue(policy.shouldAcknowledge(kind: .pointerMove, after: &acknowledged, sequence: 16, refusal: nil, previousRefusal: nil))
    }
}
