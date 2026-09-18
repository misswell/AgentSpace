# Validation record

Every claim AgentSpace makes about macOS behaviour is recorded here with the
evidence that produced it, and every claim that is **not** yet verified is
listed as such. Plan §63.12 requires this file to be updated at the end of each
phase with actual results rather than intentions.

Machine: MacBook, Apple Silicon (`hw.machine = arm64`), macOS **27.0** (build
26A428), Xcode 26.6, Swift 6.3.3.

Legend: **✓ verified** (ran here) · **~ partial** (a weaker property was
verified) · **✗ not verified** (needs something this machine does not have) ·
**— n/a**

---

## Phase 0 / 1 — status at the end of round 1

| # | Claim | Status | Evidence |
|---|-------|--------|----------|
| 1 | `CGSessionCopyCurrentDictionary()` is the right console signal, and the key is spelled `kCGSSessionOnConsoleKey` | ✓ | `SessionProbe` |
| 2 | The console bit fails closed when unreadable | ✓ | `SessionGuardTests` (7 tests) |
| 3 | `SessionGetInfo` / `sessionHasGraphicAccess` reliably reports whether the session has a window server | ✓ | `SessionProbe` + `testSystemSourceReportsGraphicAccess` |
| 4 | `CGDisplayPixelsWide()` does NOT give pixels on a scaled Retina display | ✓ | `SessionProbe` — the trap is real on macOS 27 |
| 5 | The worker refuses to start without a window server, and refuses to start as root | ~ | refusal logic verified; the *exit code paths* (69/77) not exercised end to end |
| 6 | Every input shape is refused with `SESSION_IS_CONSOLE` when the session is the console | ✓ | `testInputRejectedWhenSessionIsConsoleIntegration` — 9 shapes, live worker, live socket |
| 7 | An unauthorized client is rejected on every method | ✓ | `testUnauthorizedSocketClientRejected` |
| 8 | Two Spaces have independent sockets and tokens, and neither token opens the other | ✓ | `testDifferentSpacesHaveDifferentTokens` |
| 9 | The worker terminates cleanly on SIGTERM and removes its socket | ✓ | manual run, see below |
| 10 | Screenshots come from the worker's own session and match its reported geometry | ~ | `testScreenshotNeverReturnsConsoleSession` — capture-path invariants asserted; cross-session comparison needs a second session |
| 11 | Input really reaches a *background* session and nothing reaches the console | ✗ | **needs a second logged-in macOS user** |
| 12 | A screenshot of a background session is never the console's framebuffer | ✗ | same |
| 13 | Drag gestures work end to end | ✗ | same |
| 14 | Accessibility tree reads succeed in a background session | ✗ | same |
| 15 | App launch registration detection (`APP_LAUNCH_TIMEOUT`) | ✗ | same |
| 16 | The MCP server exposes the CLI over stdio, and the fail-closed refusal survives the MCP boundary | ✓ | `scripts/mcp-smoke.sh` |
| 17 | The SwiftUI app launches, loads the registry, and renders the real worker state | ✓ | `scripts/bundle-app.sh` + captured window, §10 |
| 18 | Clicking the Desktop Viewer's preview maps to the right display point | ~ | `PreviewMappingTests`, 12 tests; the live click needs a background session |

---

## 1. Session dictionary — measured output

`tests/probes/SessionProbe.swift`, run from the console session:

```
== CGSessionCopyCurrentDictionary ==
  CGSSessionUniqueSessionUUID = 25D3E5BE-BA76-4ECB-8D40-65136AB25C35
  kCGSSessionAuditIDKey = 100021
  kCGSSessionGroupIDKey = 20
  kCGSSessionLoginwindowSafeLogin = 0
  kCGSSessionOnConsoleKey = 1
  kCGSSessionSystemSafeBoot = 0
  kCGSSessionUserIDKey = 501
  kCGSSessionUserNameKey = guofeng
  kCGSessionLoginDoneKey = 1
  kCGSessionLongUserNameKey = Guofeng
  kSCSecuritySessionID = 100021
  --> kCGSSessionOnConsoleKey (double-S) present: true value: Optional(1)
  --> kCGSessionOnConsoleKey  (single-S) present: false value: nil
  --> managerName key present: false
```

**Three findings, one of which changes the design.**

1. The key macOS actually writes is the **double-S** `kCGSSessionOnConsoleKey`.
   The single-S spelling that the documented constant name suggests is **not
   present**. `SessionGuard` reads double-S first and accepts single-S as a
   fallback, so a future OS that switches spelling cannot silently disarm the
   guard.
2. **`kCGSSessionManagerNameKey` is not in the dictionary.** The reference
   implementation reads it and falls back to the literal `"Aqua"` — which means
   its `launchctl managername` check is inert on this OS: it always returns
   `"Aqua"` whether or not the session is a GUI session. AgentSpace therefore
   does **not** use it. It uses `SessionGetInfo`'s `sessionHasGraphicAccess`
   bit instead, which is a real answer:
   ```
   == SessionGetInfo (Security framework) ==
     OSStatus = 0
     sessionId = 100021
     raw bits = 0x6030
     sessionIsRoot            = false
     sessionHasGraphicAccess  = true
     sessionHasTTY            = true
     sessionIsRemote          = false
   ```
   This is a design change made because of a measurement, and the plan's §63.13
   is the reason it was measured rather than assumed.
3. `AXIsProcessTrusted()` and `CGPreflightScreenCaptureAccess()` both returned
   `true` **for a probe launched from a terminal**. That is not evidence that the
   *worker* holds those grants: TCC attributes a grant to the **responsible
   process**, which for a CLI is the terminal that launched it. This is why
   `agentspace doctor` labels its own TCC reading "advisory" and asks the worker
   for the real answer instead.

## 2. Display geometry — the scale trap, confirmed

```
== Display geometry ==
  CGDisplayBounds       = (0.0, 0.0, 1920.0, 1080.0)
  CGDisplayPixelsWide   = 1920  (documented as pixels)
  CGDisplayPixelsHigh   = 1080
  mode.width            = 1920  (points)
  mode.pixelWidth       = 3840  (pixels)
  derived scale         = 2.0
  !! CONFIRMED: CGDisplayPixelsWide() returns POINTS, not pixels —
     deriving scale from it yields 1 on a Retina display. Use mode.pixelWidth/mode.width.
```

`CGDisplayPixelsWide()` returned **1920**, the point width, on a display whose
backing store is **3840** wide. Any implementation deriving `scale` from it gets
`1`, and then every coordinate an agent reads off a screenshot is off by a factor
of two.

`DisplayGeometry` therefore takes the scale from
`CGDisplayCopyDisplayMode().pixelWidth / .width`, and:
- `GeometryTests.testScaleComesFromTheDisplayModeNotPixelsWide` pins it;
- `CoordinateRules` rejects an off-display coordinate with a message that names
  `scale`, so the pixel/point mix-up is diagnosable from the error alone;
- `agentspace screenshot` prints the reminder on every human-readable run.

## 3. Window server frontmost

```
== Window server frontmost ==
  on-screen windows: 17
  layer-0: pid=24213 owner=ChatGPT
  layer-0: pid=5852 owner=Zed
  layer-0: pid=11928 owner=IntelliJ IDEA
  NSWorkspace.frontmost = ChatGPT (cache; may be stale)
```

Both agree here. AgentSpace reads the frontmost **pid** from the window list
(layer 0) rather than from `NSWorkspace`, because the worker has no run loop to
service workspace notifications and that cache is documented by the reference
implementation to go stale. `app_list` uses `NSWorkspace` for names and bundle
ids but the window list for "is this app actually on screen".

Note that `loginwindow` and 80-odd helper processes appear in the app list. That
is correct: `accessory` / `LSUIElement` apps must be listed, or every launch of a
menu-bar app looks like a failure. The list is noisy, and thinning it is a GUI
concern rather than a worker one.

---

## 4. Test suite — actual results

```
$ scripts/test.sh
Executed 170 tests, with 1 test skipped and 0 failures (0 unexpected) in 7.43s
```

| Suite | Tests | Failures | Skipped |
|---|---|---|---|
| `ExecGuardTests` | 19 | 0 | 0 |
| `GeometryTests` | 11 | 0 | 0 |
| `InputActionTests` | 35 | 0 | 0 |
| `PreviewMappingTests` | 12 | 0 | 0 |
| `ProtocolTests` | 16 | 0 | 0 |
| `SafetyTests` | 19 | 0 | **1** |
| `SecurityTests` | 24 | 0 | 0 |
| `SessionGuardTests` | 15 | 0 | 0 |
| `SpaceModelTests` | 19 | 0 | 0 |

Plus 19 `node --test` tests in `packages/agentspace-mcp`.

The single skip is `testScreenshotNeverReturnsConsoleSession`. It is written to
**activate automatically** once an AgentSpace session exists; today it asserts
the capture-path invariants and then skips with an explanation, because a
console-versus-background comparison is not observable with one session.

The other 16 safety tests **ran against a live worker binary over a live unix
socket**. In particular
`testInputRejectedWhenSessionIsConsoleIntegration` sent all nine input shapes —
move, click, doubleClick, rightClick, type, key, scroll, drag and a sleep-only
batch — and every one came back `SESSION_IS_CONSOLE`. That is the central claim
of the product, verified rather than asserted.

---

## 5. End-to-end CLI run

`scripts/demo.sh`, actual output (abridged where the app list is long):

```
── $ agentspace list ──
   ● Demo  [Ready]  uid 502  _agentspace_demo
   [exit 0]

── $ agentspace status Demo ──
   Demo — On Console
     uid            501 (guofeng)
     worker         running (pid 55007)
     session        isConsole
     accessibility  granted
     screen record  granted
     display        1920x1080 points, scale 2
   [exit 0]

── $ agentspace exec Demo "id -un; id -u; sw_vers -productVersion" ──
   guofeng
   501
   27.0
   exit 0 (25ms)
   [exit 0]

── $ agentspace exec Demo "sudo whoami" ──
   agentspace: EXEC_DENIED: refused: this command matches the AgentSpace refusal
   rule 'sudo' (privilege escalation is out of scope for an agent session).
     → That command is on AgentSpace's refusal list. ...
   [exit 1]

── $ agentspace exec Demo "exit 7" ──
   exit 7 (25ms)
   [exit 1]                      ← a non-zero exit is a normal result, not an RPC error

── $ agentspace screenshot Demo --max-width 640 ──
   /tmp/as-demo/Runtime/28B1BB6F-.../screenshots/shot-1789712260381.png
     640x360 px, scale 2 — divide pixel coordinates by scale to get input points
   [exit 0]

── $ agentspace move Demo 100 100 ──
   agentspace: SESSION_IS_CONSOLE: refusing to inject input: the 'Demo' session
   is currently on the console, so events would land on the user's own screen.
   [exit 1]
   ... and identically for click, type, key, scroll and drag ...
```

`--json` on the same refusal produces exactly the envelope plan §2 requires:

```json
{
  "error" : {
    "code" : "SESSION_IS_CONSOLE",
    "message" : "refusing to inject input: the 'Demo' session is currently on the console, so events would land on the user's own screen.",
    "recoverable" : true
  },
  "fix" : "The AgentSpace desktop is on your physical display right now. Switch back to your own account; input resumes automatically and is refused until then.",
  "ok" : false,
  "reason" : "SESSION_IS_CONSOLE",
  "status" : "unavailable"
}
```

`agentspace doctor` on this machine:

```
✓ Apple Silicon
✓ macOS 27.0.0
! Input isolated        (this process's session is the physical console — correct
                         for the CLI, and it would refuse input if it were a worker)
✓ WindowServer
✓ Display geometry
! Privileged helper     (/Library/LaunchDaemons/com.agentspace.AgentSpace.Helper.plist
                         is not installed — phase 3)
✓ Fast User Switching
✓ AgentSpaces
! Worker (Demo)         (running but refusing input: onConsole = true)
✓ Unix socket path
! Workspace confinement (no space.json yet — phase 7)
✓ This process's TCC grants (advisory)

12 checks, 4 warning(s). AgentSpace can run.
```

Every warning above is an accurate description of a component that has not been
built yet, not a failure.

---

## 6. Bugs found by running things, not by reading them

Three defects were found only because the code was executed. All three are fixed
and re-verified.

**1. The worker ignored SIGTERM.** `DispatchSource.makeSignalSource(…, queue:
.main)` was paired with a `serve()` loop that blocks the main thread in
`accept()`, so the handler could never run and the process ignored `SIGTERM`
outright. A shell `wait`ing on it hung forever; only `SIGKILL` worked. Fixed by
giving the signal sources their own queue, which libdispatch services on worker
threads. Re-verified:

```
worker pid=54658 running=yes
socket exists: yes
RESULT: worker exited on SIGTERM
socket removed: yes
```

**2. `--json` was parsed as a value-taking flag.** `agentspace status --json`
answered `--json requires a value` and printed the usage text. Found by the
end-to-end script, fixed by moving it to the boolean set, re-verified above.

**3. Test harness socket paths overflowed `sun_path`.** `NSTemporaryDirectory()`
is already ~50 bytes under `/var/folders`, and the runtime layout adds
`/Runtime/<uuid>/worker.sock`. The resulting path exceeded the 103-byte
`sockaddr_un.sun_path` limit, so the worker refused to bind — correctly — and
every integration test skipped. It surfaced as "13 of 17 safety tests skipped"
rather than as a pass, which is the point of having the harness skip loudly.
Fixed by using a short `/tmp/as-<8 hex>` root, and the harness now asserts
`socketPathFits` before starting.

A fourth, silent problem was caught by the `--json` output above rather than by a
test: `KeyCombo.parse` mis-split `cmd++` into a modifier list containing an empty
string, so command-plus was rejected. Rewritten to treat a trailing `+` as naming
the `+` key.

---

## 7. Not verified — and what each one needs

Stated plainly, because plan §63.12 requires the actual result rather than a
hopeful one. **All five need the same thing: a second macOS user with a live
background Aqua session.** That requires creating a user, which requires root,
and this session has no passwordless `sudo` and approval prompts are disabled.
The privileged helper that will do it is phase 3.

| Not verified | Why it matters | What it needs |
|---|---|---|
| Input delivered to a background session, and the console untouched | The entire product claim | A second user logged in via fast user switching |
| `cgSessionEventTap` routing to a background session's key window | Whether input works at all | same |
| A background screenshot is not the console's framebuffer | The other half of the product claim | same |
| Drag gestures | AppKit drag tracking is timing-sensitive; the reference implementation reports it as unreliable | same |
| Accessibility tree over a real app in a background session | Whether AX is a usable grounding path | same |
| Worker exit codes 69 (`NO_WINDOW_SERVER`) and 77 (`WORKER_IS_ROOT`) | Startup refusal paths | A no-WindowServer session, and root |
| `APP_LAUNCH_TIMEOUT` | Launch registration detection | A background session |
| Privileged helper, `SMAppService`, user creation, ACLs | Phases 3 and 4 | Root, or a signed app bundle |
| Multi-Space concurrency (plan §48: A types `AAA`, B types `BBB`, console unaffected) | Phase 4 | Two background sessions |

### What unblocks them

1. **A human grants `sudo` once** to create `_agentspace_*` users, or phase 3's
   helper is built and signed. There is no way around this: creating a macOS user
   is a root operation and AgentSpace deliberately has no unprivileged path to it.
2. After one fast-user-switch login into the AgentSpace user, the worker starts
   from its LaunchAgent and every `✗` above becomes testable. The tests are
   already written to activate — they skip today and assert tomorrow.

### Standing procedure for closing these

```bash
scripts/test.sh          # must stay green before any of the below
agentspace doctor        # confirms the session state
# then, with a background AgentSpace session live:
#   run the suite a second time *from inside that session* so both halves fire
```

---

## 8. Reference-implementation divergences

Where this implementation deliberately differs from `viraatdas/offstage`, with
the reason. Offstage is MIT; see `THIRD_PARTY_NOTICES.md`.

| Area | Offstage | AgentSpace | Why |
|---|---|---|---|
| Console key | double-S, then single-S fallback | same | Measured; the fallback costs nothing |
| "Is this an Aqua session?" | reads a dictionary key that is absent, so it always answers `"Aqua"` | `SessionGetInfo`'s `sessionHasGraphicAccess` | The former is inert on macOS 27; the latter is a real answer |
| Error vocabulary | lowercase kebab (`on-console`) | UPPER_SNAKE (`SESSION_IS_CONSOLE`) | The plan fixes these names in §21 and the MCP/CLI surface depends on them |
| Input validation | all-or-nothing | all-or-nothing, plus per-index messages naming the offending action | A model that sends a malformed action must be able to fix it from the error alone |
| Click without coordinates | rejected | rejected, and the deviation from the plan's §14 example is pinned by a test | Same; the test makes the divergence visible rather than implicit |
| Token | none — the socket directory is the only control | 256-bit per-Space token, constant-time compared | A compromise inside one Space must not drive a sibling Space (§20) |
| Interactive input | `CGEvent` posting only | same, behind an injectable guard so it is unit-testable | Untestable safety code is safety code nobody has run |
| `exec` | `run`, streaming events | `exec`, buffered `{exitCode, stdout, stderr, duration}` | The plan fixes the buffered shape in §23 |
| Screenshot | base64 in the reply | a file in the Space runtime directory, base64 only on request | Keeps the default reply small; the path is readable by both the main user and the agent user |

---

## 9. MCP server — verified end to end

The MCP server is a bridge, not a second implementation: it spawns the
`agentspace` CLI with `--json` and relays the result. That is only worth anything
if the refusal survives the extra hop, so `scripts/mcp-smoke.sh` speaks real MCP
JSON-RPC over the child's stdio — `initialize` → `tools/list` → `tools/call` —
exactly as a client would. Actual output:

```
== initialize ==
  PASS  initialize returns a server name
     server: agentspace 0.1.0
  PASS  instructions recommend the status -> screenshot -> input loop
  PASS  instructions warn about SESSION_IS_CONSOLE
== tools/list ==
     14 tools
  PASS  tool agentspace_list exists
  ... (all 14)
  PASS  no tool can create a Space
  PASS  every tool has a description
  PASS  every tool has an input schema
== tools/call agentspace_status ==
  PASS  status call returns content
     { "acceptsInput": false, "accessibility": true,
       "display": { "height": 1080, "scale": 2, ...
== tools/call agentspace_{click,type,key} — must be refused, not fall back ==
  PASS  agentspace_click reports an error
  PASS  agentspace_click names SESSION_IS_CONSOLE
  PASS  agentspace_click includes the fix text
  PASS  agentspace_click says nothing about running locally
  ... identically for agentspace_type and agentspace_key ...
== unknown tool is refused ==
  PASS  unknown tool errors

all MCP smoke checks passed
```

Two assertions in that list are the ones that matter:

- **`names SESSION_IS_CONSOLE`** — the refusal is not swallowed or generalised
  into "something went wrong". A model that gets this string can tell the
  difference between "I did the wrong thing" and "the human is looking at this
  desktop".
- **`says nothing about running locally`** — the MCP layer does not invent a
  fallback, mention one, or apologise for not having one. Plan §2's rule has to
  hold at every boundary, and this is the boundary a model actually talks to.

Also asserted: `no tool can create a Space`. There is no
`agentspace_create_space`, and no TCC-grant tool, because those change the
machine and require a human in the GUI — a tool that existed would eventually be
called. The absence is the control.

`packages/agentspace-mcp`'s own unit tests (`npm test`, 19 tests) cover argument
construction only, and one of them asserts that **no builder ever returns a shell
string** — the MCP server spawns the CLI with an argument vector and never
concatenates a command, so an agent-supplied `space` or `command` cannot inject
one.

### Status honesty

`agentspace_status` returns `"acceptsInput": false` above, from a live worker
whose session is the console. That field is the one a well-behaved MCP client
should read before deciding whether to send input at all, and it is derived from
the same `SessionGuard` verdict that gates the input path — not from a separate
guess that could disagree with it.

---

## 10. The SwiftUI app — verified by looking at it

The GUI cannot be confirmed by compiling it. `scripts/bundle-app.sh` builds a
signed `AgentSpace.app` (Developer ID, TeamIdentifier `U8U443D7ZL`), and the app
was launched against a two-Space registry with one worker actually running. The
window was then captured **by window id** rather than by screen region, so the
capture is the app's own content and not whatever happened to be on top of it:

```
$ /tmp/windowlist AgentSpace
WINDOWID PID     LAYER  BOUNDS            OWNER / TITLE
10964    18120   0      900x612@538,250   AgentSpace — Frontend Test

$ screencapture -x -o -l10964 /tmp/guiwindow.png
```

The result showed, from real data rather than fixtures:

- the sidebar with both Spaces and their *effective* states — `Frontend Test / On
  Console` in orange, `Safari Test / Needs Login` in yellow;
- `User  _agentspace_a37f91 (uid 502)`, `Worker  running (pid 18115)`,
  `Session  isConsole`, `Accepts input  no`;
- `Accessibility` and `Screen Recording` chips both green, read from the worker;
- `Points 1920 × 1080`, `Scale 2×`;
- live resources with a process count in the hundreds.

Two of those lines were **wrong**, and the screenshot is the only reason they were
caught. Details in §11.

`tests/probes/WindowListProbe.swift` is what made this possible, and it is worth
keeping: `screencapture -R x,y,w,h` captures a screen *region* and therefore
whoever is on top, so it is useless for verifying that one app rendered. Only
`screencapture -l <id>` isolates the window, and the id is reachable only through
`CGWindowListCopyWindowInfo`.

### Why the window came up behind everything

Launching the bundled binary directly from a shell — `AGENTSPACE_ROOT=… 
dist/AgentSpace.app/Contents/MacOS/AgentSpace` — gives the process the bundle's
identity (so TCC attributes correctly) but does **not** ask the window server to
activate it, so it appears behind existing windows. `open -a` activates properly
but gives no way to pass the environment. `osascript … set frontmost` did not
raise it either. The AX window query and `screencapture -l` worked anyway, which
is the reason to prefer them over a region capture.

## 11. Bugs found by looking at the running app

Four defects were found after everything compiled and all tests passed. Three of
them a test could not have found, because each was a *disagreement between two
correct components* rather than a failure inside one.

### 1. `agentspace` and `AgentSpace` are the same file on macOS

The package declared two executable products, `agentspace` (CLI) and `AgentSpace`
(GUI). The default macOS filesystem is **case-insensitive**, so both were written
to the same path in `.build/debug` and one silently overwrote the other. The
symptoms were bizarre and gave no hint of the cause:

- the app bundle contained no CLI at all, though `cp` reported success;
- `agentspace --version` printed no version — it started a **SwiftUI event loop
  and hung forever**, because the file at that path was the GUI;
- the bundle's `AgentSpace` was the CLI, so the app did not exist either.

Nothing errored. Confirmed the filesystem fact directly:

```
$ echo AAA > Foo && echo BBB > foo && cat Foo
BBB
```

Fixed by naming the GUI's SwiftPM product `AgentSpaceApp` (the bundle renames it
to `AgentSpace` on the way in, where the destinations genuinely differ) and
putting the CLI in `Contents/Helpers/agentspace`. Two guards now make it
impossible to reintroduce: `bundle-app.sh` refuses to finish if the GUI and CLI
binaries have the same SHA-256, and `build.sh` runs `agentspace --version` and
requires it to print a version.

### 2. `--version` dumped the help text

`agentspace --version` printed the usage and exited 2, because `--version` is a
boolean flag, so `positionals` was empty and the empty-command check fired before
the version branch. `--help` was handled; `--version` was overlooked. Fixed, and
`build.sh` now asserts the output, so a CLI that cannot answer `--version` fails
the build rather than shipping.

### 3. `status` reported the display in only one coordinate space

`hello` returned `width`, `height`, `pixelWidth`, `pixelHeight` and `scale`.
`status` returned only the first two and `scale`. Both were "correct" against
their own tests; the disagreement only showed up as `Pixels 0 × 0` in the app's
Display card, and would have cost the Desktop Viewer its mapping fallback before
the first capture arrives. Fixed, documented in `docs/protocol.md`, and pinned by
`testStatusReportsBothCoordinateSpaces`, which asserts that `hello` and `status`
agree — the cross-check that neither side's own tests could make.

### 4. The preview mapping was wrong for a downscaled capture

`PreviewMapping` initially converted a click by dividing the image's pixel
coordinate by the backing scale. That is right only when the image *is* the
framebuffer. A `--max-width 640` preview of a 1920×1080-point display has three
different widths in play, and the click landed at 320 instead of 960 — a third of
the way across the screen, with no error. `PreviewMappingTests` caught it before
the app existed: the type now carries the display's **point** size and works in
fractions, so a downscale cannot move a click, and the backing scale is not a
parameter at all.

The same file also pinned the off-by-one at the bottom-right corner: rounding
gave `displayWidth`, one point off the display, which the worker would reject as
`INVALID_COORDINATE` — a bug that would have looked like an agent problem.

### The pattern

Three of these four were only visible by *running the thing and looking at it*.
The plan's §63.13 says not to guess macOS behaviour and to write minimal programs
to check it; this round suggests the rule generalises to the product too — a
green suite over correctly-unit-tested parts said nothing about whether the parts
agreed with each other.
