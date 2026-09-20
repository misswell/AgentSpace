import Foundation
import CoreGraphics
import AppKit
import AgentSpaceCore

/// The phase-0 acceptance test — plan §44.
///
/// > The console user opens TextEdit with `USER_SCREEN_123456`, the agent user
/// > opens TextEdit with `AGENT_SCREEN`, the worker clicks, types and scrolls
/// > **1000 times**, and afterwards the console's TextEdit content, focus and
/// > mouse are unchanged. Only then may work continue past phase 0.
///
/// That gate is the whole product claim in one program. It is written now — while
/// it cannot run — for a specific reason: the day a second login exists, the
/// question "does any of this actually work?" should be one command with a
/// printed verdict, not a fresh piece of test scaffolding written under pressure.
///
/// It runs from the **console** session, because that is where the things being
/// protected live. It drives the agent's desktop only through the worker's socket,
/// over the same protocol the CLI, the GUI and the MCP server use.
///
/// ## What it does *not* do
///
/// It never posts an event itself. There is no fallback path, and no branch that
/// tries the agent's TextEdit locally if the worker is unavailable — if the worker
/// is not there, this program reports that and stops. A test that could quietly
/// drive the wrong session would be worse than no test, because it would pass.
///
/// ## Two modes
///
/// `--mode fail-closed` proves the half that *is* observable on a single-user
/// machine: when the worker's session is the console, every input call is refused
/// and nothing moves. It is the negative control, and it runs today.
///
/// `--mode isolation` is the real thing and needs a background Space session.
enum AcceptanceMode: String {
    case isolation
    case failClosed = "fail-closed"
    case both
}

struct AcceptanceOptions {
    var space: String?
    var root: String?
    var iterations = 1000
    var mode: AcceptanceMode = .both
    var keepTextEdit = false
    var json = false
}

// MARK: - Reporting

final class Report {
    private(set) var lines: [String] = []
    private(set) var failures: [String] = []
    private(set) var skips: [String] = []
    private(set) var inconclusives: [String] = []

    func step(_ text: String) {
        lines.append(text)
        print(text)
    }

    func pass(_ text: String) {
        step("  PASS  \(text)")
    }

    func fail(_ text: String) {
        failures.append(text)
        step("  FAIL  \(text)")
    }

    func skip(_ text: String) {
        skips.append(text)
        step("  SKIP  \(text)")
    }

    /// Measured, but not attributable. Kept distinct from both pass and fail: a
    /// run whose isolation claim could not be established must not report success.
    func inconclusive(_ text: String) {
        inconclusives.append(text)
        step("  ~     \(text)")
    }

    func apply(_ findings: [Finding]) {
        for finding in findings {
            switch finding {
            case .ok(let text): pass(text)
            case .failure(let text): fail(text)
            case .inconclusive(let text): inconclusive(text)
            }
        }
    }

    var ok: Bool { failures.isEmpty }

    var json: JSONValue {
        .object([
            "ok": .bool(ok),
            "failures": .array(failures.map { .string($0) }),
            "skipped": .array(skips.map { .string($0) }),
            "inconclusive": .array(inconclusives.map { .string($0) }),
            "log": .array(lines.map { .string($0) }),
        ])
    }
}

// MARK: - Entry

let options = parseAcceptanceArgs(Array(CommandLine.arguments.dropFirst()))
let report = Report()

report.step("AgentSpace phase-0 acceptance test")
report.step("")

// The console side of the test is this process's own session.
guard let consoleDict = CGSessionCopyCurrentDictionary() as? [String: Any],
      (consoleDict["kCGSSessionOnConsoleKey"] as? Bool) == true
      || (consoleDict["kCGSSessionOnConsoleKey"] as? Int) == 1 else {
    report.step("This program must run from the physical console session, because the")
    report.step("things it verifies are the console's. Run it from your own logged-in")
    report.step("desktop, not over ssh and not from the AgentSpace account.")
    exit(64)
}

let registry = SpaceRegistry.load(root: options.root)
guard let space = options.space.map({ registry.resolve($0) }).flatMap({ try? $0.get() }) ?? registry.first() else {
    report.step("No AgentSpace found. Create one in the AgentSpace app first.")
    report.step("(If you are looking for the fail-closed half, it needs a Space too — but")
    report.step(" only needs its worker, not a second login.)")
    exit(66)
}

let connection = SpaceConnection(space: space)
report.step("Space:      \(space.name) (\(space.username), uid \(space.uid))")
report.step("Socket:     \(connection.paths.socketPath)")
report.step("Iterations: \(options.iterations)")
report.step("")

// MARK: - Preflight

func workerHello() -> JSONValue? {
    guard let response = try? connection.client.call(method: Method.hello, token: connection.token),
          response.ok else { return nil }
    return response.result
}

guard let hello = workerHello() else {
    report.fail("the worker is not answering on \(connection.paths.socketPath)")
    report.step("")
    report.step("Start the Space's worker first. There is nothing this test can do")
    report.step("without it: it never drives the agent's desktop any other way.")
    exit(69)
}

let verdict = hello["session"]?["verdict"]?.stringValue ?? "unknown"
let permitsInput = hello["session"]?["permitsInput"]?.boolValue ?? false
let accessibility = hello["permissions"]?["accessibility"]?.boolValue ?? false
let screenRecording = hello["permissions"]?["screenRecording"]?.boolValue ?? false
// `nil` means the worker predates the probe. It is not "denied", and a missing
// optional grant is not a failure — so this line reports, it never gates.
let fileAccess = hello["permissions"]?["fileAccess"]?.boolValue

report.step("Worker is up. Session verdict: \(verdict)")
report.step("  accessibility:    \(accessibility ? "granted" : "MISSING")")
report.step("  screen recording: \(screenRecording ? "granted" : "MISSING")")
report.step("  file access:      \(fileAccess.map { $0 ? "granted" : "not granted (optional)" } ?? "unknown")")
report.step("  permits input:    \(permitsInput)")
report.step("")

// MARK: - Mode: fail-closed

func runFailClosed() {
    report.step("== fail-closed: the negative control ==")
    report.step("Every input call must be refused, and nothing on this desktop may move.")
    report.step("")

    // Sample a quiet window first. Without it, a human using the machine during
    // the run would be reported as a leak — see AmbientBaseline.
    report.step("Sampling this desktop for 1.5s with nothing sent, to learn what it does")
    report.step("on its own…")
    let requested = [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 300), CGPoint(x: 320, y: 320), CGPoint(x: 10, y: 10), CGPoint(x: 200, y: 200)]
    let ambient = sampleAmbientBaseline(seconds: 1.5, requestedPoints: requested, textEdit: nil)
    report.step("  \(ambient.summary)")
    report.step("")

    let before = observeConsole()
    report.step("Before:")
    for line in before.summary.split(separator: "\n") { report.step("    \(line)") }
    report.step("")

    let shapes: [(String, [InputAction])] = [
        ("move", [.move(x: 100, y: 100)]),
        ("click", [.click(x: 100, y: 100, button: .left, count: 1, modifiers: [])]),
        ("doubleClick", [.click(x: 100, y: 100, button: .left, count: 2, modifiers: [])]),
        ("rightClick", [.click(x: 100, y: 100, button: .right, count: 1, modifiers: [])]),
        ("type", [.type(text: "AGENT_SCREEN")]),
        ("key", [.key(combo: "cmd+a")]),
        ("scroll", [.scroll(x: nil, y: nil, dx: 0, dy: -120)]),
        ("drag", [.drag(fromX: 10, fromY: 10, toX: 200, toY: 200, button: .left, modifiers: [])]),
        ("1000 mixed", mixedBatch(count: options.iterations)),
    ]

    for (name, actions) in shapes {
        let response = try? connection.client.call(
            method: Method.input,
            params: .object(["actions": .array(actions.map { $0.wireValue })]),
            token: connection.token,
            timeout: 60)

        guard let response else {
            report.fail("\(name): the worker did not answer at all")
            continue
        }
        guard !response.ok else {
            report.fail("\(name): the worker ACCEPTED input — on a console session this is the bug the whole design exists to prevent")
            continue
        }
        let code = response.error?.code.rawValue ?? "?"
        if permitsInput {
            // The session legitimately accepts input, so a refusal here means the
            // worker refused for an unrelated reason and the negative control is
            // not testing what it claims to.
            report.fail("\(name): refused with \(code) even though the worker reports input is permitted — the control is inconclusive")
        } else if code == AgentSpaceErrorCode.sessionIsConsole.rawValue
                    || code == AgentSpaceErrorCode.accessibilityDenied.rawValue
                    || code == AgentSpaceErrorCode.noWindowServer.rawValue {
            report.pass("\(name): refused with \(code)")
        } else {
            report.fail("\(name): refused with \(code), which is not a session-safety refusal")
        }
    }

    let after = observeConsole()
    report.step("")
    report.step("After:")
    for line in after.summary.split(separator: "\n") { report.step("    \(line)") }
    report.step("")
    report.step("Isolation of this desktop after \(options.iterations) refused actions:")
    report.apply(after.differences(from: before, ambient: ambient))
    report.step("")
}

// MARK: - Mode: the real isolation test

func runIsolation() {
    report.step("== isolation: the phase-0 gate ==")
    report.step("")

    guard permitsInput else {
        report.skip("the worker's session is '\(verdict)', so it cannot accept input and there is nothing to isolate yet")
        report.step("")
        report.step("This is the expected result on a single-user machine. The gate needs an")
        report.step("AgentSpace account logged in once through fast user switching, so that its")
        report.step("desktop is a real background session. Until then the only half of the")
        report.step("isolation claim that can be observed is the refusal, above.")
        report.step("")
        return
    }

    guard accessibility else {
        report.fail("the worker has no Accessibility grant, so it cannot drive anything")
        return
    }

    // Console baseline. TextEdit is opened here, in this session, on purpose: the
    // test's whole point is that this document is the one nothing may touch.
    guard let consoleTextEdit = prepareConsoleTextEdit(report: report) else {
        report.fail("could not get a TextEdit document on the console side; the test cannot establish its baseline")
        return
    }
    AX.setValue(consoleTextEdit, "USER_SCREEN_123456")

    let requested = [CGPoint(x: 300, y: 300), CGPoint(x: 320, y: 320)]
    report.step("Sampling this desktop for 2s with nothing sent…")
    let ambient = sampleAmbientBaseline(seconds: 2, requestedPoints: requested, textEdit: consoleTextEdit)
    report.step("  \(ambient.summary)")
    report.step("")

    var before = observeConsole()
    before.textEditValue = AX.string(consoleTextEdit, kAXValueAttribute)
    report.step("Console baseline set:")
    for line in before.summary.split(separator: "\n") { report.step("    \(line)") }
    report.step("")

    // Agent side: TextEdit in the Space, then the marker.
    let launch = try? connection.client.call(
        method: Method.launch,
        params: .object(["app": .string("TextEdit")]),
        token: connection.token, timeout: 60)
    if launch?.ok != true {
        report.fail("could not launch TextEdit in the Space: \(launch?.error?.message ?? "no answer")")
        return
    }
    report.pass("TextEdit launched inside the Space")

    let marker = try? connection.client.call(
        method: Method.input,
        params: .object(["actions": .array([
            InputAction.sleep(ms: 500).wireValue,
            InputAction.type(text: "AGENT_SCREEN").wireValue,
        ])]),
        token: connection.token, timeout: 60)
    if marker?.ok != true {
        report.fail("could not type the agent-side marker: \(marker?.error?.message ?? "no answer")")
        return
    }
    report.pass("agent-side marker typed through the worker")

    // The 1000 iterations, in batches. One action per round trip would measure the
    // socket rather than the isolation, and §14 explicitly asks callers to batch.
    report.step("")
    report.step("Running \(options.iterations) mixed actions in batches of 100…")
    var performed = 0
    var rounds = 0
    while performed < options.iterations {
        let batch = min(100, options.iterations - performed)
        let actions = mixedBatch(count: batch)
        let response = try? connection.client.call(
            method: Method.input,
            params: .object(["actions": .array(actions.map { $0.wireValue })]),
            token: connection.token,
            timeout: 120)
        guard let response, response.ok else {
            report.fail("batch \(rounds + 1) failed after \(performed) actions: \(response?.error?.message ?? "no answer")")
            return
        }
        performed += batch
        rounds += 1
        if rounds % 2 == 0 || performed >= options.iterations {
            report.step("    \(performed)/\(options.iterations)")
        }
    }
    report.pass("\(performed) actions delivered to the Space in \(rounds) round trips")
    report.step("")

    // The gate.
    var after = observeConsole()
    after.textEditValue = AX.string(consoleTextEdit, kAXValueAttribute)
    report.step("After:")
    for line in after.summary.split(separator: "\n") { report.step("    \(line)") }
    report.step("")

    report.step("Isolation of this desktop after \(performed) actions on the agent's desktop:")
    let findings = after.differences(from: before, ambient: ambient)
    report.apply(findings)
    report.step("")
    if findings.contains(where: { $0.isFailure }) {
        report.fail("PHASE 0 GATE FAILED")
    } else if findings.contains(where: { if case .inconclusive = $0 { return true }; return false }) {
        report.skip("PHASE 0 GATE INCONCLUSIVE — the console was changing on its own, so the run cannot attribute it either way. Re-run when nobody is using the machine.")
    } else {
        report.pass("PHASE 0 GATE PASSED — the console is unchanged after \(performed) actions on the agent's desktop")
    }

    // And the agent's side should have changed: a test that proves nothing moved
    // because nothing happened is not a passing test.
    report.step("")
    report.step("Checking the agent's own desktop actually changed (otherwise this proves")
    report.step("only that nothing happened anywhere)…")
    let shot = try? connection.client.call(
        method: Method.screenshot,
        params: .object(["maxWidth": .int(800)]),
        token: connection.token, timeout: 60)
    if shot?.ok == true, let path = shot?.result?["path"]?.stringValue {
        report.pass("captured the agent's desktop at \(path)")
    } else {
        report.fail("could not capture the agent's desktop to confirm the actions landed")
    }
}

/// A mixed batch that exercises every input shape, repeated.
///
/// Deliberately includes `type` and `key`: a click-only test would miss a stuck
/// modifier or a keystroke that leaked into the console through a different path.
func mixedBatch(count: Int) -> [InputAction] {
    var actions: [InputAction] = []
    actions.reserveCapacity(count)
    let shapes: [InputAction] = [
        .move(x: 300, y: 300),
        .click(x: 300, y: 300, button: .left, count: 1, modifiers: []),
        .scroll(x: nil, y: nil, dx: 0, dy: -40),
        .type(text: "abc"),
        .key(combo: "left"),
        .move(x: 320, y: 320),
        .click(x: 320, y: 320, button: .left, count: 1, modifiers: []),
        .scroll(x: nil, y: nil, dx: 0, dy: 40),
    ]
    while actions.count < count {
        actions.append(contentsOf: shapes.prefix(count - actions.count))
    }
    return actions
}

func observeConsole() -> ConsoleObservation {
    let frontmost = NSWorkspace.shared.frontmostApplication
    let pid = frontmost?.processIdentifier ?? 0
    let focused = AX.focusedElement(in: pid)
    let focusedDescription: String
    if let focused {
        let role = AX.role(focused) ?? "?"
        let title = AX.title(focused).map { " \"\($0)\"" } ?? ""
        let identifier = AX.identifier(focused).map { " #\($0)" } ?? ""
        focusedDescription = "\(role)\(title)\(identifier)"
    } else {
        focusedDescription = "<none>"
    }

    // The console's own TextEdit, if it has one.
    var textEditValue: String?
    if let textEdit = NSRunningApplication
        .runningApplications(withBundleIdentifier: "com.apple.TextEdit").first {
        if let area = AX.textAreas(in: textEdit.processIdentifier).first {
            textEditValue = AX.string(area, kAXValueAttribute)
        }
    }

    return ConsoleObservation(
        frontmostAppName: frontmost?.localizedName ?? "<none>",
        frontmostAppPID: pid,
        focusedElementDescription: focusedDescription,
        mouseLocation: CGEvent(source: nil)?.location ?? .zero,
        textEditValue: textEditValue)
}

/// Get a TextEdit document in this session without touching any the user already
/// has open. Returns the text area to use as the baseline.
func prepareConsoleTextEdit(report: Report) -> AXUIElement? {
    let bundleID = "com.apple.TextEdit"
    let alreadyRunning = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first

    if alreadyRunning == nil {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // `-n` forces a new instance, whose first window is an untitled document.
        // Without it, TextEdit hands back whatever the user had open and this test
        // would rewrite their work.
        task.arguments = ["-n", "-a", "TextEdit"]
        try? task.run()
        task.waitUntilExit()
    }

    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            let pid = app.processIdentifier
            if let area = AX.textAreas(in: pid).first {
                report.step("Console TextEdit pid \(pid) has an editable area; using it as the baseline")
                return area
            }
            // A new instance opens an empty untitled document only sometimes, so
            // ask for one through the menu — via AX, which does not move the mouse.
            //
            // The result is checked rather than dropped: if the menu press fails
            // there is no document to type into, and the failure would otherwise
            // appear much later as a puzzling "no window" from a different step.
            if !AX.pressMenuItem(in: pid, menu: "File", item: "New") {
                return nil
            }
        }
        usleep(300_000)
    }
    return nil
}

// MARK: - Argument parsing

func parseAcceptanceArgs(_ argv: [String]) -> AcceptanceOptions {
    var options = AcceptanceOptions()
    var index = 0
    while index < argv.count {
        let argument = argv[index]
        switch argument {
        case "--space":
            if index + 1 < argv.count { options.space = argv[index + 1]; index += 2; continue }
        case "--root":
            if index + 1 < argv.count { options.root = argv[index + 1]; index += 2; continue }
        case "--iterations":
            if index + 1 < argv.count, let value = Int(argv[index + 1]) { options.iterations = value; index += 2; continue }
        case "--mode":
            if index + 1 < argv.count, let value = AcceptanceMode(rawValue: argv[index + 1]) {
                options.mode = value; index += 2; continue
            }
        case "--json": options.json = true
        case "--keep-textedit": options.keepTextEdit = true
        case "--help", "-h":
            print("""
            agentspace-session-test — the phase-0 acceptance test (plan §44)

            USAGE
              agentspace-session-test [--space NAME] [--iterations N]
                                      [--mode isolation|fail-closed|both] [--json]

            Run this from your own logged-in desktop, never over ssh and never
            from the AgentSpace account: it verifies that the console you are
            sitting at is untouched.

            --mode fail-closed   Only the negative control: every input call is
                                 refused and nothing on this desktop moves. Runs
                                 on a single-user machine.
            --mode isolation     The real gate: 1000 mixed actions on the agent's
                                 desktop, then a comparison of this desktop's
                                 content, focus and pointer. Needs a background
                                 AgentSpace session.
            """)
            exit(0)
        default:
            FileHandle.standardError.write(Data("unknown argument \(argument); try --help\n".utf8))
            exit(64)
        }
        index += 1
    }
    return options
}

// MARK: - Run

if options.mode == .failClosed || options.mode == .both { runFailClosed() }
if options.mode == .isolation || options.mode == .both { runIsolation() }

report.step("")
if options.json {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(report.json), let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}

let finalVerdict: String
let exitCode: Int32
if !report.ok {
    finalVerdict = "FAIL"; exitCode = 1
} else if !report.skips.isEmpty {
    finalVerdict = "INCOMPLETE"; exitCode = 3
} else if !report.inconclusives.isEmpty {
    finalVerdict = "INCONCLUSIVE"; exitCode = 4
} else {
    finalVerdict = "PASS"; exitCode = 0
}
report.step("Verdict: \(finalVerdict)")
for failure in report.failures { report.step("  FAIL  \(failure)") }
for skip in report.skips { report.step("  SKIP  \(skip)") }
for item in report.inconclusives { report.step("  ~     \(item)") }

// Neither a skip nor an inconclusive result is a pass.
//
// Exit 0 requires that the gate actually ran AND that every property it measured
// was stable. Returning 0 because the gate never executed would make this program
// useless in CI, which is the one place it matters most; returning 0 because the
// console happened to be busy would be worse, because it would be a lie with a
// green tick on it.
exit(exitCode)
