import XCTest
import AgentSpaceCore

/// Pins the viewer's keyboard translation — plan §17's "键盘输入也一样"
/// and §52's 输入. The function is pure, so these test the exact contract
/// the NSEvent local monitor relies on without synthesising events.
final class KeyboardForwardingTests: XCTestCase {

    private func action(
        _ characters: String?,
        ignoring: String? = nil,
        command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false
    ) -> InputAction? {
        KeyboardForwarding.action(
            characters: characters,
            charactersIgnoringModifiers: ignoring ?? characters,
            command: command, shift: shift, option: option, control: control)
    }

    func testAPrintableCharacterIsTyped() {
        XCTAssertEqual(action("h"), .type(text: "h"))
    }

    func testAShiftComposedCapitalIsTypedAsItAppears() {
        // The layout already produced "A"; forwarding the character is more
        // faithful than re-deriving shift+a.
        XCTAssertEqual(action("A"), .type(text: "A"))
    }

    func testAnOptionComposedCharacterStaysText() {
        // Option alone is how a Mac types å — not a shortcut.
        XCTAssertEqual(action("å", ignoring: "a", option: true), .type(text: "å"))
    }

    func testReturnIsACombo() {
        XCTAssertEqual(action("\r"), .key(combo: "return"))
    }

    func testCommandReturnKeepsItsModifier() {
        XCTAssertEqual(action("\r", command: true), .key(combo: "cmd+return"))
    }

    func testCommandCIsAComboNotText() {
        XCTAssertEqual(action("c", command: true), .key(combo: "cmd+c"))
    }

    func testCommandShiftTIsCanonicalOrder() {
        XCTAssertEqual(action("t", ignoring: "T", command: true, shift: true), .key(combo: "cmd+shift+t"))
    }

    func testControlTabKeepsItsModifier() {
        XCTAssertEqual(action("\t", control: true), .key(combo: "ctrl+tab"))
    }

    func testAnArrowKeyIsACombo() {
        XCTAssertEqual(action("\u{F702}"), .key(combo: "left"))
    }

    func testCommandLeftIsACombo() {
        XCTAssertEqual(action("\u{F702}", command: true), .key(combo: "cmd+left"))
    }

    func testAnFKeyIsACombo() {
        XCTAssertEqual(action("\u{F704}"), .key(combo: "f1"))
        XCTAssertEqual(action("\u{F70F}"), .key(combo: "f12"))
    }

    func testAnUnknownPrivateUseCharacterIsIgnored() {
        XCTAssertNil(action("\u{F810}"))
    }

    func testAnUntranslatableControlCharacterIsIgnored() {
        // ctrl+a synthesises 0x01 when not intercepted; there is no faithful
        // combo for it without the ignoring-modifiers base, so drop it.
        XCTAssertNil(action("\u{01}"))
    }

    func testCommandOnABaseOutsideTheTableIsIgnored() {
        // No keycode entry for "é" as a base — guessing would be wrong.
        XCTAssertNil(action("é", ignoring: "é", command: true))
    }
}
