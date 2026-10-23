import XCTest
import AppKit
import AgentSpaceCore
@testable import AgentSpaceApp

/// The whole gesture, once, for real — the one claim unit tests cannot make.
///
/// Every layer of the clipboard bridge is pinned separately: the policy and the
/// limits by `ClipboardBridgePolicyTests`, the staging by
/// `ClipboardTransferTests`, the transport by `ClipboardBridgeTests`, and the
/// worker's own board write by row 1324/1325 of validation §397. What none of
/// those can say is that **the composite works**: a ⌘V arriving at a window's
/// local monitor ends with the agent's own application holding the person's text
/// on its clipboard and pasting it.
///
/// This test therefore does the smallest thing that is still the real path:
///
/// - a real `NSWindow` in this (the person's) process,
/// - the real `RemoteKeyboardMonitor.install` the Desktop Viewer uses,
/// - the real `ClipboardBridgeHost` the viewer's `handleClipboard` calls,
/// - a real `NSEvent` key-down for ⌘V delivered through `NSApplication.sendEvent`,
///   which is exactly where `addLocalMonitorForEvents` hooks,
/// - a real worker in the agent's own session over its real unix socket,
/// - and the same `SpaceService().input` fallback the viewer uses when the fast
///   channel is down.
///
/// It is opt-in (`AGENTSPACE_LIVE_CLIPBOARD_TEST=1`) because it needs an attached
/// account whose worker is live in a *usable, non-console* session, and because
/// it presses keys meant for another desktop. It saves and restores the person's
/// clipboard in full format, so running it disturbs nothing. It never posts an
/// event to the person's screen: the only key it sends is delivered straight to
/// its own window.
final class ClipboardCompositeLiveTests: XCTestCase {
    private var window: NSWindow?
    private var monitor: Any?
    private var savedItems: [[(String, Data)]] = []
    /// Set when the person's board could not be put back exactly; reported at the
    /// end of the test rather than swallowed.
    private var restoreNote: String?
    private var pastedMarker: String?

    @MainActor
    func testARealCommandVPastesThePersonsTextIntoAnAgentApplication() async throws {
        guard ProcessInfo.processInfo.environment["AGENTSPACE_LIVE_CLIPBOARD_TEST"] == "1" else {
            throw XCTSkip("""
                Requires an attached account with a live worker in a usable session. \
                Set AGENTSPACE_LIVE_CLIPBOARD_TEST=1 to run it deliberately.
                """)
        }
        let account = try XCTUnwrap(
            SpaceRegistry.load().spaces.first { $0.name == "AgentUse" },
            "this test needs the attached account the session checks use")
        let connection = SpaceConnection(space: account)
        let statusResponse: RPCResponse
        do {
            statusResponse = try connection.client.call(
                method: Method.status, params: .object([:]), token: connection.token)
        } catch {
            return XCTFail("the worker must answer status: \(error)")
        }
        let status = try XCTUnwrap(statusResponse.result,
                                   "the worker must answer status with a result")
        // Explicit dictionary reads: a chained `JSONValue` subscript in this
        // position trips the type checker rather than the code being wrong.
        let statusFields: [String: JSONValue] = status.objectValue ?? [:]
        let advertisedBridge: Bool? = statusFields["clipboard"].flatMap { value -> Bool? in
            (value.objectValue ?? [:])["bridge"]?.boolValue
        }
        let acceptsInput: Bool? = statusFields["acceptsInput"]?.boolValue
        XCTAssertEqual(advertisedBridge, true,
                       "a worker without the bridge cannot take part in this gesture")
        XCTAssertEqual(acceptsInput, true, "input must be permitted in that session")

        // The agent's own application, so the last step is an app pasting rather
        // than a board changing. TextEdit owns a document window with a text
        // view, and an untitled one is created by launching it.
        _ = try? connection.client.call(method: Method.launch,
                                        params: .object(["app": .string("TextEdit")]),
                                        token: connection.token, timeout: 20)
        _ = try? connection.client.call(method: Method.activate,
                                        params: .object(["app": .string("TextEdit")]),
                                        token: connection.token, timeout: 10)

        // A file the person "copied", in this process's temporary directory.
        let marker = "AgentSpace clipboard acceptance \(UUID().uuidString.prefix(8))"
        pastedMarker = marker
        let sourceFile = NSTemporaryDirectory() + "clipboard-acceptance-\(UUID().uuidString.prefix(8)).txt"
        try Data("a file the person copied\n".utf8).write(to: URL(fileURLWithPath: sourceFile))
        defer { try? FileManager.default.removeItem(atPath: sourceFile) }

        savePersonClipboard()
        // Restored by hand rather than by `defer`, so a failure cannot skip it and
        // the outcome is asserted instead of hoped for.
        var restoreChecked = false
        func restoreNow() {
            guard !restoreChecked else { return }
            restoreChecked = true
            restorePersonClipboard()
        }
        defer { restoreNow() }

        // The person copies text and a file, then presses ⌘V in an agent window.
        let board = NSPasteboard.general
        board.clearContents()
        let textItem = NSPasteboardItem()
        textItem.setString(marker, forType: .string)
        board.writeObjects([textItem, URL(fileURLWithPath: sourceFile) as NSURL])

        let host = ClipboardBridgeHost(space: account)
        var noticed: [ClipboardBridgeNotice] = []
        var monthsForwarded: [InputAction] = []

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        self.window = window
        window.isReleasedWhenClosed = false
        window.contentView = FirstResponderSink()
        window.makeFirstResponder(window.contentView)
        window.orderFront(nil)

        let send: (InputAction) -> Void = { action in
            monthsForwarded.append(action)
            // The viewer's documented fallback path when the fast channel is not
            // up; the worker applies the key through the same parser and gates.
            _ = SpaceService().input(for: account, actions: [action])
        }
        monitor = RemoteKeyboardMonitor.install(
            window: window,
            permitsInput: { true },
            clipboard: { intent, action in
                host.handle(intent: intent, action: action,
                            bridgingAvailable: advertisedBridge,
                            permitsInput: { true },
                            send: send,
                            note: { notice in noticed.append(notice) })
            },
            send: send)

        let expectation = expectation(description: "the bridge finished and the keystroke went")
        // The bridge answers asynchronously (a real RPC and, for a file, real
        // copies), so the assertion waits for the keystroke rather than sleeping
        // a guessed interval.
        let deadline = Date().addingTimeInterval(25)
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            characters: "v", charactersIgnoringModifiers: "v",
            isARepeat: false, keyCode: 9)
        let unwrappedEvent = try XCTUnwrap(event)
        // Straight to the application's event dispatch: this is the call that runs
        // `addLocalMonitorForEvents` blocks, so the monitor, the intent decision
        // and the bridge are all the production ones.
        NSApplication.shared.sendEvent(unwrappedEvent)

        // Did the keystroke reach the agent?
        var forwarded: InputAction?
        while Date() < deadline, forwarded == nil {
            if let key = monthsForwarded.first { forwarded = key; break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNotNil(forwarded, """
            ⌘V was consumed by the monitor and never forwarded — the one failure \
            this feature must not have. Notices: \(noticed.map(\.message))
            """)
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 1)

        // And did the agent's board receive it? Read it through the worker, which
        // is the only process that owns the agent's board.
        let pulled = try XCTUnwrap(
            try connection.client.call(method: Method.clipboardPull,
                                       params: .object(["waitMilliseconds": .int(0)]),
                                       token: connection.token).result)
        let contents = ClipboardContents(json: pulled)
        XCTAssertTrue(contents.text?.contains(marker) ?? false, """
            the agent's clipboard should hold the person's text; it held \
            \(contents.text.map { "\($0.utf8.count) bytes" } ?? "nothing")
            """)
        XCTAssertFalse(contents.files.isEmpty, "the file the person copied should be on the agent's clipboard too")
        for file in contents.files {
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path),
                          "the agent's clipboard must point at a file that exists")
        }

        // Finally: the agent's own app took it. The forwarded ⌘V went to that
        // session and TextEdit was frontmost there, so its document is where the
        // result shows up — read through accessibility, which is how anything in
        // that session is inspected.
        //
        // A *mixed* board (text + a file) legitimately becomes a **file
        // attachment** in TextEdit: measured on 2026-10-23, the document then
        // holds U+FFFC and no text, and preferring the file is the app's choice
        // rather than a defect in the bridge. So the assertion here is the
        // attachment, and the unambiguous "the app pasted the text" case is the
        // text-only keystroke below.
        var attached = false
        let until = Date().addingTimeInterval(10)
        while Date() < until, !attached {
            if let tree = try? connection.client.call(
                method: Method.axSnapshot, params: .object([:]),
                token: connection.token, timeout: 10).result {
                let rendered = String(describing: tree)
                // U+FFFC is the object-replacement character a text view shows
                // for an attachment; JSON escaping may hand it back either way.
                if rendered.contains("\u{FFFC}") || rendered.contains("ufffc") { attached = true; break }
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        XCTAssertTrue(attached, """
            the keystroke reached the agent session but TextEdit's document shows \
            neither the text nor an attachment, so the paste did not land
            """)

        // The unambiguous case: a text-only board must appear as text.
        board.clearContents()
        board.setString(marker, forType: .string)
        let textOnlyEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            characters: "v", charactersIgnoringModifiers: "v",
            isARepeat: false, keyCode: 9))
        NSApplication.shared.sendEvent(textOnlyEvent)

        var textPasted = false
        let textUntil = Date().addingTimeInterval(15)
        while Date() < textUntil, !textPasted {
            if let tree = try? connection.client.call(
                method: Method.axSnapshot, params: .object([:]),
                token: connection.token, timeout: 10).result,
               String(describing: tree).contains(marker) {
                textPasted = true
                break
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        XCTAssertTrue(textPasted, """
            a text-only ⌘V from the person's window did not reach TextEdit's \
            document, so the composite gesture is still unproven
            """)

        // The person's clipboard is not the test's to spend: put it back and say
        // so. This runs before the assertion below can fail, so a broken restore
        // is reported as itself rather than as a mystery about a paste.
        restoreNow()
        XCTAssertNil(restoreNote, """
            the person's clipboard was not put back exactly: \(restoreNote ?? "")
            """)
    }

    // MARK: - The person's clipboard, saved and put back

    /// Full format, not just text: the person may have had anything copied.
    private func savePersonClipboard() {
        savedItems = (NSPasteboard.general.pasteboardItems ?? []).compactMap { item in
            // A type whose data cannot be read is dropped rather than kept as an
            // empty pair: `compactMap` alone would turn such an item into an empty
            // group, and writing an empty group restores *nothing* — which is how
            // the first run of this test left the person's board holding one line
            // of test text instead of what they had copied. An item that loses
            // every type is therefore dropped whole, and `restoredNothing` below
            // says so out loud.
            let pairs: [(String, Data)] = item.types.compactMap { type in
                item.data(forType: type).map { (type.rawValue, $0) }
            }
            return pairs.isEmpty ? nil : pairs
        }
    }

    /// Put the person's board back, and be honest when it cannot be done exactly.
    ///
    /// Runs even when an assertion failed, because the person's clipboard is not
    /// the test's to spend. `restoreFailed` is reported rather than swallowed: a
    /// silent half-restore is how a board gets lost without anyone noticing.
    private func restorePersonClipboard() {
        let board = NSPasteboard.general
        guard !savedItems.isEmpty else {
            // Nothing was captured, so nothing may be written. Clearing here would
            // destroy whatever the person has now for the sake of tidiness.
            restoreNote = "nothing was captured, so the board was left as it is"
            return
        }
        board.clearContents()
        // Fresh items: a pasteboard item that has been through `writeObjects`
        // once cannot be written again — the shape that aborts the process
        // (§397 row 1323).
        let items: [NSPasteboardItem] = savedItems.map { pairs in
            let item = NSPasteboardItem()
            for (type, data) in pairs {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        let ok = board.writeObjects(items)
        restoreNote = ok ? nil : "the person's clipboard could not be fully restored"
        savedItems = []
    }
}

/// A content view that can be first responder and does nothing with the keys it
/// receives, so the window is a faithful stand-in for the surface's window.
private final class FirstResponderSink: NSView {
    override var acceptsFirstResponder: Bool { true }
}
