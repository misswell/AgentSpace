import XCTest
import AgentSpaceCore

final class InputActionTests: XCTestCase {

    private func parse(_ json: String) -> Result<[InputAction], AgentSpaceError> {
        guard let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .failure(AgentSpaceError(code: .badRequest, message: "test JSON did not decode"))
        }
        return InputAction.parseBatch(value)
    }

    // MARK: Happy paths

    /// The plan's §14 example batch is *almost* accepted. It is asserted here as
    /// a rejection on purpose, to pin the one place this implementation deviates
    /// from the example rather than letting the difference live only in prose:
    /// its `click` carries no coordinates.
    func testPlanExampleBatchIsRejectedOnlyForTheCoordinateLessClick() {
        let result = parse("""
        [
          {"type": "move", "x": 500, "y": 300},
          {"type": "click", "button": "left"},
          {"type": "type", "text": "hello"},
          {"type": "key", "keys": ["cmd", "enter"]}
        ]
        """)
        guard case .failure(let error) = result else {
            return XCTFail("expected the coordinate-less click to be rejected")
        }
        XCTAssertEqual(error.code, .invalidAction)
        XCTAssertTrue(error.message.contains("action 1"), error.message)
        XCTAssertTrue(error.message.contains("requires numeric x and y"), error.message)
    }

    /// With coordinates supplied the same batch is accepted, and the `key`
    /// action uses the plan's `keys: [...]` spelling.
    func testPlanExampleBatchWithClickCoordinatesIsAccepted() {
        let result = parse("""
        [
          {"type": "move", "x": 500, "y": 300},
          {"type": "click", "x": 500, "y": 300, "button": "left"},
          {"type": "type", "text": "hello"},
          {"type": "key", "keys": ["cmd", "enter"]}
        ]
        """)
        guard case .success(let actions) = result else {
            return XCTFail("the corrected batch should parse")
        }
        XCTAssertEqual(actions.count, 4)
        XCTAssertEqual(actions[0], .move(x: 500, y: 300))
        guard case .key(let combo) = actions[3] else { return XCTFail("expected a key action") }
        XCTAssertEqual(combo, "cmd+enter")
    }

    func testClickRequiresCoordinates() {
        // Documented deviation from the plan's §14 example: a click without
        // coordinates cannot be routed, so it is INVALID_ACTION rather than a
        // click at the current pointer position.
        let result = parse(#"[{"type":"click","button":"left"}]"#)
        guard case .failure(let error) = result else {
            return XCTFail("click without coordinates should be rejected")
        }
        XCTAssertEqual(error.code, .invalidAction)
        XCTAssertTrue(error.message.contains("requires numeric x and y"), error.message)
    }

    func testClickWithCoordinates() {
        let result = parse(#"[{"type":"click","x":10,"y":20,"button":"right","count":2,"modifiers":["cmd","shift"]}]"#)
        guard case .success(let actions) = result else {
            return XCTFail("should parse")
        }
        XCTAssertEqual(actions[0], .click(x: 10, y: 20, button: .right, count: 2, modifiers: [.cmd, .shift]))
    }

    func testDoubleClickShorthand() {
        let result = parse(#"[{"type":"doubleClick","x":1,"y":2}]"#)
        guard case .success(let actions) = result else { return XCTFail("should parse") }
        XCTAssertEqual(actions[0], .click(x: 1, y: 2, button: .left, count: 2, modifiers: []))
    }

    func testRightClickShorthand() {
        let result = parse(#"[{"type":"rightClick","x":1,"y":2}]"#)
        guard case .success(let actions) = result else { return XCTFail("should parse") }
        if case .click(_, _, let button, _, _) = actions[0] {
            XCTAssertEqual(button, .right)
        } else {
            XCTFail("expected a click")
        }
    }

    func testKeyAcceptsBothSpellings() {
        // Plan §14 uses `keys: [...]`; the CLI uses `key: "cmd+l"`. Both must
        // produce the same event.
        guard case .success(let fromArray) = parse(#"[{"type":"key","keys":["cmd","l"]}]"#) else {
            return XCTFail("array form should parse")
        }
        guard case .success(let fromCombo) = parse(#"[{"type":"key","key":"cmd+l"}]"#) else {
            return XCTFail("combo form should parse")
        }
        guard case .key(let a) = fromArray[0], case .key(let b) = fromCombo[0] else {
            return XCTFail("expected key actions")
        }
        guard case .success(let parsedA) = KeyCombo.parse(a),
              case .success(let parsedB) = KeyCombo.parse(b) else {
            return XCTFail("both combos should resolve")
        }
        XCTAssertEqual(parsedA.keyCode, parsedB.keyCode)
        XCTAssertEqual(parsedA.flags, parsedB.flags)
    }

    func testSleepAliases() {
        guard case .success(let a) = parse(#"[{"type":"sleep","ms":250}]"#) else { return XCTFail() }
        guard case .success(let b) = parse(#"[{"type":"wait","ms":250}]"#) else { return XCTFail() }
        XCTAssertEqual(a[0], .sleep(ms: 250))
        XCTAssertEqual(b[0], .sleep(ms: 250))
    }

    func testScrollDefaults() {
        guard case .success(let actions) = parse(#"[{"type":"scroll","dy":-500}]"#) else { return XCTFail() }
        XCTAssertEqual(actions[0], .scroll(x: nil, y: nil, dx: 0, dy: -500))
    }

    func testDragParses() {
        guard case .success(let actions) = parse("""
        [{"type":"drag","fromX":100,"fromY":100,"toX":500,"toY":500}]
        """) else { return XCTFail() }
        XCTAssertEqual(actions[0], .drag(fromX: 100, fromY: 100, toX: 500, toY: 500, button: .left, modifiers: []))
    }

    // MARK: All-or-nothing

    /// The central contract: one bad action means *nothing* is performed.
    func testOneBadActionRejectsTheWholeBatch() {
        let result = parse("""
        [
          {"type": "move", "x": 1, "y": 1},
          {"type": "click", "x": 2, "y": 2},
          {"type": "nonsense"},
          {"type": "type", "text": "never typed"}
        ]
        """)
        guard case .failure(let error) = result else {
            return XCTFail("a batch containing an unknown action must be rejected wholesale")
        }
        XCTAssertEqual(error.code, .invalidAction)
        XCTAssertTrue(error.message.contains("action 2"), error.message)
    }

    func testErrorMessageNamesTheOffendingIndex() {
        guard case .failure(let error) = parse(#"[{"type":"move","x":1,"y":1},{"type":"move","x":"nope","y":2}]"#) else {
            return XCTFail()
        }
        XCTAssertTrue(error.message.contains("action 1"), "message was: \(error.message)")
    }

    func testUnknownKeyInComboIsRejected() {
        guard case .failure(let error) = parse(#"[{"type":"key","key":"cmd+notakey"}]"#) else {
            return XCTFail()
        }
        XCTAssertEqual(error.code, .invalidAction)
        XCTAssertTrue(error.message.contains("unknown key"), error.message)
    }

    func testUnknownModifierIsRejected() {
        guard case .failure(let error) = parse(#"[{"type":"click","x":1,"y":2,"modifiers":["hyper"]}]"#) else {
            return XCTFail()
        }
        XCTAssertTrue(error.message.contains("modifiers"), error.message)
    }

    func testTwoNonModifierKeysRejected() {
        guard case .failure(let error) = parse(#"[{"type":"key","keys":["cmd","a","b"]}]"#) else {
            return XCTFail()
        }
        XCTAssertTrue(error.message.contains("more than one non-modifier"), error.message)
    }

    func testModifiersOnlyRejected() {
        guard case .failure = parse(#"[{"type":"key","keys":["cmd","shift"]}]"#) else {
            return XCTFail("a key action with no key is not an action")
        }
    }

    // MARK: Bounds

    func testTooManyActionsRejected() {
        let actions = Array(repeating: #"{"type":"move","x":1,"y":1}"#, count: InputLimits.maxActions + 1)
        let result = parse("[" + actions.joined(separator: ",") + "]")
        guard case .failure(let error) = result else { return XCTFail("should reject") }
        XCTAssertTrue(error.message.contains("exceeds the limit"), error.message)
    }

    func testClickCountBound() {
        guard case .failure = parse(#"[{"type":"click","x":1,"y":2,"count":99}]"#) else {
            return XCTFail("count 99 should be rejected")
        }
        guard case .success = parse(#"[{"type":"click","x":1,"y":2,"count":5}]"#) else {
            return XCTFail("count 5 should be accepted")
        }
    }

    func testSleepBounds() {
        guard case .failure = parse(#"[{"type":"sleep","ms":999999}]"#) else {
            return XCTFail("an enormous sleep should be rejected")
        }
    }

    func testTotalSleepBound() {
        let one = #"{"type":"sleep","ms":30000}"#
        let result = parse("[" + Array(repeating: one, count: 10).joined(separator: ",") + "]")
        guard case .failure(let error) = result else {
            return XCTFail("a batch whose total sleep is unbounded should be rejected")
        }
        XCTAssertTrue(error.message.contains("total sleep"), error.message)
    }

    func testTypeLengthBound() {
        let long = String(repeating: "a", count: InputLimits.maxTypeLength + 1)
        guard case .failure = parse(#"[{"type":"type","text":"\#(long)"}]"#) else {
            return XCTFail("over-long text should be rejected")
        }
    }

    func testNonArrayRejected() {
        guard case .failure(let error) = parse(#"{"actions":[]}"#) else { return XCTFail() }
        XCTAssertEqual(error.code, .invalidAction)
    }

    func testEmptyBatchIsAllowed() {
        guard case .success(let actions) = parse("[]") else { return XCTFail() }
        XCTAssertTrue(actions.isEmpty)
    }

    // MARK: Key combos

    func testKeyComboPlusKey() {
        // A trailing "+" means the key itself is "+", which is the only
        // unambiguous way to name it.
        guard case .success(let parsed) = KeyCombo.parse("cmd++") else { return XCTFail() }
        XCTAssertEqual(parsed.keyCode, KeyCombo.keycodes["="])
        XCTAssertTrue(parsed.flags.contains(.maskCommand))
        XCTAssertTrue(parsed.flags.contains(.maskShift))
    }

    func testKeyComboModifierAliases() {
        let spellings = ["cmd+l", "command+l", "meta+l", "⌘+l"]
        var codes: Set<UInt16> = []
        for spelling in spellings {
            guard case .success(let parsed) = KeyCombo.parse(spelling) else {
                return XCTFail("\(spelling) should parse")
            }
            codes.insert(parsed.keyCode)
        }
        XCTAssertEqual(codes.count, 1, "all spellings of command should map to one keycode")
    }

    func testKeyComboCanonicalises() {
        guard case .success(let parsed) = KeyCombo.parse("Shift+CMD+t") else { return XCTFail() }
        XCTAssertEqual(parsed.canonical, "shift+cmd+t")
    }

    func testKeyComboPlainKeyHasNoFlags() {
        guard case .success(let parsed) = KeyCombo.parse("enter") else { return XCTFail() }
        XCTAssertEqual(parsed.flags, [])
        XCTAssertEqual(parsed.keyCode, 36)
    }

    func testKeyComboEmptyRejected() {
        guard case .failure = KeyCombo.parse("") else { return XCTFail("an empty combo is not a key") }
    }

    /// A trailing "+" is not a syntax error: it is how the "+" key is named,
    /// since "cmd++" cannot be spelled any other way on a US layout.
    func testTrailingPlusMeansThePlusKey() {
        guard case .success(let parsed) = KeyCombo.parse("cmd+") else {
            return XCTFail("'cmd+' should mean command-plus, not a dangling modifier")
        }
        XCTAssertEqual(parsed.canonical, "shift+cmd+=")
        // "cmd+shift+" is command-shift-plus, which is equally legitimate.
        guard case .success(let withShift) = KeyCombo.parse("cmd+shift+") else {
            return XCTFail("'cmd+shift+' should parse as command-shift-plus")
        }
        XCTAssertTrue(withShift.flags.contains(.maskCommand))
        XCTAssertTrue(withShift.flags.contains(.maskShift))
        XCTAssertEqual(withShift.keyCode, KeyCombo.keycodes["="])
    }

    func testEveryDocumentedKeyResolves() {
        for name in KeyCombo.keycodes.keys {
            guard case .success = KeyCombo.parse(name) else {
                XCTFail("\(name) is in the keycode table but does not parse")
                return
            }
        }
    }

    // MARK: Does this action need an app to receive it?
    //
    // The worker refuses input it believes has no target. Measured, that belief is
    // wrong for pointer events: a click posted into a session with zero layer-0
    // windows was hit-tested by the window server against the Dock tile under the
    // named point and launched the app (§322, `tests/probes/DockClickProbe.swift`).
    // So only the keyboard-half of the API may be refused for want of a responder —
    // refusing the rest locks the desktop, because that Dock click is how a window
    // gets open in the first place.

    func testPointerActionsDoNotNeedAResponder() {
        let pointer: [InputAction] = [
            .move(x: 1, y: 1),
            .click(x: 1, y: 1, button: .left, count: 1, modifiers: []),
            .click(x: 1, y: 1, button: .left, count: 2, modifiers: []),
            .drag(fromX: 0, fromY: 0, toX: 1, toY: 1, button: .left, modifiers: []),
            .pointerDown(x: 0, y: 0, button: .left, modifiers: []),
            .pointerDrag(fromX: 0, fromY: 0, toX: 1, toY: 1, button: .left, modifiers: []),
            .pointerUp(x: 1, y: 1, button: .left, modifiers: []),
            .scroll(x: nil, y: nil, dx: 0, dy: -100),
            .scroll(x: 5, y: 6, dx: 0, dy: -100),
            .sleep(ms: 10),
        ]
        for action in pointer {
            XCTAssertFalse(action.needsResponder, "\(action) is delivered to a point, not to a focused app")
        }
    }

    func testKeyboardActionsNeedAResponder() {
        let keyboard: [InputAction] = [.type(text: "hello"), .key(combo: "cmd+l")]
        for action in keyboard {
            XCTAssertTrue(action.needsResponder, "\(action) with no frontmost window is dropped, not delivered")
        }
    }
}

// MARK: - Wire encoding

extension InputActionTests {
    /// Every action must survive the trip the GUI and the MCP server make: encode
    /// it with `wireValue`, then feed it to the worker's own parser.
    ///
    /// This is the test that keeps the encoder honest. A field renamed on one side
    /// only would otherwise surface as `INVALID_ACTION` at runtime, in a session
    /// the developer cannot see, for an action that looked correct where it was
    /// constructed.
    func testEveryActionRoundTripsThroughItsWireForm() {
        let cases: [InputAction] = [
            .move(x: 500, y: 300),
            .click(x: 10, y: 20, button: .left, count: 1, modifiers: []),
            .click(x: 10, y: 20, button: .left, count: 2, modifiers: []),
            .click(x: 10, y: 20, button: .right, count: 1, modifiers: [.cmd, .shift]),
            .drag(fromX: 1, fromY: 2, toX: 300, toY: 400, button: .left, modifiers: []),
            .pointerDown(x: 1, y: 2, button: .left, modifiers: [.shift]),
            .pointerDrag(fromX: 1, fromY: 2, toX: 3, toY: 4, button: .left, modifiers: [.shift]),
            .pointerUp(x: 3, y: 4, button: .left, modifiers: [.shift]),
            .scroll(x: nil, y: nil, dx: 0, dy: -500),
            .scroll(x: 5, y: 6, dx: 12, dy: 34),
            .type(text: "hello, world"),
            .type(text: "日本語 — accents: éàü"),
            .key(combo: "cmd+l"),
            .key(combo: "shift+cmd+="),
            .sleep(ms: 250),
        ]

        for (index, action) in cases.enumerated() {
            let wire = action.wireValue
            switch InputAction.parse(wire, index: index) {
            case .failure(let error):
                XCTFail("\(action) did not survive its own wire form \(wire): \(error.message)")
            case .success(let parsed):
                XCTAssertEqual(parsed, action,
                    "\(action) encoded to \(wire) and came back as \(parsed)")
            }
        }
    }

    /// The discriminator must match what the worker switches on, since that is
    /// how it picks the parser.
    func testWireTypeNameMatchesTheDiscriminator() {
        let cases: [InputAction] = [
            .move(x: 1, y: 1),
            .click(x: 1, y: 1, button: .left, count: 1, modifiers: []),
            .click(x: 1, y: 1, button: .left, count: 2, modifiers: []),
            .drag(fromX: 0, fromY: 0, toX: 1, toY: 1, button: .left, modifiers: []),
            .scroll(x: nil, y: nil, dx: 0, dy: 1),
            .type(text: "x"),
            .key(combo: "a"),
            .sleep(ms: 1),
        ]
        for action in cases {
            XCTAssertEqual(action.wireValue["type"]?.stringValue, action.typeName,
                "\(action) is discriminated as \(action.typeName) but encoded otherwise")
        }
    }

    /// A single click must not carry a redundant `count`, so a worker that treats
    /// a present-but-1 count as suspicious cannot reject the common case.
    func testSingleClickOmitsTheRedundantCount() {
        let wire = InputAction.click(x: 5, y: 5, button: .left, count: 1, modifiers: []).wireValue
        XCTAssertNil(wire["count"])
        XCTAssertEqual(wire["type"]?.stringValue, "click")
    }

    /// Modifiers are only sent when there are some, and they use the worker's own
    /// spelling.
    func testModifiersAreOmittedWhenEmptyAndNamedCorrectlyWhenNot() {
        let plain = InputAction.click(x: 1, y: 1, button: .left, count: 1, modifiers: []).wireValue
        XCTAssertNil(plain["modifiers"])

        let modified = InputAction.click(x: 1, y: 1, button: .left, count: 1,
                                         modifiers: [.cmd, .shift]).wireValue
        let names = modified["modifiers"]?.arrayValue?.compactMap { $0.stringValue }
        XCTAssertEqual(names, ["cmd", "shift"])
    }

    /// Scroll's optional origin must be absent rather than zero — a scroll at
    /// (0,0) is a different request from a scroll wherever the pointer is.
    func testScrollOmitsAnAbsentOriginRatherThanSendingZero() {
        let centred = InputAction.scroll(x: nil, y: nil, dx: 0, dy: -100).wireValue
        XCTAssertNil(centred["x"])
        XCTAssertNil(centred["y"])

        let located = InputAction.scroll(x: 0, y: 0, dx: 0, dy: -100).wireValue
        XCTAssertEqual(located["x"]?.intValue, 0)
        XCTAssertEqual(located["y"]?.intValue, 0)
    }
}
