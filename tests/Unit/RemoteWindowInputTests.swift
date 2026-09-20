import XCTest
import AgentSpaceCore

/// What a Fusion proxy's action becomes once the worker resolves it.
///
/// The proxy sends fractions of its own window and the vocabulary the desktop
/// path already uses; this is the seam where the two meet, so it is where the
/// ways they can disagree are pinned — a drag whose press is named `x` instead
/// of `fromX` is rejected by the parser, and a click that loses its modifier
/// silently does the wrong thing on the agent's screen.
final class RemoteWindowInputTests: XCTestCase {
    /// A 400×200 window with its origin at (200, 100).
    private let window = RemoteWindow(
        id: 42, pid: 7, appName: "TextEdit", bundleIdentifier: nil, title: nil,
        frame: CGRectValue(x: 200, y: 100, width: 400, height: 200),
        layer: 0, visible: true, minimized: false, generation: 1)

    private func action(_ json: String) throws -> InputAction {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return try RemoteWindowInput.action(from: .object(["action": value]), window: window)
    }

    private func failure(_ json: String) -> AgentSpaceError {
        let data = Data(json.utf8)
        let value = try! JSONDecoder().decode(JSONValue.self, from: data)
        do {
            _ = try RemoteWindowInput.action(from: .object(["action": value]), window: window)
        } catch let error as AgentSpaceError {
            return error
        } catch {
            return AgentSpaceError(code: .internalError, message: "unexpected error: \(error)")
        }
        XCTFail("expected \(json) to be refused")
        return AgentSpaceError(code: .internalError, message: "not refused")
    }

    func testPointerFractionsResolveIntoTheWindowsOwnFrame() throws {
        XCTAssertEqual(
            try action(#"{"type":"click","xFraction":0.5,"yFraction":0.25}"#),
            .click(x: 400, y: 150, button: .left, count: 1, modifiers: []))
    }

    /// The press is the drag's *start*, which the parser names `fromX`/`fromY`.
    /// A drag built the way a click is gets rejected, and the proxy's gesture
    /// never reaches the agent.
    func testProxyDragParsesAsADragAndKeepsBothEnds() throws {
        XCTAssertEqual(
            try action(#"{"type":"drag","xFraction":0,"yFraction":0,"toXFraction":1,"toYFraction":1}"#),
            .drag(fromX: 200, fromY: 100, toX: 600, toY: 300, button: .left, modifiers: []))
    }

    /// Which button and which modifiers were held is the difference between a
    /// selection and a context menu, so it survives the mapping verbatim.
    func testGestureAttributesReachTheSharedVocabulary() throws {
        XCTAssertEqual(
            try action(#"{"type":"drag","xFraction":0.1,"yFraction":0.1,"toXFraction":0.9,"toYFraction":0.2,"button":"right","modifiers":["cmd","shift"]}"#),
            .drag(fromX: 240, fromY: 120, toX: 560, toY: 140, button: .right, modifiers: [.cmd, .shift]))
        XCTAssertEqual(
            try action(#"{"type":"click","xFraction":0,"yFraction":0,"button":"left","count":2,"modifiers":["alt"]}"#),
            .click(x: 200, y: 100, button: .left, count: 2, modifiers: [.alt]))
        XCTAssertEqual(
            try action(#"{"type":"rightClick","xFraction":0,"yFraction":0}"#),
            .click(x: 200, y: 100, button: .right, count: 1, modifiers: []))
    }

    /// Pointer travel is the one input that must stay a `move`, because the
    /// worker treats a hover differently from every other action.
    func testTravelIsAMoveAndStaysAHover() throws {
        let parsed = try action(#"{"type":"move","xFraction":0.25,"yFraction":0.75}"#)
        XCTAssertEqual(parsed, .move(x: 300, y: 250))
        XCTAssertTrue(parsed.isHover)
    }

    func testScrollDeltasPassThroughWithTheirPosition() throws {
        XCTAssertEqual(
            try action(#"{"type":"scroll","xFraction":0.5,"yFraction":0.5,"dx":3,"dy":-2}"#),
            .scroll(x: 400, y: 200, dx: 3, dy: -2))
    }

    /// Text and key combinations carry no window geometry, so there is nothing
    /// to resolve — and nothing to lose by routing them through the same door.
    func testTypingAndKeysAreParsedUnchanged() throws {
        XCTAssertEqual(try action(#"{"type":"type","text":"hi"}"#), .type(text: "hi"))
        XCTAssertEqual(try action(#"{"type":"key","key":"cmd+c"}"#), .key(combo: "cmd+c"))
    }

    func testRefusalsSayWhichPartIsWrong() {
        XCTAssertEqual(failure(#"{"type":"click","xFraction":1.5,"yFraction":0}"#).code, .invalidCoordinate)
        XCTAssertEqual(failure(#"{"type":"click"}"#).code, .invalidCoordinate)
        XCTAssertEqual(
            failure(#"{"type":"drag","xFraction":0,"yFraction":0}"#).code, .invalidCoordinate)
        XCTAssertEqual(failure(#"{"type":"sleep","ms":5}"#).code, .invalidAction)
        XCTAssertEqual(failure(#"{"xFraction":0,"yFraction":0}"#).code, .invalidAction)
    }

    /// A modifier the protocol does not know is a refused action, not a click
    /// quietly sent without it.
    func testAnUnknownModifierIsRefusedNotDropped() {
        let error = failure(
            #"{"type":"click","xFraction":0,"yFraction":0,"modifiers":["hyper"]}"#)
        XCTAssertEqual(error.code, .invalidAction)
        XCTAssertTrue(error.message.contains("modifiers"), error.message)
    }

    /// `window.input` without an `action` at all: the request is malformed, and
    /// the worker must not guess which window region the caller meant.
    func testARequestWithoutAnActionIsRefused() {
        do {
            _ = try RemoteWindowInput.action(from: .object([:]), window: window)
            XCTFail("expected a refusal")
        } catch let error as AgentSpaceError {
            XCTAssertEqual(error.code, .invalidAction)
        } catch {
            XCTFail("expected an AgentSpaceError, got \(error)")
        }
    }
}
