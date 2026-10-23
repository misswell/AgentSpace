import XCTest
import AgentSpaceCore

/// The two pure decisions behind 「复制粘贴进子窗口」: what a clipboard is worth
/// (`ClipboardBridgePolicy`) and whether a keystroke is a clipboard shortcut at
/// all (`ClipboardShortcut`).
///
/// Both are separated from AppKit on purpose, and these tests are what that
/// separation buys: the Desktop Viewer and a Fusion proxy both call the same two
/// functions, so a rule that is wrong here is wrong in two windows at once — and
/// a rule that is untested here can only be checked by pasting into a live agent
/// desktop, which is the instrument that cannot run on a machine a person is
/// using.
///
/// Nothing in this file touches a pasteboard: the clipboard is just text and
/// paths to these functions.
final class ClipboardBridgePolicyTests: XCTestCase {

    private func decision(text: String? = nil, files: [String] = [],
                          unsupported: Bool = false) -> ClipboardBridgePolicy.Decision {
        ClipboardBridgePolicy.decision(text: text, filePaths: files,
                                       hasUnsupportedFormats: unsupported)
    }

    private func paths(_ count: Int) -> [String] {
        (0..<count).map { "/tmp/clipboard-item-\($0).txt" }
    }

    // MARK: - What is worth carrying

    func testPlainTextUnderTheLimitIsBridged() {
        // The common case, and the one the person judges the feature by: a text
        // selection must reach the agent's board rather than the agent's own
        // (empty) clipboard answering the ⌘V.
        XCTAssertEqual(decision(text: "hello 中文"),
                       .bridge(text: "hello 中文", filePaths: []))
    }

    func testAnEmptyClipboardIsForwarded() {
        // An empty board is not a refusal: there is nothing to carry and nothing
        // to explain, so the keystroke is simply sent as it always was.
        XCTAssertEqual(decision(text: nil), .forward)
        XCTAssertEqual(decision(text: ""), .forward)
        XCTAssertEqual(decision(text: "", unsupported: false), .forward)
    }

    func testTextAtTheByteBoundaryBridgesAndOneByteMoreIsRefused() {
        let limit = ClipboardLimits.maxTextBytes
        let atLimit = String(repeating: "a", count: limit)
        XCTAssertEqual(decision(text: atLimit), .bridge(text: atLimit, filePaths: []))

        let overLimit = String(repeating: "a", count: limit + 1)
        XCTAssertEqual(decision(text: overLimit), .refuse(.textTooLarge))

        // The bound counts UTF-8 bytes, not characters: three bytes per CJK
        // scalar means a selection well under 1 MiB *characters* is already over
        // the limit. A character-counting rule would bridge it and the worker
        // would then answer BAD_REQUEST — a paste that fails after the person
        // already pressed ⌘V.
        let cjkAtLimit = String(repeating: "中", count: limit / 3)
        XCTAssertEqual(decision(text: cjkAtLimit),
                       .bridge(text: cjkAtLimit, filePaths: []))
        let cjkOverLimit = String(repeating: "中", count: limit / 3 + 1)
        XCTAssertEqual(decision(text: cjkOverLimit), .refuse(.textTooLarge))
    }

    func testThirtyTwoFilesBridgeAndThirtyThreeAreRefused() {
        // 32 is the number a person can select in the Finder without thinking
        // about it; the bound exists because each entry costs a pasteboard item.
        // Off by one in either direction is a paste that silently drops a file or
        // one that refuses a normal selection.
        XCTAssertEqual(decision(files: paths(ClipboardLimits.maxFiles)),
                       .bridge(text: nil, filePaths: paths(ClipboardLimits.maxFiles)))
        XCTAssertEqual(decision(files: paths(ClipboardLimits.maxFiles + 1)),
                       .refuse(.tooManyFiles))
    }

    func testFilesAndTextTravelTogether() {
        // An app that copies a selection plus a file reference writes both; the
        // two are independent and neither may be dropped for the other.
        XCTAssertEqual(decision(text: "note", files: ["/tmp/report.pdf"]),
                       .bridge(text: "note", filePaths: ["/tmp/report.pdf"]))
    }

    func testAClipboardWithOnlyUncarriedFormatsIsRefusedWithAReason() {
        // An image is the gap a person will actually hit. Forwarding silently
        // would make it look like the product pasted the wrong thing; the
        // refusal is what turns "broken" into "this content is not carried yet".
        let refusal = decision(unsupported: true)
        XCTAssertEqual(refusal, .refuse(.unsupportedFormats))
        // The keystroke still goes through on a refusal — a refusal must never
        // look like a dead keyboard.
        XCTAssertTrue(refusal.forwardsImmediately)

        for (label, decision) in [("unsupported", refusal),
                                  ("textTooLarge", decision(text: String(repeating: "a",
                                                                         count: ClipboardLimits.maxTextBytes + 1))),
                                  ("tooManyFiles", decision(files: paths(ClipboardLimits.maxFiles + 1)))] {
            if case .refuse(let reason) = decision {
                XCTAssertFalse(reason.message.isEmpty, "\(label) must say why")
            } else {
                XCTFail("\(label) was not a refusal: \(decision)")
            }
        }
        // Each refusal explains its own cause; a shared "not supported" sentence
        // would tell a person nothing about what to do with their clipboard.
        XCTAssertNotEqual(ClipboardBridgePolicy.Refusal.textTooLarge.message,
                          ClipboardBridgePolicy.Refusal.tooManyFiles.message)
        XCTAssertNotEqual(ClipboardBridgePolicy.Refusal.unsupportedFormats.message,
                          ClipboardBridgePolicy.Refusal.textTooLarge.message)
        XCTAssertNotEqual(ClipboardBridgePolicy.Refusal.unsupportedFormats.message,
                          ClipboardBridgePolicy.Refusal.tooManyFiles.message)
        // The English source text is the key, so a test bundle with no .lproj
        // still sees the sentence a person reads.
        let unsupported = ClipboardBridgePolicy.Refusal.unsupportedFormats.message
        XCTAssertTrue(unsupported.lowercased().contains("image")
                      || unsupported.lowercased().contains("rich text"),
                      "the message must name the gap: \(unsupported)")
    }

    func testCarryableContentWinsOverAnUncarriedFormat() {
        // A rich-text copy usually carries plain text as well. Refusing because
        // *something* extra is present would drop a paste that works.
        XCTAssertEqual(decision(text: "hello", unsupported: true),
                       .bridge(text: "hello", filePaths: []))
    }

    func testTheTextLimitIsDecidedBeforeTheFileCount() {
        // Both over budget at once: the answer has to be one deterministic
        // reason, or two hosts could tell the same person two different things
        // about the same clipboard. Text is checked first because the text
        // size is one count on a string already in hand, while the file count
        // is the list that would be walked next.
        XCTAssertEqual(decision(text: String(repeating: "a", count: ClipboardLimits.maxTextBytes + 1),
                                files: paths(ClipboardLimits.maxFiles + 1)),
                       .refuse(.textTooLarge))
    }

    // MARK: - Which keystroke is a clipboard shortcut

    private func intent(_ characters: String?, ignoring: String? = nil,
                        command: Bool = true, control: Bool = false)
        -> ClipboardShortcut.Intent? {
        ClipboardShortcut.intent(characters: characters,
                                 charactersIgnoringModifiers: ignoring ?? characters,
                                 command: command, control: control)
    }

    func testCommandVAndCommandCAreTheClipboardShortcuts() {
        XCTAssertEqual(intent("v"), .pasteIntoAgent)
        XCTAssertEqual(intent("c"), .copyFromAgent)
        // A different letter is typing, not a clipboard operation.
        XCTAssertNil(intent("x"))
    }

    func testExtraModifiersKeepTheClipboardIntent() {
        // ⌘⇧V is "paste and match style" and ⌘⌥C copies a style attribute; both
        // are a paste or a copy as far as the board is concerned. The event's
        // `characters` is shift-composed ("V") while the ignoring-modifiers base
        // is not, and either spelling has to resolve.
        XCTAssertEqual(intent("V", ignoring: "v"), .pasteIntoAgent)
        XCTAssertEqual(intent("V"), .pasteIntoAgent)
        XCTAssertEqual(intent("C", ignoring: "c"), .copyFromAgent)
    }

    func testControlVIsNotTheClipboardShortcut() {
        // Control-V is the Emacs-style paste of a terminal, not a macOS
        // clipboard operation: the agent's own board answers it, and bridging it
        // would put the person's selection into a shell they did not aim at.
        XCTAssertNil(intent("v", control: true))
        // Even with Command also held — "command wins" is not the rule, the rule
        // is that a Control-modified keystroke is not this shortcut.
        XCTAssertNil(intent("v", command: true, control: true))
        XCTAssertNil(intent("c", command: true, control: true))
    }

    func testAPlainLetterIsNotAClipboardShortcut() {
        // Without Command there is no clipboard operation on macOS; a bare "v"
        // is typing.
        XCTAssertNil(intent("v", command: false))
        XCTAssertNil(intent("c", command: false))
    }

    func testAKeyNameIsNotALetter() {
        // The event's ignoring-modifiers string is a *key name* for special keys
        // ("left", "return", "f5") and can be empty. Treating a multi-character
        // string as a letter would make a key name that happens to start with
        // "v" a paste.
        XCTAssertNil(intent("left", ignoring: "left"))
        XCTAssertNil(intent("vv", ignoring: "vv"))
        XCTAssertNil(intent("v", ignoring: ""))
        XCTAssertNil(intent(nil))
        // An event that carries no ignoring-modifiers string at all (a function
        // key, or an event read from a tap without the field) cannot be a letter.
        XCTAssertNil(ClipboardShortcut.intent(characters: "v",
                                             charactersIgnoringModifiers: nil,
                                             command: true, control: false))
    }
}
