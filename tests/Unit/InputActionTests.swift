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
}
