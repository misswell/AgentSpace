import Foundation
import AppKit
import ApplicationServices

/// The session-side half of `scripts/gui-verify.sh` — layer 4's checks, run
/// inside the **agent account's own session** instead of in front of whoever is
/// sitting at the Mac.
///
/// Why it exists (§323 row 863): the console gate clears the slate — it closes
/// every AgentSpace copy the human owns and then drives a window of its own on
/// their screen for a minute or two. During 0.1.31's release that ran six times
/// in an afternoon while the owner was working, and the request that came back
/// was 「做测试的时候可否尽量不要打扰我操作」. This program is the durable answer:
/// it opens its subject on the agent account's desktop, where the human's
/// screen, focus and windows are untouched.
///
/// It is not merely politer than the console gate, it is *incapable* of the
/// harm: it runs as the agent user, inside that account's session, and cannot
/// signal a process owned by the human — measured, `pkill` of the owner's copy
/// from here answers `Operation not permitted` (§324 row 872).
///
/// The 13 checks below are the console gate's own, in its order and under its
/// names, so the two reports can be read side by side. What changed is the
/// instrument, not the claim: AXIdentifier lookups instead of System Events,
/// key equivalents found through the accessibility menu bar instead of
/// keystrokes typed at whatever holds focus, and no reliance on a screen.
///
/// **It must run inside the agent session** — launched by
/// `scripts/session-gui-verify.sh`, which reaches that session through the
/// worker's shipped `exec`. Run from a login shell it will find
/// `AXIsProcessTrusted() == false` and refuse (exit 3) rather than lie.

// MARK: - Arguments

func usage() -> String {
    "usage: agentspace-gui-check --bundle /path/to/AgentSpace.app [--root DIR] [--keep-root] [--verbose]"
}

/// 3 is this repository's "could not run — not a pass" code (`scripts/acceptance.sh`
/// uses it for the same reason), and it is deliberately not 1: a gate that could
/// not look must never be readable as a gate that looked and saw a failure.
func fail(_ message: String, code: Int32 = 3) -> Never {
    FileHandle.standardError.write(Data(("agentspace-gui-check: " + message + "\n").utf8))
    exit(code)
}

var arguments = Array(CommandLine.arguments.dropFirst())
var bundlePath: String?
var rootPath: String?
var keepRoot = false
var verbose = false
while !arguments.isEmpty {
    let argument = arguments.removeFirst()
    switch argument {
    case "--bundle":
        bundlePath = arguments.first; if !arguments.isEmpty { arguments.removeFirst() }
    case "--root":
        rootPath = arguments.first; if !arguments.isEmpty { arguments.removeFirst() }
    case "--keep-root": keepRoot = true
    case "--verbose": verbose = true
    case "--help", "-h": print(usage()); exit(0)
    default: fail("unknown argument '\(argument)'\n\(usage())")
    }
}
guard let bundlePath else { fail("--bundle is required\n\(usage())") }
let bundle = URL(fileURLWithPath: bundlePath).standardizedFileURL
guard bundle.pathExtension == "app", FileManager.default.fileExists(atPath: bundle.path) else {
    fail("no app bundle at \(bundle.path)\n\(usage())")
}
let home = URL(fileURLWithPath: NSHomeDirectory())
let root = URL(fileURLWithPath: rootPath ?? home.appendingPathComponent(".agentspace-gui-check").path)
let deadRoot = URL(fileURLWithPath: root.path + "-dead")
let appBinary = bundle.appendingPathComponent("Contents/MacOS/AgentSpace")
let appName = bundle.deletingPathExtension().lastPathComponent
let bundleID = Bundle(url: bundle)?.bundleIdentifier ?? "unknown"
let reports = Report()

// MARK: - Session preconditions

/// Is this process's session the one on the physical screen?
///
/// The whole premise of this program is a desktop nobody is looking at. If it
/// is started on the console it would open its subject in front of whoever is
/// sitting there — which is precisely the harm it exists to remove, and doing
/// it *without asking* would make this program worse than the gate it replaces.
/// So the premise is enforced rather than assumed, with the same probe the
/// console gate uses. Undetermined is refused too: a session state nobody can
/// read is exactly when a check would mean nothing.
///
/// Two traps, both already paid for in `scripts/gui-verify.sh`: the dictionary
/// carries `kCGSSessionOnConsoleKey` (two S's), not the single-S spelling the
/// documentation suggests, and the value arrives as CFBoolean for one key and
/// CFNumber for the other.
func sessionIsOnConsole() -> Bool? {
    guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
    func flag(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.intValue != 0 }
        return nil
    }
    return flag(dictionary["kCGSSessionOnConsoleKey"]) ?? flag(dictionary["kCGSessionOnConsoleKey"])
}

switch sessionIsOnConsole() {
case .some(true):
    fail("this process is running in the session that is on the physical screen.\n"
        + "  These checks open windows and drive them, so here they would appear in front\n"
        + "  of whoever is sitting at this Mac — the exact disturbance this program was\n"
        + "  written to remove. Nothing has been launched.\n"
        + "      run it where it belongs:   scripts/session-gui-verify.sh\n"
        + "      to verify on the console:  scripts/gui-verify.sh  (which asks first)")
case .none:
    fail("this session's console state could not be read, and a check that cannot say\n"
        + "  what it would disturb does not get to disturb it. Nothing has been launched.")
case .some(false):
    break
}

guard AXIsProcessTrusted() else {
    fail("Accessibility is not granted to this program, so no accessibility tree can be read.\n"
        + "  Run it the way the repository does — inside the agent account's session:\n"
        + "      scripts/session-gui-verify.sh\n"
        + "  A process spawned by the worker's own `exec` inherits the worker's grant; one\n"
        + "  started from a login shell does not, and this program refuses rather than\n"
        + "  reporting the empty tree that results as a failing build.")
}
guard FileManager.default.fileExists(atPath: appBinary.path) else {
    fail("no app bundle at \(bundle.path) — expected \(appBinary.path) inside it")
}
guard FileManager.default.isExecutableFile(atPath: appBinary.path) else {
    fail("\(appBinary.path) is not executable by \(NSUserName()). A bundle under a directory\n"
        + "  this account cannot traverse cannot be tested from its session — check the mode\n"
        + "  of the bundle and of every directory above it.")
}

/// Fresh scratch registry, inside the agent account's home so no permission
/// dance is needed: this program is that account's own process.
func prepareRoot(_ url: URL) {
    let fileManager = FileManager.default
    try? fileManager.removeItem(at: url)
    try? fileManager.createDirectory(at: url.appendingPathComponent("Spaces"),
                                     withIntermediateDirectories: true)
    try? Data(#"{"spaces":[]}"#.utf8)
        .write(to: url.appendingPathComponent("Spaces/index.json"))
}
prepareRoot(root)

func cleanupRoots() {
    if !keepRoot {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: deadRoot)
    }
}

/// A failure that stops the run: the surfaces every remaining check reads cannot
/// exist without the one that just came back missing. The subject is closed and
/// the scratch roots removed first — a gate that leaves an app running in
/// somebody's agent session on its way out is the same rudeness it exists to
/// remove, one session over. The message says the rest was not scored, because
/// "1 failed" reads like a count of 13 and this is not one.
func abort(_ message: String) -> Never {
    quit(runningInstances())
    cleanupRoots()
    FileHandle.standardError.write(Data(("agentspace-gui-check: " + message + "\n").utf8))
    FileHandle.standardError.write(Data("  the remaining checks were not scored — this stopped the run\n".utf8))
    exit(1)
}

// MARK: - Launching the subject

/// Instances of this bundle that are already running *in this session*. The
/// console gate closes every AgentSpace this uid owns; here the scope is
/// narrower on purpose — the same bundle path only — because a different build
/// in the agent session is not this check's business.
func runningInstances() -> [NSRunningApplication] {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { $0.bundleURL?.standardizedFileURL.path == bundle.path }
}

func quit(_ instances: [NSRunningApplication], timeout: TimeInterval = 8) {
    guard !instances.isEmpty else { return }
    for instance in instances { instance.terminate() }
    let until = Date().addingTimeInterval(timeout)
    while Date() < until {
        if instances.allSatisfy({ $0.isTerminated }) { return }
        Thread.sleep(forTimeInterval: 0.3)
    }
    for instance in instances where !instance.isTerminated { instance.forceTerminate() }
    Thread.sleep(forTimeInterval: 1)
}

@discardableResult
func launchSubject(root: URL) -> pid_t {
    let process = Process()
    process.executableURL = appBinary
    process.arguments = ["-NSQuitAlwaysKeepsWindows NO"]
    var environment = ProcessInfo.processInfo.environment
    environment["AGENTSPACE_ROOT"] = root.path
    process.environment = environment
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch {
        abort("could not launch \(appBinary.path): \(error.localizedDescription)")
    }
    return process.processIdentifier
}

/// The console gate's count rule, kept: two equal readings in a row, and a
/// reading of 0 spends the whole budget — a window that has not been ordered on
/// screen yet reads as 0, and agreement does not make a launch further along
/// (§299 rows 641–642).
func settledWindowCount(_ pid: pid_t, seconds: TimeInterval = 15) -> (count: Int, samples: [String]) {
    var previous = ""
    var samples: [String] = []
    let until = Date().addingTimeInterval(seconds)
    while Date() < until {
        let count = AXUI.windows(pid).count
        samples.append("\(count)")
        if "\(count)" == previous && count != 0 { return (count, samples) }
        previous = "\(count)"
        Thread.sleep(forTimeInterval: 1)
    }
    return (AXUI.windows(pid).count, samples)
}

/// What is on screen, when something that should be there is not. A bare
/// "missing" cannot say whether the window never appeared or the control did.
func windowDiagnostics(_ pid: pid_t) -> String {
    let windows = AXUI.windows(pid)
    guard !windows.isEmpty else { return "windows=0" }
    return windows.map { window in
        let title = AXUI.string(window, kAXTitleAttribute as String) ?? ""
        let identifiers = AXUI.descendants(of: window)
            .compactMap { AXUI.identifier($0) }
            .filter { !$0.isEmpty && !$0.hasPrefix("SwiftUI.") }
        let sheetCount = (AXUI.attribute(window, "AXSheets") as? [AXUIElement])?.count ?? 0
        return "[\(title) sheets=\(sheetCount) ids=\(identifiers.prefix(6).joined(separator: ","))]"
    }.joined(separator: " ")
}

// MARK: - Phase A: launch, build stamp, registry notice

let before = runningInstances()
if !before.isEmpty {
    reports.note("closing \(before.count) instance(s) of this bundle already in the agent session")
    quit(before)
}

var pid = launchSubject(root: root)
let settled = settledWindowCount(pid)
reports.check("launch opens exactly one window", "1", "\(settled.count)")
if settled.count != 1 {
    reports.note("  window count samples: \(settled.samples.joined(separator: ","))")
    reports.note("  bundle under test: \(bundle.path) (pid \(pid))")
    reports.note("  \(windowDiagnostics(pid))")
}

// The build number is stamped at bundle time (scripts/bundle-app.sh); if the UI
// ever drifts from the plist, "am I on the new build?" becomes unanswerable.
let short = Bundle(url: bundle)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
let build = Bundle(url: bundle)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
let wanted = "\(short) (\(build))"
let stamp = AXUI.wait(10) { () -> String? in
    for window in AXUI.windows(pid) {
        if let element = AXUI.find(window, identifier: "appBuildVersion"),
           let value = AXUI.string(element, kAXValueAttribute as String), value.contains(wanted) {
            return value
        }
    }
    return nil
}
reports.check("sidebar build stamp matches the bundle", "found", stamp == nil ? "missing" : "found")
if stamp == nil {
    reports.note("  wanted \(wanted) in \(windowDiagnostics(pid))")
}

let notice = AXUI.wait(6) { () -> String? in
    for window in AXUI.windows(pid) {
        if let element = AXUI.find(window, identifier: "registryRootOverrideNotice"),
           let value = AXUI.string(element, kAXValueAttribute as String) { return value }
    }
    return nil
}
// The whole premise of this run is a scratch registry; an owner looking at such
// a window once concluded their Agent had been deleted, so the panel has to say
// which file it read (§300).
reports.check("empty state names the registry it read", contains: root.path, in: notice ?? "missing")

if verbose {
    reports.note("verbose: windows=\(AXUI.windows(pid).count) build=[\(stamp ?? "-")] notice=[\(notice ?? "-")]")
}

// MARK: - Phase B: Settings — the Advanced tab and the Update pane

let settingsOpener = AXUI.pressMenuItem(pid, cmdChar: ",")
Thread.sleep(forTimeInterval: 2)

/// The Settings window, by shape rather than by index: the window server's
/// order is not the app's, and reading `window 1` once scored the dashboard's
/// controls as missing Settings controls (§299 rows 639–640). The settings
/// window carries one toolbar button per tab — five today — while the dashboard
/// carries four of its own, so the count is what separates them.
func settingsWindow() -> AXUIElement? {
    let candidates = AXUI.windows(pid).filter { AXUI.toolbarButtons($0).count >= 5 }
    guard !candidates.isEmpty else { return nil }
    let main = AXUI.mainWindow(pid)
    if let main, let hit = candidates.first(where: { $0 == main }) { return hit }
    return candidates.first
}

guard var settings = settingsWindow() else {
    reports.note("settings opener: \(settingsOpener), \(windowDiagnostics(pid))")
    abort("no window with five toolbar buttons — the Settings window did not open in pid \(pid)")
}
if verbose { reports.note("verbose: settings toolbar = \(AXUI.toolbarButtonTitles(settings))") }

// Advanced is the fourth tab (index 3); Update is the last. The order is a
// contract both gates depend on, and the buttons carry no identifiers, so the
// index is read from the toolbar rather than counted in the source.
let tabs = AXUI.toolbarButtons(settings)
guard tabs.count >= 5 else { abort("settings toolbar has \(tabs.count) buttons, expected 5") }
AXUI.press(tabs[3])
let slider = AXUI.wait(8) { () -> AXUIElement? in
    guard let window = settingsWindow() else { return nil }
    return AXUI.find(window, identifier: "statusRefreshSlider")
}
guard let slider else {
    reports.note("settings opener: \(settingsOpener), \(windowDiagnostics(pid))")
    abort("the Advanced tab revealed no statusRefreshSlider")
}
settings = settingsWindow() ?? settings

let minimum = AXUI.double(slider, "AXMinValue")
let maximum = AXUI.double(slider, "AXMaxValue")
reports.check("refresh slider min=2.0", "2.0", minimum.map { "\($0)" } ?? "missing")
reports.check("refresh slider max=10.0", "10.0", maximum.map { "\($0)" } ?? "missing")

// Read, never clicked: a SwiftUI picker's menu is not in the accessibility tree
// until the menu is open, and clicking one puts the app into menu tracking,
// where the window's own elements stop resolving (§323 row 860).
let picker = AXUI.find(settings, identifier: "displayQualityPicker")
let pickerValue = picker.flatMap { AXUI.string($0, kAXValueAttribute as String) }
// The control's own menu items are the language-proof oracle when they are
// readable; the six shipped spellings are the fallback. Either way the
// assertion is exact, and which rule decided it is printed.
let pickerTitles = picker.map { element in
    AXUI.children(element).compactMap { AXUI.string($0, kAXTitleAttribute as String) }
        .filter { !$0.isEmpty }
} ?? []
let knownModes = ["Native Retina", "原生 Retina", "Balanced", "均衡", "Performance", "性能"]
let modes = pickerTitles.isEmpty ? knownModes : pickerTitles
let qualityVerdict = (pickerValue.map { modes.contains($0) ? "one of the three modes" : $0 }) ?? "missing"
reports.check("display quality control", "one of the three modes", qualityVerdict)
if verbose {
    reports.note("verbose: picker value=[\(pickerValue ?? "-")] items=\(pickerTitles) rule=\(pickerTitles.isEmpty ? "shipped spellings" : "the control's own items")")
}

// The claim worth gating is not "the tab is there" but "the destructive control
// is not on screen yet": `updateInstallButton` lives only in the state a
// verified download produced, so before any of that the pane offers a check and
// a preference and nothing that could replace the app.
AXUI.press(tabs[tabs.count - 1])
let updateWindow = AXUI.wait(8) { () -> AXUIElement? in
    guard let window = settingsWindow() else { return nil }
    return AXUI.find(window, identifier: "softwareUpdatePane") == nil ? nil : window
}
func has(_ identifier: String) -> Bool {
    updateWindow.map { AXUI.find($0, identifier: identifier) != nil } ?? false
}
reports.check("update pane reachable", "y", has("softwareUpdatePane") ? "y" : "n")
reports.check("update check control", "y", has("updateCheckButton") ? "y" : "n")
reports.check("update preference control", "y", has("automaticUpdateCheckToggle") ? "y" : "n")
let checkEnabled = updateWindow.flatMap { AXUI.find($0, identifier: "updateCheckButton") }
    .flatMap { AXUI.bool($0, kAXEnabledAttribute as String) }
reports.check("checking is possible", "enabled", checkEnabled.map { $0 ? "enabled" : "disabled" } ?? "?")
reports.check("install control before a release is verified", "absent",
              has("updateInstallButton") ? "present" : "absent")
if updateWindow == nil {
    reports.note("  update pane not found; \(windowDiagnostics(pid))")
}

// Close the Settings window — *its own* close button, and only that one: a
// sweep over every window with a toolbar once closed the dashboard too.
if let rawClose = AXUI.attribute(settings, kAXCloseButtonAttribute as String) {
    AXUI.press(rawClose as! AXUIElement)
    Thread.sleep(forTimeInterval: 1)
}

// MARK: - Phase C: the New Agent wizard

let wizardOpener = AXUI.pressMenuItem(pid, cmdChar: "n")
let nameField = AXUI.wait(14) { () -> AXUIElement? in
    for window in AXUI.windows(pid) {
        if let field = AXUI.find(window, identifier: "agentNameField") { return field }
    }
    return nil
}
guard let nameField else {
    reports.note("wizard opener: \(wizardOpener)")
    reports.note("  \(windowDiagnostics(pid))")
    abort("the wizard did not open (no agentNameField)")
}

let wizardWindow = AXUI.windows(pid).first { AXUI.find($0, identifier: "agentNameField") != nil }
AXUI.setValue(nameField, "gui verify")

// The account list is filled asynchronously by Directory Service. Reading the
// card once caught it mid-flight and reported an empty state on a machine that
// does have an attachable account (§300), so wait for *either* answer before
// deciding which state the wizard is really in.
enum AccountCard { case picker(AXUIElement), emptyState }
let accountCard = AXUI.wait(10) { () -> AccountCard? in
    guard let wizardWindow else { return nil }
    if let group = AXUI.find(wizardWindow, identifier: "macOSUserPicker") { return .picker(group) }
    if AXUI.find(wizardWindow, identifier: "openUsersGroupsButton") != nil { return .emptyState }
    return nil
}
if case .picker(let group) = accountCard {
    let radios = AXUI.children(group)
    // The first radio item is the unselected placeholder; choosing the first
    // real account exercises the enabled path too.
    if radios.count > 1 {
        AXUI.press(radios[1])
        Thread.sleep(forTimeInterval: 1.5)
    }
}

let wizardVerdict: String
let continueButton: AXUIElement? = {
    guard let wizardWindow else { return nil }
    return AXUI.wait(6) { AXUI.find(wizardWindow, identifier: "wizardContinue") }
}()
if let continueButton, AXUI.bool(continueButton, kAXEnabledAttribute as String) == true {
    AXUI.press(continueButton)
    Thread.sleep(forTimeInterval: 2.5)
    let reachedReview = AXUI.wait(6) { () -> Bool? in
        AXUI.windows(pid).contains { AXUI.find($0, identifier: "createAgentButton") != nil } ? true : nil
    } ?? false
    wizardVerdict = reachedReview ? "step 2" : "continue did not reach review"
} else if let wizardWindow,
          AXUI.find(wizardWindow, identifier: "openUsersGroupsButton") != nil,
          AXUI.find(wizardWindow, identifier: "refreshAccountsButton") != nil {
    wizardVerdict = "empty account state"
} else if continueButton == nil {
    wizardVerdict = "no continue button"
} else {
    wizardVerdict = "account selection required"
}

// A wizard that cannot move forward has three valid explanations and they are
// not interchangeable, so the state is named before it is judged: no attachable
// account (with its own next actions), a helper that is too old for this app,
// or a healthy path to the review card.
let createButton = AXUI.wait(4) { () -> AXUIElement? in
    for window in AXUI.windows(pid) {
        if let button = AXUI.find(window, identifier: "createAgentButton") { return button }
    }
    return nil
}
let createEnabled = createButton.flatMap { AXUI.bool($0, kAXEnabledAttribute as String) }
let helperOutdated = AXUI.windows(pid).contains { window in
    AXUI.descendants(of: window).contains { element in
        AXUI.role(element) == "AXStaticText"
            && (AXUI.string(element, kAXValueAttribute as String) ?? "").contains("HELPER_OUTDATED")
    }
}

switch wizardVerdict {
case "empty account state":
    // The exact next actions, not merely "nothing found".
    reports.check("wizard explains how to add an account", "empty account state", wizardVerdict)
case "step 2":
    reports.check("wizard reaches the helper card", "step 2", wizardVerdict)
default:
    if createButton == nil {
        reports.check("wizard reaches a real next state", "step 2", wizardVerdict)
    } else if helperOutdated {
        reports.check("Create is refused while the helper is stale", "false",
                      createEnabled.map { "\($0)" } ?? "missing")
    } else {
        reports.check("Create is armed for a current helper", "true",
                      createEnabled.map { "\($0)" } ?? "missing")
    }
}
reports.note("wizard: \(wizardVerdict)")

// MARK: - Phase D: a dead deep link raises SPACE_NOT_FOUND

// Relaunched rather than re-used: the wizard phase leaves a sheet up, and the
// console gate reaches the same clean state by restarting the app. The root is
// fresh too, so a misrouted URL cannot be handed a registry this run cares
// about.
quit(runningInstances())
prepareRoot(deadRoot)
pid = launchSubject(root: deadRoot)
_ = settledWindowCount(pid)

let deadID = "11111111-2222-4333-8444-555555555555"
let deadURL = URL(string: "agentspace://space/\(deadID)")!
let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = true
configuration.createsNewApplicationInstance = false
let semaphore = DispatchSemaphore(value: 0)
// Always target the bundle under test: a bare scheme open can route to another
// copy, and the assertion would then inspect the wrong app (§300).
NSWorkspace.shared.open([deadURL], withApplicationAt: bundle, configuration: configuration) { _, error in
    if let error { FileHandle.standardError.write(Data("open url: \(error.localizedDescription)\n".utf8)) }
    semaphore.signal()
}
_ = semaphore.wait(timeout: .now() + 15)

/// The sheet or dialog the alert lives in, wherever this build puts it.
func alertContainers() -> [AXUIElement] {
    var containers: [AXUIElement] = []
    for window in AXUI.windows(pid) {
        if let sheets = AXUI.attribute(window, "AXSheets") as? [AXUIElement] { containers.append(contentsOf: sheets) }
        containers.append(contentsOf: AXUI.descendants(of: window).filter {
            AXUI.role($0) == "AXSheet" || AXUI.role($0) == "AXDialog"
        })
    }
    return containers
}

func staticTexts(_ root: AXUIElement) -> [String] {
    AXUI.descendants(of: root)
        .filter { AXUI.role($0) == "AXStaticText" }
        .compactMap { AXUI.string($0, kAXValueAttribute as String) }
}

// The error code is never localized, which is what makes it the assertion.
let alert = AXUI.wait(12) { () -> String? in
    for container in alertContainers() {
        if let first = staticTexts(container).first, first.contains("SPACE_NOT_FOUND") { return first }
    }
    return nil
}
reports.check("dead link alert", "SPACE_NOT_FOUND", alert.map { String($0.prefix(16)) } ?? "missing")
if alert == nil {
    let seen = alertContainers().map { staticTexts($0) }
    reports.note("  alert containers=\(alertContainers().count) texts=\(seen)")
    reports.note("  \(windowDiagnostics(pid))")
}

// MARK: - Report

quit(runningInstances())
cleanupRoots()
print()
print("agentspace-gui-check (\(appName)): \(reports.summary)")
exit(reports.failed == 0 ? 0 : 1)
