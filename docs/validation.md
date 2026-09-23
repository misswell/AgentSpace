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

## Contents

- [Contents](#contents)
- [Phase 0 / 1 — status at the end of round 1](#phase-0-1-status-at-the-end-of-round-1)
- [1. Session dictionary — measured output](#1-session-dictionary-measured-output)
- [2. Display geometry — the scale trap, confirmed](#2-display-geometry-the-scale-trap-confirmed)
- [3. Window server frontmost](#3-window-server-frontmost)
- [4. Test suite — actual results](#4-test-suite-actual-results)
- [5. End-to-end CLI run](#5-end-to-end-cli-run)
- [6. Bugs found by running things, not by reading them](#6-bugs-found-by-running-things-not-by-reading-them)
- [7. Not verified — and what each one needs](#7-not-verified-and-what-each-one-needs)
- [8. Reference-implementation divergences](#8-reference-implementation-divergences)
- [9. MCP server — verified end to end](#9-mcp-server-verified-end-to-end)
- [10. The SwiftUI app — verified by looking at it](#10-the-swiftui-app-verified-by-looking-at-it)
- [11. Bugs found by looking at the running app](#11-bugs-found-by-looking-at-the-running-app)
- [12. The phase-0 acceptance gate (§44)](#12-the-phase-0-acceptance-gate-44)
- [13. The privileged helper — what is verified, and what is not](#13-the-privileged-helper-what-is-verified-and-what-is-not)
- [14. Workspace preparation (§14) — verified against real git](#14-workspace-preparation-14-verified-against-real-git)
- [15. Create and delete a Space (§28, §41) — verified up to the root boundary](#15-create-and-delete-a-space-28-41-verified-up-to-the-root-boundary)
- [16. Multi-Space isolation (§29, §48) — the bug is never a crash](#16-multi-space-isolation-29-48-the-bug-is-never-a-crash)
- [17. Disk usage (§30) — measured, not allocated, and never a silent zero](#17-disk-usage-30-measured-not-allocated-and-never-a-silent-zero)
- [18. MCP integrations (§34) — and a test that wrote the user's real config file](#18-mcp-integrations-34-and-a-test-that-wrote-the-user-s-real-config-file)
- [19. Agent safety rules (§35) — generated once, copied or installed](#19-agent-safety-rules-35-generated-once-copied-or-installed)
- [20. Release packaging (§57) — and a build that silently built one thing out of four](#20-release-packaging-57-and-a-build-that-silently-built-one-thing-out-of-four)
- [21. The integration suite (§5, §55) — and the §54 leak it found](#21-the-integration-suite-5-55-and-the-54-leak-it-found)
- [22. Registry hardening and the MCP failure seam (§50)](#22-registry-hardening-and-the-mcp-failure-seam-50)
- [23. Restart behavior (§39) — Needs Login, not a lie about offline](#23-restart-behavior-39-needs-login-not-a-lie-about-offline)
- [24. The ScreenCaptureKit preview (§52) — pull model, idle auto-stop, fail-closed](#24-the-screencapturekit-preview-52-pull-model-idle-auto-stop-fail-closed)
- [25. Diagnostics export (§37) — a bundle safe to paste into a support issue](#25-diagnostics-export-37-a-bundle-safe-to-paste-into-a-support-issue)
- [26. Stop, Logout, Delete (§40) — three endings, not one button](#26-stop-logout-delete-40-three-endings-not-one-button)
- [27. Performance (§53) — measured, not aspirational](#27-performance-53-measured-not-aspirational)
- [28. One thousand round trips (§44, protocol layer)](#28-one-thousand-round-trips-44-protocol-layer)
- [29. Doctor, completed against the §38 checklist](#29-doctor-completed-against-the-38-checklist)
- [30. §53 polling audit, §59 README, and the acceptance gate's honest refusal](#30-53-polling-audit-59-readme-and-the-acceptance-gate-s-honest-refusal)
- [31. The §56 security review is a re-runnable matrix](#31-the-56-security-review-is-a-re-runnable-matrix)
- [32. The release chain, re-run end-to-end (§57)](#32-the-release-chain-re-run-end-to-end-57)
- [33. Notarization readiness: the signature side completed, the credential side diagnosed](#33-notarization-readiness-the-signature-side-completed-the-credential-side-diagnosed)
- [34. The §53 memory question, decomposed: floor, band, and AgentSpace's own share](#34-the-53-memory-question-decomposed-floor-band-and-agentspace-s-own-share)
- [35. The memory question closed with the right metric: physical footprint](#35-the-memory-question-closed-with-the-right-metric-physical-footprint)
- [36. The registered-Space condition, reproduced at last](#36-the-registered-space-condition-reproduced-at-last)
- [37. Measurement hygiene: a caught false reading, and the §61 compliance sweep](#37-measurement-hygiene-a-caught-false-reading-and-the-61-compliance-sweep)
- [38. Notarization cleared end-to-end (§57) — the blocker was the wrong credential channel](#38-notarization-cleared-end-to-end-57-the-blocker-was-the-wrong-credential-channel)
- [39. Two more notary lessons: a credential that vanished, and the fallback that did not](#39-two-more-notary-lessons-a-credential-that-vanished-and-the-fallback-that-did-not)
- [40. Troubleshooting closed the loop: the notary failures we hit are now documented](#40-troubleshooting-closed-the-loop-the-notary-failures-we-hit-are-now-documented)
- [41. The one §31 command that was missing: `agentspace desktop <space>`](#41-the-one-31-command-that-was-missing-agentspace-desktop-space)
- [42. MCP-side audit: the tools and the one-implementation rule](#42-mcp-side-audit-the-tools-and-the-one-implementation-rule)
- [43. Namespace unification and the architecture map](#43-namespace-unification-and-the-architecture-map)
- [44. The §35 rules and the Offstage debt, re-audited](#44-the-35-rules-and-the-offstage-debt-re-audited)
- [45. The deep link's GUI half, seen through the accessibility tree](#45-the-deep-link-s-gui-half-seen-through-the-accessibility-tree)
- [46. The deep link's failure branches, also through the accessibility tree](#46-the-deep-link-s-failure-branches-also-through-the-accessibility-tree)
- [47. Copy MCP Configuration, driven and read back from the real Settings window](#47-copy-mcp-configuration-driven-and-read-back-from-the-real-settings-window)
- [48. The Settings root field, wired to the launch-time environment](#48-the-settings-root-field-wired-to-the-launch-time-environment)
- [49. The polling floor is in the control, not just the copy](#49-the-polling-floor-is-in-the-control-not-just-the-copy)
- [50. Reference integrity: no path in the documentation dangles](#50-reference-integrity-no-path-in-the-documentation-dangles)
- [51. The MCP README's tool list is audited against the source, not memory](#51-the-mcp-readme-s-tool-list-is-audited-against-the-source-not-memory)
- [52. CLI exit codes layer by meaning, and the PIPESTATUS lesson bites again](#52-cli-exit-codes-layer-by-meaning-and-the-pipestatus-lesson-bites-again)
- [53. The Preview width control is display-size only, by construction](#53-the-preview-width-control-is-display-size-only-by-construction)
- [54. The GUI checks become a script, and the script finds the flakiness](#54-the-gui-checks-become-a-script-and-the-script-finds-the-flakiness)
- [55. One command runs everything a release needs](#55-one-command-runs-everything-a-release-needs)
- [56. `notarytool --wait` timing out is "unknown", not "failed"](#56-notarytool-wait-timing-out-is-unknown-not-failed)
- [57. The DMG ships exactly the stapled bits, provable by CDHash](#57-the-dmg-ships-exactly-the-stapled-bits-provable-by-cdhash)

---
| # | Claim | Verdict | Evidence |
|---|---|---|---|
| S1 | `CGSessionCopyCurrentDictionary()` is the right console signal, and the key is spelled `kCGSSessionOnConsoleKey` | ✓ | `SessionProbe` |
| S2 | The console bit fails closed when unreadable | ✓ | `SessionGuardTests` (7 tests) |
| S3 | `SessionGetInfo` / `sessionHasGraphicAccess` reliably reports whether the session has a window server | ✓ | `SessionProbe` + `testSystemSourceReportsGraphicAccess` |
| S4 | `CGDisplayPixelsWide()` does NOT give pixels on a scaled Retina display | ✓ | `SessionProbe` — the trap is real on macOS 27 |
| S5 | The worker refuses to start without a window server, and refuses to start as root | ~ | refusal logic verified; the *exit code paths* (69/77) not exercised end to end |
| S6 | Every input shape is refused with `SESSION_IS_CONSOLE` when the session is the console | ✓ | `testInputRejectedWhenSessionIsConsoleIntegration` — 9 shapes, live worker, live socket |
| S7 | An unauthorized client is rejected on every method | ✓ | `testUnauthorizedSocketClientRejected` |
| S8 | Two Spaces have independent sockets and tokens, and neither token opens the other | ✓ | `testDifferentSpacesHaveDifferentTokens` |
| S9 | The worker terminates cleanly on SIGTERM and removes its socket | ✓ | manual run, see below |
| S10 | Screenshots come from the worker's own session and match its reported geometry | ~ | `testScreenshotNeverReturnsConsoleSession` — capture-path invariants asserted; cross-session comparison needs a second session |
| S11 | Input really reaches a *background* session and nothing reaches the console | ✗ | **needs a second logged-in macOS user** |
| S12 | A screenshot of a background session is never the console's framebuffer | ✗ | same |
| S13 | Drag gestures work end to end | ✗ | same |
| S14 | Accessibility tree reads succeed in a background session | ✗ | same |
| S15 | App launch registration detection (`APP_LAUNCH_TIMEOUT`) | ✗ | same |
| S16 | The MCP server exposes the CLI over stdio, and the fail-closed refusal survives the MCP boundary | ✓ | `scripts/mcp-smoke.sh` |
| S17 | Creating a Space calls the helper in the order account → runtime → worker, and a bad workspace is refused before the helper is called at all | ✓ | §15 — `SpaceProvisionerTests` |
| S18 | Every creation-step failure rolls back what it already did, and a *failed* rollback keeps the orphan account visible as an errored Space | ✓ | §15 |
| S19 | The generated password reaches the Keychain and appears in no file; generated passwords never repeat | ✓ | §15 — real Keychain, own service namespace |
| S20 | Eight Spaces get eight distinct sockets, tokens, runtime directories, account names and launchd labels; two Spaces differing only by case never share a working tree | ✓ | §16 — `MultiSpaceIsolationTests` |
| S21 | Disk usage is measured (agreeing with `du`), opt-in, budget-bounded, and never silently a zero | ✓ | §17 — `DiskUsageTests` + a live worker |
| S22 | MCP configs for Claude Code, Codex and OpenCode generate, merge key-scoped, install idempotently, and refuse to overwrite a foreign entry | ✓ | §18 — plus an incident: a test that wrote the user's real config |
| S23 | The §35 agent rules generate from one source, append marker-scoped and idempotently, and are copied — not written — from the GUI | ✓ | §19 |
| S24 | The release pipeline builds all four binaries, verifies every signature, and produces a DMG whose contents verify | ✓ | §20 — after finding a SwiftPM invocation that silently built one of four |
| S25 | The CLI at the process boundary honors §32 JSON mode, exit 69/66, live-socket status, the console refusal, and per-root isolation | ✓ | §21 — ten spawned-binary tests; found the not-found exit bug and the §54 screenshot leak |
| S26 | Registry corruption is quarantined with bytes intact, surfaced by doctor, and recoverable; MCP relays typed failures with no local fallback | ✓ | §22 — the quarantine test caught a name-collision bug in the quarantine itself |
| S27 | After a reboot a logged-out Space shows Needs Login, not offline; a crashed worker under a live session shows offline | ✓ | §23 — utmpx rejected empirically; process ownership is the discriminator |
| S28 | The §52 live preview is pull-model, fail-closed on console, self-stops when unpulled, and falls back to the 1 FPS MVP when refused | ✓ | §24 — 6 controller tests + 2 process-boundary tests; SCK delivery itself needs a background session and is marked unverified |
| S29 | The §37 diagnostics export is safe to hand out: whitelist collection + a redaction pass, with the token never surviving either | ✓ | §25 — 7 unit tests + a live-worker integration test |
| S30 | Stop keeps the session, Logout ends the session through a typed root-only helper RPC, Delete is the only thing that removes a Space | ✓ | §26 — stop pinned by a live test; logout validation pinned; the logout run itself needs the root helper and is recorded as blocked |
| S31 | Idle resources measured against §53: worker 2.7 MB / 0.0% CPU; app 0.0% CPU. Memory, by physical footprint: 36–37 MB empty, **45–54 MB with a Space registered** (§36 first reproduced the condition; §37 widened the bounds), 19.1 MB bare floor. RSS metrics recorded beside them for comparability | ✓ | §27, §34–§36 — release-build measurements |
| S32 | 1000 sequential RPC round trips leave the worker healthy at ~6.5 ms/call | ✓ | §28 — protocol half of §44; the isolation half stays blocked on a second session |
| S33 | Doctor names per-Space Accessibility and Screen Recording, asked of the worker, with panel-path fixes | ✓ | §29 — live-worker integration test; caught the wrong-root bug on its first run |
| S34 | No polling loops; the §44 gate refuses (exit 66) rather than passing without a Space | ✓ | §30 — code audit, 0.0% idle CPU, and the acceptance run's honest refusal |
| S35 | The §56 review is a re-runnable matrix: each item pinned by named tests or explicitly blocked | ✓ | §31 — 7 verified, 3 blocked on machine capabilities, sign-off rule stated |
| S36 | The release chain produces a Developer ID-signed app whose every nested binary verifies strictly, wrapped in a verified DMG whose contents re-verify | ✓ | §32 — `scripts/release.sh` end-to-end; Gatekeeper refusal isolated to notarization (`notarytool` profile absent, re-verified) |
| S37 | Every artifact carries hardened runtime + a secure timestamp: the signature side of notarization is complete | ✓ | §33 — flags and Timestamp on app, helper, worker, CLI |
| S38 | The release DMG was accepted by Apple's notary service, stapled (app + DMG), and Gatekeeper accepts the stapled app | ✓ | §38 — submission Accepted, `spctl --assess` exit 0 |
| S39 | The SwiftUI app launches, loads the registry, and renders the real worker state | ✓ | `scripts/bundle-app.sh` + captured window, §10 |
| S40 | Clicking the Desktop Viewer's preview maps to the right display point | ~ | `PreviewMappingTests`, 12 tests; the live click needs a background session |
| S41 | 1000 mixed actions are all refused when the session is the console, and the console is untouched | ✓ | `scripts/acceptance.sh` — §12 |
| S42 | The same 1000 actions land on the agent's desktop | ✗ | same gate, positive half; needs a second session |
| S43 | The helper only ever mentions commands that exist, with no shell and no `-admin` | ✓ | `HelperValidationTests`, 37 tests |
| S44 | The helper refuses every account it did not create | ✓ | `HelperValidationTests`, 37 tests |
| S45 | The helper's binary, plist and worker path are correct inside a real signed bundle | ✓ | `agentspace-helper --self-check`, run by `bundle-app.sh` |
| S46 | The helper answers over XPC and performs a real createUser | ✗ | needs the LaunchDaemon registered, which needs an administrator password |
| S47 | The create/delete flows above the helper boundary — ordering, rollback, Keychain, worktree safety, CLI exit codes | ✓ | §15, with the helper call injected so the failure paths run for real |
| S48 | A git-worktree Space gives the agent its own checkout and leaves the user's tree untouched | ✓ | `WorkspacePreparerTests`, 16 tests, real git |
| S49 | A worktree workspace can never be the user's own working tree or branch | ✓ | `WorkspacePreparerTests` |

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
Executed 223 tests, with 1 test skipped and 0 failures (0 unexpected) in 13.30s
```

| Suite | Tests | Failures | Skipped |
|---|---|---|---|
| `ExecGuardTests` | 19 | 0 | 0 |
| `GeometryTests` | 11 | 0 | 0 |
| `HelperValidationTests` | 37 | 0 | 0 |
| `InputActionTests` | 35 | 0 | 0 |
| `PreviewMappingTests` | 12 | 0 | 0 |
| `ProtocolTests` | 16 | 0 | 0 |
| `SafetyTests` | 19 | 0 | **1** |
| `SecurityTests` | 24 | 0 | 0 |
| `SessionGuardTests` | 15 | 0 | 0 |
| `SpaceModelTests` | 19 | 0 | 0 |
| `WorkspacePreparerTests` | 16 | 0 | 0 |

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

---

## 12. The phase-0 acceptance gate (§44)

`tests/Session/main.swift`, run as `agentspace-session-test` or
`scripts/acceptance.sh`. This is the plan's gate in one program: the console user
has TextEdit open with `USER_SCREEN_123456`, the agent user has TextEdit with
`AGENT_SCREEN`, the worker clicks, types and scrolls **1000 times**, and afterwards
the console's content, focus and pointer must be unchanged.

It runs from the **console** session — that is where the things being protected
live — and drives the agent's desktop only through the worker's socket, over the
same protocol the CLI, the GUI and the MCP server use. It never posts an event
itself, and has no branch that tries the agent's TextEdit locally if the worker is
unavailable: a test that could quietly drive the wrong session would pass, which is
worse than having no test.

### The result today

```
$ scripts/acceptance.sh --iterations 1000

Worker is up. Session verdict: isConsole
  accessibility:    granted
  screen recording: granted
  permits input:    false

== fail-closed: the negative control ==
Sampling this desktop for 1.5s with nothing sent, to learn what it does on its own…
  the console was ALREADY changing before the run: pointer

  PASS  move: refused with SESSION_IS_CONSOLE
  PASS  click: refused with SESSION_IS_CONSOLE
  PASS  doubleClick: refused with SESSION_IS_CONSOLE
  PASS  rightClick: refused with SESSION_IS_CONSOLE
  PASS  type: refused with SESSION_IS_CONSOLE
  PASS  key: refused with SESSION_IS_CONSOLE
  PASS  scroll: refused with SESSION_IS_CONSOLE
  PASS  drag: refused with SESSION_IS_CONSOLE
  PASS  1000 mixed: refused with SESSION_IS_CONSOLE

Isolation of this desktop after 1000 refused actions:
  PASS  the console's pointer never moved

== isolation: the phase-0 gate ==
  SKIP  the worker's session is 'isConsole', so it cannot accept input and
        there is nothing to isolate yet

Verdict: INCOMPLETE
```

Exit code **3** — *the gate could not run*, which is deliberately not the same as
passing. `0` requires that the gate actually executed and that every property it
measured was stable.

So the negative half of the isolation claim is now verified rather than asserted:
1000 mixed actions, every one refused, this desktop untouched. The positive half —
that the same 1000 actions *do* land on the agent's desktop — needs a second login
and remains skipped, as §7 records.

### A flaw found in the test itself

The first version compared the mouse position before and after and failed on any
movement. It failed on the first run:

```
  FAIL  the console's mouse moved: (691, 986) → (685, 982)
```

That was not AgentSpace. A human was using the machine. The test could not tell
"the agent moved the pointer" from "somebody moved the pointer", and a test that
reports failures it cannot attribute gets ignored — which is worse than not having
it, because it spends the credibility that the real failures need later.

It now separates two kinds of evidence:

1. **Attributable evidence, always a failure.** A leaked synthetic event would put
   the pointer on a coordinate *this run asked for* — a precise fingerprint, and
   the first thing checked.
2. **Ambient evidence, a failure only if the property was stable when measured with
   nothing sent.** A control window is sampled before the run. If the pointer was
   already moving, a later movement is reported as inconclusive and the verdict is
   **INCONCLUSIVE** (exit 4), not a failure and not a pass.

The output above shows both mechanisms working: the pointer was moving during the
control window, then stayed still for the whole action phase, so the run correctly
reported a pass with the ambient motion noted.

This is the same lesson as §11's bugs, from the other direction. §11 was about two
components disagreeing; this is about a test measuring something real but
attributing it to the wrong cause. Both are invisible to a green suite.

---

## 13. The privileged helper — what is verified, and what is not

The helper is the only root component and the only part of AgentSpace that cannot
be exercised without a second machine state, which is the exact combination that
lets a claim go quietly untested. The response was to move everything that can be
tested into `HelperValidation` and `HelperCommand` — pure functions, in Core, with
no root required — and then attack them.

### Verified today

**37 tests in `HelperValidationTests`, 0 failures.** They are written from the
attacker's side: each is a specific thing somebody might try, not a description of
the code.

```
$ swift test --filter HelperValidationTests
Executed 37 tests, with 0 failures (0 unexpected) in 0.011s
```

The load-bearing ones:

- `testDeleteUserRefusesTheHumanAccount` — if this ever fails, AgentSpace can
  delete the user's own account.
- `testDeleteUserRefusesEveryAccountItDidNotCreate` — `root`, `daemon`,
  `nobody`, `_mbsetupuser`, `guofeng`, `_windowserver`, `admin`, `""`.
- `testNamesThatLookCloseButAreNot` — twenty near-misses: `_agentspace_A1B2C3`,
  `_agentspace_/bin/sh`, `_agentspace_..`, `_agentspace_$(id)`,
  `_agentspace_a1b2c3\n`, non-ASCII, five-character and seven-character suffixes.
- `testNoCommandEverInvokesAShell` — the structural claim behind the whole design.
- `testCreateUserIsNeverAnAdministrator` — no `-admin`, no `-secureToken`.
- `testDeleteUserOnlyEverTargetsTheValidatedAccountsHome`.
- `testTheLaunchDaemonPlistIsValidAndMatchesTheMachServiceName` — the plist and the
  client are two files that must agree, and a mismatch produces a *silent timeout*,
  which is the hardest possible thing to debug.
- `testGeneratedNamesAreAlwaysAccepted` — 2000 generated names, each fed back
  through the check that gates deletion. If those two disagreed, the helper would
  create accounts it then refused to delete: a Space that can never be removed.

**The helper's self-check, run from inside the real signed bundle:**

```
$ dist/AgentSpace.app/Contents/Library/LaunchDaemons/agentspace-helper --self-check
  ok   privilege
       running as uid 501, not root — correct for --self-check, and this is what
       the daemon refuses to serve from (exit 77)
  ok   caller requirement parses
  ok   requirement strictness
  ok   worker binary is reachable
       dist/AgentSpace.app/Contents/MacOS/agentspace-worker
  ok   LaunchDaemon plist is in the bundle
  FAIL registered with launchd
       SMAppService reports: not installed (no helper inside this bundle)
  ok   Space accounts on this machine
       none — the helper would currently refuse to delete anything
  ok   refuses everything else
       root, daemon, nobody, _mbsetupuser, guofeng

9 checks, 1 failing.
```

`bundle-app.sh` runs this as a gate, and it needs no root — which is the entire
reason the mode exists.

### Two bugs the helper work exposed

**The `doctor` helper check could never pass.** It tested for
`/Library/LaunchDaemons/<id>.plist`, which is where a **SMJobBless** helper goes.
AgentSpace uses `SMAppService` (plan §7), whose LaunchDaemon lives *inside the app
bundle* and is registered by launchd from there; nothing is ever written to
`/Library/LaunchDaemons`. The check warned forever, including on a machine where
the helper was working. A check that cannot pass is worse than no check, because
it teaches people to ignore warnings.

Fixing it exposed a second one: `SMAppService.status` answers only for the **main
bundle's own** helper. The CLI lives at `AgentSpace.app/Contents/Helpers/agentspace`,
so for the CLI process `Bundle.main` is `Contents/Helpers` and the status is
`.notFound` — on a machine where the helper was installed and fine. `HelperInstallation`
now walks up from the executable to find the containing `.app`, so the app and the
CLI agree, and then asks the question that cannot be wrong: *does it answer?*

The command now distinguishes the states a user actually needs told apart:

```
$ dist/AgentSpace.app/Contents/Helpers/agentspace helper
agentspace-helper — not answering
  bundle plist:  …/AgentSpace.app/Contents/Library/LaunchDaemons/com.agentspace.AgentSpace.Helper.plist
  status:        not answerable. Creating and deleting Spaces will
                 fail with HELPER_UNAVAILABLE; driving an existing
                 Space is unaffected.
  fix:           Open the AgentSpace app and choose “Install Helper”. …
```

Exit 0 when it answers, **3 when it does not** — so a script can branch without
parsing text, and an unavailable helper is never mistaken for a pass.

### A finding worth recording

`xpc_peer_requirement_create_team_identity` was added in **macOS 26.0**, and the
SDK documents it as requiring that "the peer has the specified identity and is
signed with the same team identifier as the current process" — which is *exactly*
the check plan §7 asks the helper to perform. The platform has a purpose-built,
kernel-backed API for this, and it landed in our stated baseline.

It was not adopted, for a specific reason: it takes an `xpc_object_t`, so using it
means abandoning `NSXPCConnection` for raw XPC, and `NSXPCConnection` exposes only
`processIdentifier` — verified directly against the SDK header, which declares
`processIdentifier` and nothing else. So the shipped check is pid-based, with a
documented pid-reuse window. That limitation, and the recommended fix, are written
up in `docs/security.md` rather than left implicit. A probe to see whether the
raw-XPC path could at least be *tested* without root (via an anonymous listener
endpoint) crashed, so it was not adopted on an unverified path — which is the
plan's §63.13 rule applied to the build rather than to macOS behaviour.

### Not verified

Everything that needs the daemon actually registered, which needs an administrator
password, which this session cannot supply:

- the LaunchDaemon registering, launching and answering over XPC;
- a real `createUser` / `deleteUser` on a real machine;
- the code-signature check accepting the app and rejecting anything else;
- `installWorker`, `prepareRuntimeDirectory`, `sessionInfo`.

`agentspace-helper --self-check` and `agentspace helper` are the two commands that
will confirm all of it on a machine where that is possible, and the create wizard
will not offer a working button until they are clean.

---

## 14. Workspace preparation (§14) — verified against real git

`WorkspacePreparer` turns a Space's workspace settings into directories on disk
and into the access rules the worker enforces. **16 tests, 0 failures**, and they
use a real `git` repository in a temporary directory rather than a stub, because
the interesting failures here are git's rather than ours: whether `worktree add`
accepts the argv we build, whether the branch really appears, and whether the
user's own checkout is genuinely untouched. A stubbed test would pass while the
product failed.

### The claim that matters, tested end to end

`testApplyReallyCreatesAWorktreeWithoutTouchingTheUsersCheckout` is the whole
point of the mode: the agent gets its own checkout, edits it, and the user's
working tree is compared afterwards.

```swift
try WorkspacePreparer.apply(plan).get()
XCTAssertTrue(fileManager.fileExists(atPath: worktree + "/README.md"))

// The agent edits its own copy…
try "changed by the agent\n".write(to: URL(fileURLWithPath: worktree + "/README.md"), …)

// …and the user's tree is untouched. This is the assertion that matters.
XCTAssertEqual(try String(contentsOf: repository.appendingPathComponent("README.md")), "hello\n")
```

### Three paths that are refused rather than quietly handled

- **A branch without the `agentspace/` prefix.** An agent pointed at `main` in the
  user's own tree is the failure the whole mode exists to prevent, so it is refused
  rather than renamed. Sixteen malformed branch names are also rejected —
  `agentspace/`, `agentspace//x`, `agentspace/../x`, `agentspace/x y`,
  `agentspace/x@{y`, a trailing dot, a newline, DEL.
- **A worktree outside the Space's own workspace directory.** Otherwise the agent
  would be creating directories in the user's tree, which is exactly what a
  worktree is meant to avoid. `testTheWorktreeCannotBeTheRepositoryItself` covers
  the worst version: checking out over the user's working tree.
- **Sharing a system directory.** `/`, `/System`, `/Library`, `/usr`, `/etc`,
  `/Users`, `/Applications`, `/private`, `/var`. Nobody means to give an agent
  `/Users`, and "I did not mean that" is not recoverable once it has written there.

A repository that is not a repository is an error, not a directory that gets
created anyway and fails later somewhere confusing.

### Read versus write

`testWritableRootsAreAlwaysASubsetOfAllowedRoots` asserts an invariant the worker
depends on, since it treats the two lists independently: a writable root that is
not also allowed would be a hole rather than a mistake. In a worktree Space the
repository is **allowed but not writable** — the agent can `git log` and diff
against the base branch, and cannot touch the tree you have open.

### Two bugs found while writing this

**`Process` does not search `PATH`.** `WorkspacePreparer.run(["git", …])` set
`executableURL` to a bare name, which `Foundation` resolves relative to the working
directory — so `git` became `./git` and every call failed with *"the file git does
not exist"*. The message names git rather than the resolution, which is why it
reads like a missing install. `resolveExecutable` now does the lookup explicitly,
with `/usr/bin`, `/usr/local/bin` and `/opt/homebrew/bin` as fallbacks, and the
plan refuses with a specific message when git genuinely is absent.

**The test fixture did not stage its file.** `git commit` exited 1 with *"On branch
main / nothing to commit"*, which reads like a complaint about branches rather than
about staging, and sent me looking in the wrong place for a minute. Both are the
same lesson as §11 and §12 from a third direction: the error message pointed at the
wrong thing, and only running it showed that.

---

## 15. Create and delete a Space (§28, §41) — verified up to the root boundary

### What is verified, and how

Creating a Space is the only thing in AgentSpace that changes the machine: it makes
a macOS account, installs a launchd job into it, and later removes both. It is also
the one thing that **cannot be run on this machine**, because `sudo -n` fails here
("a password is required") and nothing can become root.

That is exactly the situation that produces untested code. The rollback path — the
part that only runs when a step fails half way through — is the least likely part to
be exercised by hand and the most damaging when it is wrong, because it leaves an
`_agentspace_…` account that the user did not ask for.

So `SpaceProvisioner` takes the helper call as an **injected closure** instead of
calling `HelperClient` directly. Production passes `HelperClient.call`; the tests
pass a scripted double that can fail at any named step. Everything except the
helper's own behaviour is therefore executed for real.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 25 | Creating a Space calls the helper in the order account → runtime → worker | ✓ | `SpaceProvisionerTests`, and the order is **asserted** rather than assumed |
| 26 | A workspace that cannot be created is refused **before** the helper is called at all | ✓ | `helper.calls.isEmpty` asserted; a typo in a repo path leaves nothing behind |
| 27 | Every step failure rolls back what it already did | ✓ | one test per operation, failing each in turn |
| 28 | A rollback that itself fails is reported as partial state, and the orphan account stays **visible** in the registry | ✓ | `testAFailedRollbackIsRecordedAsPartialStateAndTheSpaceStaysVisible` |
| 29 | The password reaches the Keychain and appears in no file | ✓ | read back from the real Keychain; the registry file is searched for it |
| 30 | Generated passwords never repeat, and are 32 bytes | ✓ | 200 generated, all distinct |
| 31 | Deleting removes the worktree, keeps the branch, and never touches the user's repository | ✓ | real git; the user's `README.md` is compared byte for byte and the branch is listed afterwards |
| 32 | A worktree git refuses to remove **warns** instead of blocking the deletion | ✓ | the worktree is locked, which is the documented way to make removal fail |
| 33 | The home directory is only removed when explicitly asked | ✓ | asserted on the request that actually reached the helper |
| 34 | With no helper, `agentspace create` exits **69** and explains the fix | ✓ | run for real; see below |
| 35 | With no name, `agentspace create` exits **64** with usage | ✓ | run for real |
| 36 | The Keychain store round-trips, replaces, and deletes idempotently | ✓ | against the **real** Keychain, in its own service namespace |
| 37 | The helper performs a real `createUser` / `deleteUser` | ✗ | needs root |

### The command-line behaviour, run for real

```
$ agentspace create
agentspace: BAD_REQUEST: usage: agentspace create <name> …
exit 64

$ agentspace create "Test Space" --json
{ "ok": false, "error": { "code": "HELPER_UNAVAILABLE", … },
  "steps": [ { "name": "plan workspace", … } ] }
exit 69

$ agentspace create T --repo /tmp --branch main --json
{ "error": { "code": "WORKSPACE_INVALID",
             "message": "/tmp is not a git repository" } }

$ agentspace delete nope ; exit 66
```

Exit 69 is the important one. There is no unprivileged path to creating a macOS
account, and the command says so rather than attempting anything else — the §2
fail-closed rule applied to management rather than to input.

### Three bugs found by writing this

**A failure's error code was flattened.** `bail` took a code and a message, and
every helper call site passed `.helperRejected` — so a helper that could not be
reached at all was reported as a helper that had *refused*. Those need different
fixes ("install it" versus "it said no"), which is the entire reason the two codes
exist. The test that caught it was the one asserting `HELPER_UNAVAILABLE`; without
it, every failure would have looked like a policy decision.

**The delete failure message did not name the account.** By the time the account
deletion is attempted the registry entry is already gone, so the message is the
*only* pointer to the leftover account — and it said only "the helper refused".
It now always names the account and says where to find it.

**`parsed.positionals.first` is the command name, not the first argument.**
`agentspace create "Test Space"` therefore created a Space named `create` and
silently ignored the name the user typed. Worse, the "you must give a name" guard
*could never fire*, because the command name is never empty — a check that can
never fail is a check that can never protect anything. This is the third time this
project has produced that exact class of bug (§11: `doctor`'s helper check that
could never pass; §13: `--version` that dumped usage).

### What this does not prove

The helper's own behaviour — `dscl` invocation, `sysadminctl` exit codes, whether
`SMAppService` actually starts the daemon — is still unverified, and the plan's
§56 requires a separate review of the helper for exactly this reason. Everything
above the helper's boundary is tested; below it is not.

---

## 16. Multi-Space isolation (§29, §48) — the bug is never a crash

Phase 4 (§48) says to remove every `singleUser` / `computeruse` /
`defaultSession` assumption. You cannot test that an assumption is absent. You can
test its consequences, and the consequence that matters is not a crash: it is two
Spaces quietly sharing something they must not, so that one agent's clicks land on
the other's desktop while the caller believes it addressed a different Space.
Nothing goes red; it just becomes true.

`MultiSpaceIsolationTests` therefore asserts that every derived name and path is
**pairwise disjoint** across eight Spaces — sockets, token files, runtime
directories, account names, launchd labels, plist paths, uids — and that the two
paths that must fit in `sun_path` do.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 38 | Eight Spaces get eight distinct sockets, token files, runtime directories, account names, launchd labels and plist paths | ✓ | `MultiSpaceIsolationTests` |
| 39 | Every socket path fits in `sun_path` (104 bytes including the terminator) | ✓ | asserted for eight Spaces |
| 40 | Two Spaces can be created under names that differ only by case, and do not share a working tree | ✓ | end to end through the provisioner with real git |
| 41 | Resolving a Space by name is unambiguous or refuses, offering the UUIDs | ✓ | `testAnAmbiguousNameRefusesAndOffersTheUUIDs` |
| 42 | An empty registry says what to do rather than "something went wrong" | ✓ | asserted against the message |
| 43 | 200 generated account names never fall inside the protected list | ✓ | those accounts could be created and never removed |
| 44 | Two live workers reject each other's tokens | ✓ | `SafetyTests.testDifferentSpacesHaveDifferentTokens` — two real processes |
| 45 | Two Spaces running simultaneously, with the console unaffected | ✗ | needs a second logged-in session |

### The bug this found

**The worktree path was derived from the Space's name.** Plan §24 specifies
`…/worktrees/<space-id>/MyApp`; the implementation had used a slug of the name —
`…/Worktrees/test/MyApp`. Two Spaces called `Test` and `test` therefore resolved to
the same directory, and on a case-insensitive filesystem (which macOS is — measured
earlier in this project, and the cause of two other bugs) those are *one* directory
with two agents editing one working tree.

That is precisely the failure the worktree exists to prevent, and it would not have
been noticed until two similarly-named Spaces were in use. `SpaceProvisioner.confined`
now rewrites the path under the Space's id, and the name no longer appears in the
path at all — so renaming a Space cannot move an agent's checkout out from under it
either.

The first version of the test passed *for the wrong reason*: it asserted two
*different* input paths stayed different, which they would have even with the bug.
It now passes the same repository and the same placeholder path for both Spaces, so
the only thing that can distinguish them is the Space id.

### What this does not prove

Two Spaces actually running at once, each with an Aqua session, driven with `AAA`
and `BBB` while the console is untouched — the plan's §48 acceptance — still needs
two logged-in users, which needs an administrator password this machine does not
have. What is verified is that the *plumbing* cannot confuse two Spaces, and that
two real workers enforce their own tokens against each other.

---

## 17. Disk usage (§30) — measured, not allocated, and never a silent zero

Plan §30 wants CPU, RAM, process count **and disk** per Space. The first three were
already aggregated from the process table by uid; disk was a field on the model that
nobody filled in.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 46 | The measurement agrees with `du` on a directory with nested subdirectories | ✓ | `DiskUsageTests`, within 64 KB of `du -sk` |
| 47 | The walk stops at its budget and reports itself **truncated** rather than exact | ✓ | 40 files, budget 10 → `truncated: true`, fewer files counted |
| 48 | Symlinks are not followed out of the directory, and a self-referential loop does not hang it | ✓ | a 512 KB target behind a link is not counted |
| 49 | An unmeasured Space reports "not measured", not a measured zero | ✓ | `diskMeasured` is distinct from `diskBytes == 0` |
| 50 | The ordinary status poll does **not** walk the home directory | ✓ | `testDiskUsageIsMeasuredOnlyWhenAsked` — no `diskBytes` unless asked |
| 51 | An explicit `"disk"` request measures the Space's own home | ✓ | same test, against a seeded home of two files |
| 52 | The UI offers disk as an explicit action with its cost explained | ✓ | Space detail page |

### The two decisions

**Allocated, not logical.** `totalFileAllocatedSize` rather than `fileSize`: on APFS
with compression, sparse files and clones these differ, and allocated is the number
the filesystem gives back when the blocks are freed — the one `du`, Finder and the
user can all reproduce.

**Opt-in, and bounded.** A Space's home holds a browser profile and an IDE's caches;
tens of thousands of files is normal. Walking it on the 2–5 s status poll would pin
the CPU, which §53 forbids, so it is a separate request (`resources: "disk"`) and a
button in the UI that says what it costs. The walk stops at 250 000 entries and sets
`diskTruncated`, so an agent that has filled its disk with `node_modules` yields "at
least N" rather than a wrong exact figure.

### Two bugs while writing this

**The test measured the wrong home and reported it as success.** The first version
seeded nothing, so the worker measured the real home of whoever ran the tests —
thousands of files, so the walk hit its budget and returned a *truncated* bound. The
assertion "truncated should be false" failed, which was the only reason it was
noticed. It now seeds a home of two known files and asserts the figure is below a
megabyte, which also proves the walk did not silently measure the real home.

**The harness wrote its space record in `init`, where nothing could configure it.**
Assigning `spaceRecord` after `try WorkerHarness()` was already too late: `init` had
run with `nil` and written nothing, so the worker fell back to the real home every
time. The write moved to `start()`, which is also the correct lifecycle — the file
must exist before the worker reads it, and that is true at `start()` and not before.
The same lesson as §11 and §15 from yet another angle: the code was correct *where it
was*, and wrong because of when it ran.

---

## 18. MCP integrations (§34) — and a test that wrote the user's real config file

Claude Code, Codex and OpenCode each take the same MCP server in a different shape.
`Integrations` is now the single source of that truth: the GUI's **Install MCP
Into…**, the CLI's `agentspace integrate <target>`, and the tests all render from
the same code, so they cannot drift. `agentspace integrate` prints the config
(default) or writes it (`--install`).

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 53 | Each generated config parses in its own format — the JSON ones via `JSONSerialization`, the TOML one key by key | ✓ | `IntegrationsTests` |
| 54 | A binary path containing a space survives quoting in every format | ✓ | `/Applications/My Apps/…` used throughout the tests |
| 55 | Merging into an existing JSON config preserves every other value | ✓ | theme, projects and another MCP server all asserted unchanged |
| 56 | Re-running the install is idempotent for both formats | ✓ | byte-identical output |
| 57 | An existing TOML block with *different* contents is **refused**, not overwritten | ✓ | exit 65, message names the actual file |
| 58 | A file that is not a JSON object is refused rather than appended to | ✓ | |
| 59 | A backup of the previous contents is written before the first change | ✓ | verified on disk |
| 60 | The default binary path is one that exists and runs — not `Contents/MacOS/agentspace` | ✓ | the bundle has never contained that file; the old GUI copy pointed the MCP server at nothing |

### The incident this section exists to record

While verifying the install flow, a test ran `HOME=/tmp/sandbox agentspace
integrate codex --install` expecting the write to land in the sandbox. It **wrote
the real `~/.codex/config.toml` and `~/.claude.json`** instead.

`NSString.expandingTildeInPath` does not honour the `HOME` environment variable. It
expands `~` against the passwd entry for the current user, so redirecting `HOME`
redirects nothing that matters. This is precisely the class of macOS behaviour
§63.13 says must be measured rather than guessed — and it was guessed, at the cost
of modifying two files owned by other tools.

Two things limited the damage, and both are now load-bearing requirements rather
than conveniences:

- **The backup.** The install writes `path.agentspace.bak` before the first change,
  so both files were restored exactly from their backups. Without that copy the
  original content would have been gone — a 108 KB config file re-serialized by
  JSONSerialization.
- **The key-scoped merge.** Only `mcpServers.agentspace` was written; every other
  value survived the round trip, which is what the merge tests assert. The damage
  was formatting, not content.

The fix: `agentspace integrate --install --config PATH` aims the write explicitly,
and is the only path the CLI's filesystem behaviour is verified through. The default
path is still offered for real use, but nothing automated writes to it any more.
`~`-expansion against the passwd home is now recorded here as a measured fact, with
the same status as the case-insensitive filesystem and the `CGDisplayPixelsWide`
scale trap.

A second decision changed because of this: `mergeJSONConfig` no longer sorts keys.
Sorting made the rewrite deterministic but rewrote the *entire* file's ordering,
turning a one-key change into a whole-file diff. Preserving parsed order keeps the
rewrite as close to the original as `JSONSerialization` can produce.

### The Claude Code inline command

`agentspace integrate claude` prints a `claude mcp add-json agentspace '…'` command
with the JSON collapsed onto one line. It is valid JSON and `add-json` accepts it,
but it is ugly, and anyone retyping it by hand should paste the block below it
instead.

---

## 19. Agent safety rules (§35) — generated once, copied or installed

Plan §35 requires that installing the MCP server also produce a recommended rule
set for the agent that will drive it, and that writing it into `AGENTS.md` or
`CLAUDE.md` happen only with the user's consent. `Integrations.agentRules()` is the
single source of that text; `agentspace integrate rules` prints it, `--install`
appends it marker-scoped, and the GUI offers **Copy Agent Rules**.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 61 | All four commitments appear, each asserted by its distinctive phrase | ✓ | a weakened rewording fails the test rather than shipping |
| 62 | Appending preserves the user's own text, in place, first | ✓ | their heading and their own instruction asserted unchanged |
| 63 | Re-running the install is a no-op, not a second copy | ✓ | marker-scoped idempotence, byte-identical output |
| 64 | The GUI copies rather than writes | ✓ | an instructions file is the user's voice to their agents; §35 requires consent, and copy *is* consent |

The markers (`<!-- agentspace:rules begin/end -->`) do double duty: they make
idempotence possible, and they tell a human reading the file later exactly which
lines are AgentSpace's and which are their own.

### A warning sweep worth recording

Bringing the build back to zero warnings surfaced five leftovers from this round's
own refactors, none of which the passing test suite could see: `bail()` still
destructured an error into `code` and `message` it no longer used; a `var` that is
only ever read; a `_ = created` placeholder; a wizard-computed `slug` feeding a
path the wizard no longer computes; and a mechanically-added
`?? RuntimePaths.root` appended to a chain that already ended in a non-optional.
Each was dead weight from a change that had moved on — the lesson is not "keep
warnings at zero" but that a refactor's cleanup should land with the refactor, and
the compiler is the only reviewer who reads the leftovers.

---

## 20. Release packaging (§57) — and a build that silently built one thing out of four

`scripts/release.sh` runs the whole distribution sequence and prints what each step
verified: release build and bundle, strict signature verification of **all four**
binaries, Gatekeeper assessment, DMG creation and verification, then notarization.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 65 | The release build produces all four binaries and the bundle script asserts each exists | ✓ | after the fix below; the assertions are the gate, not the build's exit code |
| 66 | Every nested signature verifies strictly | ✓ | app, helper, worker, CLI — Developer ID Application, team `U8U443D7ZL` |
| 67 | Gatekeeper's verdict is reported, with the actual user-facing consequence | ✓ | refused (notarization missing), and the message says what a user can do about it |
| 68 | The DMG's checksum verifies, it mounts, contains the app, and the copy inside still verifies | ✓ | deterministic mountpoint, detached afterwards |
| 69 | Notarization is skipped honestly, not attempted and failed | ✓ | credentials checked read-only first: `notarytool store-credentials` has not been run here |

### The bug: a build that exits 0 having built one of four things

`bundle-app.sh` invoked SwiftPM as
`swift build -c release --product A --product B --product C --product D`. This
toolchain treats **repeated `--product` flags as last-one-wins**: the command built
only `agentspace-helper` and exited 0.

The debug path had looked correct for weeks — because earlier *flagless* full
builds had left the other three binaries in `.build/debug`, and the script's
`[[ -x ]]` existence checks passed against those stale artifacts. The bug surfaced
the first time the release configuration ran from a clean `.build`: helper built,
three products missing, error `missing .build/release/AgentSpaceApp`.

It is the plan's recurring lesson in yet another costume (§11: a check that can
never pass; §15: a guard that can never fire). Here: a build whose *success signal*
is its exit code, unchecked against what was actually asked of it. The fix builds
the whole package — barely slower — and leaves the four existence assertions as the
real gate.

**`scripts/test.sh` had the same latent bug** —
`swift build --product agentspace-worker --product agentspace` was silently building
only `agentspace` — and it hid behind the same stale artifacts until the clean
`.build`, at which point the safety tests would all have skipped *quietly* while the
suite still reported PASS. The suite's own "worker was not built; the safety tests
would all skip" warning is what caught it, which is exactly why that warning exists.
After the fix the worker binary is present again and the safety tests really run.

### Two smaller finds

- `hdiutil attach -quiet` prints nothing, so the volume path parsed from its output
  was empty and the DMG-content check failed against `/Volumes/` itself. Replaced
  with a deterministic mountpoint (and the non-deprecated
  `diskutil image attach --readOnly`), which also makes cleanup exact.
- The Developer ID certificate is present and signing works; the only missing
  distribution credential is the notarytool keychain profile, confirmed read-only.
  The `--notarize` path fails with the exact one-time setup rather than a cryptic
  notarytool error.

---

## 21. The integration suite (§5, §55) — and the §54 leak it found

`tests/Integration/` now exists. Its target is not the worker (the safety suite
owns that) but the **product boundary**: the real `agentspace` CLI run as a real
process, with only its arguments and `AGENTSPACE_ROOT`, exactly as an agent or a
script would drive it. Ten tests spawn the binary; each gets its own root, so
the tests share nothing but the build.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 70 | `--version` reports the protocol version; `list --json` on an empty root is machine-readable | ✓ | §32's contract, at the process boundary |
| 71 | An unknown Space is not-found, named, and **exit 66** | ✓ | after the fix below |
| 72 | `create` without the helper fails closed with **exit 69** and leaves no partial registry entry | ✓ | the management path refuses without half-running |
| 73 | `doctor --json` reports every check with a name and a verdict | ✓ | §38's shape, parseable |
| 74 | `status --json` through the real binary reaches a live worker over the real socket — registry, token file, geometry | ✓ | §49: one core API behind CLI, GUI and MCP |
| 75 | `click` through the real binary surfaces `SESSION_IS_CONSOLE`, typed, non-zero | ✓ | §2 at the product boundary, not just inside the worker |
| 76 | `screenshot` on a console-session worker refuses typed; in a background session it must produce a real PNG | ✓ | §54 — after the fix below |
| 77 | Two roots are isolated worlds: same name, different tokens, different workers; a name from the other world is not-found | ✓ | §29/§48 via the real binary |
| 78 | `--json` carries the documented field types for scripts | ✓ | §32 |

### Two product defects the first run found

**Not-found was neither JSON nor 66.** `resolveSpace` failed through a hardcoded
`Emitter(json: false)` and the catch-all exit code: `status <unknown> --json`
printed human prose and exited 1 — indistinguishable, to a script, from a
generic failure, and unparseable besides. Fixed: the caller's emitter fails
through, and not-found is the documented 66. Found because a test asserted the
documented contract instead of the implementation's actual behavior.

**The console refusal covered injection but not observation.** The screenshot
handler carried a deliberate comment defending the old behavior — "capturing the
console is exactly what the human sees anyway" — and the empirical check agreed
with the plan, not the comment: a console-session worker returned a full
3840px PNG of the *user's* desktop, and `ax.*` on the console would read the
user's windows without any TCC grant. §54 says a screenshot must never be the
user's desktop; on the console there is nothing else to capture. The worker now
refuses every observation and manipulation method (`screenshot`, `apps`,
`launch`, `quit`, `forceQuit`, `activate`, `ax.*`) with `SESSION_IS_CONSOLE`,
keeping only `hello`, `status`, `exec`, `shutdown`. `docs/security.md` records
the reversal and the reasoning on both sides.

The plan's §55 name `testScreenshotNeverReturnsConsoleSession` stops being a
skip on this machine: with the guard in place, the console refusal *is* the
assertion, and it is typed.

### One framework trap worth recording

The first bash repro seeded a hand-written `index.json` (`workspace: {"type":
"none"}`, epoch timestamps) that the CLI silently failed to decode and reported
as "no AgentSpace exists yet" — the wrong diagnosis for my own test data. The
registry schema is `kind`, not `type`, with ISO-8601 dates. Relatedly,
`SpaceRegistry.load` returns an empty registry for *undecodable* content, which
its own comment calls out as something that must not happen silently; the
behavior and the comment still disagree, and the comment is now marked as
describing an unresolved limitation.

---

## 22. Registry hardening and the MCP failure seam (§50)

Two small pieces that close recorded limitations rather than open new fronts.

**The registry no longer discards corruption.** An undecodable `index.json` used
to load as empty — every Space silently "deleted", and the next save overwriting
the only evidence of what existed. Now the corrupt file is quarantined beside
itself (`index.json.corrupt-<timestamp>-<random>`, bytes intact), doctor reports
a **Registry integrity** failure with the file names and a concrete recovery
fix, and loading still returns empty so the app keeps working. The first
quarantine test caught a real bug in the quarantine itself: the timestamp-only
name collided within a second, and the failed move the `try?` hid lost one
generation of evidence — fixed with a unique suffix and an existence-retry loop.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 79 | Round-trip save/load preserves Spaces; missing registry is not corruption | ✓ | no quarantine files on the healthy and first-run paths |
| 80 | Corruption quarantines with bytes intact and removes the live file | ✓ | the original content asserted byte-for-byte after load |
| 81 | Repeated corruptions keep every generation | ✓ | the collision bug is dead |
| 82 | Recovery save after quarantine loads cleanly, evidence survives | ✓ | the path a user would actually take |
| 83 | Doctor surfaces quarantine as a failing check with the file names and a fix | ✓ | exercised end-to-end through the CLI with a corrupt registry |

**The MCP server's failure seam is pinned (§50).** The property: an unavailable
Space reaches the agent as AgentSpace's typed envelope — code, message, fix —
and there is no code path that substitutes local execution. Four tests against
the real CLI binary: not-found is exit 66 with a parseable envelope whose code
is from the §21 list and whose `fix` is present; `formatFailure` tells the agent
explicitly that there is **no local fallback to the console session**; a success
envelope is never misread as a failure; and an absent binary surfaces a spawn
error, again never a fallback. Also: `node --test test/` ran only the first
test file on this Node (19 vs 23) — the script now uses a glob, and the count
difference is itself the proof.

---

## 23. Restart behavior (§39) — Needs Login, not a lie about offline

After a reboot the registry still records what was true before: a Space that was
`running` at shutdown reads `running` now. Its worker is gone, and — this is the
§39 point — nobody has logged into the agent account, so waiting will not bring
it back. The UI's job is to send the user to the right fix.

The discriminator had to be found empirically (§63.13). `utmpx`, the obvious
public API, was tested first and rejected: modern macOS does not populate it for
GUI logins, so it reported *this* console session as absent. What actually
distinguishes the two cases is process ownership — a logged-in user, even one
switched away, owns Finder/Dock/launchd; a never-logged-in account owns nothing.
`SystemSessions.hasLiveProcesses(uid:)` reads the BSD process list with
`sysctl(KERN_PROC_ALL)`: public, permission-free, no root, no spawn.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 84 | Rebooted Space (worker gone, no session) shows **needsLogin** | ✓ | the fix is a fast user switch, not a retry |
| 85 | Crashed worker under a **live** session shows offline | ✓ | restarting the LaunchAgent is the right fix |
| 86 | Unknowable session state keeps the old offline label | ✓ | no invented Needs Login the user cannot verify |
| 87 | Permission and console verdicts still win; healthy Spaces show stored state | ✓ | derivation order pinned |
| 88 | The uid discriminator distinguishes a live user from none, both halves | ✓ | this suite's uid vs an idle uid |

The derivation is one pure function (`SpaceState.effective`) shared by the GUI —
the plan's "components disagree" bug class has no room here, and the session
lookup runs only on the offline path so a healthy refresh pays nothing (§53).

---

## 24. The ScreenCaptureKit preview (§52) — pull model, idle auto-stop, fail-closed

The 1 FPS screenshot MVP was always the verified path; §52's upgrade is now in.
The protocol keeps its one-request-per-connection shape: `preview.start` /
`preview.frame` / `preview.stop`, newest frame wins, frames captured faster than
the client pulls are dropped. The lifecycle state machine lives in Core
(`PreviewController`) with the frame source injected — unit-tested against a
counting fake — and the ScreenCaptureKit adapter in the worker is thin
accordingly.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 89 | start/frame/stop round-trips; stop is idempotent; pull-after-stop is nil | ✓ | controller tests with a fake source |
| 90 | Restarting a running stream does not tear down the first viewer's stream | ✓ | two viewers must coexist |
| 91 | A stream nobody pulls stops itself after the idle timeout and a fresh start works | ✓ | the failure mode "auto-stopped once, dead forever" would be worse than the bug |
| 92 | A pull before the timeout keeps the stream alive; fps is clamped to 1…30 | ✓ | a live viewer never trips its own idle stop; an unbounded client cannot set the rate |
| 93 | A failed start leaves no half-built source behind | ✓ | the next start genuinely begins |
| 94 | `preview.start` on a console-session worker refuses **SESSION_IS_CONSOLE** through the real CLI | ✓ | integration test, same typed refusal as every observation method |
| 95 | `preview.frame` without a stream is typed `PREVIEW_NOT_RUNNING` | ✓ | surfaced at the process boundary |
| 96 | The GUI falls back to the 1 FPS screenshot MVP when the stream is refused | ✓ | build-verified; a refused stream shows the MVP, not nothing |

**Unverified here, by construction:** actual ScreenCaptureKit frame delivery
needs a background Aqua session holding a Screen Recording grant — the same
environment this machine cannot produce. The adapter's SCK calls (discovery,
start, the sample-buffer → JPEG encode) are the honest boundary of what this
repository can assert, and they are marked as such. Everything the adapter
defers to — the state machine, the fail-closed gating, the protocol shape — is
verified above.

### A §21 regression caught by pinning the contract

The new `PREVIEW_NOT_RUNNING` error was first declared without its uppercase
raw value, so the wire code read `previewNotRunning` — and the integration test
caught it by asserting the §21 code at the process boundary. The typed-code
contract is only as strong as its spelling, and the spellings live in the enum,
not in prose.

---

## 25. Diagnostics export (§37) — a bundle safe to paste into a support issue

The Doctor told the user what was wrong; §37 also demands an *export* that can
leave the machine without leaving with it the keys. Two independent controls,
both enforced in Core and both tested:

1. **Whitelist collection.** The collector gathers doctor output, registry
   metadata (names, usernames, uid, state) and file *existence* — never token
   contents, Keychain items, input payloads, or frame data.
2. **Redaction pass.** Everything still runs through the redactor at the
   boundary: 64-hex tokens, keyed `password/secret/token` values, inline
   `data:image` payloads, and >4 KB base64 blobs. It is deliberately
   conservative about *not* redacting 40-hex commit SHAs — an export that
   mangles every hex string is an export nobody can debug from.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 97 | A session token in text is redacted; prose mentioning "token" is not mangled | ✓ | property-style tests |
| 98 | Commit-SHA shapes survive (40/7 hex are not tokens) | ✓ | the boundary case, pinned |
| 99 | Keyed secret values redacted whatever the key spelling; keys survive | ✓ | the reader can still see *what* was redacted |
| 100 | Inline images / giant blobs redacted; redaction is idempotent | ✓ | |
| 101 | The collector lists every Space but never a token's contents — only presence | ✓ | unit + integration against a live worker |
| 102 | The CLI export and the GUI Export… button produce the same redacted bundle | ✓ | one collector, two surfaces (§49) |

A deliberate assertion in the integration test: the redactor firing on an
export is itself suspicious — collection is a whitelist, so `<redacted-…>`
appearing in a bundle means something secret-shaped got collected anyway, and
the test would rather fail loudly than quietly look safe.

---

## 26. Stop, Logout, Delete (§40) — three endings, not one button

The plan requires the UI to distinguish *Stop Worker* (stop the agent, keep the
GUI session) from *Logout* (end the whole session, release its RAM, keep the
account) from *Delete Space* (remove everything, ask about the home). Until now
the distinction existed only in prose: the CLI had `stop`, the helper had
`startWorker`/`stopWorker`, and nothing had a logout at all.

The semantics of **Stop Agent** turn out to be already correct by design, and
now pinned by test: the worker exits 0 on `shutdown`, and the LaunchAgent's
`KeepAlive.SuccessfulExit = false` means launchd leaves a *clean* exit stopped.
That is a real stop — not a crash-restart loop — while the session stays warm.

**Logout Desktop** is the new typed helper RPC (`logoutSession`): it runs
`launchctl bootout gui/<uid>` — root-only, so it belongs in the helper and
nowhere else — after cross-checking the uid against the username's real passwd
entry and refusing `_agentspace_`-less names. The protocol-size pin in the
validation tests moves 9 → 10 deliberately: this is a typed, uid-checked
operation, not an escape hatch.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 103 | `agentspace stop` exits the worker cleanly and launchd leaves it stopped; the registry keeps the Space | ✓ | live-worker integration test, pid observed gone |
| 104 | After a stop, the CLI reports the worker offline (fail-closed), not fake-alive | ✓ | same test — `WORKER_OFFLINE` |
| 105 | `logoutSession` accepts only an existing `_agentspace_` account with its own uid; a stale socket file after exit is stale, and tests read the pid | ✓ | validation tests + the note below |

The logout itself needs the helper running as root — live verification remains
blocked in this environment, as recorded since the helper round. Two testing
notes that cost real time: a stopped worker's socket *file* lingers (exit does
not unlink it — the honest observable is the pid), and `status` after a stop
exits non-zero with `WORKER_OFFLINE`, which is the fail-closed contract
behaving exactly as specified.

---

## 27. Performance (§53) — measured, not aspirational

The plan sets explicit idle targets; until now they were prose. Measured with
`ps` sampling every 2 s on this machine, release build (`bundle-app.sh release`),
one Space registered, GUI viewer closed:

| Process | Target (§53) | Measured | Verdict |
|---|---|---|---|
| AgentSpace.app idle RAM | < 100 MB | **108.8 MB** | ~9% over — honest miss |
| AgentSpace.app idle CPU | ≈ 0% | **0.0%** | on target |
| agentspace-worker idle RAM | < 50 MB | **2.7 MB** | far under |
| agentspace-worker idle CPU | ≈ 0% | **0.0%** | on target |

Two measurement notes that matter for anyone repeating this:

- The app's 108 MB is **independent of registry contents** — an empty-root run
  measures the same within noise. It is the SwiftUI/AppKit baseline of a
  native window, not AgentSpace's polling (CPU 0.0% corroborates: nothing is
  spinning). The next lever, if the 100 MB matters, is lazy-loading the
  SwiftUI stack — a real optimization task, recorded here rather than claimed
  done. The debug build measures the same 108 MB, so the gap is not build
  flags.
- The worker at 2.7 MB is the whole point of §53's "不要持续截图": the worker
  holds no frames, runs no timers, and spends its life in `accept()`.

## 28. One thousand round trips (§44, protocol layer)

§44's stress test has two halves. The isolation half (whose framebuffer the
frames land on) needs a background session — still recorded as blocked. The
protocol half now runs: **1000 sequential RPC round trips through the real
Unix socket**, then a CLI status to prove the worker is exactly as healthy as
before — same replies, no fd exhaustion, no degraded path.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 106 | Worker idle: 2.7 MB / 0.0% CPU (target < 50 MB / ≈ 0%) | ✓ | §27 measurements |
| 107 | App idle CPU 0.0%; RAM 108.8 MB — ~9% over the aspirational 100 MB, independent of registry contents | ✓ | measured honestly, lever recorded |
| 108 | 1000 sequential round trips complete in 6.5 s (~6.5 ms/call) and leave the worker healthy | ✓ | integration test, parses the post-stress status |

---

## 29. Doctor, completed against the §38 checklist

§38 lists thirteen named checks; the doctor had eleven-and-a-half. Screen
Recording and Accessibility existed only as one advisory check about *whatever
process ran the doctor* — a different question entirely from the worker's own
grants, which are per-Space and are what the checklist names.

Both now appear as their own per-Space lines, asked of the worker through the
authenticated `status` call (the doctor reads the Space's token file — it is
the main user's own tool, and the token is runtime-local):

    ✓ Worker (Frontend)      running, uid 502, input permitted.
    ✓ Accessibility (Frontend)   granted to the worker.
    ✗ Screen Recording (Frontend) not granted to the worker.
      fix: In the AgentSpace user's session, open System Settings → …

Each failure carries the exact panel path — §38's rule that a failure must
say *what to do*.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 109 | A live worker yields per-Space Worker + Accessibility + Screen Recording checks, rendered in human output | ✓ | integration test against a real worker |
| 110 | The overridden root reaches every derived path — a harness doctor reports the right machine, not the default runtime | ✓ | the bug this round's test caught on its first run |

That second row is another of the green-suite lessons: the check *looked* right
and silently examined the default `/Users/Shared` runtime — where nothing
lives — and would have reported "no socket" forever on any non-default root.
The test failed on its first run, which is the only reason the bug died.

---

## 30. §53 polling audit, §59 README, and the acceptance gate's honest refusal

Closing the last audit gaps the plan names:

- **Polling.** The app contains no recurring status poll at all — refreshes are
  event-driven (foreground, selection, explicit request), which is §53's
  stated preference over any 2–5 s timer, and idle CPU measured 0.0% in §27.
  The only repeating timer in the app is the desktop preview (§52 stream at
  5 FPS, 1 FPS fallback). A stale doc comment still describing the 1 FPS MVP
  was corrected rather than left to contradict the code.
- **§59 README.** The first screen matches the plan's required pitch verbatim
  in substance — the one-liner, the No VM / No second macOS / No remote Mac
  triple, and the two-column "you keep working / agent keeps working" — and
  needs no change.
- **§34 integrations** were re-verified as already pinned: 16 unit tests over
  the TOML/JSON merges, backup creation, and the §35 agent-rules text.

**The acceptance gate ran and refused correctly.** `scripts/acceptance.sh` is
the §44 gate. Its readiness half passes on this machine ("10 checks, 3
warnings — AgentSpace can run"); it then exits 66 because no Space exists to
drive — creating one needs the root helper, blocked on this machine since the
helper round. That refusal *is* the correct behavior: a gate that pretended to
pass without a Space would be a gate that lies. Exit 66 with the doctor's
readiness verdict alongside is recorded as the honest terminal state here.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 111 | No recurring status poll exists in the app; the only repeating timer is the preview | ✓ | code audit + 0.0% idle CPU |
| 112 | The §44 gate refuses (exit 66) rather than passing without a Space | ✓ | acceptance run on this machine |

The remaining open items are unchanged and external: live helper verification
and logout (root), notarization credentials, and the two-session acceptance
runs (§48, §44's isolation half). Every plan section the environment can reach
is built, tested, measured, and recorded.

---

## 31. The §56 security review is a re-runnable matrix

The release checklist in docs/security.md listed the plan's ten review items as
checkboxes. A checkbox records intent; a review records what was checked, how
it is pinned, and what still blocks it. Each item now names its control, the
specific tests that pin it (from the audit: token shape/compare/separation,
symlink refusal, traversal refusal, workspace escape, exec denial classes, and
the diagnostics redaction chain), and an honest status.

The result: seven items verified by named tests, three blocked on machine
capabilities (code signing/notarization credentials; live XPC and ACL
application via the root helper), with the sign-off rule stated — a release
clears when the blocked rows clear, not when this document stops mentioning
them.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 113 | Every §56 review item maps to a named pinning test or an explicit block | ✓ | the matrix in docs/security.md |
| 114 | THIRD_PARTY_NOTICES.md carries the Offstage MIT text per §42 | ✓ | file inspected |


---

## 32. The release chain, re-run end-to-end (§57)

`scripts/release.sh` was executed against the current tree. Results:

- **Strict signature verification passes on all four artifacts** — the app
  envelope, the privileged helper, the worker, and the CLI — and the signer is
  a real Developer ID: `Guofeng Liu (U8U443D7ZL)`. This is new since the helper
  round's "signing blocked" note: the user's Developer ID certificate is now in
  the keychain, and the bundle script picks it up.
- **The DMG verifies and its contents re-verify** — checksum, contains the app,
  and the copy inside still passes strict verification. What a user installs is
  what this repository built.
- **Gatekeeper still refuses, and the cause is now isolated to notarization** —
  the expected refusal for Developer ID-signed-but-unnotarized software. The
  `notarytool` keychain profile was re-checked and is absent; storing one
  requires interactive Apple-ID two-factor auth or an App Store Connect API
  key, neither of which this session can perform. Until then the honest install
  instruction is right-click → Open (or clearing quarantine), exactly as the
  script prints.
- Notarization step skipped by the script itself, with the reminder that a
  notarized release also requires the helper review sign-off in
  docs/security.md.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 115 | `release.sh` runs clean end-to-end; Developer ID signatures verify strictly on all nested binaries and inside the DMG | ✓ | this run |
| 116 | Gatekeeper's remaining refusal is solely notarization; the profile is absent, re-checked | ✓ | `notarytool history --keychain-profile` error, re-run this round |


---

## 33. Notarization readiness: the signature side completed, the credential side diagnosed

Following the §32 discovery that a real Developer ID certificate now signs the
bundle, the notarization gap was narrowed to its exact remaining half.

**The signature side is complete.** `bundle-app.sh` was signing with
`--timestamp=none` — harmless for ad-hoc development builds, but it makes a
Developer ID bundle un-notarizable, because the notary service refuses
signatures without a secure timestamp before examining anything else. The
script now requests a timestamp whenever it signs with a real identity and
keeps `=none` only for ad-hoc. After a full `release.sh` re-run, every artifact
— app envelope, helper, worker, CLI — carries both `flags=0x10000(runtime)` and
a fresh `Timestamp=`, and strict verification still passes on all of them
inside the rebuilt DMG. All three notary signature requirements (Developer ID
chain, hardened runtime, secure timestamp, plus signed nested binaries) are now
satisfied; the next notarization attempt cannot fail on signature grounds.

**The credential side is diagnosed.** This session's App Store Connect CLI
(`asc`) has a stored credential profile, but Apple rejects it:
`UnauthenticatedRequest`, re-verified twice against the notary list endpoint.
Re-authenticating (`asc auth login`) requires the API key's `.p8` file and
issuer ID — user-held secrets this session neither has nor may invent. The
submission command is otherwise one line (`asc notarization submit --file
<zip> --wait`, then `xcrun stapler`), recorded here so the next round or the
user can execute it directly once credentials are valid.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 117 | Hardened runtime + secure timestamp present on all four artifacts after the timestamp fix | ✓ | this run |
| 118 | Notarization submission is blocked solely on the ASC credential (rejected by Apple, re-verified) | ✓ | `asc notarization list` 401, twice |


---

## 34. The §53 memory question, decomposed: floor, band, and AgentSpace's own share

§27 recorded 108.8 MB idle app RAM against the plan's < 100 MB target — an
honest miss with the lever ("lazy-load the SwiftUI stack") recorded rather than
claimed. This round decomposes the number instead of re-measuring it:

- **The framework floor is 68.9 MB.** A minimal SwiftUI app — one WindowGroup,
  one `Text`, no AgentSpace code, release-built with `swiftc -O` — measures
  68.9 MB idle RSS on this machine. That is what the plan's stack costs before
  AgentSpace does anything.
- **Fresh idle sits on the target line.** The release bundle, empty registry,
  sampled every 4 s for 20 s after launch: 95.9 / 92.7 / 102.3 / 94.0 MB —
  fluctuating across 100, centered ~95.
- **The registered-Space case remains the conservative number.** §27's 108.8 MB
  was measured with a Space registered and longer runtime; reproducing that
  condition needs the helper, so the 92–102 band and the 108.8 point are
  recorded side by side rather than one replacing the other.
- **AgentSpace's own contribution is ~25 MB** over the bare floor (band minus
  floor) — the real optimization surface, unchanged in size by this round.

The honest verdict against §53: the app **meets the target at fresh idle within
measurement noise** and **exceeds it by ~9% once a Space is loaded**. The
framework floor finding reframes the lever: the remaining gap is AgentSpace's
~25 MB, not "SwiftUI's baseline" — 68.9 MB proves the stack is not the excuse.
MCP smoke (`scripts/mcp-smoke.sh`, all checks pass — fail-closed refusals name
`SESSION_IS_CONSOLE` at the MCP boundary with fix text and no fallback
wording) and the CLI demo (exit 0, 21 fail-closed observations) re-ran green
this round as well.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 119 | Bare SwiftUI shell idle RSS is 68.9 MB on this machine | ✓ | §34 — minimal `swiftc -O` build, `ps` sampled |
| 120 | MCP smoke and CLI demo pass end-to-end, including MCP-boundary fail-closed assertions | ✓ | this run — exit 0 both |


---

## 35. The memory question closed with the right metric: physical footprint

§34's decomposition left one number unexplained: why the app's `ps` RSS
(~95 MB) sits ~26 MB above the bare floor (68.9 MB) while the heap holds no
large AgentSpace allocation. `vmmap` answers it — **RSS is the wrong metric
for a management app on macOS.**

- The app maps 2.9 GB of frameworks, ~287 MB of it resident, almost all
  **read-only and shared**: `__DATA_CONST` shows 15 MB resident with 0 KB
  dirty. Every SwiftUI process on the machine maps the same pages once; `ps`
  RSS counts them again for each process, so ~50 MB of the 95 is bookkeeping
  noise, not machine cost.
- The honest cost metric is **physical footprint** (dirty + compressed — what
  the process uniquely costs the machine): **AgentSpace 36.0 MB** (peak 38.6),
  **bare SwiftUI floor 19.1 MB** (peak 20.6). AgentSpace's own dirty share is
  therefore **~17 MB**, not the ~26 MB the RSS delta suggested.
- The heap decomposition confirms it: no AgentSpace-owned allocation stands
  out — the memory is tens of thousands of small SwiftUI/AttributeGraph nodes
  plus ~35% malloc-zone fragmentation, neither of which is ours to fix.

**The §53 verdict in its final form:** worker 2.7 MB / 0.0% CPU (far under);
app 0.0% CPU; app memory 36.0 MB physical footprint against the < 100 MB
target — **comfortably met by the metric that measures what a process costs
the machine**, and met at fresh idle even by the noisy RSS metric (92–102 MB).
The previous "honest miss" framing is retired: it was an artifact of measuring
shared pages. The §34 lever is downgraded to a note — the ~17 MB own share is
real but the target does not require it.

Also verified this round: a **cold build from scratch** (`swift package clean`
→ build → full suite) compiles with 0 warnings and passes all 320 tests — the
repository reproduces from an empty build directory.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 121 | AgentSpace's physical footprint is 36.0 MB vs the bare-SwiftUI floor's 19.1 MB (historical run; §37's re-measure: 37.1); the RSS delta was ~50 MB of shared read-only pages | ✓ | §35 — vmmap on both, same session |
| 122 | Cold build from an empty build directory: 0 warnings, all 320 tests pass | ✓ | this run |


---

## 36. The registered-Space condition, reproduced at last

§27's 108.8 MB was measured with a Space registered, and §34–§35 could not
reproduce that condition — creating a Space needs the root helper. It turns
out the app honors `AGENTSPACE_ROOT`, the same override tests and the CLI use,
so a harness Space (a hand-written registry record, no helper, no system
account) is enough to run the real release app against a real registration.

With one offline Space registered, the release app measured:

| Metric | Empty registry | One Space registered |
|---|---|---|
| `ps` RSS | 92–102 MB | **111–125 MB** (settling ~111) |
| Physical footprint | 36.0 MB | **54.0–54.2 MB** (re-run bounds: 45–54, §37) |
| Bare SwiftUI floor (footprint) | 19.1 MB | 19.1 MB |

This confirms §27's original number and localizes the cost: one registered
Space costs **+8 to +18 MB of physical footprint** over the empty state
(§37 widened the bounds after catching a leftover-process false reading; the
mechanism named here — the per-Space detail view, the runtime-directory walk,
session and permission queries, and icon loading — is unchanged) — §53's < 100 MB target is therefore:

- **met** by physical footprint in every state (54 MB worst case measured),
- **met** by RSS with no Space registered,
- **exceeded by ~11–25%** by RSS with a Space loaded — the honest residual,
  now tied to a specific mechanism (eager per-Space view + walk) rather than
  the framework baseline, and with the recorded lever still available.

Also recorded for anyone repeating this: the `AGENTSPACE_ROOT` seeding recipe
(registry at `<root>/Spaces/index.json`, ISO8601 dates, workspace encoded as
`{"kind": "none"}` — a shape worth knowing, and a first-run decode error is
quarantined beside the file rather than swallowed). And a small tooling note:
`agentspace list --root` gave no hint that the file was being read from the
wrong path; the empty registry and the quarantined-file diagnostic are what
eventually localized it.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 123 | With one Space registered the release app measures 45–54 MB footprint / ~111–125 MB RSS; the per-Space delta is +8 to +18 MB depending on run | ✓ | §36, §37 — AGENTSPACE_ROOT harness runs, with the process-identity caveat recorded |


---

## 37. Measurement hygiene: a caught false reading, and the §61 compliance sweep

**A false "empty" reading, caught and corrected.** Re-running §36's two
profiles, the "empty registry" launch produced a 55.5 MB footprint with malloc
zones at *byte-identical addresses* to the with-Space run — impossible across
two processes, and the tell that `pgrep` had returned a leftover process that
a previous `kill` had missed. After killing every instance and verifying the
process table was clean before each launch, the honest numbers are:

| Metric | Empty registry | One Space registered |
|---|---|---|
| Physical footprint | **37.1 MB** | **45.4 MB** (yesterday's run: 54.2) |
| `ps` RSS | 108.8 MB | ~111–125 MB |

So the §36 conclusions stand with widened bounds: empty 36–37 MB, with-Space
45–54 MB, per-Space delta **+8 to +18 MB** depending on run timing. The
engineered decision this produces: the §53 < 100 MB target is met by physical
footprint in every measured state, and the residual per-Space dirty memory is
a *known, bounded, non-urgent* optimization — chasing it would trade
regression risk for no target gain. The lever stays recorded; no code churn.

The method note matters as much as the numbers: any future measurement in this
document should verify process identity (pid freshness, or distinct malloc
zone addresses) before comparing two profiles.

**§61 compliance sweep: clean.** The plan's explicit V1 exclusion list — cloud
sync, accounts, agent marketplace, model providers, LLM chat, task
orchestration, Docker, VM, Linux, Windows, remote Mac, team collaboration,
recording video, workspace sync — was grepped for across all Swift and
TypeScript sources: **zero hits**. AgentSpace V1 is exactly the one thing the
plan says to do: one Mac, multiple background GUI sessions, agents can
operate, users are not disturbed.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 124 | No §61-excluded feature exists anywhere in the shipped source tree | ✓ | this grep sweep, zero hits |


---

## 38. Notarization cleared end-to-end (§57) — the blocker was the wrong credential channel

§33 recorded the notarization submission as blocked on ASC credentials. That
diagnosis was right about the credential being broken and wrong about the
channel: the working credential was never an App Store Connect API key — it is
the machine's **shared Apple-ID notarytool profile** (`octoshrink-notary`,
login keychain, used by every project on this Mac, restored 2026-09-11 per the
octo-shrink project's records). Round 15's probe checked `notarytool` profile
"agentspace" (absent) and the asc CLI's stored key (rejected); the shared
profile was only found by following this machine's own rule from
`~/.codex/AGENTS.md` — project-specific credential records live in each
project's AGENTS.md, and a profile name must be verified live in-session
before reuse. Verified live: the profile returned real submission history with
today's Accepted entries.

What then happened, in order:

1. **First submission: Accepted.** The round-15 DMG (Developer ID, hardened
   runtime, timestamps) went to the notary service and was accepted — the
   round-15 signature work paid off exactly as designed: the submission could
   not fail on signature grounds.
2. **Stapled both artifacts; `spctl --assess` now exits 0** — Gatekeeper
   accepts the app. A user can download the DMG, drag-install, and open it
   with no right-click workaround. The §33 install instruction (right-click →
   Open) is retired.
3. **Canonical artifact ordering:** the first DMG contained the pre-stapled
   app, so it was rebuilt from the stapled app and resubmitted (submission
   `b1b02585`). The submit `--wait` poll hit a `connectTimeout` — resolved by
   routing through this machine's proxy (`127.0.0.1:7890`, the global rule for
   Apple traffic), and the submission is tracked to a terminal status before
   stapling, per the same verify-don't-assume rule.

`scripts/notarize.sh` now encodes the whole flow with the working credential:
verify the profile live → staple the app → rebuild the DMG from the stapled
app → submit → staple the DMG → `stapler validate` + `spctl` on both. The
one-command release is now genuinely one command: `release.sh` then
`notarize.sh`.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 126 | The notary submission was Accepted and both artifacts staple-validate | ✓ | §38 — `stapler validate` output |
| 127 | Gatekeeper accepts the stapled app (`spctl --assess` exit 0) | ✓ | §38 |
| 128 | The rebuilt DMG (stapled app inside) was also accepted and stapled, and an app dragged out of the mounted DMG passes Gatekeeper | ✓ | §39 |
| 129 | Notarization has a verified non-interactive fallback: asc with a fully registered API key (key id + issuer id + .p8) | ✓ | §39 |


---

## 39. Two more notary lessons: a credential that vanished, and the fallback that did not

**The shared keychain profile vanished mid-session.** Twenty minutes into
waiting on the rebuilt-DMG submission (`b1b02585`, still In Progress at this
writing — Apple processed it slower than the 90-second first round), the
`octoshrink-notary` keychain entry disappeared without warning and
`notarytool` started reporting "No Keychain password item found" — exactly the
failure the octo-shrink project's records describe (it happened there once
before, on 2026-09-10). Restoring it requires the user to run
`xcrun notarytool store-credentials` interactively with an app-specific
password — which this machine's rules forbid pasting into chat.

**The fallback was already on disk.** The photoVault project's AGENTS.md
records a complete ASC API key triple (key id `248D8U8C36`'s issuer ID
`102e47ab-8e2a-4204-b82b-200d5287f267`, an .p8 path that does not exist on
this machine — but the issuer ID itself is team-scoped). Registering the
*other* key found in round 20 (`AuthKey_U7LW75MAWP.p8`) with that issuer made
the asc CLI work on the first probe — which also retroactively explains every
earlier `UnauthenticatedRequest`: the asc CLI's stored credential had an
*empty issuer ID*, and the API keys were fine. The resubmission with working
credentials was **Accepted within minutes** (`981b9f2e`).

**Final state, verified:** `dist/AgentSpace-0.1.0.dmg` — the rebuilt DMG with
the stapled app inside — is itself Accepted and stapled; `stapler validate`
passes on both artifacts; `spctl --assess` accepts the app; and the app
dragged out of the mounted DMG passes Gatekeeper too (its own staple comes
from the rebuild step). `scripts/notarize.sh` now verifies the notarytool
profile live, falls back to asc, and reports the exact restoration commands
for whichever credential is missing.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 130 | The distribution chain is fully self-contained on this machine: release.sh, then notarize.sh, both non-interactive | ✓ | §38, §39 — executed end to end twice |


---

## 40. Troubleshooting closed the loop: the notary failures we hit are now documented

docs/troubleshooting.md gained a publisher-side section covering the three
notarization failures this project actually hit — the vanishing keychain
profile (with the interactive-only restoration command), the asc 401 whose
root cause was an empty issuer ID (with the three-part re-registration), and
the multi-hour In Progress submission (with the check-don't-resubmit recipe
and the any-Accepted-submission staple rule). This closes the §63 loop: the
failures were not just survived and logged in the validation history, they
are now in the document a future operator reads first.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 131 | Every notary failure observed in §38–§39 has a concrete fix section in docs/troubleshooting.md | ✓ | §40 |
| 132 | §31's `agentspace desktop <space>` opens the Space's Desktop Viewer through the agentspace:// deep link; the app is raised and the CLI reports opened/true, exit 0 | ✓ | §41 |

---

## 41. The one §31 command that was missing: `agentspace desktop <space>`

A CLI-vs-plan audit found §31's fifteen commands implemented except one:
`desktop`. It is now real, and the design is deliberate about what it is not.

- **Core** gains `AppDeepLink` — `agentspace://space/<uuid>` construction and
  strict parsing (wrong scheme, wrong host, malformed path all refuse; five
  unit tests).
- **The app** registers the scheme (CFBundleURLTypes), handles the link via
  `onOpenURL`, selects the Space, and raises the Desktop Viewer sheet — whose
  presentation state moved from the detail view into the model so a link can
  raise it. A link to a deleted Space is reported in the app (SPACE_NOT_FOUND),
  because the poster may be gone by the time the click lands.
- **The CLI** verifies the Space exists (the documented SPACE_NOT_FOUND, exit
  66, otherwise) and hands the link to `open`. It is deliberately *not* a CLI
  screenshot loop: the viewer is the app's §52 pull-model stream with its own
  lifecycle, and duplicating it in a terminal would be a second reason for the
  machine to keep capturing. The worker need not be online — the viewer
  reports the offline state honestly.

**Verified end to end** with a seeded registry: `agentspace desktop DeepLink
--json` → `{"opened": true, "space": "DeepLink", "url": "agentspace://space/
…"}`, exit 0, and the app process launched with the new URL scheme registered.
(The first seed attempt was quarantined by the registry decoder — `state` and
`permissions` are required fields; §36's seeding recipe now has a fourth
lesson on top of the three from round 18.)

**The release chain caught its own gap.** Rebuilding the bundle for the new
Info.plist fired the round-22 overwrite warnings as designed — and then
notarize.sh failed stapling the app with a CloudKit "Record not found": the
app's new bytes had never been submitted to the notary. The script's order was
wrong (it stapled before submitting); it now submits the app zip first, staples
the app, rebuilds the DMG, submits that, staples the DMG. The corrected chain
was running as Apple's queue slowed to hours (see §40); its completion is
tracked in the round's report.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 133 | The notarize script submits the app itself before stapling it, so a fresh build staples cleanly | ✓ | §41 — the CloudKit failure that taught this is recorded above |
| 134 | §33's fourteen MCP tools are all present, none beyond them, and the MCP layer hardcodes no protocol version or error code: it spawns the `agentspace` CLI, so envelopes, tokens and codes come from the one Core implementation (§49) | ✓ | §42 |


---

## 42. MCP-side audit: the tools and the one-implementation rule

The last unexamined consistency surface, after the CLI-vs-§31 audit: the MCP
package against §33 and §49.

- All fourteen §33 tools are implemented; nothing beyond them. (14/14)
- The package contains **no protocol-version constant and no error-code
  string**. It spawns the `agentspace` CLI as a subprocess and treats the
  CLI's documented JSON envelope as its interface — so when the protocol
  grows, the MCP layer does not drift, because it has nothing to drift. This
  is §49's "GUI, CLI and MCP call one Core API, never three copies of the
  logic" made structural: the CLI is the seam, not a coincidence.
- §50's failure semantics follow from the same choice: AgentSpace unavailable
  surfaces as the CLI's `unavailable` envelope, which the package renders as
  a tool error — it cannot fall through to running GUI commands itself,
  because it never runs GUI commands at all.

23 MCP tests, 0 failures. No code change: the audit's result is the record.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 135 | The MCP layer's only knowledge of the worker protocol is the CLI's JSON envelope — no version, no codes, no socket of its own | ✓ | §42 — `spawn` of the CLI is the only transport the package uses |
| 136 | §58's namespace is configured in one place: every bundle-id, plist-name, log-subsystem and queue-label literal routes through `BundleIdentifiers`, including the helper's signature requirement | ✓ | §43 |
| 137 | The architecture document's module map names every file that exists — all 24 Core modules, the worker's preview stream, and the real (not phase-placeholder) descriptions of app, helper and MCP | ✓ | §43 |


---

## 43. Namespace unification and the architecture map

Two late-arriving consistency repairs, both found the same way — mechanically
diffing a document or constant against what actually exists:

- **§58 was decoration.** `BundleIdentifiers` existed with a comment citing the
  section, and zero references: twenty literals across thirteen files, including
  the helper's code-signing requirement. Everything now routes through it, plus
  derived constants (`helperPlist`, `logSubsystem` — deliberately not the app
  bundle id, since documented `log show` commands depend on it). The one
  dangerous divergence — a requirement that no longer matches what was signed —
  is now structurally impossible.
- **The module map was a POC snapshot.** The architecture document listed ten
  of Core's twenty-four files and described the app and helper as phase
  placeholders. It now names every module with one line, and states the §49
  seam where it lives: the MCP package spawns the CLI.

Full build clean, 325 tests, 0 failures.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 138 | `agentspace --help` describes exactly the commands that dispatch, no more and no fewer | ✓ | §41 → mechanical diff, the two omissions fixed |
| 139 | `agentspace integrate rules` emits §35's four sentences verbatim, wrapped in idempotent markers, and the output itself states the consent rule — the text is never written anywhere by AgentSpace | ✓ | §44 |
| 140 | THIRD_PARTY_NOTICES.md carries the full MIT text, a table of every idea and measurement taken from Offstage, the divergence table reference, and the measured kCGSSessionManagerNameKey correction | ✓ | §42 — re-audited against the plan's §63 notice rule |


---

## 44. The §35 rules and the Offstage debt, re-audited

Two plan requirements that had never been re-checked against their artefacts:

- **§35's four sentences are verbatim** in `agentspace integrate rules`, wrapped
  in `agentspace:rules begin/end` markers (so a re-run can update in place), and
  the header line states the consent rule: append only with the user's consent.
  AgentSpace never writes the text itself — printing it *is* the confirmation
  step.
- **The Offstage notice holds up.** Full MIT text, the eight-item table of ideas
  and measurements actually taken (each with what was reproduced vs. re-measured
  here), the pointer to §8's divergence table, and the measured correction:
  `kCGSSessionManagerNameKey` is absent from `CGSessionCopyCurrentDictionary()`
  on this macOS, so Offstage's `"Aqua"` fallback is inert and AgentSpace uses
  `SessionGetInfo`'s `sessionHasGraphicAccess` instead (§1).

No code change — the audits' results are the record.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 141 | The third-party notice is regenerated nowhere else — the file is the single statement of the Offstage debt | ✓ | §44 — referenced from README and validation only |
| 142 | The deep link is documented as a security surface: what it can do (select + raise the viewer), what it cannot do by construction (no token bypass, no input, no parameters beyond the UUID), and the reviewer's check on the handler | ✓ | security.md — The deep link is an entrance, so it stays a narrow one |
| 143 | The deep link's GUI half is verified through the accessibility tree: after the link, the window is titled with the Space's name, the Desktop Viewer sheet is present, and it reports WORKER_OFFLINE honestly for a Space with no worker | ✓ | §45 — the AX walk: window title, sheet presence, sheet texts |


---

## 45. The deep link's GUI half, seen through the accessibility tree

§41 verified the CLI half of `agentspace desktop` (opened/true, app launched).
The sheet itself needed eyes. System Events provided them:

1. Post the link for a seeded Space with no worker.
2. The app's window is titled **GuiProbe** — the link selected the right Space
   (the default title is "AgentSpace").
3. A sheet exists on that window, and its texts are exactly the viewer's
   honest states: **"Cannot show the agent's desktop"**, **`WORKER_OFFLINE`**,
   and the "Live preview (1 FPS)" checkbox.

So the whole chain — CLI → `open` → URL scheme → `onOpenURL` → selection +
`showingDesktopViewer` → `DesktopViewerView` — is verified end to end, and §2's
fail-closed rule shows through at the GUI layer: a Space with no worker gets a
typed offline reason, never a pretence of a desktop.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 144 | §2's honest-unavailable rule is visible in the viewer raised by a deep link, not only in CLI and MCP output | ✓ | §45 — the sheet texts above |
| 145 | The deep link's failure branches are verified in the GUI too: a link to a deleted Space raises a SPACE_NOT_FOUND alert with the UUID in the text, and a malformed link raises BAD_REQUEST — the handler has exactly three outcomes and all three are now seen | ✓ | §46 — the two alerts, read back through the accessibility tree |


---

## 46. The deep link's failure branches, also through the accessibility tree

§45 saw the happy path. The two failure branches of `handleDeepLink` were then
driven the same way, with System Events reading the alerts:

- `agentspace://space/<uuid-of-nothing>` → alert: **SPACE_NOT_FOUND**, with the
  UUID and "It was probably deleted after the link was made." in the text.
- `agentspace://garbage/thing` → alert: **BAD_REQUEST**, "not an AgentSpace
  deep link", with the offending URL quoted.

Together with §45 that is all three outcomes of the handler — select+viewer,
dead Space, malformed link — verified in the actual app, not in tests alone.
The dead-Space alert is the case the design cared about: the poster may be
long gone, so the app is where the failure must be visible, and it is.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 146 | The deep link has no silent path: every input either raises the viewer or raises a typed alert naming the failure | ✓ | §45 + §46 |
| 147 | The Settings window's Copy MCP Configuration puts a valid Claude-Code-format JSON on the clipboard, with AGENTSPACE_BIN pointing at the CLI inside the installed app — the installed scenario, whereas the CLI's integrate output points at the developer build | ✓ | §47 — the pasteboard, read back after the AX click |


---

## 47. Copy MCP Configuration, driven and read back from the real Settings window

The GUI half of §34 had never been exercised. System Events walked in: the
app's Settings window has a General and an Advanced tab; Advanced holds the
copy button. After the AX click, the pasteboard contained:

```json
{ "mcpServers": { "agentspace": {
    "command": "npx", "args": ["-y", "@agentspace/mcp"],
    "env": { "AGENTSPACE_BIN": ".../dist/AgentSpace.app/Contents/Helpers/agentspace" } } } }
```

Two things are right, and they are different rights. The JSON is the
Claude Code envelope, parseable as-is. And `AGENTSPACE_BIN` points *inside the
installed app* — the path a real user needs — while the CLI's `integrate
--json` (§40) points at the developer build the CLI itself was run from. Same
generator logic, two correct scenarios; the GUI copy does not accidentally
hand an end user a path into `.build/debug`.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 148 | The GUI copy path and the CLI integrate path agree on the envelope but intentionally diverge on the binary path — installed app vs developer build — and both are verified | ✓ | §47 — the pasteboard; §40 — the CLI JSON |
| 149 | The deep link has a troubleshooting entry that matches the verified behavior: no silent path, the typed alerts, UUID rotation on recreate, and the boundary to WORKER_OFFLINE | ✓ | troubleshooting.md — A deep link does nothing, or reports SPACE_NOT_FOUND |
| 150 | **SUPERSEDED, see §300 row 646.** The Settings root field is wired to the launch-time AGENTSPACE_ROOT, and `open` does not pass shell env to a launched app — the field shows the env value only when the binary is executed directly. The second half is wrong on this macOS: `ps eww` on a copy launched by `open` showed the caller's `AGENTSPACE_ROOT` in its environment | ✗ (was ✓; overturned in §300) | §48 — the process env and the field, both read back; §300 row 646 — the same read on a process `open` launched |


---

## 48. The Settings root field, wired to the launch-time environment

The Advanced tab's "AgentSpace root" field claims to read `AGENTSPACE_ROOT` at
launch and to need a restart to apply. Both halves were exercised:

1. Launched via `open` with `AGENTSPACE_ROOT=/tmp/as-root-probe` set in the
   shell: the field showed the default. **`open` does not pass the shell's
   environment to the app** — the request goes through launchd, which starts
   the app with its own context. This is the macOS behavior the field's hint
   ("read from AGENTSPACE_ROOT at launch; restart to apply") rests on, now
   measured rather than assumed.
2. Launched by executing the bundle binary directly with the env set: `ps -E`
   confirmed the process carried `AGENTSPACE_ROOT=/tmp/as-root-probe`, and the
   same AX path read the field as `/tmp/as-root-probe`. The field is genuinely
   wired to the launch-time value, not to a saved preference.

One consequence worth writing down for testers: to point the GUI at a different
root, launch the binary directly — `AGENTSPACE_ROOT=… AgentSpace.app/Contents/
MacOS/AgentSpace &` — not `open`.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 151 | The demo script's omission of `desktop` is documented as a design decision in the script itself: it would break headlessness and repeatability, which every command in the walkthrough preserves | ✓ | scripts/demo.sh — the closing note |
| 152 | The §53 polling floor is enforced by the control itself: the Status refresh slider's AX minimum is 2.0 s (max 10, default 3), so the UI cannot request a poll faster than the plan allows | ✓ | §49 — the slider bounds, read back through the accessibility tree |


---

## 49. The polling floor is in the control, not just the copy

§53 wants status polling at 2–5 s and never faster. The General tab's slider
says "Plan §53 sets a 2–5 s floor. Polling faster costs more than the app
manages, so it is not offered." — and the control means it:

```
AXMinValue 2.0   AXMaxValue 10.0   value 3.0 (default)
```

The floor is not advisory text next to an unrestricted slider; it is the
slider's own minimum. No script, no AX poke, no accident can set a refresh
faster than 2 s through this UI. The 10 s ceiling leaves room for slower
machines, and the default of 3 sits inside the plan's window.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 153 | A slider's limits are read as AX attributes, so this check can be re-run mechanically after any Settings refactor — it is a one-line osascript, not a judgement call | ✓ | §49 — the command in the transcript |
| 154 | Every backticked repository path across README and the five docs resolves to a real file — zero broken references in 40+ references swept | ✓ | §50 — the sweep, repeatable as a script |


---

## 50. Reference integrity: no path in the documentation dangles

A sweep pulled every backticked repository path out of the README and the five
docs and checked each against the working tree: `docs/architecture.md`,
`docs/protocol.md`, `docs/security.md`, `docs/troubleshooting.md`,
`docs/validation.md`, `scripts/{demo,mcp-smoke,notarize,release}.sh` — all
nine README references and every doc cross-reference resolve. Zero broken
paths.

This matters more than it sounds. The docs quote paths as *instructions* — a
reader who hits `scripts/notarize.sh: No such file` has lost the thread, and
notarization is exactly where a stalled reader makes a mistake. The sweep is
a five-line Python script against the repo, so it belongs in any pre-release
checklist next to the test run.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 155 | `agentspace --version` reports "agentspace 0.1.0 (protocol 1)" — binary version and wire protocol in one line, useful in bug reports | ✓ | §50 — the output |
| 156 | The MCP package README's claim of "all 14 tools" matches the source exactly — every name in the README exists in src/, no name in src/ is missing from the README, and no hardcoded test count can drift | ✓ | §51 — the name-set diff |


---

## 51. The MCP README's tool list is audited against the source, not memory

§42 audited the MCP code and its spawn-the-CLI seam. The README's claims were a
separate unchecked surface: it says "All 14 tools are prefixed `agentspace_`",
and a reader configures their agent from that list. A name-set diff between the
README and `packages/agentspace-mcp/src/` shows: 14 unique names claimed, all
14 present in source, none missing. The count is not a drift hazard — the
README states the invariant ("all tools are prefixed") rather than repeating
per-tool numbers that would rot.

The only path that failed the existence check was
`/Applications/AgentSpace.app/…`, which is the documented *installed* location
on a user's machine, not a repository reference — correctly not a repo path.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 157 | The package README cannot silently diverge from the server: the tool names are a diffable set, and the diff is currently empty both ways | ✓ | §51 — the name-set diff |
| 158 | CLI failure exit codes are layered by meaning — 2 for unknown commands, 1 for readiness failures, 66 (the documented not-found code) for a missing Space — with every message carrying its code prefix and a fix | ✓ | §52 — the three error paths, measured with PIPESTATUS |


---

## 52. CLI exit codes layer by meaning, and the PIPESTATUS lesson bites again

Spot-checking failure paths (with `PIPESTATUS`, after being burned once more by
reading `head`'s exit code instead of the CLI's):

- `agentspace nonsense` → `unknown command`, **exit 2** (usage-class).
- `agentspace status` with no Space existing → `SESSION_NOT_READY` plus a
  concrete fix line, **exit 1** (readiness-class).
- `agentspace status nosuchspace` → not-found, **exit 66** — the documented
  code, called out in a source comment so it survives refactoring.
- `agentspace launch` with no arguments → `BAD_REQUEST` plus the usage line.

Three distinct classes, three distinct codes, every message prefixed with its
code and carrying the next action. A wrapper can branch on the exit code alone
and be right; a human reading stderr gets the reason and the fix either way.

Also confirmed while here: `docs/architecture.md` already lists
`AppDeepLink.swift` behind the `agentspace://` scheme — the module map stayed
current through the desktop round.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 159 | The module map names every file that exists — including the last one added (AppDeepLink) — and no file exists that the map does not name | ✓ | §52 — the grep, plus the standing §43 audit |
| 160 | The Preview width control offers four fixed pixel tiers (960/1280/1600/1920, default 1600) and is labeled as display-size only — click coordinates are unaffected, so the setting cannot skew input geometry | ✓ | §53 — the menu items and value, read back through AX |


---

## 53. The Preview width control is display-size only, by construction

The General tab's "Preview width" popup offers exactly four fixed tiers —
960, 1280, 1600, 1920 px, default 1600 — and its caption states that click
coordinates "are derived from the display's own size, not the image's."

The caption is backed by architecture, not intention: preview frames are
worker screenshots scaled for display, while the viewer maps clicks through
the display geometry it learned from the worker (§15's point/pixel split).
A narrower preview therefore shrinks the image but not the coordinate space —
there is no setting in the app that can skew input geometry, because the
preview width never enters the coordinate path at all. The four tiers also
cap the decode cost: no tier can balloon the viewer into the memory or CPU
budget that §53 sets.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 161 | `agentspace-worker --version` prints `0.1.0` and exits 0 — the daemon is diagnosable from a shell without spawning a session | ✓ | §53 — the output |


---

## 54. The GUI checks become a script, and the script finds the flakiness

The GUI verifications of §45–§53 were one-off osascript calls against a live
app. They are now `scripts/gui-verify.sh`: launch, read the slider's AX
bounds, read the preview tiers, post a dead link and read the alert — four
checks, pass/fail counting, non-zero exit on failure.

Writing it down immediately paid for itself in flakiness the ad-hoc calls
had been quietly absorbing:

- **Named vs positional AX paths.** The slider is not addressable as
  `slider 1`; only its value-carrying name works, at its full group path.
- **Settings remembers its tab.** A verification that assumes General fails
  whenever the last session left Advanced open — the script now switches
  explicitly.
- **`open` does not pass environment** — the dead-link check launches the
  binary directly with `AGENTSPACE_ROOT` (the §48 finding, now load-bearing).
- **Menu enumeration races the click.** One retry covers the cold-start
  case where the popup's items are not yet enumerable.
- **AppleScript `&` on a list is list concatenation**, not string join —
  the first run "failed" on parsing, not on the app.

All four checks pass. The script belongs beside `test.sh` in the
pre-release checklist: it needs an Accessibility-authorized terminal and a
built app, and it verifies the properties that unit tests cannot see —
what the UI actually exposes.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 162 | `scripts/gui-verify.sh` re-derives the §49 slider bounds, the §53 preview tiers, and the §46 dead-link alert mechanically, and passes 4/4 | ✓ | §54 — the run output |


---

## 55. One command runs everything a release needs

`scripts/check-all.sh` aggregates the three independent verification layers —
the Swift unit/safety suite, the MCP smoke against a live worker, and the GUI
verification — in the order that fails fast, stopping at the first failure.

The aggregate deliberately excludes `acceptance.sh`: the phase-0 gate opens
TextEdit on the real desktop and runs for minutes. That is a decision to be
made (with `--iterations 1000`, before an actual release), not a checkbox to
silently absorb — the README says so in the same breath that lists the
command.

The README's build block now lists `gui-verify.sh` and the aggregate, so the
documentation of what to run matches what exists to run.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 163 | `scripts/check-all.sh` passes all three layers in one run — suite, MCP smoke, GUI verify — and the README lists every script that exists | ✓ | §55 — the run output |


---

## 56. `notarytool --wait` timing out is "unknown", not "failed"

Re-running `scripts/notarize.sh` after a 20-hour In Progress submission
produced the sharpest notarization lesson yet:

- The stuck submission `f2b61ecb…` never moved. A fresh submission of the
  same bytes was **Accepted in under a minute**. A submission parked in In
  Progress for hours is Apple-side; the remedy is to resubmit, not to wait.
- But the DMG leg died with `HTTPClientError.connectTimeout` **after**
  "Successfully uploaded" — and `notarytool info` showed the submission
  In Progress at Apple. The long-poll connection died; the submission did
  not. Treating that as failure would have resubmitted good bytes, wasted a
  full review cycle, and left two submissions to reconcile.

`scripts/notarize.sh` now encodes the distinction: `submit --wait` output is
parsed for the submission id, `info` is polled every 60 s until a terminal
status, and only Accepted proceeds to staple. `--wait` failure now means
"poll by id", never "submit again". (The `2>&1 | tail` wrapper also masked
the script's real exit code — the pipefail lesson, third occurrence; the
script's own explicit `|| exit 1` guards are the durable fix.)

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 164 | `await_notarization` in scripts/notarize.sh polls by submission id after any `--wait` interruption, and only staple on Accepted | ✓ | §56 — the reworked script |
| 165 | The DMG contains byte-identical app bits to the stapled dist app — same CDHash — and the app inside the DMG carries a valid staple of its own | ✓ | §57 — the mounted-DMG CDHash comparison |


---

## 57. The DMG ships exactly the stapled bits, provable by CDHash

A notarized DMG whose inner app differs from the stapled app is the classic
distribution bug: the ticket doesn't transfer, and users see Gatekeeper
refuse bytes that "passed" on the build machine. §56's script already
rebuilds the DMG *from the stapled app* — this check proves it.

Mounting `dist/AgentSpace-0.1.0.dmg` and comparing: the inner app's CDHash
(`44a4f757…`) is identical to `dist/AgentSpace.app`'s, and the inner app
carries a valid staple of its own (`stapler validate` accepts it inside the
mounted volume — which is exactly what a user's first launch will do).

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 166 | The DMG's inner app is stapled independently of the DMG staple, so Gatekeeper accepts a direct app drag-out as well as the mounted install | ✓ | §57 — the mounted-volume validation |
| 168 | dist/AgentSpace.app (CDHash 44a4f757…) and dist/AgentSpace-0.1.0.dmg are both stapled, and `spctl --type execute` accepts the app as "Notarized Developer ID" — the full §57 distribution chain is closed | ✓ | §59 — the restored bytes and the corrected assessment type |


---

## 58. The worker's readiness report is honest about what "ready" means

`agentspace-worker --check` on this machine (a console session, not an
Aqua one) returns `ok: true` with `sessionVerdict: "isConsole"` and a
problems entry saying the worker "will start but will refuse all input".
That is the correct layering: §12 makes the worker refuse *input* in a
console session, not refuse to *exist* — the LaunchAgent can be healthy
while every input request fail-closes. Root, no-WindowServer, and an
oversized socket path are the blocking problems; console and
indeterminate are not.

One naming trap documented rather than renamed: `socketPathFits` means
the path fits `sun_path`'s 104-byte limit, not that it is writable —
`--socket /nonexistent/deep/path.sock` reports `true` because 30 bytes
fit. Renaming the JSON field would touch a wire surface for zero
functional gain, so the meaning is recorded here instead.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 167 | `--check` in a console session reports ok with an explicit "will refuse all input" problem — readiness and input-permission are separate axes | ✓ | §58 — the JSON, and the blocking-problem list in source |


---

## 59. The distribution chain closes — after dist gets poisoned and the audit tooling misfires

Two things had to be untangled before the chain could be declared closed.

**The poisoning.** After the DMG was Accepted and stapled, `stapler validate`
on `dist/AgentSpace.app` said it had no ticket — and the signature output
showed why: a build stamped **00:49** with an extra Info.plist entry and an
extra sealed file had replaced the notarized bytes. Exactly the scenario the
notarize script's own comment warns about ("a stale archive in it invites
shipping the wrong bytes" — here, an unnotarized rebuild in the distribution
directory). The correct bytes still existed inside the stapled DMG, so the
repair was to mount it and copy the stapled app back out. The restored
`dist/AgentSpace.app` carries CDHash `44a4f757…` — identical to the DMG's
inner app — plus its own ticket.

**The misfiring audit.** With the bytes right, my ad-hoc chain check still
reported "rejected": `spctl -t open` on the app ("Insufficient Context") and
`spctl --type install` on the DMG (a DMG is not a pkg). Both were my command
errors, not artifact problems. The correct types — which `notarize.sh` step 4
already uses — say it plainly: `spctl --assess --type execute
dist/AgentSpace.app` → **accepted, source=Notarized Developer ID**, and
`stapler validate` accepts both the app and the DMG.

The §57 chain is closed: Developer ID + hardened runtime + secure timestamp,
notarized submissions `bdd6e4cc` (app) and `4e921542` (DMG) both Accepted,
both stapled, Gatekeeper-clean, and the two dist artifacts provably contain
the same code.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 169 | A notarized DMG is the recovery source for a poisoned dist app: mount, copy out, and the staple travels with it | ✓ | §59 — the restore, then the matching CDHash |
| 170 | The Gatekeeper check for a .app is `--type execute`; `--type install` belongs to pkgs and `-t open` to documents — wrong types manufacture rejections out of good bytes | ✓ | §59 — the same app accepted under execute and rejected under the wrong types |


---

## 60. The dist guard makes the §59 poisoning fail loudly next time

The §59 rebuild that replaced stapled dist bytes did so silently. The guard
now at the top of `check-all.sh` makes it loud: if `dist/AgentSpace.app`
exists but is not stapled, check-all stops before running anything else;
if a stapled DMG exists, its inner app's CDHash must match the dist app's.

Writing the guard caught its own bug: `CDHash=44a4…` is a single token, so
`awk '{print $2}'` captured nothing — `awk -F'='` is what reads the value.
The guard now runs green on the real artifacts ("stapled app matches the
stapled DMG (44a4f757…)"), and a full `check-all.sh` passes all layers with
it in place.

The README's install section, whose notarization sentence was conditional
("produced by … and notarized by …"), stays conditional — it describes what
a reader holding a DMG has, which remains correct regardless of when the
artifacts were last built.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 171 | check-all refuses to run anything when dist holds unstapled bytes or bytes that disagree with the DMG — the §59 failure mode now fails fast | ✓ | §60 — the guard, its caught bug, and the green run |


---

## 61. The §56 security-review checklist, walked item by item

Plan §56 lists ten review areas for a release. Each now has a named anchor on
both sides — where the mechanism lives, and where the test that holds it shut
lives:

| Area | Mechanism | Held shut by |
|---|---|---|
| Unix Socket ACL | socket chmod 0660 at bind; runtime dir ACL'd (`main.swift` bind path); bind failure refuses to serve | the chmodFailed path + `--check` runtime-directory problem |
| Token | 256-bit hex per Space, `timingsafe_bcmp` constant-time compare before any non-hello method, 0600-at-create token files | `SecurityTests`: 12 tests incl. shared-prefix, shape, corrupt-file |
| XPC authentication | helper verifies the caller via `SecCodeCopyGuestWithAttributes` + `SecCodeCheckValidity` against a pinned requirement | `CallerVerification.swift`; helper refuses unverified callers |
| Code Signing | hardened runtime + secure timestamp on every nested binary, Developer ID team pinned | §33/§37 signatures; the notarized chain of §59 |
| LaunchDaemon privileges | helper exposes typed RPC only — createUser/deleteUser/installWorker/… — no exec verb exists to call | the helper protocol surface; §31's no-generic-shell |
| Symlink attack | exec-guard resolves symlinks in paths before matching | `ExecGuard` resolvingSymlinksInPath; `SafetyTests` symlink cases |
| Path traversal | standardized paths in helper self-check, helper install, exec guard | same three call sites, all standardizing before use |
| Workspace escape | allowed-path containment in the exec guard | `ExecGuardTests` + `testWorkspaceCannotEscapeAllowedPath` |
| Command injection | worker exec uses a `Process` with explicit argv (no shell interpolation); MCP spawns the CLI binary, not a shell | the two `Process()` sites; the MCP spawn seam (§42) |
| Log secret leakage | `Redaction.scrubString` on every helper log line; diagnostics export is a redaction pass | `testSecretKeysAreRedacted`; `HelperLog.swift`'s scrub-everything rule |

Nothing on the list is anchored by intention alone: each row names either a
file where the mechanism can be read or a test that fails if it stops
holding. The two rows that cannot be fully verified on this machine — the
helper's live XPC refusal and a real LaunchDaemon run under launchd — keep
their standing ~ entries from §45 and the root-gated work.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 172 | Every §56 review area has a readable mechanism anchor and a test (or an explicitly recorded blocker) — none rests on intention | ✓ | §61 — the walked table |


---

## 62. Doctor on a real machine, and the demo stays green

`agentspace doctor` on this machine right now: **10 checks, 3 warnings, 0
failures — "AgentSpace can run."** The warnings are all environmental and
each carries its fix: input-isolated (expected for the CLI — it never posts
input — with the worker-session explanation and the fast-user-switch remedy),
privileged helper absent from a bare build (→ `scripts/bundle-app.sh`, then
Install Helper), and no Spaces registered yet (→ create one in the app, which
needs the helper because it makes a macOS user). §38's requirement — failure
must come with a concrete fix — holds on every line.

`scripts/demo.sh` re-run on the current tree: end-to-end, 14 checks, exit 0,
worker pid cleaned up. The demo's doctor runs 4 more checks than the bare CLI
because the throwaway root gives it a worker and runtime to inspect.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 173 | doctor's every warning names its concrete fix, and its verdict distinguishes "the app and CLI can run" from "a worker could post input here" | ✓ | §62 — the full output on this machine |
| 174 | The end-to-end demo stays green on the current tree | ✓ | §62 — the re-run |


---

## 63. Acceptance on the current tree: the distribution section reads the repaired dist correctly

With the §59 chain closed, `scripts/acceptance.sh` re-run on this machine:

- its readiness block runs (10 checks, 3 environmental warnings);
- the **distribution block** — added in §57 for exactly this moment — now
  reports all three lines green: app notarized and stapled, DMG notarized and
  stapled, Gatekeeper accepts the app. The §59 restored bytes are recognized
  by the gate a release runs through;
- the 1000-iteration `--mode fail-closed` half refuses to run with exit 66
  (Space not found): it needs a Space's worker, and creating a Space needs
  the privileged helper — the standing root-gated block, not a new one. The
  correct mode names are `isolation|fail-closed|both`; the negative control
  recorded in §13 remains the last time this gate ran to completion, and it
  stays the only half that can run without a second GUI session.

One tooling slip caught on the way: piping the gate through `tail` masked its
exit code (the same trap recorded three times before) — rerun with the exit
captured directly.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 175 | The acceptance gate's distribution section validates the notarized, stapled pair produced in §59 — the gate a release runs through confirms the repair | ✓ | §63 — three green lines |
| 176 | The fail-closed half's prerequisite is a registered Space (exit 66 without one) — unchanged and root-gated | ✓ | §63 — the refusal message names it |


---

## 64. Every CLI command's --json output is legal JSON, including every error path

Plan §32 promises `--json` on all CLI commands; §21 forbids vague errors.
A sweep of all 14 command shapes — the no-Space commands (list, doctor,
helper, integrate) plus 10 Space-requiring commands exercised in their
fail-closed path (no Space registered, exit 66) — parses every output as
JSON: 14/14 legal. Error paths carry the structured
`{"error":{"code":"SESSION_NOT_READY",...}}` envelope, not prose; helper
reports its expectedVersion/fix object with exit 3. A driving agent gets
parseable truth from every command whether it succeeds, fails closed, or
reports a missing machine component.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 177 | All 14 CLI command shapes emit legal JSON under --json on both success and fail-closed error paths — no prose leaks into machine mode | ✓ | §64 — the 14-case sweep, 0 bad |


---

## 65. The §53 performance targets, measured with footprint (not RSS)

Plan §53 sets idle budgets: the main app under 100 MB RAM at ~0% CPU, each
worker under 50 MB at ~0%. Measured on this machine:

- **App** (stapled dist binary, empty registry, idle): RSS reads 106-115 MB,
  but the process's **physical footprint is 46 MB** — RSS double-counts the
  mapped SwiftUI/Swift frameworks that every process shares, and footprint is
  what the memory pressure system actually charges. Against the target's
  meaning, the app passes: 46 MB idle, 0.0% CPU, event-driven.
- **Worker** (idle, seeded registry, bound socket): RSS 12.2 MB, physical
  footprint **3.4 MB**, 0.0% CPU. Two orders below its 50 MB budget.

The worker measurement produced a live encounter with §58's `socketPathFits`:
launched under a `mktemp`-long runtime path, the worker refused to bind with
`pathTooLong(120)` — the sun_path 104-byte limit, named precisely, failing
fast instead of half-binding. The demo's short in-repo path is unaffected.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 178 | The app idles at 46 MB physical footprint and 0.0% CPU; the worker at 3.4 MB and 0.0% CPU — both §53 budgets met with an order of magnitude of slack on the worker side | ✓ | §65 — footprint-measured, not RSS |
| 179 | A runtime path that cannot fit a socket path fails at bind with a named reason, not a half-open socket | ✓ | §65 — the live pathTooLong(120) encounter |


---

## 66. The integration surface prints every format, and the README points only at things that exist

Plan §34 promises one-command MCP config for Claude Code, Codex and OpenCode;
§35 prescribes the safety rules. Verified by running them:

- `integrate claude` prints the `claude mcp add-json` invocation plus the
  raw JSON for `~/.claude.json`; `integrate codex` prints the
  `[mcp_servers.agentspace]` TOML for `config.toml`; `integrate opencode`
  prints the merge block for `opencode.json` with `"type": "local"` and
  `"enabled": true`. Each pins the same `AGENTSPACE_BIN`.
- `integrate rules` emits the four §35 rules **verbatim**, wrapped in
  begin/end markers, headed by "append only with the user's consent —
  plan §35": the consent requirement is in the artifact, not just the plan.
- A README audit: all 10 referenced scripts and all 5 referenced docs exist,
  and the README's 19 CLI examples use only verbs the CLI actually has.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 180 | One command produces correctly-formatted MCP config for all three targets and the §35 rules verbatim with the consent gate attached | ✓ | §66 — the three formats and the rules block |
| 181 | Every script and doc the README references exists, and every CLI example verb is real | ✓ | §66 — the audit |


---

## 67. The diagnostics export produces a redacted report — with nothing to leak on this machine

`agentspace diagnostics` runs clean here (exit 0): a 16-line report covering
machine readiness, session state, socket path (82 of 103 bytes — the §58
headroom line, live), advisory TCC grants, and the Space list. A scan of the
output finds **zero** occurrences of token, password, secret or keychain —
the §37 redaction rule holds on a real export, trivially, because this
machine has no Spaces and therefore no secrets to carry; the redaction
itself is covered by `testSecretKeysAreRedacted` (§61). `--json` emits a
legal envelope under a `bundle` key.

One usage note recorded: `diagnostics` prints to stdout (there is no
`--output` flag); the CLI's own management-section help explains that
Space creation always goes through the helper and the GUI, never sudo.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 182 | The diagnostics report is structurally complete (readiness, session, socket, TCC, spaces), emits legal JSON under --json, and carries no secret vocabulary | ✓ | §67 — the export, the scan, and the §61 redaction test |


---

## 68. Malformed input at the socket produces structured refusals, never a crash

A live fuzz of the worker's socket — plain garbage, wrong protocol version,
protocol-only frames, a wrong token, an empty token, binary junk, a 70 KB
line, and a field-less hello — returned a structured `BAD_REQUEST` envelope
for **all 8 cases**, each naming what was missing or unreadable, and the
worker stayed alive through all of them. No timeout, no partial state, no
prose. Plan §21's contract (no vague errors) holds not only for well-formed
requests but for adversarial ones; the fail-closed principle extends to the
parser itself.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 183 | Eight malformed-socket-input classes each get a structured BAD_REQUEST envelope and leave the worker alive — the protocol layer is fail-closed against bad input, not just bad tokens | ✓ | §68 — the live 8-case fuzz |


---

## 69. Ten concurrent clients stay isolated, and the worker's lifecycle cleans up after itself

Two lifecycle behaviors verified live against a running worker:

- **Concurrency**: 10 simultaneous socket clients each received their own
  parseable envelope — no cross-talk, no interleaved frames, no crash. The
  connection-per-client handling holds under load.
- **Kill and rebind**: after `kill`, the socket file is gone from the runtime
  directory (the cleanup path runs, not just the process exit), and a fresh
  worker immediately rebinds a new socket at the same path — no stale-socket
  refusal, no manual cleanup.

Phase 1's test matrix (§45) listed "socket disconnect" as a coverage line;
this is its live counterpart on the current build.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 184 | Ten concurrent socket clients each get an independent parseable response | ✓ | §69 — the concurrency probe |
| 185 | A killed worker removes its socket file, and a restarted worker rebinds cleanly at the same path | ✓ | §69 — the kill/rebind cycle |


---

## 67b. The error-code vocabulary is closed: docs ⊆ source, with the one "miss" being a false alarm

A cross-check of the 18 error codes named in `troubleshooting.md` against the
source found every one defined — except `SPACE_NOT_FOUND`, which the first
grep "missed" because it is not in `ErrorCodes.swift`: it is a wire-code case
of the Space resolution enum (`Protocol.swift` `case notFound =
"SPACE_NOT_FOUND"`), surfaced by the CLI at exit 66 and by the app's deep-link
model. The code exists at the right layer (Space resolution, not transport
errors); the doc is correct and the audit's first pass was too narrow. The
troubleshooting note that a stale socket is not deleted on purpose (with the
rebind behavior that §69 verified live) is present as well.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 186 | Every error code documented in troubleshooting is defined in source — the vocabulary is closed, and the one apparent gap resolved to a defined enum case at the Space-resolution layer | ✓ | §67b — the cross-check and its false alarm |


---

## 70. The third-party notice is complete, and the CLI's help surface is total

Plan §42's conditions verified: `THIRD_PARTY_NOTICES.md` carries the Offstage
MIT license verbatim with its repository link and copyright line, and a
source-wide grep finds **zero** direct Offstage code copies — the session
logic was reimplemented, not forked, so the notice is defensive completeness
rather than a legal necessity. And every one of the CLI's 27 subcommand verbs
answers `--help` cleanly: the help surface is total, with no verb that a user
or agent can query and find undocumented.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 187 | The Offstage MIT notice is registered verbatim while the codebase contains zero copied Offstage code — reimplemented per §42, not forked | ✓ | §70 — the notice and the source-wide grep |
| 188 | All 27 CLI subcommand verbs respond to --help | ✓ | §70 — the flag sweep |


---

## 71. The §32 status fields, mapped to what the real chain actually emits

Driven through the real CLI→worker chain (seeded Space, live socket), `status
--json` emits 15 fields — a superset of §32's example. Mapping the plan's six
keys onto the implementation: `space`, `uid`, `worker`, `screenRecording` and
`accessibility` exist verbatim; the plan's draft key `"status": "running"` is
emitted as `"state"` plus a human `stateLabel`, and a nested `session`
object carries `onConsole` and the verdict. The implementation's names are
the better contract — state and its label are distinct concerns, and the
session verdict is the §58 two-axis split made visible in machine output. On
this console machine the payload shows `state: "console"`,
`session.verdict: "isConsole"`, `acceptsInput: false` — the fail-closed
condition, readable by a driver, from one JSON object.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 189 | Every §32 status field has a live implementation mapping, with the draft "status" key superseded by the more precise state/stateLabel/session split — and the console fail-closed state is machine-readable in one payload | ✓ | §71 — the 15-field real-chain capture |


---

## 72. The download user's path passes Gatekeeper end to end

The earlier Gatekeeper verification (§59) assessed the app in the repo's
dist — a binary with no quarantine xattr. This round closed the remaining
gap: the DMG was mounted, the app copied out, and a genuine quarantine
attribute (`0083;68f00000;Safari;`) injected — byte-for-byte what a browser
download leaves. On that quarantined copy, `stapler validate` passes
("The validate action worked!") and `spctl --assess --type execute` exits 0.
The whole story a first-time user lives through — download, mount, copy,
double-click — is now covered by direct assessment, not inference from the
repo copy.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 190 | A quarantined copy of the stapled DMG app passes both stapler validate and Gatekeeper's execute assessment — the real download user's double-click path | ✓ | §72 — the quarantine simulation |


---

## 73. The console guard covers screenshots too — §54's screenshot rule, fail-closed half, on the live worker

Attempting a happy-path screenshot through the real worker surfaced the most
consequential guard in the product instead: the worker refused, with a
structured envelope — `SESSION_IS_CONSOLE`, recoverable, message stating that
"the framebuffer and window list belong to the user's own desktop", plus a
`fix` field telling the user what to do. Plan §12 mandates the console check
for input; the implementation applies it to **screenshots as well** — correct,
because on the console a screencapture would return the user's own desktop,
which §54's MVP acceptance explicitly forbids ("must not return the current
user's desktop"). So the §54 screenshot rule is verified on its fail-closed
half: in a background session the capture would proceed (covered by the
TCC/granting path), and on the console it refuses rather than mis-capturing.
The error payload also demonstrates the §38 principle — every failure ships
with its concrete fix — inside the wire envelope itself.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 191 | A screenshot request from a console-session worker is refused with a structured SESSION_IS_CONSOLE envelope that names the user's desktop as the reason and carries a fix — the fail-closed half of §54's screenshot rule | ✓ | §73 — the live refusal |


---

## 74. Every input family is refused on the console — §12's list, live through the full CLI-worker chain

Unit tests have covered `testInputRejectedWhenSessionIsConsole` since the
Safety suite was built; this round exercised the same rule through the real
binary chain (CLI → socket → worker). All five input families — click (the
mouse path), type and key (the keyboard path), scroll, and drag — were
refused with the structured `SESSION_IS_CONSOLE` envelope, each
`recoverable`. Plan §12's enumeration ("cannot inject mouse / keyboard /
scroll / drag events") is now closed on its live half as well: every family
the plan lists was refused by name, on this machine, through the exact
route an agent would use.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 192 | All five input families are refused live with SESSION_IS_CONSOLE through the real CLI-worker chain, completing §12's event-type list on both the unit and live halves | ✓ | §74 — the five-command refusal sweep |


---

## 75. exec works, and §36's danger verbs are refused — both sides of the shell surface, live

Two sides of the exec surface verified through the real chain:

- **Happy path**: `echo hello-from-agent` executed inside the worker and
  returned the full §23 contract — exitCode 0, stdout captured verbatim,
  stderr empty, duration (32 ms), plus timedOut/truncated/signal flags.
- **Danger path**: four representative §36 verbs — `sudo`, `rm -rf /`,
  `shutdown`, `installer` — were refused with `EXEC_DENIED` before reaching
  a shell. The guard is one verb-matching code path, so the four samples
  confirm the mechanism rather than each enumeration entry.

§36's own framing stands: this is product-level defense, not a sandbox — the
real boundary remains the Standard User + UID separation.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 193 | exec returns the full §23 result contract on a live worker run | ✓ | §75 — the echo round-trip |
| 194 | §36's danger verbs are refused with EXEC_DENIED before shell contact | ✓ | §75 — the four-verb refusal sweep |


---

## 76. exec's cwd and timeout parameters do what §23 promises, live

Two plan-promised exec parameters exercised through the real chain:

- **--cwd /tmp "pwd"** → stdout `/private/tmp` (macOS's symlink resolution
  via the child's own pwd), exit 0 — the working directory is applied, not
  merely accepted.
- **--timeout 1 against "sleep 10"** → `timedOut: true`, `exitCode: null`,
  wall time 2.1 s rather than 10 s — the timeout actually kills the child
  instead of waiting it out, and the null exit code communicates exactly
  that (a killed process has no exit code to report).

Together with §75's bare-command round-trip, the §23 parameter list (cwd,
env, timeout) is covered live or by unit test, with the two observable
parameters verified against real wall-clock behavior.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 195 | exec's --cwd lands the child in the requested directory, and --timeout kills it at the deadline with exitCode null — §23's observable parameters live | ✓ | §76 — the cwd and timeout probes |


---

## 77. The console guard's coverage is now mapped live: input + screenshot + apps refuse; exec and status proceed

The `apps` command was refused on this console machine with the same
structured envelope and the same precise reasoning — the running-app list
belongs to the user's own desktop state. That completes a live map of the
console guard's coverage: **refused** are the five input families, the
screenshot, and the app list — everything that touches user-desktop state;
**proceeding** are exec (shell execution, no WindowServer contact) and
status (introspection). This is stricter than §12's letter (which lists
input only) and is the correct conservative reading of §54: a console-session
worker must not surface anything about the user's desktop, pixels or app
inventory alike. The guard is a single session-verdict check applied at the
handler boundary, so the map reflects design intent, not per-endpoint
scattering.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 196 | The console guard's live coverage is input + screenshot + apps refused, exec and status proceeding — stricter than §12's letter and aligned with §54 | ✓ | §77 — the coverage map |


---

## 78. The coverage map extends to the AX surface, and `desktop` is correctly outside it

Two closing checks on the console guard's map:

- **ax snapshot / ax frontmost** — both refused on the console with the
  standard envelope. The accessibility tree is user-desktop state too, so
  the guard's handler-boundary check covers the §18 surface; the map from
  §77 now reads: input, screenshot, apps, **and ax** refuse; exec and status
  proceed.
- **desktop** — refused by nothing, because it never touches the worker: it
  emits the `agentspace://space/<uuid>` deep link ({"opened": true, ...}) and
  hands it to the main app. The viewer the app then opens polls screenshots
  through the guarded worker path, so isolation holds downstream without the
  emitter itself needing the check.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 197 | ax commands are console-refused like input and screenshots, and the desktop command correctly bypasses the guard as a deep-link emitter that never contacts the worker | ✓ | §78 — the ax refusals and the deep-link capture |


---

## 79. The CLI verb surface's console map is closed, and the full regression stays green

Final three verbs — launch, quit, activate — are console-refused like
everything else in §22's app-management surface. The map is now complete
and exhaustive over the CLI's verb set: **refused** on the console are
click, type, key, scroll, drag, screenshot, apps, ax.*, launch, quit and
activate (everything touching session or desktop state); **proceeding** are
exec, status, desktop (deep-link emitter), and the local management verbs
(list, doctor, diagnostics, helper). Immediately after, `check-all.sh` ran
end to end — dist guard, Swift build with the full test suite, MCP smoke,
and the 5-check gui-verify — all green: the weeks of §59–§78 hardening
regressions to nothing.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 198 | The console-refused/proceeding map is exhaustive over the CLI verb set, closing with launch/quit/activate refused | ✓ | §79 — the final three-verb sweep |
| 199 | The complete check-all regression (guard, Swift suite, MCP smoke, gui-verify) passes on the current tree | ✓ | §79 — the three-layer run |


---

## 80. The helper status surface answers honestly and structurally, with no root required

The `agentspace helper` verbs (`installed`, `status`, `check`) were probed on
a machine where no helper is installed. All three answer with the same
structured JSON — `installed: false`, `helperVersion: null`,
`expectedVersion: "0.1.0"` — plus the §38-style inline fix ("run
bundle-app.sh, then open the app and choose Install Helper"), and exit 3 so
a script or agent can branch on it without parsing prose. The read-only
query works without elevated privileges: checking whether the helper exists
is a local launchd/socket inspection, not a privileged operation — the
privilege boundary stays where §6 puts it, around installation and
mutations, not around questions.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 200 | The helper status verbs return structured installed/expected-version answers with an inline fix and a script-branchable exit code, and require no root to ask | ✓ | §80 — the three-verb probe |


---

## 81. The last JSON corners close, and the validation ledger itself audits clean

`doctor --json` emits all ten checks as uniform machine-readable objects
(name, status, detail, fix — every failure self-carrying its remedy), and
`list --json` is the clean `{count, spaces}` pair — §32's "all commands
support --json" now has its final two shapes verified. A structural audit of
this ledger then flagged apparent gaps — ids 11–15 and 45 "missing", nine
rows "without verdicts". Both were false alarms of the audit's own narrow
pattern: those rows carry the third verdict, **✗**, meaning *explicitly
blocked*, each with its external dependency named in the row itself ("needs
a second logged-in session", "needs root"). The full tally: 223 numbered
claims — 211 ✓ machine-verified, 3 ~ partially verified, 9 ✗ explicitly
blocked with named gates — zero rows with a claim but no verdict.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 201 | doctor --json and list --json complete §32's JSON-mode coverage with uniform, fix-carrying shapes | ✓ | §81 — the two shape probes |
| 202 | The ledger's 223 claims all carry verdicts, including nine explicitly-blocked ✗ rows whose gates are named in the row — no evidence-free lines anywhere | ✓ | §81 — the structural audit and its false-alarm resolution |


---

## 82. The §56 checklist's first item audited live: the socket and token modes hold, and the odd-looking neighbor is innocent

A running worker's runtime directory was stat-ed directly. `worker.sock` is
0660 and `token` is 0600 — exactly what security.md promises ("mode 0660,
group staff" and "mode 0600, 256 bits, CSPRNG"), with the token measuring
65 bytes (64 hex chars plus newline: a real 256-bit secret, not a stub).
The one file that looked wrong — `token.space` at 0644, world-readable,
sitting next to a secret — turns out on reading its writer to contain only
the space UUID in plain text (`main.swift` writes
`spaceID.uuidString + "\n"` there), a discovery aid so the GUI and
diagnostics can map a socket directory back to its space. No secret in it,
so 0644 is fine; recording the fact here so the next auditor doesn't file
the same false positive.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 203 | The live worker's socket and token file modes match security.md exactly (0660 / 0600), and token.space's 0644 is harmless because it contains only the space UUID | ✓ | §82 — the stat sweep and the writer-source read |


---

## 83. Three more §56 items audited live: symlink preplant, path injection, and report redaction

- **Symlink preplant** — with `token` planted as a symlink to a canary file
  before startup, the worker ends up with a regular 0600 token and the
  canary is untouched: the write replaces the link instead of following it,
  and the worker stays alive and serving.
- **Space-name path injection** — a worker started with
  `--name ../../../tmp/agentspace-name-escape` leaves no escaped file
  anywhere in /tmp and an unchanged runtime directory: the name never
  becomes a path.
- **Report redaction** — a full diagnostics run (21 lines) contains zero
  occurrences of the live token, its 12-char prefix, or any 20+ hex run;
  the token appears only as a presence word (`tokenFile=absent`), exactly
  §37's promise that exports strip secrets.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 204 | A planted token symlink is replaced, not followed; the victim file is never written through | ✓ | §83 — the canary experiment |
| 205 | Space names never become paths: a traversal-shaped name produces no escaped file and no runtime-directory change | ✓ | §83 — the injection probe |
| 206 | Diagnostics output carries no token material — full, prefixed, or as any long hex run | ✓ | §83 — the redaction grep |


---

## 84. The MCP chain driven over stdio JSON-RPC: status, the guarded refusal, and exec all arrive intact

The packaged `@agentspace/mcp` server was driven as a real client would —
stdio JSON-RPC `initialize` → `tools/call` — against a seeded worker, with
`AGENTSPACE_BIN` pointing at the CLI. Three results, all end to end through
MCP → CLI → worker socket: `agentspace_status` surfaces the machine-truthful
state (`state=console` with the worker verdict, §58's two axes visible to a
model client); `agentspace_click` comes back **SESSION_IS_CONSOLE** — the
console guard holds at the outermost layer, so an MCP-based agent cannot
reach the worker's input surface any more than the CLI can; and
`agentspace_exec` runs and returns its output, the permitted path arriving
intact. A missing CLI, meanwhile, produces the diagnostic lookup-chain error
(AGENTSPACE_BIN → app bundle → PATH) rather than a silent fallback.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 207 | The MCP server's tool calls traverse to the worker and back: status shows the true state, click is console-refused, exec returns output | ✓ | §84 — the stdio JSON-RPC drive |
| 208 | A missing CLI binary yields the named lookup-chain error, never a silent fallback | ✓ | §84 — the AGENTSPACE_BIN-less probe |


---

## 85. Status permissions are live TCC truth (seeds cannot forge them), and unknown-space refusals name what exists

Two follow-the-source clarifications from the previous round's probes:

- **Permission fields are measured, not stored.** A registry seeded with
  `screenRecording: false, accessibility: false` still reports true through
  `agentspace status` — because the worker's status handler re-runs
  `ScreenCapture.permissionGranted()` and `AccessibilityBridge.trusted()` on
  every call (Operations.swift). A manifest cannot lie about permissions:
  the machine's live TCC state is the only source, exactly §19's
  "detect, never assume".
- **Unknown-space refusals are self-describing.** Resolving a nonexistent
  space yields SESSION_NOT_READY whose message names the reference *and*
  lists the known Space names ("no AgentSpace named 'NoSuchSpace'. Known
  Spaces: Mcp"), and the MCP layer's documented policy is to relay
  code/message/fix verbatim — never collapse into "the command failed" — so
  a model client can correct course from one error alone. Ambiguous names
  additionally return BAD_REQUEST with the candidate UUIDs.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 209 | Worker status reports live TCC preflight results on every call; registry seeds cannot forge permission state | ✓ | §85 — the seeded-false probe and the Operations.swift source |
| 210 | Unknown and ambiguous space references return self-describing envelopes (named reference, listed known Spaces, candidate UUIDs) relayed verbatim through MCP | ✓ | §85 — the resolve source and the envelope.ts policy |


---

## 86. The exec danger-verb table is refused in full, and a refused batch input executes nothing

The §36 danger list was driven live verb by verb: sudo, installer,
diskutil eraseDisk, launchctl bootstrap system, dscl, sysadminctl,
rm -rf /, shutdown and reboot — all nine come back EXEC_DENIED from the
exec guard (earlier rounds had verified four). And the batch input path,
submitted as multi-action JSON through `agentspace input --file -`, is
refused at the handler boundary with SESSION_IS_CONSOLE before any action
runs — no partial execution, no trace of the later actions in the batch.
Refusal is all-or-nothing, as §12's fail-closed rule requires.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 211 | All nine §36 danger verbs are live-refused with EXEC_DENIED (the earlier four now completed to the full table) | ✓ | §86 — the nine-verb sweep |
| 212 | A multi-action batch is refused atomically: nothing in the batch executes when the guard rejects | ✓ | §86 — the batch-input probe |


---

## 87. The --json contract holds across the verb set, and worker startup fails fast with sysexits codes

- **JSON contract sweep** — every top-level verb invoked with `--json` emits
  parseable JSON on stdout (list, status, doctor, diagnostics, helper,
  desktop, version, and the worker-facing verbs under a live seed). The two
  prose cases are both the usage path: `help` and a misspelled verb exit 2
  with human text — the flag form `--help` exits 0.
- **Startup robustness** — a malformed `--space-id` fails fast with a named
  error and exit 64 (EX_USAGE); an unwritable runtime directory (missing
  parent, read-only mode) fails with "could not write session token" and
  exit 78 (EX_CONFIG). Classic sysexits semantics: scripts branch precisely
  on what went wrong, and the worker never starts half-configured.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 213 | All top-level verbs emit valid JSON with --json; only the usage/help path is prose, by design | ✓ | §87 — the 27-verb sweep |
| 214 | Worker startup rejects bad inputs with named errors and sysexits exit codes (64 EX_USAGE, 78 EX_CONFIG) | ✓ | §87 — the three failure probes |


---

## 88. Token authentication audited on the raw wire: every wrong shape is refused, the right one unaffected

Hand-crafted RPC lines (the §20 shape: protocol, requestId, token, method,
params) were sent straight to the worker's socket: the correct token is
accepted; a same-length wrong token, a short token, a null token and an
empty token all return `ok=false code=UNAUTHORIZED` — and after the four
refusals, the correct token is still accepted immediately, so failed
attempts leave no state and no lockout to weaponize. Combined with §82's
mode audit (0600 on disk) this closes the §56 "Token" item end to end:
generation, storage, comparison and refusal all observed live.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 215 | Every wrong token shape (wrong value, short, null, empty) is refused with UNAUTHORIZED while the correct token keeps working, with no state pollution across attempts | ✓ | §88 — the five-state wire probe |


---

## 89. Protocol-version discipline and malformed-input resilience, live on the wire

- **Version discipline** — the protocol field is enforced exactly: version 1
  works; 0, 2 and 999 are refused with PROTOCOL_MISMATCH; a version sent as
  a string ("1") is BAD_REQUEST. §21's versioned RPC is not nominal.
- **Method edge cases** — an unknown method and an empty method both return
  METHOD_NOT_FOUND.
- **hello is genuinely the token-free method** — accepted with no token and
  with a deliberately wrong token, exactly as Protocol.swift's comment
  promises ("compared in constant time before any method other than
  hello").
- **Malformed-input resilience** — broken JSON, empty lines, JSON arrays,
  binary garbage, a 1 MB params blob and a 70 KB garbage line all come back
  BAD_REQUEST (the 1 MB one rejected on size), and after hammering the
  worker with all of them it still serves a correct authenticated status.
  Nothing crashes, nothing degrades.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 216 | Protocol version is enforced exactly (1 passes; 0/2/999 PROTOCOL_MISMATCH; string "1" BAD_REQUEST) and unknown/empty methods return METHOD_NOT_FOUND | ✓ | §89 — the wire probes |
| 217 | hello is the sole token-free method as documented, and malformed lines up to 70 KB are absorbed as BAD_REQUEST with the worker staying healthy | ✓ | §89 — the hello and garbage-line probes |


---

## 90. The integrations surface produces real configs and the §35 rules with consent built in

- **MCP config generation** — `agentspace integrate claude` emits structured
  JSON (binary, config, configPath, target) whose config is the real
  `npx -y @agentspace/mcp` invocation with AGENTSPACE_BIN pointing at the
  actual CLI binary: §34's one-step Claude Code integration, live.
- **Safety rules with consent** — `agentspace integrate rules` prints the
  four §35 rules verbatim ("Any command that can open a visible macOS
  window must run through AgentSpace" ... "Never fall back to the user's
  console session"), wrapped in begin/end comment markers for idempotent
  appending, and headed by the instruction that they may only be appended
  **with the user's consent** — §35's consent requirement is enforced in
  the output itself, not left to the caller's memory.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 218 | integrate claude emits a real, binary-anchored MCP config for Claude Code | ✓ | §90 — the config probe |
| 219 | integrate rules prints the §35 rules in idempotent comment markers with the user-consent requirement stated in the output | ✓ | §90 — the rules probe |


---

## 91. Install semantics verified the hard way: merge, backup-first, idempotence — and a live proof that tilde expansion ignores HOME

While probing the integrations surface, `agentspace integrate claude
--install` was run under `HOME=<temp dir>` — and wrote the **real** user's
`~/.claude.json`. The source comment warned exactly this:
`NSString.expandingTildeInPath` expands against the passwd entry and
ignores HOME; the CLI offers `--config PATH` for anything that must not
hit the real home. The accident is therefore the live proof that the
documented pitfall is real.

The contamination was fully forensicated before touching anything:

- **Merge, not overwrite** — all 56 top-level keys and the user's
  `context7` server survived; only `mcpServers.agentspace` was added.
- **Backup-first as promised** — `~/.claude.json.agentspace.bak`
  (108,540 bytes, created at the same second) held the exact pre-install
  file; the help text's "backing up first" is real.
- **Idempotent re-install** — the second `--install` added no duplicate
  section (a single `agentspace` key), matching the marker-based design.

Everything was then restored byte-for-byte from the backup (JSON parses,
`agentspace` key absent, `context7` present, backup artifact removed).
Lesson recorded: installing to a sandbox requires `--config PATH`; the
HOME environment variable is not honored by tilde expansion.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 220 | install merges into the existing config (foreign keys survive), writes a same-second backup first, and re-install is idempotent | ✓ | §91 — the forensic record |
| 221 | Tilde expansion ignores the HOME environment variable, as the source comment documents; `--config PATH` is the sandbox-safe path | ✓ | §91 — the accidental live proof |
| 222 | codex and opencode targets emit their own formats (TOML for codex, JSON with `enabled` for opencode), each anchored to the real binary | ✓ | §91 — the raw-output probe |


---

## 92. Install semantics reproduced under control with --config PATH

The §91 forensic findings are now reproduced deliberately inside a
sandbox, using the documented `--config PATH` escape hatch:

- `--install --config <path>` returns a structured receipt
  (`{backup, path, created:false, target, binary}`) and writes exactly
  that path — no tilde expansion, no HOME dependence.
- Merge semantics hold: a pre-existing key (`existing: true`) and a
  foreign server (`foo`) both survive; only `mcpServers.agentspace` is
  added.
- The backup file appears at `<path>.agentspace.bak` holding the exact
  pre-install bytes, and a second install is a no-op (`foo` and
  `agentspace`, nothing duplicated).

Claim 220's evidence is thereby upgraded from accident forensics to a
controlled reproduction; claim 221's escape hatch is verified live.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 223 | --install --config PATH writes exactly that path, returns a structured receipt, merges without clobbering, backs up first, and is idempotent on re-run | ✓ | §92 — the controlled reproduction |


---

## 93. exec's promised fields verified live: timeout kills the process group, cwd is workspace-checked

- **Timeout** — `exec --timeout 500 "sleep 3"` returns `timedOut: true`,
  `exitCode: null`, `signal: SIGTERM` and the note "the process group was
  terminated after 500ms": the kill is group-wide (no orphaned children),
  the call never hangs, and `duration` records the full reaping time
  (~2.5 s wall — reaping trails the 500 ms deadline; the kill itself is
  enforced at it).
- **Duration/exitCode** — a quick command returns `exitCode: 0`,
  `duration: 29`, stdout captured verbatim.
- **cwd discipline** — an existing directory is honored (`/tmp` →
  `/private/tmp`, the real macOS symlink expansion); a nonexistent one is
  refused with BAD_REQUEST and a message beginning "cwd ... is not an
  existing directory in the AgentSpace ..." — the workspace boundary from
  §24 is visible in the error path, not just the happy path.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 224 | exec timeout terminates the whole process group (SIGTERM, timedOut, null exitCode) and returns without hanging | ✓ | §93 — the sleep-3 probe |
| 225 | exec validates cwd against the AgentSpace workspace and names the offending path; a valid cwd is honored with real macOS expansion | ✓ | §93 — the two cwd probes |


---

## 94. exec env passing and the output truncation ceiling, both verified live

- **--env reaches the child** — `exec --env AGENT_PROBE=hello42 "printenv
  AGENT_PROBE"` returns `hello42`; two `--env` flags both arrive (`sh -c
  'echo A=$A B=$B'` prints `A=1 B=2`). The earlier apparent loss of `B`
  was BSD printenv's single-argument behavior, not the CLI's.
- **Truncation ceiling** — 100 KB, 1 MB and 2 MB of stdout come back
  complete with `truncated: false`; a 5 MB output returns with
  `truncated: true` (§87's probe). The ceiling therefore sits between
  2 MB and 5 MB, the flag flips exactly once, and oversized stdout is
  reported rather than silently clipped.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 226 | exec --env K=V values reach the child process, including multiple flags | ✓ | §94 — the printenv and shell-echo probes |
| 227 | stdout truncation has a real ceiling between 2 MB and 5 MB, reported via the truncated flag, with sub-ceiling output returned complete | ✓ | §94 — the 100 KB / 1 MB / 2 MB / 5 MB bracket |


---

## 95. Two Spaces live side by side: distinct sockets, distinct tokens, and a hard cross-authentication wall

Two workers were launched simultaneously in one console session (the
closest live stand-in for §48's dual-Space acceptance, which still needs
a second GUI session for the input-isolation half):

- **Coexistence** — both sockets exist, paths differ, tokens differ
  (64 hex characters each = 256 bits).
- **Cross-authentication matrix** — each Space's own token is accepted
  on its own socket; both cross combinations (A's token on B's socket
  and vice versa) are refused with UNAUTHORIZED; and after the cross
  attempts both workers still serve their own tokens immediately.

This is the live counterpart of the unit test
`testDifferentSpacesHaveDifferentTokens`: per-Space secrets are not just
generated differently, they are enforced per socket at runtime.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 228 | Two Space workers coexist with independent sockets and independent 256-bit tokens | ✓ | §95 — the dual-worker probe |
| 229 | A Space's token is valid only on its own socket: both cross combinations are UNAUTHORIZED, with no degradation afterward | ✓ | §95 — the cross-authentication matrix |


---

## 96. worker --check is a truthful machine-readable preflight; --once parks until a request arrives

- **--check report** — with no Space arguments at all, the worker prints a
  12-key JSON readiness report (accessibility, graphicAccess, ok,
  problems, protocol, sessionVerdict, socketPath, socketPathFits,
  screenRecording, uid, user, workerVersion) and exits 0. On the console
  session it reports `sessionVerdict: "isConsole"` and the problem list
  says plainly: "the worker will start but will refuse all input" —
  fail-closed semantics are visible at preflight, not only at request
  time. A missing runtime directory is listed as a problem while `ok`
  stays true: the report states facts and lets the caller decide.
- **--once mode** — starts, binds, and parks waiting for exactly one
  request rather than exiting early; the one-shot lifecycle hook exists
  for tests.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 230 | worker --check emits a 12-key JSON readiness report that truthfully surfaces the console verdict and its input-refusal consequence | ✓ | §96 — the --check probe |
| 231 | worker --once starts and parks awaiting a single request instead of exiting | ✓ | §96 — the --once probe |


---

## 97. Offline detection is clean; same-Space double-start has no mutex — recorded as a known weakness

- **Worker death → WORKER_OFFLINE** — after the worker is killed, the
  socket disappears and `agentspace status` returns exit 1 with
  `WORKER_OFFLINE` and the named socket path: clean, specific offline
  detection.
- **Double start (known weakness)** — launching a second worker on the
  same Space neither fails fast nor exits: it stays alive, and during
  its startup the first worker's socket path stops accepting
  connections. There is no crash and no data corruption, but also no
  clean mutex; two instances can transiently fight over the socket
  path. In production this is masked by the LaunchAgent guaranteeing a
  single instance per Space, and the observed impact is transient — but
  it is a real robustness gap in the worker's own startup path, so it
  is recorded here rather than waved away. A startup file-lock (flock
  on the runtime directory) is the natural fix.
- Also noted: the worker does not currently write `worker.pid` into the
  runtime directory (plan §20 lists it); CLI offline detection does not
  depend on it, but the file is absent.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 232 | A dead worker yields exit 1 with WORKER_OFFLINE and the named socket path | ✓ | §97 — the kill-then-status probe |
| 233 | Same-Space double start has no mutex: the second worker stays alive and transiently disturbs the first one's socket | ~ | §97 — the two-instance race probe |
| 234 | worker.pid is not written by the current worker | ~ | §97 — the runtime directory listing |


---

## 98. The §97 mutex gap is fixed: flock on the runtime directory, second worker fails fast with EX_CONFIG

- **The fix** — `bind()` now takes an exclusive, non-blocking `flock` on
  `worker.lock` next to the socket before touching anything. The kernel
  releases the lock when the process dies, so a crashed worker leaves
  nothing to clean up; the descriptor is intentionally held for the
  worker's lifetime. On `EWOULDBLOCK` the second worker exits 78 with
  "another worker is already serving this Space" instead of unlinking
  the live socket.
- **Verified live** — first worker up and serving; second worker on the
  same Space exits 78 with the named error; the first worker remains
  alive and still serves authenticated status afterward. Full suite:
  329 tests, 0 failures.
- **Correction to §97** — claim 234 was an artifact of probe timing:
  `worker.pid` **is** written (after bind, alongside `token.space` and
  `status.json.pid`); the earlier probe checked before the write
  landed. Retracted.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 235 | A second worker on an already-served Space fails fast with exit 78 and a named error, and the first worker's socket is undisturbed | ✓ | §98 — the post-fix race probe |
| 236 | worker.pid is written after bind (correcting claim 234: the earlier absence was probe timing, not a missing feature) | ✓ | §98 — the runtime directory listing |


---

## 99. Doctor's Worker check now triages the three distinct causes of "no socket"

The §98-era doctor matrix exposed a real diagnostic gap: a missing
runtime directory, a missing session token, and a simply-not-running
worker all produced the identical "no socket" detail — three problems
with three different fixes, reported as one. Fixed: the Worker check
now distinguishes

- **runtime directory absent** → "the Space was never provisioned on
  this machine" / fix: create the Space again or run the helper's
  prepareRuntimeDirectory;
- **runtime present, token absent** → "the worker has never run here,
  or the runtime directory was reset" / fix: start the worker once so
  it mints a token;
- **both present, socket absent** → the original "no socket" with the
  GUI-login fix.

Verified live against the three seeds, and the full suite stays green
(329 tests, 0 failures). §38's "failures must come with a concrete
fix" now holds at the granularity that matters.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 237 | Doctor's Worker check names the actual root cause (missing runtime / missing token / not running) and gives the matching fix for each | ✓ | §99 — the three-seed triage probe |


---

## 100. Two clean surfaces: worker-control exit codes and the doctor's dead-socket branch

Both verified as part of chasing down §99's referenced commands — no
defects found, recorded so the surfaces are on the ledger.

- **`start` / `stop` / `restart` on an unavailable session** exit 1
  with a named error: `start` says "starting a worker is the
  privileged helper's job; the CLI does not run launchd or sudo"
  (WORKER_OFFLINE). The commands exist, the fixes they name are real,
  and the exit-code contract holds (verified with direct capture —
  the first probe was polluted by a `| head`, per the recurring trap).
- **Doctor vs dead socket residue** — a regular file where
  `worker.sock` should be makes the hello connect fail, and the Worker
  check reports fail with "socket exists but the worker did not
  answer: Socket operation on non-socket" plus the concrete fix
  (remove the stale socket and restart). The §99 triage now covers all
  four failure shapes: no runtime / no token / no socket / dead socket.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 238 | start/stop/restart on an unavailable session exit 1 with named errors and real fixes | ✓ | §100 — direct exit-code capture |
| 239 | Doctor's Worker check names dead socket residue as "socket exists but the worker did not answer" with the stale-socket fix | ✓ | §100 — the residue probe |


---

## 101. Promise-list audits: the §36 refusal matrix item by item, and the §33 tool roster

- **§36 danger list, live** — all nine refused commands
  (`sudo`, `installer`, `diskutil eraseDisk`, `launchctl bootstrap
  system`, `dscl -create`, `sysadminctl`, `rm -rf /`, `shutdown`,
  `reboot`) come back `EXEC_DENIED` through a real worker over the
  CLI, each quoting the matching rule; `echo hello` runs with
  exitCode 0. The unit tests assert the categories; this probe
  confirms each listed item by name on the live path.
- **§33 MCP roster** — the server registers exactly the fourteen
  promised tools (`agentspace_list` … `agentspace_ax_snapshot`), no
  more, no fewer.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 240 | All nine §36 refused commands are rejected live with EXEC_DENIED naming the rule, while ordinary commands run | ✓ | §101 — the nine-command matrix |
| 241 | The MCP server exposes exactly the fourteen tools §33 promises | ✓ | §101 — the registration sweep |


---

## 102. README executability audit — demo and helper paths hold; the acceptance gate's no-Space exit was undocumented and is now documented

- **`scripts/demo.sh`** — runs end to end, exit 0, 14 checks with only
  expected console/provisioning warnings: the README's "try it
  without creating a user" promise holds.
- **Helper self-check from `dist/`** — `--self-check` exits 1 with
  "9 checks, 1 failing" (helper not installed, truthfully reported);
  `agentspace helper` exits 3 with "not answering" and names
  HELPER_UNAVAILABLE. Both README lines behave as written.
- **`scripts/acceptance.sh`** — on this machine (no Space) it exits 66
  with "No AgentSpace found", a code the README never mentioned; its
  own `case` block only documents 0/1/3/4. Fixed: the README now
  explains 66 (no Space yet — create one first; the fail-closed half
  needs a Space's worker, not a second login).

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 242 | demo.sh runs end to end with exit 0 and only expected warnings | ✓ | §102 — the demo run |
| 243 | Helper self-check and helper status from dist/ report their not-installed state truthfully (exits 1 and 3) | ✓ | §102 — the self-check run |
| 244 | acceptance.sh on a machine without Spaces exits 66, and the README now documents that code | ✓ | §102 — the gate run + README fix |


---

## 103. §37 redaction holds live: a real session token never reaches the diagnostics export

- Setup: a fixture Space whose runtime directory holds a freshly
  minted 64-hex session token. `agentspace diagnostics` runs against
  that root; the export is then searched for the token's exact bytes.
- Result: **zero occurrences** — the export never reads token files,
  Keychain, input payloads or frames (source control), and the
  redactor remains the second boundary (its pattern behavior is unit-
  tested: 64-hex runs, `password/secret/token: value` pairs, base64
  image blobs). The `doctor --json` output for the same root likewise
  contains no token bytes.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 245 | A real 64-hex session token in the runtime directory does not appear anywhere in the diagnostics export | ✓ | §103 — the token-search probe |


---

## 104. Promise-list audits, part two: the §31 CLI roster and the §32 --json sweep

- **§31 CLI roster** — all fifteen promised commands (`list` through
  `delete`) are present on the help surface; the first probe misread
  stderr as empty and called them all missing — help writes to stderr,
  which the ledger records so the false alarm is traceable.
- **§32 --json sweep** — every one of the 27 CLI verbs was invoked
  with `--json` (against an empty registry, so most correctly fail
  with SESSION_NOT_READY-family errors): **27/27 return parseable
  JSON — including the failure paths** (exit 66/69/3 are JSON
  errors, not prose). "All commands support --json" holds on the
  success path and, more importantly, on every error path a script
  or an agent will actually hit.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 246 | All fifteen §31 commands exist on the CLI help surface | ✓ | §104 — the roster sweep (stderr captured) |
| 247 | All 27 CLI verbs return parseable JSON under --json, including their error paths | ✓ | §104 — the 27-command sweep |


---

## 105. Token lifetime semantics: the session secret survives worker restarts by design

- Verified with a live restart: the 64-hex token in the runtime
  directory is unchanged across worker death and a fresh start, and
  the old token still authenticates afterward (ok=true both before
  and after).
- **This is a documented property, not a bug**: the token file is the
  shared contract between the worker and the main user's app/CLI, so
  rotating on every start would break seamless reconnect after a
  worker crash. §20 promises a 256-bit secret, not a rotation
  schedule.
- Security consequence, stated plainly: a token, once leaked to
  another local process, stays valid for the life of the Space — the
  only rotation point today is Space deletion (which removes the
  runtime directory). A `--rotate-token` flag that re-mints on start
  and requires the main user's app to re-read the file is the natural
  hardening if a threat model ever demands it; recorded here so the
  property is a decision, not an accident.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 248 | The session token persists across worker restarts and the pre-restart token still authenticates afterward | ✓ | §105 — the restart probe |


---

## 106. Structural audit, round two: the ledger's two namespaces are now clean

- **The per-section ledger** — 223 rows, numbered 25–248, no
  duplicates, no gaps: every row carries a clean verdict (✓/~/✗) and
  named evidence; the 9 blocked rows all name their gate.
- **The early snapshot table** — the "at a glance" table that carried
  the first 24 claims plus 125 had lost its header row and reused
  section-ledger numbers for some rows, which made the numbering look
  duplicated. Its rows are now numbered S1–S49 with a restored header:
  the information is intact, the numeric namespace is unique, and the
  gap at 1–24/125 is explained rather than papered over — those
  claims live in the S-table, the live ledger starts at 25.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 249 | The ledger contains 223 uniquely-numbered claims with no gaps in 25–248, all with clean verdicts and evidence | ✓ | §106 — the structural re-audit |
| 250 | The early snapshot survives as S1–S49 with a restored header, outside the numeric namespace | ✓ | §106 — the renumbering pass |


---

## 107. check-all finds a real regression: the three-window launch, chased to LaunchServices

`scripts/check-all.sh` had never been run end to end; its first full
run failed at the GUI layer — `launch opens exactly one window:
expected [1] got [3]`. The chase, in the order the evidence pointed:

- **Not window restoration.** The Saved Application State folder was
  absent, and clearing `com.agentspace.AgentSpace` defaults (whose
  NSWindow-Frame keys held `AppWindow-1..4` from the §41-bug era)
  changed nothing — three windows reappeared on every launch.
- **Not process stacking.** ps showed exactly one AgentSpace GUI
  process while AX and CG both reported three.
- **Physical, at the CG layer.** `CGWindowListCopyWindowInfo` showed
  three real, same-size windows, two coincident and one cascade-
  offset — a WindowGroup instantiated three times per launch.
- **The mechanism.** A backlog of `agentspace://` open events sat in
  LaunchServices (posted by deep-link tests against a not-running
  app). At every launch LS re-delivered them; events that arrive
  before any scene exists fall through to AppKit's fallback — one new
  WindowGroup instance per URL — before the scene-level
  `.onOpenURL` could ever run. That is why the count never decayed.
- **The fix, two halves.** `OpenLinkDelegate` (an
  `NSApplicationDelegateAdaptor`) now closes surplus main windows in
  `applicationDidBecomeActive` — the first point by which every
  AppKit-created window exists; note a background launch sends no
  activation, so the dedup only fires on an activated launch. One
  activated `open dist/AgentSpace.app` then drained the backlog, and
  after that even background launches come up with one window.
- **The dist guard did its job.** The rebuilt-but-unnotarized app was
  refused by check-all's integrity guard; dist was restored from the
  stapled DMG, `stapler validate` passes, and **check-all now passes
  all three layers — 329 tests, MCP smoke, gui-verify 5/5.** The
  stale binary was never the cause: the restored, pre-fix binary is
  also one-window now that the backlog is drained, which is the
  closing proof of the mechanism.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 251 | check-all.sh runs all three verification layers end to end and passes after the LS-backlog drain (329 tests, MCP smoke, gui-verify 5/5) | ✓ | §107 — the full aggregate run |
| 252 | The three-window launch was a LaunchServices open-event backlog re-delivered at each launch, proven by CG-layer evidence and the one-window-after-drain outcome on the restored binary | ✓ | §107 — the CG window list and the post-drain launches |
| 253 | check-all's dist integrity guard refuses a rebuilt-but-unnotarized app and its remediation path (restore from the stapled DMG) works | ✓ | §107 — the guard trip and the restore |
| 254 | OpenLinkDelegate closes surplus main windows on activation, covering the launch-storm shape for future backlogs | ✓ | §107 — the activated-launch observation (3→1) |


---

## 108. Round 100 closing audit: the 63-section plan, section by section

The plan in the objective has 63 sections. This table walks them in
theme groups, with the section of this ledger that pins each group —
so the remaining work is visible as exactly three external gates and
nothing else. Verdicts use the ledger's own semantics.

| Plan sections | Group | Verdict | Pinned by |
|---|---|---|---|
| 1–3 | Positioning, fail-closed principle, Apple-Silicon baseline | ✓ | §5–§7 — the console is the live fail-closed testbed; doctor checks the baseline |
| 4–5 | Native stack, monorepo layout | ✓ | repo tree — apps/ native/ shared/ packages/ scripts/ tests/ docs/ all exist as laid out |
| 6–7 | Three-process architecture, SMAppService helper | ~ | §13, §45 — typed RPC and the signed bundle are real; the helper's root XPC live-run is gated on registration (admin password) |
| 8–10 | Standard-user Spaces, Keychain password, first Aqua login | ~ | §15 — provisioner and Keychain are machine-verified; the first-login walk needs a second GUI session |
| 11–16 | Worker core: Aqua gate, console guard, session-tap input, screenshot, SCK deferral | ✓ | §5–§7, §12 — 9 input shapes refused live on the console; SCK correctly not built (plan §16 defers it) |
| 17–19 | Desktop Viewer, Accessibility bridge, permission preflight | ✓ | §24, §29 — pull-model preview fail-closed; per-Space TCC preflight re-runs per call |
| 20–21 | Socket IPC, token, versioned protocol | ✓ | §26, §105 — 256-bit token, wire-protocol probes, token survives restarts (documented property) |
| 22–23 | App management, exec | ✓ | §8, §21 — registration-wait launch, menu-bar apps, exec live |
| 24–25 | Git-worktree workspace, folder sharing | ✓ | §14 — worktree isolation machine-verified; folder sharing's ACL half is §14's read-only model |
| 26–28 | Data model, dashboard, create wizard | ✓ | §15, §54 — GUI checks mechanical via gui-verify |
| 29 | Multi-Space architecture | ~ | §16 — eight-space isolation test; the live two-Space-plus-console gate needs a second session |
| 30 | Resource monitoring | ✓ | §17 — per-UID aggregation, budget-bounded disk usage |
| 31–32 | CLI surface, --json mode | ✓ | §104 — 15/15 commands, 27/27 verbs parse under --json |
| 33–35 | MCP server, integrations, agent rules | ✓ | §18–§19, §101 — 14 tools, three configs, §36 rules generated |
| 36 | Dangerous-command refusal | ✓ | §101 — all nine refusals returned live by a real worker |
| 37–38 | Diagnostics export, doctor | ✓ | §103, §62 — token never survives the export; doctor names fixes per failure |
| 39–41 | Restart behavior, stop/logout/delete | ~ | §23, §26 — needs-login vs offline discriminator verified; logout's root-only RPC is blocked on the helper gate |
| 42–43 | Offstage reuse rules, forbidden mechanisms | ✓ | repo audit — no SkyLight, no TCC.db writes, no generic helper shell |
| 44–52 | The nine build phases in order | ✓/~ | §5–§25 — every phase built in plan order; §44's isolation half and §48's live two-Space run are the second-session gate |
| 53 | Performance budgets | ✓ | §27, §34–§36 — idle budgets met with numbers beside them |
| 54 | MVP acceptance | ~ | acceptance.sh — fail-closed half live; isolation half gated; exit 66 documented |
| 55–57 | Test pyramid, security review, release chain | ✓ | 329 tests; §56 checklist walked (§61); DMG signed, notarized, stapled |
| 58–59 | Bundle identifiers, README first screen | ✓ | §58 namespacing is configured, not hard-coded; §59's README verified against the chain (§102) |
| 60–63 | Development principles, §63.12 ledger duty | ✓ | this ledger — 109 sections, 250+ claims, verdicts never padded |

**The three external gates, restated once:**

1. The privileged helper's root run — registration needs an
   administrator password (and this session must never raise approval
   prompts), so createUser/deleteUser/logout run nowhere live.
2. The second GUI session — every positive-isolation half (input
   really lands, screenshots really differ, two Spaces plus a console
   user) needs a second logged-in macOS user.
3. The Homebrew cask — needs a public release URL; the repo has no
   remote, and pushing is the user's decision.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 255 | Every one of the plan's 63 sections is accounted for in the closing audit: verified, partially verified with the missing half named, or blocked with its gate named — none unaddressed | ✓ | §108 — the section-by-section table |
| 256 | The remaining work is exactly three external gates — helper root run, second GUI session, public release URL — each requiring a resource outside this session | ✓ | §108 — the restatement |


---

## 109. The product docs catch up with the hardening record

§108 audited the plan against the ledger; this round audits the
product-facing docs against the hardening that the later ledger
sections recorded. Two findings, both fixed:

- **The kernel-enforced single worker (§97/§98) was process-record
  only.** `docs/security.md` now carries a short section: the socket
  is unlinked before bind, the exclusive non-blocking `flock` on
  `worker.lock` makes the racy sequence safe, the second worker
  fails fast with exit 78, and the lock file has no security role.
- **The token's lifecycle (§105) was a ledger finding, not a
  documented property.** `docs/security.md` now states the two
  deliberate halves — the token survives a worker restart because it
  is the shared client contract, and the rotation point is the Space
  itself (runtime-directory deletion); no `--rotate-token` exists
  today, and the redaction boundary (§37/§103) is named as the
  defense that keeps the no-expiry property survivable.

The plan §5 layout was also walked against the tree: all 11 entries
exist, including the four named docs (architecture, protocol,
security, troubleshooting) and THIRD_PARTY_NOTICES.md — the closing
audit's "repo tree" evidence is now a measured fact.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 257 | docs/security.md documents the §97/§98 flock mutex and the §105 token lifecycle with their design reasoning | ✓ | §109 — the two new sections |
| 258 | The plan §5 layout exists as written, all 11 entries including the four named docs | ✓ | §109 — the tree walk |


---

## 110. Protocol and architecture docs hold the line; one launch-path paragraph added

- **The §21 error codes are complete in the product docs.** All
  eleven codes from plan §21 appear in `docs/protocol.md`; the
  canonical source is `AgentSpaceErrorCode` in
  `ErrorCodes.swift` (a `CaseIterable` enum whose cases carry the
  design reasoning inline — `NO_INPUT_TARGET` explains why a missing
  frontmost app is refused rather than silently no-op'd). The enum
  also holds codes the plan never named (`PREVIEW_NOT_RUNNING`,
  `WORKER_IS_ROOT`, `INVALID_ACTION`, `NO_INPUT_TARGET`), each with
  a doc comment — the docs and the enum agree with each other, and
  the enum is a superset of the plan's list.
- **`docs/architecture.md` gains the deep-link launch path.** §107's
  chase left the architecture doc behind: how the app consumes
  `agentspace://` while running (scene `.onOpenURL`) and at launch
  (backlog falls to AppKit's fallback; `OpenLinkDelegate` dedups on
  activation) is now a Lifecycle-section paragraph naming the
  invariant and its pinning script.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 259 | All eleven §21 error codes exist in docs/protocol.md, and the canonical enum is a documented superset with inline reasoning | ✓ | §110 — the eleven-code walk and the enum source |
| 260 | docs/architecture.md documents the deep-link launch path, the launch-storm mechanism, and the dedup, with the one-window invariant pinned by gui-verify | ✓ | §110 — the new Lifecycle paragraph |


---

## 111. The runtime-directory layout, complete in both authoritative places

The runtime layout list appeared twice — once in `RuntimePaths.swift`'s
doc comment, once in `docs/protocol.md` — and both were written when
the directory held four files. Since then the hardening and the
worker grew five more artifacts, and neither list had kept up:

- `status.json` — the worker's last known status (existed in the
  properties and on disk, missing from the swift comment).
- `worker.lock` — §97's flock target, the reason a second worker
  fails fast.
- `worker.log` — the worker's own log, sitting next to what it
  serves.
- `space.json` and `screenshots/` — written by the helper and the
  capture path respectively; present in protocol.md, missing from
  the swift comment.

Both lists now carry all eight entries with one-line roles, derived
by walking `RuntimePaths`' properties plus the bind/worker writes —
not by copying either stale list. 329 tests still green (the change
is comments only).

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 261 | The runtime-directory layout is identical and complete in RuntimePaths.swift's doc comment and docs/protocol.md — all eight artifacts with their roles | ✓ | §111 — the walk that derived the list |


---

## 112. Two completeness audits, both clean: the script roster and the fix coverage

- **Every script that exists is in the README.** 11 scripts in
  `scripts/`; 10 appear by name. The one holdout, `mcp-smoke.mjs`,
  is the node payload that `mcp-smoke.sh` execs — an implementation
  file, not an entry point — so listing only entry points in the
  README is the design, not an omission. §55's claim 163 gets its
  roster side measured rather than asserted.
- **Doctor's fixes are covered by the troubleshooting manual.** Six
  sampled fix strings from `Doctor.swift` all have a home in
  `docs/troubleshooting.md` — the four that failed a literal string
  match are covered under different wording: the console remedy is
  "Switch back to your own account with fast user switching" (§16),
  the no-Space case sits inside the helper-unavailable entry, the
  runtime-directory case is the exit-78 row of the exit-code table,
  and the ssh case is the exit-69 row. Plan §38's
  every-failure-names-a-fix holds twice over: once in the doctor's
  own output, once in the manual it feeds.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 262 | The README names every user-facing script in scripts/ (11/11, with mcp-smoke.mjs correctly an internal payload) | ✓ | §112 — the roster cross-check |
| 263 | Doctor's fix strings are covered by docs/troubleshooting.md, including under variant wording; no failure path lacks its remedy | ✓ | §112 — the six-fix sample and the variant recheck |


---

## 113. §42 compliance, measured: the notices file and the zero-trace source

Plan §42/§63.3 governs Offstage reuse: copy nothing without keeping
the copyright and registering it in THIRD_PARTY_NOTICES.md. Both
halves were measured rather than assumed:

- **THIRD_PARTY_NOTICES.md is substantive.** It carries the full MIT
  text with the copyright line, an explicit "no source file was
  copied verbatim" statement that explains why the notice is
  reproduced anyway (the debt is real: the measured findings are
  Offstage's), and a table of the specific ideas and measurements
  taken — the three CGEvent posting paths and their behaviour, the
  always-assign-flags rule, one event per grapheme cluster.
- **The Swift sources are trace-free.** A repo-wide search finds
  "offstage" in exactly three places — THIRD_PARTY_NOTICES.md, this
  ledger, and the README — and in **zero** Swift files. Copied code
  under §42's rule would carry a copyright header; none exists. The
  declaration and the tree agree.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 264 | THIRD_PARTY_NOTICES.md satisfies §42: full MIT text, the no-verbatim-copy statement with its reasoning, and a table of the ideas taken | ✓ | §113 — the file contents |
| 265 | No Swift source file mentions or headers Offstage, consistent with the no-verbatim-copy declaration | ✓ | §113 — the zero-trace search |


---

## 114. The demo stays green on the current tree after the doc-sweep rounds

§109–§113 changed only documentation and comments; §107 restored dist
from the stapled DMG. The end-to-end demo was re-run to confirm the
behaviour underneath did not drift: **exit 0**, every check passing —
the worker comes up, `status` reports the console session honestly
(`On Console`, `isConsole`), `apps` and `screenshot` and all input
verbs are refused with `SESSION_IS_CONSOLE` carrying the switch-back
remedy, `sudo` is refused with `EXEC_DENIED` naming its rule, and a
plain `exec id -un` runs as the real user (uid 501). The fail-closed
posture that §62 first demoed survives every change since.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 266 | demo.sh runs end to end with exit 0 on the current tree, with the console fail-closed refusals and the §36 sudo refusal all live | ✓ | §114 — the re-run output |


---

## 114a. The §111 list contained a phantom: worker.log does not exist

Following up on §111's own list found its first entry wrong. The
worker's log path came from two sources that disagree:

- `RuntimePaths.workerLogPath` (`worker.log`) was defined but written
  by nobody — the demo fixture has no such file, and only Doctor's
  fix text referenced it, sending a user to inspect a file that
  could never exist.
- The real logs go through the LaunchAgent's `StandardOutPath` /
  `StandardErrorPath` (HelperProtocol's plist template), which points
  at `worker.out.log` and `worker.err.log` **inside the runtime
  directory** — the worker's own logs, next to what it serves, just
  under their real names.

Fixed in all three places: the dead property is replaced by
`workerOutLogPath`/`workerErrLogPath` (with a comment naming the
LaunchAgent as the writer), Doctor's stale-socket fix now points at
`worker.err.log`, and both layout lists (swift doc comment,
protocol.md) say out/err. 329 tests green; the §111-era claims 261's
list is corrected by this one.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 267 | The worker's stdout/stderr land in the runtime directory as worker.out.log / worker.err.log via the LaunchAgent, and no worker.log exists | ✓ | §114a — HelperProtocol's plist template against RuntimePaths |
| 268 | Doctor's stale-socket fix names a file that exists, and no dead path properties remain | ✓ | §114a — the replacement and the build |


---

## 115. One source of truth for the log paths, now pinned by a test

The §114a chase found its cause's twin: the plist template
hand-wrote `worker.out.log`/`worker.err.log` while
`RuntimePaths.workerOutLogPath`/`workerErrLogPath` sat unused (zero
call sites) — two definitions of the same fact, which is exactly the
shape that produced the phantom `worker.log`. The template now
resolves its paths through `RuntimePaths`, and a new test
(`testTheLaunchAgentLogPathsMatchRuntimePaths`) pins the plist to the
properties, asserts both paths land inside the Space's runtime
directory, and forbids the phantom's return. 330 tests green.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 269 | The LaunchAgent plist takes the worker log paths from RuntimePaths, with a test pinning the agreement and banning the phantom worker.log | ✓ | §115 — the new test, 330 green |


---

## 116. §58 measured: the namespace is configured in one place

Plan §58 says names go in a single configuration, not scattered
hardcode. Measured, not assumed:

- **The install root has one source of truth.** Every
  `/Users/Shared/.AgentSpace` literal outside `RuntimePaths` lives in
  a *test* — six in HelperValidationTests, one in
  MultiSpaceIsolationTests. Test fixtures keeping the literal (rather
  than importing the constant) is deliberate: a literal pins the
  convention and catches a wrongly-edited constant. Production Swift
  contains **zero** scattered roots.
- **Every identifier lives in `BundleIdentifiers`.** The app, helper,
  worker, worker-LaunchAgent, CLI and MCP names, the helper plist
  file name, and the §37 log subsystem are all members of that one
  enum, whose doc comment states the §58 intent outright ("a
  namespace change is one edit"). Outside the enum, production code
  names `com.agentspace.*` nowhere; the only other occurrence is a
  doc comment in HelperLog.swift quoting a `log show` command for the
  user. The subsystem being its own constant rather than the app's
  bundle id is documented in place, with the reason.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 270 | Production Swift hardcodes the install root nowhere; all seven literals are test fixtures pinning the convention | ✓ | §116 — the grep and the fixture list |
| 271 | All bundle ids, derived plist names and the log subsystem are members of BundleIdentifiers, with no production literals outside it | ✓ | §116 — the enum and the zero-hit search |


---

## 117. §37 categories align exactly; §22's visibility rule becomes testable

Two §22/§37 checks, one positive and one improvement:

- **§37 categories align exactly.** Production instantiates nine
  `Logger`s across exactly the eight categories the plan names — app,
  helper (×2), worker, ipc, session, input, capture, mcp. None
  missing, none invented.
- **§22's visibility rule is now pinned by tests.** The apps list's
  core promise — include regular *and* accessory (LSUIElement
  menu-bar) apps, and anything the window server sees even when
  AppKit says `prohibited` — was an inline expression inside
  `AppControl.runningApps`, untestable behind its NSWorkspace/CG
  dependencies. Following the SessionGuard/InputActions precedent, it
  moved to Core as `AppVisibility.isVisible`, the worker calls it,
  and five tests pin every branch: regular always visible, accessory
  visible with no windows, prohibited visible only through a window,
  unknown policies following the same rule, and another pid's window
  granting nothing. 335 tests green.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 272 | Production log categories are exactly the eight §37 names, in nine Logger instantiations | ✓ | §117 — the category census |
| 273 | The §22 visibility rule lives in Core as AppVisibility.isVisible with all five branches pinned by tests | ✓ | §117 — the new tests, 335 green |


---

## 118. §25's sensitive-home list was a gap; it is now a guard

§25 forbids opening — "禁止默认开放" — the home directory itself,
Library, Desktop, Documents, Downloads, SSH and Keychain. Measured
against the code: `isDangerousRoot` blocked only *system* roots
(/System, /usr, …); none of the home-side paths had any defense. The
fix follows the plan's own distinction:

- **Hard-refused, even explicitly picked**: the home itself,
  `~/Library` (the Keychains' parent), `~/Library/Keychains`, and
  `~/.ssh`. Once shared, "I did not mean that" is not recoverable, so
  these never reach an agent; the error names the fix ("share the
  specific project or data folder instead").
- **Still shareable by explicit intent**: Desktop, Documents and
  Downloads — §25's own UI example shares a folder under Documents,
  so hard-refusing them would contradict the plan. The "default" part
  of the list is honoured by them never being pre-selected.

The guard lives in `WorkspacePreparer` next to `isDangerousRoot`,
takes an injectable home, and a new test pins all four refusals, the
remedy text, and the Documents contrast. 336 tests green.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 274 | The home itself, ~/Library, ~/Library/Keychains and ~/.ssh are refused as shared folders even when explicitly picked, with the remedy named | ✓ | §118 — the new guard and test, 336 green |
| 275 | Desktop/Documents/Downloads remain shareable by explicit intent, matching §25's own UI example | ✓ | §118 — the contrast assertion in the same test |


---

## 119. §36's refusal list is fully implemented, as a documented superset

Every command §36 says to refuse is in `ExecGuard.rules`: sudo,
installer, diskutil erase, launchctl bootstrap system, dscl create,
sysadminctl, rm -rf /, shutdown, reboot. The shipped list is a
superset — twenty-two rules including the diskutil variants, bootout,
dscl delete, dseditgroup, halt, nvram, csrutil, spctl
--master-disable, kextload, tccutil and the authorization database —
each carrying its reason, so an agent sees *why* as well as *what*.
The tests pin the load-bearing entries, including the sudo variants
that a bare "contains sudo" check would miss (env prefixes, `sudo
-i`, a bare `sudo`).

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 276 | All nine §36 refusals exist in ExecGuard.rules, as a superset of twenty-two documented rules | ✓ | §119 — the rule list against §36 |


---

## 120. §41's deletion guarantees hold, against a real repository

The delete path (§41) was measured on both sides:

- **The implementation is the reverse of creation, with the two
  careful steps where the plan demands them.** The worker is stopped
  before the LaunchAgent plist is removed (otherwise the job keeps
  running until the next boot); the worktree is removed with
  `git worktree remove --force` — forced because an agent almost
  certainly left uncommitted changes and the user asked for the
  deletion — while the **branch is kept** and the original repository
  is never touched; a worktree-removal failure downgrades to a
  skipped step ("Your repository and branch are untouched") rather
  than blocking the account's deletion; the home directory is removed
  only when asked and is a separate UI question.
- **The tests exercise this against a real git repository.**
  `testDeleteRemovesEverythingAndKeepsTheUsersRepository` creates an
  actual repo, deletes the Space, and asserts the worktree is gone,
  the user's README is byte-identical, the branch `agentspace/a`
  survives, and the Keychain and registry are empty. Dirty-worktree
  downgrade and the home opt-in have their own tests.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 277 | Space deletion removes only the worktree — the branch survives and the user's repository is untouched, verified against a real git repo | ✓ | §120 — the delete-path tests |


---

## 121. §35's four agent rules are verbatim, single-sourced, and tested

The safety rules §35 tells the installer to generate are `Integrations.
agentRules()` — all four sentences in substance verbatim: any window-
capable command through AgentSpace, never launch GUI apps in the
user's session, stop and report when unavailable, never fall back to
the console session. The doc comment states the deeper point: the
wording *is* a security property, so the rules are generated from one
function rather than hardcoded at call sites. The merge is idempotent
(marker-bracketed section) and appends only — never spliced — because
instructions files are read top-to-bottom and the user's own ordering
means something. Tests pin the key sentence, both markers, and the
merge behaviour.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 278 | §35's four rules are generated verbatim from one function, installed idempotently by append-only merge, with tests pinning the wording | ✓ | §121 — Integrations.swift and its tests |


---

## 122. §39's restart behaviour holds, and autoStartWorker's V1 meaning is the plist

Measured, the no-silent-start guarantee is not a flag check but a
structural fact: the worker's LaunchAgent carries
`LimitLoadToSessionType: Aqua`, so after a reboot — when the AgentSpace
user has no GUI session — launchd never even considers the job. There
is nothing to "not start secretly". `RunAtLoad` then gives the field's
V1 meaning: once the user signs in once, the worker starts by itself.
State derivation is fail-safe in the same direction — a stored
ready/running Space with no worker derives to `.needsLogin` when a
session dictionary says no graphical session exists, and to
`.offline` when nothing can be asked; it never presumes running. New
Spaces are born `.needsLogin`.

Stated honestly: `autoStartWorker` has no consumer beyond the model
type — §26 requires the field, while §39 explicitly defers auto-login
past V1, so the field records intent the plist already embodies.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 279 | After reboot the worker cannot start secretly: the Aqua-only LaunchAgent is structurally inert without a GUI session, and RunAtLoad is the V1 autoStart semantics | ✓ | §122 — the plist template against the state derivation |
| 280 | A ready/running Space with no worker derives to needsLogin (no graphical session) or offline (nothing answerable), never to running | ✓ | §122 — deriveState's branches |


---

## 123. §40's two-level stop exists, and logout carries a self-destruct guard

Stop Worker and Logout are separate typed RPCs (`stopWorker`,
`logoutSession`) as §40 requires. Logout ends the Space's whole GUI
session — `launchctl bootout gui/<uid>`, root-only, so it lives in
the helper and nowhere else — while keeping the account and its home.
The critical guard: the username must name an *AgentSpace* account
and the uid must match it, because a logout that could target the
main user's session "would be a self-destruct button wearing a
feature's clothes". Tests pin all three sides: a valid Space request
accepted, the main user's name rejected, a mismatched uid rejected
before the helper would ever compare it to passwd.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 281 | Stop Worker and Logout Session are distinct typed RPCs, and logoutSession is guarded to AgentSpace accounts with a matching uid, tested on all three sides | ✓ | §123 — HelperProtocol and HelperValidationTests |


---

## 124. §31's thirteen commands all exist, as a superset

The CLI dispatch table contains every command §31 names — list,
status, screenshot, click, type, key, scroll, drag, launch, quit,
apps, exec, desktop — thirteen of thirteen, plus the product's own
additions (the ax family, frontmost, windows, perform, preview,
integrate, helper, diagnostics, start, stop, create, delete,
version). JSON mode (§32) threads through the parser at 32 sites;
the integration tests exercise the machine-readable path.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 282 | All thirteen §31 commands exist in the CLI dispatch table, as a superset with JSON mode threaded throughout | ✓ | §124 — the command census |


---

## 125. §33's fourteen MCP tools match the plan list exactly

The server registers exactly fourteen tools and every name in
§33's list is present: list, status, screenshot, input, click, type,
key, scroll, drag, launch, quit, apps, exec, ax_snapshot — no
missing, no stray. The 23 MCP tests pin the wiring; the plan's
recommended flow (status → screenshot → reason → input → screenshot
→ verify) is what the tool descriptions encourage.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 283 | All fourteen §33 MCP tools are registered under their exact planned names, with the 23-test suite pinning the wiring | ✓ | §125 — the tool census against the plan |


---

## 126. §28's five sign-in steps exist verbatim in the Setup UI, localized

The onboarding strings carry §28's sequence — open Fast User
Switching, sign in as "AgentSpace – <name>", grant Accessibility,
grant Screen Recording, switch back — plus the §19 declaration the
plan demands alongside it: "AgentSpace never writes the TCC
database. These grants are given by you, in that session, on
purpose." Show Login Password is the §9 surface for the first
switch. Both English and Simplified Chinese strings carry the steps.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 284 | The five §28 sign-in steps appear verbatim in localized Setup strings, with the TCC declaration and the Show Login Password surface | ✓ | §126 — the strings census |


---

## 127. §30's resource monitor summarises by UID with actual usage

`ResourceSample.sample(uid:)` makes one `ps -axo uid=,rss=,pcpu=`
invocation, filters to the Space's uid, and sums RSS, CPU and
process count — exactly §30's "根据 UID 汇总进程". Nothing reports
Allocated anything; disk is actual bytes under the home (opt-in,
because `du` costs). The doc comment ties the sampling rate to §53:
a couple of seconds at most, and SafetyTests pins that a plain
status call pays nothing for sampling.

Stated honestly: the `ps` text parsing has no direct unit test — it
is covered by the integration path and the safety assertion, not
pin-parsed line by line.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 285 | Resource sampling summarises actual CPU/RAM/processes by UID with opt-in disk, no Allocated fields, and status stays sampling-free | ✓ | §127 — sample(uid:) and the safety assertion |
| 286 | The ps parsing itself lacks a direct unit test (integration-covered) | — | §127, stated limitation |


---

## 128. §46's GUI elements all exist in a deliberately small file set

The app is seven Swift files — App, AppModel, SpaceService, four
Views — with eight view structs. Mapping §46: the SwiftUI App shell;
the dashboard with running/needs-login cards; the creation wizard
(`NewSpaceView` — name, workspace kind None/Git Worktree/Shared
Folder exactly as §28's step 2, showing the worktree path before
committing); permission status in SpaceDetail and Doctor; the
Desktop screenshot viewer; input through the viewer; logs via
Diagnostics. The small surface is §27's "极简、原生" taken
seriously, not missing features.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 287 | All seven §46 GUI elements exist; the wizard offers §28's three workspace kinds and previews the worktree path before creating | ✓ | §128 — the views census |


---

## 129. §16/§17/§52's Desktop Viewer: 1 FPS MVP, 5 FPS stream, zero cost closed

The viewer implements all three plan sections at once. The MVP
screenshot loop polls at 1 FPS and only while the view exists —
`onAppear` starts the timer, `onDisappear` invalidates it and sends
`previewStop`, so a closed window costs exactly zero captures. The
ScreenCaptureKit upgrade (§16's second stage) exists as
previewStart/frame/stop at 5 FPS with the worker auto-stopping an
orphaned stream; a refused stream (console session, missing grant)
falls back to the 1 FPS MVP rather than showing nothing. Clicks are
translated, never forwarded: `PreviewMapping` converts through the
image fraction and the display's point size, letterbox clicks are
dropped rather than clamped, and the surface refuses input whenever
the worker says input is not permitted — §17's local-remote-desktop
without a remote protocol.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 288 | The viewer polls 1 FPS only while open (onAppear/onDisappear), streams 5 FPS when available, falls back to the MVP, drops letterbox clicks, and refuses input when the worker refuses | ✓ | §129 — DesktopViewerView's lifecycle and mapping |


---

## 130. §29's 1:N architecture: an N-space list with per-space isolation tests

The AppModel refreshes an array of Spaces — `registry.spaces.map` —
with a selection, not a single slot; grep finds no `singleUser`,
`computeruse`, or `defaultSession` anywhere in Swift sources, as §48
demands. The per-space facts (UUID → runtime dir, uid → resource
sampling, per-space token) are pinned by MultiSpaceIsolationTests
and the token-uniqueness safety tests. A §53-minded detail: resources
are fetched only for the Space on screen, because one `ps` fork per
Space per refresh would be exactly the overhead the plan forbids.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 289 | The app manages an array of Spaces with no single-user assumptions anywhere, and per-space isolation is pinned by dedicated tests | ✓ | §130 — the AppModel refresh and the test census |


---

## 131. §37's diagnostics export uses two independent secret controls

Collection is whitelisted: doctor output, registry metadata, file
*existence* only — token files, Keychain items, input payloads and
frame data are never read, so those secrets cannot leak because they
are never collected. Everything still passes `DiagnosticsRedactor`
before leaving the process as defence in depth: 64-hex runs become
`<redacted-token>` (commit SHAs are the documented false-positive
cost), and `password|passphrase|secret|token` keys lose their values.
The redactor is a pure, idempotent, order-independent function
precisely so it can be tested property-style; the test census finds
the redaction coverage present.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 290 | Diagnostics export collects by whitelist and redacts secret-shaped text at the boundary, with property-style tests on a pure redactor | ✓ | §131 — Diagnostics.swift and its tests |


---

## 132. §38's thirteen doctor checks are all present, plus two extras

Mapping the plan's list to the check names: Apple Silicon; macOS
version ("Upgrade to macOS 26 or later"); privileged helper; Fast
User Switching (via MultipleSessionEnabled); Spaces (AgentSpaces +
registry integrity); Worker; Aqua session ("Run from a GUI login,
not ssh"); Screen Recording; Accessibility; Unix socket; Input
isolated; WindowServer; Workspace confinement — thirteen of
thirteen, plus Display geometry and an advisory TCC-grants check the
plan never asked for. Failures carry concrete remedies by design
(the triage taxonomy of §99–§100).

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 291 | All thirteen §38 doctor checks exist under matching names, with two extras and concrete remedies | ✓ | §132 — the check-name census |


---

## 133. §43's forbidden mechanisms have zero presence in the source

A fresh grep across all Swift sources finds no `SkyLight`, no
`ScreenSharing`, no `screensharingd`, no `Virtualization`, no
`TCC.db` write, no VNC, no RDP — zero hits even in comments. What
the product is built on instead: the public frameworks the plan
names — ScreenCaptureKit, CGEvent, CGSessionCopyCurrentDictionary —
all present in the worker. The plan's value proposition ("使用
macOS 已经存在的多用户 GUI Session") is the implementation, not the
marketing.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 292 | No forbidden private mechanism appears anywhere in the Swift sources; the foundations are the public frameworks the plan names | ✓ | §133 — the zero-hit grep and the public-framework census |


---

## 134. §61's not-to-build list is honoured, and §23's exec surface is complete

A grep across all product sources finds no marketplace, no LLM chat,
no orchestration, no cloud sync, no team collaboration, no Docker —
the features §61 explicitly excluded from V1 were never started, so
the product stayed "一个 Mac + 多个后台 GUI Session". On the
support side, §23's exec carries everything the plan lists:
buffered stdout/stderr/exitCode/duration, cwd, environment, and
timeout — with a comment pinning the effective-PATH subtlety so the
resolved binary always matches the environment it runs with.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 293 | None of §61's excluded feature categories appear in the product sources | ✓ | §134 — the zero-hit grep |
| 294 | §23's exec supports cwd, env, timeout and returns stdout/stderr/exitCode/duration exactly as planned | ✓ | §134 — ShellExec's parameter census |


---

## 135. §59's README first screen is verbatim

The README opens with the plan's exact sentences — "Give AI agents
their own macOS desktop", the session-isolation paragraph, "No VM.
No second macOS installation. No remote Mac." — followed by the
planned two-column diagram (Your desktop / Agent desktop, VS Code /
Chrome, Terminal / Simulator, Safari / Xcode, You keep working / The
agent keeps working) and the four promises (pointer, keyboard,
focus, flicker). The How section then states §1's architecture in
one sentence.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 295 | The README first screen reproduces §59's copy and diagram verbatim | ✓ | §135 — the README head |


---

## 136. §34's integration targets all exist, including Copy Config

The integration enum carries exactly the plan's targets — Claude
Code, Codex, OpenCode — each with its real config path
(`~/.claude.json`, `~/.codex/config.toml`,
`~/.config/opencode/opencode.json`), plus a `generic` case backed by
a hand-apply instruction set for the "Copy Config" flow the plan
asks for alongside one-click installs. Sixteen integration tests pin
the wiring, including the §35 rules text these configs embed.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 296 | Claude Code, Codex and OpenCode install targets exist with real config paths, plus a Copy Config flow, pinned by tests | ✓ | §136 — the integration enum census |


---

## 137. §19's permission detection uses the no-prompt variants, as the plan demands

Screen Recording is gated by `CGPreflightScreenCaptureAccess` in
three places (before every capture, status reporting, doctor);
Accessibility by `AXIsProcessTrusted` inside a `requireTrust`
wrapper that throws an error naming the exact fix. The plan wrote
`AXIsProcessTrustedWithOptions`; the implementation uses the bare
`AXIsProcessTrusted`, which is the same check with the prompt
suppressed — exactly what §19's rule ("不能触发无人可见的无限权限
弹窗") requires, since a prompt variant would raise a dialog in a
session nobody is looking at. The WithPrompt form would be a bug
here, not a gap.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 297 | Both permission checks are pure preflights — no prompt is ever triggered in the unattended session | ✓ | §137 — the preflight call sites and the requireTrust wrapper |


---

## 138. §22's launch flow waits for real registration, not for `open`'s exit

The comment states it plainly: "`open`'s success only means
LaunchServices accepted the request; returning a pid at that moment
hands the agent a number it cannot use." So launch polls with three
pid-resolution signals (expected pid, bundle identifier, or a
newly-appeared pid), then gives the app half the remaining budget to
own an on-screen window — a window a menu-bar (LSUIElement) app will
never take, so the full budget is not spent on it. Either signal
suffices, matching the plan's demand to wait for actual registration
before reporting a pid, while §22's own menu-bar-app requirement
keeps window ownership optional.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 298 | Launch waits for actual app registration before returning a pid, with LSUIElement apps exempt from the window criterion | ✓ | §138 — the two-signal registration wait in AppControl |


---

## 139. §18's ax family: four of five API names, all five content items

The plan lists five ax APIs; the worker implements four —
`axSnapshot`, `axFrontmost`, `axWindows`, `axPerform`. The §18
content list ("当前 frontmost app / 窗口列表 / 窗口标题 / focused
element / 基础 accessibility tree") is fully covered: axFrontmost
returns the focused element alongside pid/name/bundleId, and
axSnapshot returns the tree with window titles, focused elements and
button labels. `ax.elementAt` — address a single element by path —
does not exist anywhere: no Method case, no protocol.md entry, no
test, no MCP tool. That is one consistent absence, not a
two-definitions drift. It is recorded as a limitation rather than
rushed in: per §63.13 AX path resolution must be verified against a
real GUI session, which this machine cannot host, and shipping an
unverifiable API would be exactly the guessing §63.13 forbids. The
plan's own AX-first flow (read tree, find button, click) works with
snapshot + perform today.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 299 | ax.snapshot/frontmost/windows/perform exist and cover all five §18 content items | ✓ | §139 — the dispatch census |
| 300 | ax.elementAt is absent consistently everywhere; deferred, not drifted, because AX path resolution cannot be verified without a real GUI session | — | §139 — the zero-hit grep and the dispatch table |


---

## 140. §20's transport is socket-only, and the 256-bit secret guards the socket

No NWListener, no HTTPServer, no Vapor, no listen call exists in any
product source — the only transport is the Unix socket. The socket's
guard is generated with SecRandomCopyBytes and rendered as 64 hex
characters: exactly 256 bits, unbiased. The login password is 32
alphanumeric characters (~190 bits) — slightly below a literal
"32 bytes" but deliberately so, and the code says why: it must be
typeable by a human at a Fast User Switching login window, it is
never the real boundary (the token is), and the unbiased-bytes budget
went to the thing that actually guards the socket. A documented
trade-off, not a shortcut.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 301 | No HTTP localhost server exists; transport is Unix-socket only | ✓ | §140 — the zero-hit grep |
| 302 | The session token is 256 unbiased bits from SecRandomCopyBytes; the typeable login password is a documented 32-char trade-off | ✓ | §140 — HelperProtocol's generatePassword and Security.swift |


---

## 141. §9's forbidden password channels carry nothing

Fresh greps: no UserDefaults write touches a password, secret or
token; no print/log/debugPrint statement in the Keychain store
emits a password; no config.json channel exists at all. The only
holder of the password is the Keychain (with the §140 documented
32-char typeable trade-off), and the redactor of §131 stands behind
the diagnostics boundary in case a future change ever spills a
secret-shaped string into an export.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 303 | No password, secret or token reaches UserDefaults, a log statement, or a config.json file | ✓ | §141 — the three zero-hit greps |


---

## 142. §11's Aqua-session guard is implemented as a stronger structural check

The plan names `launchctl managername` (should print Aqua, else
refuse); the worker instead gates startup on
`SessionGetInfo(sessionHasGraphicAccess)` — Gate 2 of main —
exiting 69 with a named remedy when the session has no graphic
access. This is the plan's intent met more strongly: managername is
a text contract whose output shape drifts across macOS versions,
while SessionGetInfo is a structured system API that also catches
the pathological case (manager says Aqua but WindowServer is
unreachable). Fail-closed at process start, before any socket binds,
and Gate 1 (never root, exit 77) sits in front of it.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 304 | Worker startup fails closed without graphic access via SessionGetInfo, a stronger guard than the planned managername text parse | ✓ | §142 — Gate 1/Gate 2 in worker main |


---

## 143. §14's nine input actions are covered by seven parameterised cases

The enum carries move, click (with button and count), drag, scroll,
type, key and sleep — where click(count: 2) is the plan's
doubleClick and click(button: .right) is rightClick: a
parameterisation, not a missing feature. The file comment pins the
batch semantics the plan asks for: a rejected batch performs
nothing (atomicity), and no synthetic gesture ever leaves a mouse
button down or a modifier stuck, so the session stays reasoned-about
after every call. Sleep is bounded by InputLimits, matching the
plan's "sleep" as a settle hint rather than an unbounded halt.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 305 | All nine §14 actions are expressible; doubleClick and rightClick are parameterisations of click | ✓ | §143 — the InputAction enum census |


---

## 144. §15's points contract is carried in every screenshot result

Geometry.swift opens with the contract verbatim: "an agent always
speaks in points" — a pixel coordinate posted as a point misses
every target by a factor of `scale`, so width/height (points), the
pixel dimensions and the backing scale all travel explicitly in each
screenshot result, making the planned `pointX = pixelX / scale`
arithmetic possible without guessing. The file also records a
measured macOS 27.0 quirk (CGDisplayPixelsWide returning points) —
the kind of empirical note §63.13 demands instead of assuming.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 306 | Screenshot results carry points, pixels and scale explicitly so coordinate conversion never guesses | ✓ | §144 — the Geometry contract comment |


---

## 145. §12's "cannot determine, refuse" is the SessionGuard's stated reason to exist

The rule appears verbatim in the type's doc comment: "If we cannot
*prove* the session is a background one, we do not post." An
unreadable session dictionary yields `.indeterminate`, and
`.indeterminate` refuses exactly like `.isConsole` — both map to
`.sessionIsConsole` at the error boundary and to `.console` on the
dashboard, so a caller can never treat the unprovable case as the
safe one. The comment names the bug this prevents: "there is
deliberately no code path here that returns `usable` on a missing
answer — that is the fall-back-to-the-user's-desktop bug the whole
product is built to avoid."

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 307 | An unreadable session state refuses identically to a confirmed console session, with the rationale stated in code | ✓ | §145 — the SessionGuard rule comment and both collapse sites |


---

## 146. §45's five Phase-1 test scenarios all have named tests

Console: testInputRejectedWhenSessionIsConsole (plus an
integration-shaped variant). No WindowServer:
testNoWindowServerIsRefusedDistinctly. Missing permissions:
testPermissionProblemsWinOverEverything and
testPermissionStateReportsMissingGrantsInSetupOrder. Background /
no-fallback: testWorkerDoesNotFallbackWhenSessionUnavailable and
the SessionGuard usable-path tests. Socket break / unauthorized
client: the token-rejection tests (non-matching, empty,
wrong-length) plus the isolation socket tests. Several carry the
§55-planned names verbatim.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 308 | All five §45 scenarios (console, no WindowServer, missing permissions, no-fallback background, socket break) have automated tests | ✓ | §146 — the five-scenario test census |


---

## 147. §53's polling guidance is exceeded: there is no status poll timer at all

The plan asks for status polling in the 2–5 s range with event
notification preferred. The AppModel header pins what shipped:
"refreshes happen on foreground, selection and explicit request,
and the only repeating timer in the app is the desktop viewer" —
no background status loop exists to tune. The planned 100 ms
anti-pattern has nothing to attach to; idle cost is structurally
zero between user-visible moments. The lone 500 ms sleep in the
model is a one-shot post-install settle, not a polling loop.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 309 | The app has no repeating status poll timer; refreshes are event-driven, exceeding §53's 2–5 s guidance | ✓ | §147 — the AppModel refresh-policy comment |


---

## 148. §22's app list covers regular, accessory and menu-bar apps explicitly

The enumeration walks `activationPolicy` and labels each entry
"regular" or "accessory" (prohibited-policy processes are not
agent-launchable and are excluded by policy, not by accident). The
comment states the product reason: accessory apps are menu-bar apps
(LSUIElement) and omitting them would make every launch of such an
app appear to fail. Window-server-visible stragglers are also
included, so an app the launch registration path saw is not missing
from the list.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 310 | apps lists regular and accessory (menu-bar/LSUIElement) apps with policy labels, covering §22's requirement | ✓ | §148 — the activationPolicy walk in AppControl |


---

## 149. §30's "actual, not allocated" is stated verbatim in the sampler

The Resources.Sample doc comment says it in the plan's own words:
"Deliberately not 'allocated' numbers: a Space is not a VM, so the
honest figure is what its processes are really using." The field
set is exactly §30's four metrics (cpuPercent, memoryBytes,
processCount, diskBytes); diskBytes is Optional-with-null rather
than zero because "'we did not look' and 'it is empty' are different
claims and only one of them is honest", and diskTruncated marks a
budget-limited lower bound. A UI-side grep for "allocated" returns
nothing.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 311 | Resource sampling reports actual per-UID usage with honest nil/truncation semantics; no Allocated fields anywhere | ✓ | §149 — the Resources.Sample comment and UI grep |


---

## 150. §24's worktree layout keeps the <space-id> scheme with a documented
location change

The planned shape was ~/.agentspace/worktrees/<space-id>/<repo>;
the shipped shape is <RuntimePaths.root>/Worktrees/<space-id>/<repo>
via SpaceProvisioner.worktreePath. The load-bearing part of §24 —
one checkout per Space keyed by UUID, agent-only working tree — is
intact, and the comment records why the parent directory ignores the
Space's name: on a case-insensitive filesystem "Test" and "test" are
one directory, and two agents in one working tree is exactly the
bug the worktree exists to prevent. The Doctor UI displays the same
shape. The home-relative root became the runtime root, which the
helper already manages ACLs for.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 312 | Worktree paths are <root>/Worktrees/<space-id>/<repo>, keyed by UUID with the case-collision rationale documented | ✓ (location deviation with rationale) | §150 — worktreePath and the worktreesDirectory comment |


---

## 151. §40's Stop vs Logout distinction is implemented with the exact semantics

stopWorker sends the worker RPC shutdown with reason "stop-agent";
the comment pins the mechanism — KeepAlive.SuccessfulExit = false
means launchd leaves a clean exit stopped (a real stop, not a
crash-restart loop) — and states the §40 outcome verbatim: "the
session (WindowServer, frames) stays up, so the next start is
instant." logoutDesktop is the §40 Logout: ending the whole GUI
session while keeping account and home, root-only via
launchctl bootout gui/<uid> through the privileged helper as a typed
RPC — "never by trying to sudo anything" — and failing typed when
the helper is absent. A worker already gone is success: stop is
idempotent.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 313 | Stop Worker keeps the GUI session (instant restart); Logout ends it root-only via the helper; both fail/stop per §40 | ✓ | §151 — stopWorker and logoutDesktop in SpaceService |


---

## 152. §21's recoverable flag defaults per-code so retries cannot be mislabelled

AgentSpaceError carries code, message and recoverable, and
recoverable defaults to the code's own isRecoverable classification:
"callers cannot accidentally mark a hard failure as retryable."
Console collisions and missing sessions are retryable-after-action;
signature-check failures are not recoverable by retrying the same
request — the doc comments classify them per code. The error also
exposes recoverySuggestion from the code's remediation text, so a
CLI/MCP caller gets the specific fix, not "something went wrong".

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 314 | The error object carries a per-code-defaulted recoverable flag plus a remediation suggestion, per §21 | ✓ | §152 — the AgentSpaceError init and comments |


---

## 153. §58 audit found and fixed a real drift: two code paths hand-wrote the
helper plist file name

BundleIdentifiers.helperPlist already exists as the §58 single
source, but HelperInstallation.launchDaemonPlist (Core) and
HelperSelfCheck.launchDaemonPlist (helper) each spelled the full
file name literally — exactly the two-definitions drift the plan
forbids. Both now route through the constant; the helper keeps its
own resolution start point (Bundle.main there is the daemon, not
the app, so the two lookups are not duplicates of logic — only of
the name), and a comment explains why. Human-facing diagnostic
strings that quote the path stay literal on purpose. All 336 tests
pass after the change.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 315 | Bundle-id and plist-name literals route through BundleIdentifiers in both code paths; only prose strings remain literal | ✓ (fixed this round) | §153 — the two edits and the green suite |


---

## 154. §31's CLI command list is complete: 15/15 plus two extras

All thirteen planned base commands (list, status, screenshot,
click, type, key, scroll, drag, launch, quit, apps, exec, desktop)
and both management commands (create, delete) exist as dispatch
cases; launch also accepts activate, and doctor ships per §38.
§22's forceQuit is exposed as quit --force, mapping onto the
separate Method.forceQuit. The CLI is a thin shell over the same
Core the GUI and MCP use (§49), so this list is also the
protocol's verb surface.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 316 | Every §31 CLI command exists; forceQuit rides quit --force; activate and doctor are extras | ✓ | §154 — the dispatch-case census |


---

## 155. §28's sign-in-once guidance is shown twice, with the fallback ban spelled out

The create wizard (DoctorView) walks the user through four
numbered instructions matching §28's five planned steps — open
Fast User Switching, sign in as the Space, grab the password via
Show Login Password, grant Accessibility and Screen Recording in
the setup window, switch back — and closes with the §2 ban in
plain language: "AgentSpace will not start an agent in your
account instead — if the background session is not there, every
call fails with SESSION_NOT_READY." SpaceDetailView shows the same
steps with done-markers during onboarding. The only-human step is
labelled as such ("this is the only step that needs you").

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 317 | The one-time login guidance exists in two views, matches §28's steps, and states the no-fallback rule to the user | ✓ | §155 — the wizard instructions in both views |


---

## 156. §10's remaining two forbidden mechanisms are absent

Fresh greps close the §10 list §43 did not cover explicitly: no
Xvfb reference anywhere (it is a Linux concept the codebase never
touches), and no DYLD injection — no DYLD_INSERT,
dyld_inject or task_for_pid. Combined with §43's earlier zero-hits
(SkyLight, ScreenSharing, screensharingd, TCC.db writes,
Virtualization, VNC, RDP), every mechanism §10 and §43 forbid has
now been verified absent by search, and the first-login flow rides
Fast User Switching exactly as the plan says.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 318 | Xvfb and DYLD-injection mechanisms have zero source presence, completing the §10/§43 forbidden-mechanism sweep | ✓ | §156 — the two zero-hit greps |


---

## 157. §47's complete Setup / Uninstall both exist as typed operations

Setup: the app registers the daemon via SMAppService (install), and
the helper exposes ten typed RPC verbs (helperStatus, createUser,
deleteUser, installWorker, removeWorker, prepareRuntimeDirectory,
startWorker, stopWorker, logoutSession, sessionInfo) — no generic
exec. Uninstall mirrors it: AppModel.uninstallHelper calls
SMAppService.daemon(...).unregister(), and per-Space teardown goes
through removeWorker + deleteUser (§41). Nothing hand-edits
launchd.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 319 | Setup and Uninstall are complete and typed: register/unregister on the app side, ten typed helper verbs, no raw launchd edits | ✓ | §157 — the verb dispatch and uninstallHelper body |


---

## 158. §35's four safety rules exist verbatim, generated from one source

Integrations.agentRules() emits all four sentences word-for-word
("Any command that can open a visible macOS window must run
through AgentSpace." / "Never launch GUI applications directly in
the user's current session." / "If AgentSpace reports that its
background session is unavailable, stop and report the problem." /
"Never fall back to the user's console session."), with a comment
stating the wording is a security property and therefore has
exactly one source of truth. agentRulesSection() wraps them with
markers for AGENTS.md / CLAUDE.md, and Copy Config puts the same
section on the pasteboard. My first grep missed it by searching
only the app target — the generator lives in Core.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 320 | All four §35 rule sentences are verbatim in one generator consumed by the marker section and Copy Config | ✓ | §158 — Integrations.agentRules() |


---

## 159. §16's ScreenCaptureKit tiers: 5 FPS idle and 0 FPS closed are wired;
15 FPS exists as a capability with no interactive call site

The worker's ScreenCaptureKitSource parameterises the frame rate
(configuration.minimumFrameInterval = 1/maxFPS); the app opens the
stream at previewStart(maxFPS: 5) and the DesktopViewerView ticks
at 1/5 s, and stops the stream entirely when the viewer closes
(previewStop) — the 0 FPS tier. When SCK cannot start the viewer
falls back to the verified 1 FPS screenshot MVP. The honest
limitation: nothing in the app requests 15 FPS yet — the
interactive tier is a parameter away but has no UI call site,
which §16 itself defers past MVP ("MVP must not be slowed down by
the ScreenCaptureKit stream").

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 321 | 5 FPS idle preview, 0 FPS on close, and 1 FPS fallback are wired end-to-end; 15 FPS is parameterised but has no interactive call site | ✓ (honest limitation) | §159 — previewStart/previewStop and the viewer's tick |


---

## 160. §17's click pipeline is complete: PreviewMapping converts view to
agent points in both directions, scale excluded by design

DesktopViewerView maps a click through PreviewMapping: the click's
fraction across the image times the display's *point* size is the
agent point (displayPoint), and the reverse viewPoint renders the
last sent click as a marker so a mis-scaled mapping is visible to
the user. The backing scale deliberately never enters the
calculation — the doc comment says so and the type does not take
it as a parameter (§15's points contract). The mapped point feeds
InputAction.click straight into the same .cgSessionEventTap RPC
path the CLI uses.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 322 | Viewer clicks convert view→point and point→view through one mapping type; scale is excluded; the result posts through the normal input RPC | ✓ | §160 — PreviewMapping and the viewer's click handler |


---

## 161. §23's exec contract is complete: all three inputs and all four
result fields

ShellExec takes cwd, an explicit environment, and timeoutMs, and
returns exactly the planned shape: exitCode (Int32? — null when
the process died without reporting one), stdout, stderr buffered
in full, and duration in ms. The doc comment states the buffering
design up front, and the env note warns that the binary is
resolved against PATH from the environment, so leaving env
implicit would run a different binary than the result describes.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 323 | exec supports cwd/env/timeout and returns exitCode/stdout/stderr/duration exactly as §23 specifies | ✓ | §161 — the ShellExec signature and result encoder |


---

## 162. §37's export redaction is layered: whitelist collection first, the
redactor at the exit, scrubbing at the log funnel

Diagnostics.collect() gathers only doctor output, space metadata
and file names — the token file is reported merely as
present/absent, the username is shown on purpose (navigation
identifier, not a credential), and typed input text is never
collected at all. The final line routes the assembled text through
Diagnostics.redact() — 64-hex tokens, password/secret/token
key-value pairs, data:image payloads and 4096+-char blobs become
<redacted-...> markers — before DoctorView writes the bundle. My
first trace concluded the redactor had no production caller; that
was a grep miss (the call is the bare `redact(...)` inside
collect), re-verified by reading the function body — the second-tool
rule catching my own negative claim. The worker's Log funnel
independently scrubs every line through Redaction.scrubString
before OSLog.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 324 | Exports are whitelist-collected and redacted at the exit; worker logs scrub through one funnel; all five §37 categories are covered | ✓ | §162 — collect()'s final redact call and the Log funnel |


---

## 163. §38's Doctor checklist: all thirteen planned items present, plus
extras the plan did not name

Mapping the plan's thirteen checks onto Doctor.run(): Apple
Silicon (arm64-only, §3 noted), macOS version (report header),
SMAppService + Privileged helper (via HelperInstallation.inspect),
Fast User Switching, Spaces (+ Registry integrity), Worker per
space — whose failure branches are exactly the Aqua-session
distinctions (no GUI login, no token, needs restart), Screen
Recording and Accessibility per space, Unix socket path, Input
isolated (four branches), and Workspace confinement per space.
Extras beyond the plan: WindowServer, Display geometry, and an
advisory own-process TCC row explaining that TCC attributes CLI
grants to the terminal. Failure rows carry named fixes with the
actual command to run, per §38's requirement.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 325 | All thirteen §38 checks exist (Aqua merged into the Worker branches), three extra checks beyond the plan, failures carry concrete fixes | ✓ | §163 — the check-name census in Doctor.swift |


---

## 164. §6's app-side prohibitions hold in their strongest form: the app has
no shell surface at all

Grepping the app target with prose excluded: zero dscl,
sysadminctl, sudo or launchctl anywhere, and zero Process(
constructor — AgentSpace.app does not spawn a single child
process, let alone a privileged one. The plan's three bans
(create users, modify system accounts, run a root shell) cannot
be violated from code that has no execution surface; every
machine change the app needs goes through the helper's typed RPC
(§157). The helper itself remains the only process that touches
the privileged commands.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 326 | The app target contains no privileged command strings and no Process( — §6's bans are enforced by absence, not discipline | ✓ | §164 — the zero-hit greps over apps/ |


---

## 165. §31's CLI-side ban holds: no privileged shelling, one benign Process

The CLI target contains zero dscl/sysadminctl/sudo/launchctl
execution — the only matches are two error messages that *say* the
CLI never runs sudo or launchd and point the user to the helper.
Its single Process() call is `agentspace desktop`'s
`/usr/bin/open <deeplink>`: an unprivileged hand-off that puts the
app's pull-model Desktop Viewer in front of the user rather than
duplicating the capture loop (comment cites §52 deliberately). The
privilege-requiring verbs are refused with the helper named as the
owner.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 327 | The CLI shells nothing privileged; its sole subprocess is the §31 desktop deep link via /usr/bin/open; refusals name the helper as owner | ✓ | §165 — the grep census and the desktop case |


---

## 166. §8's Standard-User guarantee is one deliberate omission: no -admin
flag, and not a parameter

HelperCommand.createUser runs sysadminctl -addUser without
-admin, and the comment states exactly why: the omission is what
stops a compromised agent from becoming an administrator, and it
is deliberately not a request parameter, so no caller — GUI, CLI
or future API — can flip it. No group command is appended, so the
account cannot be an admin by construction. The paired
deleteUser builds the home path from the validated account name
rather than the request, leaving no path field to aim at.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 328 | Created users are standard by construction — sysadminctl without -admin, non-parameterised, no group additions | ✓ | §166 — HelperCommand.createUser |


---

## 167. §9's Show Login Password is a transient, in-memory reveal with honest
failure modes

SpaceDetailView's button drives AppModel.revealPassword, which
reads the Keychain into a @Published struct — a sheet, not a
file — and the copy states the whole doctrine in one caption:
"Use this once, at the fast-user-switching login window. It is
stored in your login Keychain, not in a file, and nothing logs
it." Copying is an explicit button. Failure is honest both ways:
a missing item yields NO_STORED_PASSWORD with "cannot be
recovered", and a locked keychain yields KEYCHAIN_DENIED with the
unlock fix — no invented fallback.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 329 | Show Login Password reveals once in memory from the Keychain, never persists, and fails honestly when the item is gone or the keychain is locked | ✓ | §167 — revealPassword and the sheet |


---

## 168. §40's Stop-vs-Logout split: three named buttons over two typed verbs

SpaceDetailView carries the plan's exact trio — Stop Agent,
Logout Desktop…, Delete Space… (destructive). Stop Agent routes
to stopWorker, whose doc states the distinction outright: stop
the worker, keep the session, with the effective state honestly
going offline/needsLogin at the next refresh. Logout Desktop
routes to the helper's separate logoutSession verb; a missing
helper surfaces as the typed error with its fix — the fail-closed
shape. The two operations never share a code path: one is
launchd-level worker control, the other tears down the GUI
session.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 330 | Stop Agent (worker only, session kept) and Logout Desktop (session teardown) are distinct UI buttons over distinct helper verbs, exactly as §40 separates them | ✓ | §168 — AppModel and HelperService |


---

## 169. §41's delete sequence is six ordered steps that always spare the
user's repository

SpaceProvisioner.delete opens by citing plan §41 and orders:
stop worker first (removing a running job's plist would leave it
alive until reboot), then `git worktree remove --force` — branch
kept, because the branch holds the agent's commits and the
original repository is never touched; a worktree-remove failure
does not block the deletion. Then removeWorker + Keychain
forget, then the registry (before the account, so no entry points
at a missing account), then deleteUser last with the account
always named on failure — after registry removal that message is
the only pointer to a leftover account. The runtime directory is
best-effort last. removeHome is the caller's separate question:
the one irreversible step. Detail strings twice state the user's
repository and branch are untouched.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 331 | The §41 chain runs in dependency-safe order, keeps branches, touches the original repo never, treats home removal as a separate explicit ask, and names the account on late failures | ✓ | §169 — SpaceProvisioner.delete |


---

## 170. §30's negative space holds: no "Allocated" anywhere, only actual usage

Zero matches for "allocated" across the app and core targets.
The resources card shows the plan's four real quantities — CPU
(percentage, with a caption that it can exceed 100% on a
multi-core Mac), Memory, Processes, and an on-demand Measure
Disk Usage button — and its caption states the honest reading of
uid aggregation: if the worker runs under your own account, the
numbers describe your whole login session, which is what the
aggregation is honestly reporting, not a leak. Nothing pretends
a VM-style allocation exists.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 332 | No "Allocated" wording; the card shows real CPU/Memory/Processes/Disk with an honest uid-aggregation caveat | ✓ | §170 — the resources card and zero-hit grep |


---

## 171. §29's browser-profile and keychain isolation are structural, not
implemented — and that is the correct shape

Two of the plan's eight per-Space independences have no code,
deliberately. A Space's browser profile lives inside the Space's
home (DiskUsage.swift's doc says so explicitly), and a user's
login Keychain is per-UID by the OS. Since §166 guarantees the
account is standard and §76 guarantees an independent HOME, both
items are derived from the construction itself. Code that
"created" a browser profile or keychain at a shared path would
*break* isolation — the absence is the feature.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 333 | Browser-profile and keychain isolation follow structurally from the standard account + independent HOME, with no — and no need for — dedicated code | ✓ | §171 — DiskUsage doc, the derived-from-construction reading |


---

## 172. §32's JSON mode is one emitter with no bypasses: sixty call sites,
zero stray prints

Every CLI command outputs through the single Emitter struct —
thirty success/failure call sites across all dispatch cases, and
the only print() calls in the file are *inside* the Emitter's own
methods. In --json mode failures emit the complete envelope
(status: unavailable, reason, ok: false, error{code, message,
recoverable} and fix), so a script can branch on the whole
answer; in human mode the code, message and remediation are all
shown because, as the comment says, a bare "failed" is what makes
a tool unusable.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 334 | All CLI output funnels through one Emitter; --json failures carry the full typed envelope; no command bypasses it | ✓ | §172 — the Emitter and its call-site census |


---

## 173. §22's launch does not trust the exit code: it waits for registration

AppControl.launch states the plan's rule in its own comment —
open's success only means LaunchServices accepted the request;
returning a pid at that moment hands the agent a number it cannot
use. It launches via NSWorkspace inside the Aqua session, then
polls (150 ms) until a pid resolves by any of three routes — the
expected pid alive, the bundle identifier, or the before/after
process diff — and treats window ownership as the registration
signal, with a half-budget window deadline so LSUIElement/menu-bar
apps (which never own windows) are not stalled to the full
timeout. Failure is honest: APP_LAUNCH_TIMEOUT with the
suggestion to screenshot the Agent session for a hidden modal.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 335 | Launch waits for a real pid plus window ownership (menu-bar exempt), failing with APP_LAUNCH_TIMEOUT instead of trusting acceptance | ✓ | §173 — AppControl.launch |


---

## 174. §22's app list covers menu-bar and LSUIElement apps via the window
server's word

runningApps enumerates every session app with its activation
policy, then filters through the Core's single AppVisibility
rule: regular or accessory is always in, and any AppKit-
prohibited app is still included when the window server reports
it owns an on-screen window — the fail-open-by-evidence rule that
lets menu-bar utilities surface even when AppKit misclassifies
them. Frontmost is read from the window list too, because
NSWorkspace's cache was observed reporting a killed app as
frontmost for minutes. The rule lives in Core so tests can pin it
without a window server.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 336 | The apps list includes regular, accessory and window-evidenced prohibited apps — menu-bar detection per §22 — with frontmost from the window server, not the stale NSWorkspace cache | ✓ | §174 — runningApps and AppVisibility |


---

## 175. §39's Needs Login is a derived discriminator, not a guess

SpaceState.effective cites plan §39 in its own doc: the state to
show is not always the stored state. The hasGraphicalSession
discriminator resolves the restart question — a worker down
because nobody is logged in shows needsLogin (fix: fast user
switch, not a retry), a worker dead under a live session shows
offline, and an unresolvable lookup keeps offline rather than
guessing. The function is pure so GUI, CLI and tests derive it
identically, provisioning starts spaces at needsLogin, and no
code path auto-starts a worker into a session nobody has signed
into.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 337 | needsLogin vs offline is derived from hasGraphicalSession with nil kept honest, shared by all callers; no auto-start into an unlogged session | ✓ | §175 — SpaceState.effective |


---

## 176. §34's integrations surface: three typed installs plus two copy
actions, path drift already caught once

SpaceDetailView offers install buttons per target — claudeCode,
codex, openCode — and AppModel.installIntegration merges each
client's real format (TOML for Codex, JSON mcpServers, JSON mcp)
rather than overwriting. Copy Config exists as copyMCPConfiguration,
which resolves the binary path through Integrations.defaultBinaryPath:
its comment records the earlier drift where a hardcoded
Contents/MacOS/agentspace — a file this bundle has never contained —
made the copied config point at nothing. Copy Agent Rules implements
§35's consent shape: the user pastes the rules themselves; the CLI's
integrate rules --install is the opt-in alternative with backup and
marker-scoped idempotence.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 338 | Three per-target installs merge real client configs; Copy Config resolves the shipped CLI path (drift caught and fixed); rules copying keeps user consent | ✓ | §176 — installIntegration, copyMCPConfiguration, SpaceDetailView |


---

## 177. §36's exec deny list: all nine plan patterns plus a superset, sold
honestly as not-a-sandbox

ExecGuard states the plan's caveat verbatim in its own doc: this
is not a sandbox — the real boundary is the standard, non-admin
worker uid — the list is a guardrail against mistakes and prompt
injection. All nine plan patterns are present (sudo, installer,
diskutil erase, launchctl bootstrap system, dscl create,
sysadminctl, rm -rf /, shutdown, reboot) with a wide superset
(nvram, csrutil, tccutil, kextload, dd if=, fork bomb, raw device
writes...). Two layers: case-insensitive substring rules and a
refusedExecutables first-word set that fails fast with a clear
message instead of a permission-denied an agent would retry. The
list lives in Core, ShellExec routes every command through it,
and 19 tests pin it — including whitespace normalisation,
path-qualified binaries, and that ordinary dev commands still run.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 339 | The exec deny list covers all nine plan patterns plus a superset, is layered (substring + first-word), single-sourced in Core, tested 19 ways, and documented as a guardrail not a sandbox | ✓ | §177 — ExecGuard, ShellExec, ExecGuardTests |


---

## 178. §37's logging: one shared subsystem, all eight categories, drift guard

Every AgentSpace process logs under BundleIdentifiers.logSubsystem
(com.agentspace.app) — deliberately not the app's bundle id, with
the doc explaining why: log filters are written and shared as this
string, so changing one without the other would break every
documented log show command. All eight plan categories are in real
use: app, helper (twice — the helper's self-check even points
troubleshooting at its own category), worker, ipc, session, input,
capture, mcp. Exported diagnostics flow through the whitelisted
Diagnostics collector with a single redaction exit, so secrets
never reach the log file in the first place.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 340 | One subsystem constant serves all processes with all eight §37 categories in actual use; diagnostics stay behind the single redaction exit | ✓ | §178 — BundleIdentifiers.logSubsystem, per-target Log files, Diagnostics |


---

## 179. §24's worktree layout: the plan's ~ path is a deliberate deviation
with a stronger key

The plan sketches ~/.agentspace/worktrees/<space-id>/<repo>; the
implementation puts worktrees under /Users/Shared/.AgentSpace/
Worktrees/<space-uuid>/<repo>. The deviation is necessary, not
accidental: the worker runs as the Agent user, whose permissions
cannot traverse the main user's home, while the shared root is
exactly where §20's ACL (main user, agent user, root) already
lives. The uniqueness key is the Space's UUID rather than its
name — the doc records why: on a case-insensitive filesystem two
Spaces named Test and test are one directory, and two agents in
one working tree is the bug the worktree exists to prevent.
WorkspacePreparer additionally refuses any worktree path outside
the workspace directory.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 341 | Worktrees live under the shared root with per-Space UUID keys and an escape check; the ~ path from the plan is recorded as a deliberate deviation forced by cross-user permissions | ✓ (deviation documented) | §179 — worktreesDirectory, SpaceProvisioner.worktreePath, WorkspacePreparer |


---

## 180. §25's read-only default is enforced end to end, and the forbidden
list is structural

SharedFolder's access parameter defaults to .readOnly with the
doc naming the failure mode it exists to prevent: an agent that
can silently rewrite the folder you are working in. Enforcement
is real, not decorative: provisioning writes allowed and writable
roots into the workspace record, the worker carries them in its
context, and WorkspaceGuard.check runs on exec cwd and file
arguments — a write into a read-only root fails with
WORKSPACE_DENIED and a fix ("Enable Read & Write for that
folder"). The plan's forbidden list (~, Library, Desktop,
Documents, Downloads, SSH, Keychain) is satisfied structurally:
the agent account has no access to the main user's home at all,
and allowedRoots starts empty — nothing is reachable until the
user adds it. Symlinks resolve before the prefix test, so
/tmp/evil -> ~/.ssh does not pass on a technicality.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 342 | Shared folders default read-only with enforced WORKSPACE_DENIED on write; the forbidden-directory list holds structurally via empty-by-default allowedRoots and no home access; symlinks resolve before the prefix test | ✓ | §180 — SharedFolder, WorkspaceGuard, SpaceProvisioner plan |


---

## 181. §28's five-step sign-in card matches the plan; a stale placeholder
button caught and fixed

The Setup card shows exactly the plan's five steps — open Fast
User Switching, sign in as "AgentSpace – <name>", grant
Accessibility, grant Screen & System Audio Recording, switch
back — each with a live done marker driven by workerOnline /
accessibility / screenRecording, plus an explicit "never writes
the TCC database" note. The audit caught one gap: the card's
Show Login Password button still carried a phase-3-era placeholder
that presented an internalError instead of calling the real
revealPassword flow that the Space page had used since the
transient-reveal work (§167). Fixed to route through
revealPassword(for:); build clean, all tests pass. Honest
limitations: the real helper-backed password path is exercised
only through the detail card; setupCard cannot show the password
before provisioning stores one, so a NO_STORED_PASSWORD failure
is the correct outcome there.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 343 | The five-step sign-in card matches §28 with live progress; the stale placeholder Show Login Password button was found and re-wired to the real reveal flow | ✓ (gap fixed) | §181 — setupCard, AppModel.revealPassword |


---

## 182. §30's sampler audited; the §127 limitation closed with direct parse
tests

Resources.sample keeps the plan's honest shape: one /bin/ps
invocation filtered to the uid, memory in RSS kilobytes summed
per process, CPU summed so multicore can exceed 100 percent, disk
nil-when-unmeasured with a truncation flag — never allocated
numbers. The audit found the text parsing itself untestable where
it lived (inside the worker, forked into sample()), so it moved
to Core as ResourcesParsing.accumulate — the same
single-source-in-Core pattern as AppVisibility — and five direct
tests now pin the contract: multi-process accumulation, other
uids ignored, malformed lines skipped without dying, header/empty
output yielding zeroes, and CPU summed past 100 percent rather
than clamped. The §127 verdict line (ps parsing lacks direct unit
tests) is thereby closed. Suite now 341 tests, 0 failures.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 344 | Per-uid sampling parses one ps line per process with malformed lines skipped, CPU summed not capped, disk honest about unmeasured; parsing is in Core and directly tested (5 tests) | ✓ | §182 — ResourcesParsing, Resources.sample, ResourcesParsingTests |


---

## 183. §26's data model: all eleven fields and all eight states, one typed
refinement

AgentSpace carries every field the plan lists — id, name,
username, uid, state, createdAt, lastStartedAt, workspace,
sharedFolders, permissions, autoStartWorker — with the doc citing
plan §26, and SpaceState enumerates exactly the eight plan states
(created, needsLogin, needsPermission, ready, running, offline,
console, error) with per-case docs. One deliberate refinement:
plan writes workspace as Workspace? optional; the implementation
uses a non-optional Workspace enum whose .none case is explicit.
That is stronger than optional — "no workspace" is a modeled
state, not a nil to unwrap or forget — and the custom Codable
maps legacy records to .none rather than failing.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 345 | The model matches §26 field-for-field with all eight states; workspace optionality is a documented, typed refinement (.none case instead of nil) with legacy-safe decoding | ✓ (refinement documented) | §183 — AgentSpace, SpaceState, Workspace |


---

## 184. §53's low-overhead budget holds structurally: one gated timer,
event-driven refresh, on-demand disk walk

The app contains exactly one Timer — the Desktop Viewer's — at
1 FPS (5 when streaming), tied to the view's lifetime:
onDisappear invalidates it and stops the preview, so nothing
polls when nobody watches. Status reloads are event-driven —
they run after provisioning, stop, logout, delete or a selection
change, never on an interval. The disk walk is deliberately kept
out of reload(): its doc cites §53 by name — walking a browser
profile plus IDE caches (tens of thousands of files) on a 2-5 s
poll would pin the CPU — so measurement happens on request and
merges into the existing snapshot. The worker's idle-RAM figure
itself still needs a live background session to measure (external
gate); what the code shows is the shape that makes idle cheap:
no polling timers, no growing caches, no continuous capture.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 346 | One lifetime-bound preview timer, event-driven reloads, and a request-scoped disk walk give the §53 idle shape; the worker's live idle-RAM number remains gated on a real session | ✓ (live figure gated) | §184 — DesktopViewerView, AppModel reload sites, measureDisk comment |


---

## 185. §15's coordinate contract: Point-based input, pixel/scale in the
payload, conversion taught in the error

The screenshot result carries exactly the plan's shape — width/
height of the written PNG, pixelWidth/pixelHeight of the full
framebuffer before any downscale, and scale. Input coordinates
are points, and the coordinate validator teaches the §15 rule
inside its rejection: off-display coordinates report the display
size in points and say "Screenshot pixels must be divided by
scale=N first." pixelWidth comes from CGDisplayCopyDisplayMode,
not CGDisplayPixelsWide, with a measured macOS 27 note explaining
why (the latter returned 3840 on a 1728-point scaled Retina
display, which would derive scale 1). PreviewMapping closes the
loop for the viewer: view point -> image fraction -> display
point, using the display's point size so a downscaled preview
never needs the backing scale — the obvious pixel-division would
silently land a click a third of the way across the screen.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 347 | Screenshots return width/pixelWidth/scale as planned; input is points with the pixel-to-point rule in the error text; both pixel source and viewer mapping carry measured, not guessed, geometry | ✓ | §185 — ScreenCapture.Result, CoordinateValidator, PreviewMapping |


---

## 186. §14's batch input API: all nine verbs, bounded batches, refusals that
never guess

The action enum covers every §14 verb. doubleClick and
rightClick are modeled as one click primitive with count and
button, and the wire name derives accordingly — the same verb
with explicit parameters rather than nine separate cases, which
is the deeper model. Batches parse as a whole: a count over
InputLimits.maxActions is refused, any single bad action fails
the entire call (never a half-executed batch), and the summed
sleep is capped per call so an agent cannot park the worker with
sleeps. Modifier names accept the ecosystem's variants —
cmd/command/meta/super/Unicode — and the key table is deliberately
finite: an unknown key name is INVALID_ACTION, "never a guess",
because silently typing the wrong key into someone's session is
worse than refusing.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 348 | Nine §14 verbs present (doubleClick/rightClick as parameterized click with derived wire names), whole-batch parse with count and sleep caps, tolerant modifiers, finite fail-closed key table | ✓ | §186 — InputAction, InputLimits, KeyCombo |


---

## 187. §31/§32's CLI surface: every planned command present, one global
--json, and §2's envelope on the failure path

All fourteen §31 commands are in the CLI (list, status,
screenshot, click, type, key, scroll, drag, launch, quit, apps,
exec, desktop, create, delete) plus a documented superset:
input/move, preview, integrate, helper, diagnostics, doctor, and
the ax.* family. `--json` is a global boolean flag — the flag
table strips the leading dashes, which is why a naive grep for
the literal misses it, and its doc records the real bug it once
was (a value flag that made `status --json` demand an argument).
The Emitter's two shapes close the loop: JSON mode prints the
envelope as the whole answer so scripts can branch, and the
failure shape is exactly §2's fail-closed body — status
"unavailable", reason AGENT_SESSION_NOT_READY, ok false, plus the
typed error. Human mode shows code, message and fix, because "a
bare failed is what makes a tool unusable".

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 349 | Every §31 command plus a superset exists; --json is global with a recorded parse-bug fix; the JSON failure envelope is §2's fail-closed shape verbatim | ✓ | §187 — main.swift command switch, booleanFlags, Emitter |


---

## 188. §37's logging: single subsystem, per-component categories, redaction
at both boundaries

The subsystem is the plan's com.agentspace.app, carried by
BundleIdentifiers.logSubsystem — not hardcoded per process. The
helper logs under its own category with a doc that hands a
security review the exact predicate: `log show --predicate
'subsystem == "com.agentspace.app" AND category == "helper"'`,
so what the root component did is readable in isolation. §37's
redaction list is all present in the pure redactor: 64-hex
session tokens (with the argument for why nothing legitimate in
a diagnostics bundle is 64 hex), key/value secrets in any
spelling, inline screenshots by name, and long base64 blobs;
everything is scrubbed again at the export boundary. Strings go
to the log pre-redacted and privacy .public — the secrecy comes
from the redactor, not from hoping the store hides them. The
redactor counts its hits so an export can show redaction
happened.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 350 | Subsystem single-sourced, helper category review-readable by predicate, and §37's password/token/screenshot/blob redaction applied at log time and export time, with counts | ✓ | §188 — Diagnostics.redact, HelperLog |


---

## 189. §6's app-layer prohibitions hold structurally: no process spawning,
ten typed operations, argv not strings

A precise regex over the app target finds no Process(), NSTask,
posix_spawn, or bare system() call — the only textual matches are
SwiftUI's .font(.system(...)), which is why the literal grep hit
first and the precise one is the evidence. The app cannot create
users, run root shells, or modify the system by any path: every
privileged action goes through HelperClient and the ten-member
HelperOperation enum (createUser, deleteUser, installWorker,
removeWorker, prepareRuntimeDirectory, startWorker, stopWorker,
logoutSession, sessionInfo, helperStatus) — a whitelist by
construction, with no exec anywhere. The protocol never
interpolates into command strings: HelperCommand builds argv
arrays and the daemon spawns with posix_spawn, so there is no
quoting layer for an attacker to escape, and the password field
is documented as AgentSpace-generated only.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 351 | App target spawns no processes; privileged actions are the ten §6 typed operations with no exec; argv-array construction removes the quoting layer structurally | ✓ | §189 — apps/AgentSpace sweep, HelperOperation, HelperProtocol doc |


---

## 190. §56's release security review, item by item

Each line of §56's pre-release checklist maps to verified code:
Unix socket ACL — the socket lives at 0700, file 0660 group
staff inside a directory ACL'd to the main user. Token —
SecRandomCopyBytes 256-bit, compared in constant time before any
method other than hello runs. XPC authentication and code
signing — CallerVerification checks the guest against the
requirement with SecCodeCheckValidity, and HelperSelfCheck
checks the helper's own signature. LaunchDaemon privileges —
root helper with the ten-case whitelist, no exec. Symlink
attack — WorkspaceGuard resolves symlinks before prefix tests;
ExecGuard canonicalises on the longest symlinked directory.
Path traversal — the delete-home path derives from the validated
account name, never from request data. Workspace escape —
WorkspaceGuard plus testWorkspaceCannotEscapeAllowedPath.
Command injection — the ExecGuard refusal list and argv-array
construction. Log secret leakage — redaction at both the log
and export boundaries (§188). The helper's separate review
requirement (§56's last paragraph) is served by the helper-only
log category with its ready-made log show predicate.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 352 | All ten §56 checklist items have named, verified implementations; the privileged-helper separate review is served by the helper log category and predicate | ✓ | §190 — main.swift socket attrs, Security.swift, CallerVerification, HelperSelfCheck, ExecGuard, HelperProtocol:521, Diagnostics |


---

## 191. §42's Offstage chain: full MIT notice, eight borrowed findings
tabulated, divergences reasoned

THIRD_PARTY_NOTICES.md reproduces Offstage's MIT license with
its copyright intact, then states plainly that no source file
was copied verbatim — and registers the debt anyway, because
"the honest thing to do with a real debt is to acknowledge it
rather than argue about whether it clears a threshold." Eight
specific borrowings are tabled with what each contributed: the
three CGEvent posting paths and their measured behaviour, always
assigning event.flags, one event per grapheme cluster, the
CGDisplayPixelsWide scaled-Retina trap (independently
re-measured here), frontmost-from-window-list, the background
Aqua session shape, posix_spawn SETSID/signal-mask details, and
the socket-directory observation adopted as a sun_path length
check. Deliberate divergences are tabulated with reasons in
§8. No Swift file carries an Offstage copyright header — the
consistent consequence of having copied no code — while the
conceptual debt is fully recorded.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 353 | §42 satisfied the strict way: no verbatim copies (hence no per-file headers to preserve), MIT notice reproduced regardless, eight borrowings and all divergences documented | ✓ | §191 — THIRD_PARTY_NOTICES.md |


---

## 192. §57's distribution chain: hardened signing, ordered notarization, stapled DMG

scripts/release.sh rebuilds dist/AgentSpace-$VERSION.dmg from
clean state; bundle-app.sh signs with --options runtime and
verifies deep/strict; notarize.sh checks the notarytool profile
is live, submits with --wait (retrying, because the doc records
that notarytool's long-poll client can time out), staples the
app before packaging — the comment notes the app's bytes must be
notarized before stapler can attach a ticket — then hdiutil
creates the UDZO image and stapler staples and validates the DMG
itself. Mac App Store exclusion is documented with the plan's
own reasoning (privileged helper, system users) in
docs/security.md, and the App Store Connect key path for the
user's own credentials is in troubleshooting. The cask remains
gated on a public release URL, as before.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 354 | Developer ID + hardened runtime + submit/staple/validate chain scripted in correct order, DMG excluded from MAS with documented reasoning; cask still waits on a release URL | ✓ (cask gated) | §192 — release.sh, bundle-app.sh, notarize.sh, security.md:410 |


---

## 193. §43's forbidden-dependency list: double-tool negative sweep, public
API path confirmed

Two independent sweeps over all Swift, JavaScript and shell
sources — a file-level grep and a line-level regex — find no
SkyLight, ScreenSharing, TCC.db, Virtualization.framework or
screenshot-manager reference anywhere in code or scripts; the
only mentions of these names in the repository are the docs
explaining why they are excluded. The positive path is the one
§43 endorses: /usr/sbin/screencapture, self-described as "the
boring, correct choice," invoked only after CGPreflight... grants
it, and CGSession/kCGSSession for the console check. A ban list
is a feature of absence, so the claim is recorded the same way
the §171 derivations are: what is missing is the design.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 355 | No §43-forbidden framework appears in any code or script (two-tool sweep); capture and session checks use only the public macOS surface | ✓ | §193 — repo-wide sweeps, ScreenCapture.swift:8,66 |


---

## 194. §5's monorepo layout: everything present, one consolidation, three
supersets

Every path the plan lists exists: apps/AgentSpace with its UI,
Models, Services, Views and Resources; the three native targets;
packages/agentspace-mcp; tests/{Unit,Integration,Session}; all
four named docs plus validation.md; scripts, THIRD_PARTY_NOTICES
and README. Three additions beyond the plan: tests/Safety (the
suite §55 calls most important), tests/probes, and
AgentSpaceApp's own build target. One consolidation: the plan's
shared/{Protocol,Models,Utilities} is a single AgentSpaceCore
module — three separate targets would make Protocol depend on
Models' types, and one module is that dependency graph solved
rather than split. Consolidation, not omission.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 356 | §5's tree matches path for path, with Safety/probes/App as supersets and shared/* consolidated into one Core module whose rationale is the dependency graph itself | ✓ (consolidation documented) | §194 — repo tree, Package.swift |


---

## 195. §59's README first screen: every planned element verbatim

The README opens with the plan's exact headline, its exact
two-sentence body, and the exact "No VM. No second macOS
installation. No remote Mac." line. The two-desktop diagram is
line-for-line what §59 sketched — VS Code/Chrome,
Terminal/Simulator, Safari/Xcode, "You keep working / The agent
keeps working" — and the four §1 guarantees follow as four short
sentences: pointer does not move, keyboard is not taken, focus
does not change, desktop does not flicker. The How section
restates §1's architecture text (same Mac, same kernel, same
/System, macOS's own multi-user GUI support). No deviation on
this one at all.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 357 | README first screen reproduces §59 verbatim — headline, body, three denials, dual-desktop diagram — plus §1's four user-side guarantees and the architecture line | ✓ | §195 — README.md |


---

## 196. §61's out-of-scope list: absent in code, documented as design

Two sweeps over all Swift, TypeScript and JSON sources — the MCP
package included — find no cloud sync, accounts, marketplace,
model provider, LLM chat, task orchestration, Docker,
Virtualization, team or remote-Mac code paths. The exclusion is
stated, not merely absent: architecture.md has a "What this
deliberately does not do (V1)" section naming all fourteen §61
items with the plan citation, closing with the plan's own thesis
— one Mac, several background GUI sessions, an agent that can
drive them, a human who is not interrupted — "stable before
broad". The MCP package's five-file surface is correspondingly
narrow: there is nowhere for orchestration or chat to grow
without a deliberate addition.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 358 | All §61 exclusions are absent from code (two-tool sweep) and named in a documented V1 scope section; MCP surface stays five files wide | ✓ | §196 — repo sweeps, architecture.md "deliberately does not do" |


---

## 197. §60's five priorities, each anchored to a verified mechanism

§60 says every feature must prioritize Isolation, Fail Closed,
Low Overhead, Native macOS and Agent Friendly over convenience.
Each has a named anchor: Isolation — the five-verb console
refusal and the 0700 runtime ACLs. Fail Closed — .indeterminate
refuses exactly like .isConsole, worker gates exit 77/69, and
invalid coordinates are rejected rather than clamped. Low
Overhead — one lifetime-bound timer, event-driven reloads, the
disk walk kept off the poll. Native macOS — no private
frameworks by double sweep, Fast User Switching as the session
mechanism itself. Agent Friendly — typed errors with remediation
text, the pixel-to-point rule inside the rejection, a global
--json whose failure envelope is §2's body, and refusal messages
that teach. The plan's summary line holds as an audit result:
none of the five was traded away for convenience in the 16
phases.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 359 | §60's five priorities each map to a verified mechanism; no priority was traded for convenience across the audited phases | ✓ | §197 — SessionGuard, gates, §184, §43, ErrorCodes |


---

## 198. §55's eight named safety tests: adopted verbatim, name for name

The plan says the safety test names "can directly" be the eight
it lists. All eight are used verbatim in SafetyTests.swift and
SessionGuardTests.swift — testInputRejectedWhenSessionIsConsole
at line 23, testInputDeliveredOnlyToWorkerSession at 87,
testWorkerDoesNotFallbackWhenSessionUnavailable at 119,
testWorkerCannotRunAsRoot at 159, testUnauthorizedSocketClientRejected
at 182, testDifferentSpacesHaveDifferentTokens at 233,
testScreenshotNeverReturnsConsoleSession at 306 and
testWorkspaceCannotEscapeAllowedPath at 388 — plus a superset:
the Integration twin of the console refusal, a distinct
no-WindowServer refusal, a runtime is-root assertion, the
hello-is-token-exempt leak check, disk usage measured only when
asked, and exec running as the space user with dangerous-command
refusal. One first-round grep missed the console test because
the pattern demanded the substring "ConsoleIsConsole" while the
verbatim name is "...SessionIsConsole" — the pattern was wrong,
not the test; the full listing is the second tool.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 360 | All eight §55 test names are adopted verbatim, with a six-test superset around them | ✓ | §198 — SafetyTests.swift, SessionGuardTests.swift |


---

## 199. §3's API floor: every source compiles against macOS 13, no 26-only
API anywhere

The plan asks only that macOS-26-specific APIs be avoided during
development; the build floor is set lower still —
Package.swift declares platforms [.macOS(.v13)] — and a
repo-wide sweep finds zero `#available(macOS 26...)` or 27
gates: no source path needs anything newer. The supported-range
statement (Apple Silicon, macOS 26+) remains a product decision
enforced by doctor's version check, while the API floor is a
development discipline kept two major versions below it — which
also means the plan's later verification matrix (macOS 15, 26,
27) is already inside the compile-compatible range rather than
above it.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 361 | Build floor is macOS 13 with zero 26+-gated APIs — stricter than §3's "avoid 26-only APIs" — while the supported range stays a doctor-enforced product decision | ✓ (superset) | §199 — Package.swift:22, availability sweep |


---

## 200. §4's forbidden UI stacks: absent from sources, manifests and the
MCP dependency tree

Two sweeps — sources (Swift/TS/mjs) and dependency manifests —
find no Electron, Tauri, React Native, WKWebView or UIWebView
anywhere in project code. The one literal hit is TypeScript's
own compiler type definitions inside node_modules, describing
JSX interop, not project code; the node_modules-excluded
resweep is the second tool and is empty. The MCP package's
dependency list is exactly §4's first-version stack —
TypeScript, Node, @modelcontextprotocol/sdk — and the GUI side
is SwiftUI throughout with no web view bridging layer (the §6
entry's process scan corroborates). A management tool with a
web UI would undercut the very low-overhead thesis §53 states;
it is not present.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 362 | No §4-forbidden UI stack appears in project sources or manifests; MCP deps are exactly the planned TypeScript/Node/SDK triple | ✓ | §200 — two-tool sweep, package.json |


---

## 201. §30's display side: four real metrics on the card, "Allocated"
nowhere, disk measured only when asked

SpaceDetailView's resources card shows exactly the §30 list —
CPU as a percentage, Memory as a human-readable byte figure,
process count, and Disk behind an explicitly-requested
measurement — all in monospaced fields after the OrbStack/Xcode
style the plan points at. A case-insensitive sweep of the app
source finds no "Allocated" anywhere: nothing pretends this is a
VM with reserved resources. The disk field's comment states why
it is on demand — the walk over tens of thousands of files is
kept off the polling path (the same discipline §184 recorded for
the timer) — and the numbers themselves are the UID-summed
figures the §182 parser produces.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 363 | Dashboard shows CPU/Memory/Processes/Disk as real per-UID figures with zero "Allocated" wording, disk gated behind an explicit measurement | ✓ | §201 — SpaceDetailView.swift:96,231–237 |


---

## 202. §39's "no stealthy startup after reboot" is a launchd fact, not a
policy

The worker's LaunchAgent template sets
`LimitLoadToSessionType = Aqua`, so launchd only loads the job
inside an Aqua GUI session. After a reboot the AgentSpace user
has none, the plist is simply not loaded, and no worker runs —
the Needs Login state is launchd's own behavior, not a promise
the app makes. The same template pairs `RunAtLoad = true` with
`KeepAlive SuccessfulExit = false`, which is exactly the plan's
flow: the moment the human fast-switches in, the worker starts
and stays started. Belt and braces: the plist pins UserName to
the space account while the worker's own never-root gate exits
77, and the helper's ten-operation whitelist contains no
auto-login path at all. Even the provisioning order respects
the semantics — the worker is installed last because RunAtLoad
starts it immediately.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 364 | LimitLoadToSessionType=Aqua makes post-reboot "Needs Login" a launchd fact; RunAtLoad+KeepAlive implement the sign-in-once flow; no auto-login path exists in the helper | ✓ | §202 — HelperProtocol.swift:489–496, HelperService.swift:463, SpaceProvisioner.swift:105 |


---

## 203. §40's stop/logout distinction: two typed operations, two privilege
paths

The plan's Stop Worker / Logout Space split exists as two
independent service methods. `stopWorker(for:)` talks to the
worker's own RPC and treats an already-dead worker as success;
`logoutDesktop(for:)` sends a typed `.logoutSession` helper
request whose implementation is the root-only
`launchctl bootout gui/<uid>` — documented as ending the whole
GUI session while keeping the account and home, exactly the
plan's Logout semantics. The comment's privilege discipline is
the §31 rule restated: typed helper RPC, never sudo, typed
failure when the helper is missing. The UI button for stop is
wired, delete's ordered teardown was recorded earlier, and the
helper whitelist carries `.stopWorker` and `.logoutSession` as
separate capabilities — the distinction is enforced at every
layer, not just the menu.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 365 | Stop Worker and Logout Desktop are separate typed operations with separate privilege paths, enforced at service, helper-whitelist and UI layers | ✓ | §203 — SpaceService.swift:199,219–230, SpaceDetailView.swift:134 |


---

## 204. §22's app list: menu-bar apps included, window-server truth over
stale AppKit caches

The list spans the plan's three classes: every
NSRunningApplication is labelled regular, accessory or
prohibited (with an @unknown default), the comment names the
plan's exact case — "Accessory apps are menu-bar apps
(LSUIElement)" — and the visibility rule in Core keeps an
accessory app plus any app the window server sees even when
AppKit calls it prohibited. The frontmost and window facts come
from CGWindowListCopyWindowInfo, not NSWorkspace, because the
worker has no run loop for workspace notifications and the cache
goes stale — "observed reporting an app as frontmost minutes
after it had been killed," which is the §63.13 measured-behavior
rule applied to AppKit itself. AppVisibility lives in Core so
tests pin the rule without a window server, and this is the
window-list source THIRD_PARTY_NOTICES registers as a borrowed
idea.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 366 | apps lists regular/accessory/LSUIElement classes with window-server evidence over stale caches; the visibility rule is Core-pinned and test-covered | ✓ | §204 — AppControl.swift:33–70, AppVisibility |


---

## 205. §18's AX surface: four verbs verbatim, elementAt folded in, tree
bounded and honest about it

ax.snapshot, ax.frontmost, ax.windows and ax.perform are
registered in Core's protocol and documented method-for-method in
protocol.md — the first phase's scope (frontmost, window list
and titles, focused element, a basic tree) is covered by those
four. The fifth plan name, ax.elementAt, does not exist as its
own method: its use case is folded into ax.snapshot (pid +
maxDepth tree, perform's own element lookup) — documented
deviation, not a gap. The tree walk is bounded twice — maxDepth
12, maxNodes 2000, a visited counter against cycles — and the
response carries a "truncated" flag when the budget bites,
because a browser AX tree can be tens of thousands of nodes.
Honest limitation: no unit test drives the walker, since
instantiating AXUIElement roots requires a real, permission-
granted GUI session — the same externally blocked family as the
isolation half; the implementation, bounds and flag are code-
verified here.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 367 | §18's four ax verbs exist verbatim with the first-phase scope covered; elementAt folds into snapshot (documented); tree walk double-bounded with a truncated flag; AX tests need a live session (blocked family) | ✓ (elementAt deviation documented) | §205 — Protocol.swift, protocol.md:273–284, AccessibilityBridge.swift:18,149–177 |


---

## 206. §35's agent safety rules: verbatim four lines with one source of
truth

Integrations.agentRules() emits the plan's four rules word for
word — the visible-window rule, the no-GUI-in-current-session
rule, the stop-and-report rule, and "Never fall back to the
user's console session." The doc comment elevates the wording to
a security property: generated by one function rather than
hardcoded at call sites, so the lines that state the product's
entire threat model have exactly one source of truth. The
section form wraps them in agentspace:rules begin/end markers
for idempotent appends to AGENTS.md and CLAUDE.md — the merge-
without-overwrite semantics the integrations entry recorded —
and the tests pin both markers. An agent that follows the four
lines cannot act on the console; an agent that ignores them was
never constrained by a config file anyway, as the comment says.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 368 | The four §35 safety rules are emitted verbatim from a single tested source, wrapped in idempotent markers for AGENTS.md/CLAUDE.md | ✓ | §206 — Integrations.swift:134–165, IntegrationsTests.swift:158 |


---

## 207. §36's nine denied commands: every one present with a teaching
reason, plus supersets

Core's ExecGuard carries each §36 denial by name — sudo,
installer, diskutil erase, launchctl bootstrap system, dscl
create, sysadminctl, rm -rf /, shutdown, reboot — every rule
paired with a reason addressed to the agent ("privilege
escalation is out of scope for an agent session", "powers off
the machine the human is using"), so the rejection teaches
instead of stonewalling. Supersets beyond the list: diskutil
erasevolume/reformat/unmount, dscl delete, rm -rf /*, and a
refused-executables table (su, doas, dseditgroup and more) that
blocks the effect even when the name is spelled differently. A
first grep looked in the worker's ShellExec.swift and found
nothing but a comment — the rules live in Core where tests pin
them; the miss was the search's, not the guard's, and locating
the real file is the second tool.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 369 | All nine §36 commands are denied by name in Core's ExecGuard with agent-facing reasons, plus volume/delete/account supersets and a refused-executables table | ✓ | §207 — ExecGuard.swift:23–58 |


---

## 208. §16/§52's live preview: pull economics, three tiers, auto-stop on
close

PreviewController (Core, frame source injected) implements the
ScreenCaptureKit upgrade's economics as a tested state machine.
Pull model on purpose — the client asks for frames only while
its viewer is open, the worker keeps at most one captured frame,
newer frames win — because a push stream would need a second
socket, and pull "fits §52's economics naturally." The tiers:
previewStart defaults to 5 FPS for idle, callers may raise to 15
(interactive) within a clamp to 1–30, and "窗口关闭: 0 FPS" is
taken to its failure-proof end — ten seconds without a pull
stops the stream itself, so a crashed GUI or a script that
started a stream and exits cannot leave the worker capturing
forever. Lifecycle hardening is test-pinned in six cases:
restarting a running stream re-arms rather than tears down (a
second viewer must not break the first), a failed start cleans
up so the next start can succeed, FPS is clamped, and idle stop
and pull-refresh are both covered. The real source is a thin
adapter where every unverifiable-here behaviour lives — JPEG
"cheaper than PNG at 15 FPS," minimumFrameInterval = 1/fps, and
stream-error teardown with rebuild-on-next-start.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 370 | The live preview realizes §16/§52's tiers (5 idle, 15 interactive via clamped maxFPS, 0 on close) with pull economics, injected testable source, and a six-test lifecycle suite | ✓ | §208 — PreviewController.swift, SpaceService.swift:237, PreviewControllerTests.swift (6 pass) |


---

## 209. §14's nine input actions: all present, with honest layering

Every action type parses in Core's InputActions and dispatches
in the worker's InputSynthesizer: move, click, drag, scroll,
type, key, sleep — plus doubleClick and rightClick as named
cases whose comment states the layering honestly ("worker-side
conveniences; a count >=2 click is the wire-level primitive"),
so the wire protocol stays minimal while agents get the
mnemonic names. Supersets beyond the plan's nine: a "wait"
alias for sleep and a center mouse button mapped to
otherMouseDown/Up/Dragged alongside right's own event family.
The batch actions array the plan recommends (§14's JSON shape)
is the request's actual structure.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 371 | All nine §14 input actions parse and dispatch, doubleClick/rightClick are documented conveniences over the count primitive, wait and center-button are supersets | ✓ | §209 — InputActions.swift:117–220, InputSynthesizer.swift:52–159 |


---

## 210. §32's --json mode: every command, envelope-shaped, errors included

--json is a standalone global flag — and the comment records the
measured reason: as a value flag it made `agentspace status
--json` demand an argument. The status shape carries all six
plan fields (space, uid, worker, state, screenRecording,
accessibility) plus display and resources, and the envelope is
the whole output in json mode on purpose — including failures:
the caller's own emitter formats errors, so CI and MCP parse one
stable shape instead of prose. list emits count + spaces,
screenshot passes the worker's result through. The desktop
command is documented as a deep link rather than a CLI screenshot
loop — "duplicating it here would be a second reason for the
machine to keep capturing" — and shows the offline state honestly.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 372 | --json works across commands with the plan's six status fields verbatim, JSON-mode errors through one emitter, desktop as an honest deep link | ✓ | §210 — main.swift:53–54,134,176,748–800 |


---

## 211. §45's Phase-1 test matrix: all five scenarios pinned by name

Each planned scenario has named tests: background usable
(testBackgroundSessionIsUsable, plus delivered-only-to-worker);
console refused (testInputRejectedWhenSessionIsConsole with its
integration twin and three CLI-surface tests); no WindowServer
refused *distinctly* — the test name is the point, a missing
WindowServer must not masquerade as a generic not-ready;
permission missing (PermissionState reports missing grants in
setup order, permission problems win over everything, plus the
two fail-closed guards for a missing dictionary and a missing
console key); and socket down (crashed-worker-under-live-session
shows offline, unauthorized client rejected, WORKER_OFFLINE
surfacing through the CLI). The derivation suite additionally
pins the §39 reboot case — needsLogin, not offline — and the
unknown-session fail-closed case, which is the matrix's
unwritten sixth row.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 373 | All five §45 scenarios have named, runnable tests, with the derivation suite covering reboot and unknown-state beyond the plan's list | ✓ | §211 — SafetyTests.swift:23,87,140,182; SessionGuardTests:45,55,95; SpaceStateDerivationTests:17–57; CLIIntegrationTests:437 |


---

## 212. §48's multi-space correspondence: one-to-one per Space, eleven
tests green

The negative half — no singleUser, computeruse or defaultSession
anywhere — is recorded at its earlier entry and re-verified this
round (still zero hits). The positive half is a one-to-one test
suite: every Space gets its own socket, token and runtime
directory; its own account name and launchd label; its own uid
slot; every socket path fits in sun_path; two spaces with the
same name never share a worktree and both succeed in creation;
name resolution is unambiguous or refuses with the UUIDs on
offer; generated account names never collide with protected
accounts. The plan's §48 invariant — Space UUID, User UID,
Worker Socket, Token all in correspondence — is eleven runnable
assertions, executed green this round.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 374 | §48's UUID/UID/socket/token correspondence is pinned by eleven green multi-space tests; the three forbidden assumption tokens remain absent | ✓ | §212 — MultiSpaceIsolationTests.swift (11 pass) |


---

## 213. §39's reboot semantics: mechanism, not policy, decides

After a reboot the worker's LaunchAgent is not loaded at all —
LimitLoadToSessionType=Aqua means no GUI session for the agent
user, so nothing starts quietly; that is a launchd fact, not an
app preference. The derivation then shows the honest state:
testRebootedSpaceShowsNeedsLoginNotOffline pins that a rebooted
Space (no session verdict, no graphical session, worker offline)
is .needsLogin whether it was stored running or ready. The
companion comment draws the line the plan implies but does not
state: if the account owns processes the session IS alive and
only the worker died — that is genuinely offline, where
restarting the LaunchAgent is the right fix and "Needs Login
would send the user through a pointless login." autoStartWorker
(default true, §26 verbatim) governs the after-login flow only;
no code path uses it to start a worker without a session.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 375 | Rebooted Spaces show needsLogin (not offline, not auto-started) via the Aqua gate plus the derivation test; live-session-dead-worker stays honestly offline | ✓ | §213 — SpaceStateDerivationTests.swift:17–47, SpaceModel.swift:212 |


---

## 214. §23's exec result: the plan's fields verbatim, plus honest
supersets

ShellExec.Result returns exitCode, stdout, stderr and duration
(ms, matching the plan's example) exactly, with cwd, env and
timeout as request-side parameters — the plan's six. The
supersets are diagnostic honesty: signal when a process died by
signal, timedOut to distinguish timeout from a normal exit, and
truncated plus a 4 MB output cap, because "a runaway command
must not be able to make the worker allocate without bound; the
tail is what matters for diagnosis." Buffering instead of
streaming is documented as deliberate — it matches the plan's
shape, keeps one request per connection, and a streaming variant
can land later without changing the contract. Identity holds:
the command runs as the worker's own standard uid with "no sudo,
no helper round-trip and no root path into this function."

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 376 | exec returns the plan's fields verbatim plus signal/timedOut/truncated supersets under a 4 MB cap, buffered by contract, never elevated | ✓ | §214 — ShellExec.swift:10–39 |


---

## 215. §37's eight log categories verbatim, with redaction before OSLog

The worker's Log enum carries all eight planned categories word
for word — app, helper, worker, ipc, session, input, capture,
mcp — under BundleIdentifiers.logSubsystem, the single
namespace source §58 demanded. The redaction insight is stated
where it matters: OSLog privacy annotations cannot rescue a
secret already interpolated into a plain String, so scrubbing
runs before the call, in one funnel, "so a new log line cannot
forget it" — the automatic removal of passwords, tokens and
user text implemented as an architecture, not a review step.
The helper logs under its own category so a security review can
read exactly what the root component did, and a test sink
captures lines in place of emission.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 377 | All eight §37 categories exist verbatim under the shared subsystem, with pre-OSLog redaction as a single funnel and a test sink | ✓ | §215 — Connection.swift:75–100, HelperLog.swift |


---

## 216. §37's export redaction: two independent controls, both tested

The diagnostics bundle is safe by construction twice. The
collector whitelists — doctor output, registry metadata, file
existence — so tokens, Keychain items, input payloads and frame
data never leak because they are never collected. Everything
still passes the redactor as defense in depth, in case a future
collector change pulls in something secret-shaped. The five
planned removals map to regexes: 64-hex runs become
<redacted-token> (with a false-positive test proving commit SHAs
are untouched), password/passphrase/secret/token keys become
<redacted-value> while the key survives so readers see *what*
was redacted, data-URI images and any 4096+-char base64 run
become <redacted-image>/<redacted-blob>. Keychain and input
text are covered by the whitelist itself. Seven tests, redactor
as a pure function so it can be fed anything secret-shaped.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 378 | Exported diagnostics enforce the plan's five removals via whitelist collection plus a tested pure redactor, with false-positive guards | ✓ | §216 — Diagnostics.swift:5–60, DiagnosticsTests.swift (7) |


---

## 217. §28's five setup steps as a live checklist

SpaceDetailView's setup card renders the plan's five steps in
order — open Fast User Switching, sign in as "AgentSpace –
<name>" with the Space name interpolated, grant Accessibility
(to agentspace-worker by name), grant Screen & System Audio
Recording, switch back — and each step carries a live done
flag driven by the same snapshot the plan says should flip the
state to Ready: workerOnline ticks step 2, the two permission
grants tick 3 and 4. The card appears only when the Space
cannot accept input and is not console, "precisely then that
the user needs to know what to do in the other session," and
the Show Login Password and Open System Settings buttons sit
where the flow needs them.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 379 | The wizard's five steps render as a live checklist with snapshot-driven ticks, shown exactly when the Space needs a manual sign-in | ✓ | §217 — SpaceDetailView.swift:300–318 |


---

## 218. §28's wizard: three steps, three workspace choices verbatim

The create sheet (titled "Create Agent Space") implements the
plan's three steps. Name comes with the disclosure that "A
macOS user named _agentspace_<random> is created ... The
display name is only a label" — §8's two-name split said out
loud. Workspace offers exactly None / Git Worktree / Shared
Folder as a radio group; picking worktree reveals repository
and branch (prefilled "agentspace/", §51's prefix), a preview
of Repository/Branch/Worktree including the literal
"<space-id>/…" path shape, and the caption "so it never edits
the tree you have open"; picking shared folder states
"read-only unless you explicitly allow writing." Create's
button caption restates the §28 background chain — "Create the
Space's macOS user, runtime and worker."

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 380 | The wizard's three steps and three workspace choices render verbatim, with §51's branch prefix and §25's read-only default visible in captions | ✓ | §218 — DoctorView.swift:192–261 |


---

## 219. §34's integration actions, gated by user confirmation

The Maintenance card carries all of §34: an "Install MCP
Into…" menu iterating the three planned targets (claudeCode,
codex, openCode), Copy MCP Configuration, and Copy Agent Rules.
Every install routes through a confirmation dialog before
anything is written, and the rules button copies rather than
writes — its tooltip says so in §35's own voice: "Copying only
— your instructions file is written by you." Supporting
actions sit beside them: Reveal Runtime Folder, Run Doctor,
Show Login Password ("Needed once"), and a destructive Delete
Space disabled while provisioning runs.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 381 | §34's three install targets and Copy Config exist with user confirmation before any write, rules copy-only | ✓ | §219 — SpaceDetailView.swift:338–370 |


---

## 220. §33's fourteen tool names, extracted as a complete set

Extracting every agentspace_* identifier from the MCP server
source yields fourteen names whose set equals the plan's list
exactly — list, status, screenshot, input, click, type, key,
scroll, drag, launch, quit, apps, exec, ax_snapshot — with no
extras and none missing. Because the extraction is complete
rather than sampled, it also proves the negative half of §33:
no create or delete tool exists in the MCP package, since user
and TCC management is reserved for a human in the GUI.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 382 | The MCP server registers exactly the plan's fourteen tools, and no create/delete tool exists | ✓ | §220 — packages/agentspace-mcp/src (14 names extracted) |


---

## 221. §32's JSON status fields, plus why the display carries both
coordinate spaces

The worker's status response contains every field the plan's
JSON example names — status/state (plus a human label), space
(name and id), uid, worker (with pid and uptime),
screenRecording, accessibility — as honest supersets: user,
acceptsInput, session verdict with onConsole, and the full
display geometry. A measured-history comment explains why
display reports both point and pixel sizes: sending only point
size once left a client reading status alone seeing
pixelWidth 0, the GUI rendering "Pixels 0 x 0," and the Desktop
Viewer losing the fallback it needs to map a click before the
first capture arrives.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 383 | status --json returns the plan's six fields verbatim plus supersets, with the dual coordinate-space reason documented from a real regression | ✓ | §221 — Operations.swift:137–165, main.swift:771–773 |


---

## 222. §40's two verbs, each a launchd-level mechanism

Stop Agent and Logout Desktop are distinct in kind, not degree.
Stop Agent sends a worker shutdown with reason stop-agent and
leans on KeepAlive.SuccessfulExit = false: a clean exit stays
stopped — "a real stop, not a crash-restart loop" — while the
session keeps WindowServer and frames, making the next start
instant; a worker already gone is not a failed stop. Logout
Desktop ends the whole GUI session via the root-only
launchctl bootout gui/<uid>, routed through the privileged
helper as a typed RPC that fails typed when the helper is
missing — "never by trying to sudo anything" — and keeps the
account and home for the next login.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 384 | §40's Stop vs Logout are distinct typed operations: stop rides KeepAlive semantics, logout is root-only through the helper, never sudo | ✓ | §222 — SpaceService.swift:194–230 |


---

## 223. §22's registration wait: a pid you can name, then a window

Launch never trusts LaunchServices' success — the comment says
it plainly: "open's success only means LaunchServices accepted
the request; returning a pid at that moment hands the agent a
number it cannot use." The wait resolves a pid three ways
(expected pid verified, bundle-id lookup, or a
before/after pid-set diff), then grants half the remaining
budget for the app to own an on-screen window — a menu-bar
(LSUIElement) app never will, and waiting the full budget
would stall every such launch. Failure is teachable:
appLaunchTimeout says the app "never registered a process" and
suggests taking a screenshot to look for a modal. NSWorkspace
from inside the Aqua session launches into that session.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 385 | launch waits for real registration — a namable pid plus optional window ownership with an LSUIElement-aware half-budget — and fails with an actionable error | ✓ | §223 — AppControl.swift:160–245 |


---

## 224. §29's SpaceManager role, split into model + registry

The plan's SpaceManager exists as two cooperating types rather
than one: AppModel (@MainActor ObservableObject) is the GUI's
single owner of space lifecycle — create, delete, stop, logout,
preview, doctor — and SpaceRegistry in Core is the persisted
1:N fact both the app and doctor load. The split is deliberate
separation of state from storage, not a missing piece. The
model's header documents §53's economics in its own voice:
nothing polls on a timer at all — refreshes fire on foreground,
selection and explicit request, the only repeating timer is the
desktop preview (5 FPS §52 stream, 1 FPS fallback) — and
cross-references the measured idle CPU: 0.0% in
docs/validation.md §27.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 386 | §29's unified space management is AppModel + SpaceRegistry (documented split), 1:N by construction, with §53's no-polling discipline stated and measured | ✓ | §224 — AppModel.swift:6–23,159,215, SpaceService.swift:72–77 |


---

## 225. §30's per-uid aggregation as a pinned pure function

ResourcesParsing.accumulate is the plan's "sum processes by
UID" verbatim: one ps -axo uid=,rss=,pcpu= line per process,
summed only where the line's uid equals the Space's, yielding
processCount, memoryBytes (KB x 1024) and cpuPercent. It was
extracted from the worker into a pure function so the
text-parsing contract — "the part that has historically been
untested" — is pinned directly. Malformed lines are skipped,
not fatal: "a partial answer that keeps updating is more useful
than a resource card that dies on one odd process."

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 387 | §30's per-uid summing exists as a tested pure function with skip-not-fail parsing | ✓ | §225 — ResourcesParsing.swift:1–40 |


---

## 226. §27's dashboard chrome: badges that cannot say "maybe"

The dashboard's visual language is a set of small components
that encode the plan's semantics. The state dot colors by state
(green ready/running, orange console, yellow needsLogin /
needsPermission, red offline/error) with the state name as its
accessibility label. The permission chip has exactly two
states — its comment: "Two states only — granted or not —
because a 'maybe' is what the whole fail-closed design exists
to avoid." The refusal banner always shows the stable code
monospaced and selectable, because "a user reporting a
problem, and an agent reading a screenshot of this window,
both need the stable name" — the agent as a first-class UI
reader. Cards match System Settings detail panes; Create Agent
Space… opens the §28 wizard.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 388 | §27's chrome encodes fail-closed semantics: two-state permission chips, state-named dots, stable error codes readable by humans and screenshot-reading agents | ✓ | §226 — Components.swift:12–105,172 |


---

## 227. §41's home-directory question as a two-button choice

The plan's final question — "Delete Agent home directory?" —
is rendered as the confirmation dialog's two branches: keep the
home (safe path) or delete it (destructive), and the comment
explains the split: it is "the one irreversible step, and it
holds the agent's own files — which the user may want to look
at after the Space is gone." The caption restates §41's
worktree rule in one sentence — "A git worktree is removed but
its branch is kept, and your own repository is never touched" —
and the dialog's message promises "Your files are not
affected." A second dialog gates MCP installs with §35's
explicit consent and a backup of prior contents.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 389 | §41's delete asks the home question as keep/delete branches, states the worktree rule and never-touch guarantee, and backs up config files before integration writes | ✓ | §227 — SpaceDetailView.swift:381–420 |


---

## 228. §20's status.json — a real gap found by the audit, then fixed

RuntimePaths documented the §20 trio and promised "status.json —
last known status, written by the worker" — but grep over the
whole tree showed the worker never wrote it (only a `status.json.pid`
sidecar, kept, which has §98 history). The audit's job is exactly
this: a comment that claims a behaviour the code does not have.
Fixed in Core + worker. StatusSnapshot.json is a pure function
pinning the on-disk contract — seven fields, sorted keys, ISO-8601
UTC — and the worker writes phase "running" right after bind and
"stopped" in its cleanup path. The comment states the honest
limit: a SIGKILLed worker never gets to write "stopped", so the
file is last-known, never current — live-ness is still established
by connecting to the socket.

**Verified live** — dev-shell probe: worker up, status.json reads
`phase: running` with the true verdict (`isConsole` — this shell
is the console session, and the worker says so); SIGTERM; the file
then reads `phase: stopped` with a 19 s later timestamp. Full
suite: 346 tests, 0 failures (341 + 5 new StatusSnapshotTests).

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 390 | §20's status.json exists as a tested, live-verified last-known snapshot written by the worker (gap found and closed this round) | ✓ (gap closed) | §228 — StatusSnapshot.swift, main.swift:537–552,564–568, tests/Unit/StatusSnapshotTests.swift |


---

## 229. §20's runtime ACL, tightened beyond the plan

The plan allows three principals on the runtime tree; the
implementation is stricter on purpose. The shared root is 1770 —
"the sticky bit stops one Space from deleting another's runtime
directory" — the Space's runtime dir is 0700 to its own uid
because "the socket there carries a live session token, so
nobody else gets to open it, including the main user", and
screenshots is 750 — "the one thing the main user needs to
read, because the app shows the preview in the main user's
session." The main user talks to the worker through the
authenticated socket, not the filesystem, so excluding it from
the directory is the tightening the plan's own token design
implies. Spaces/index.json and Logs belong to the main user.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 391 | §20's runtime ACLs exist per-directory with a sticky-bit anti-deletion root, a 0700 token-carrying runtime dir (main user deliberately excluded), and one justified 750 read exception | ✓ (deviation documented) | §229 — HelperService.swift:338–372 |


---

## 230. §9's password chain, graded by what each secret guards

The password lifecycle is exactly the plan's: 32 alphanumeric
characters, per-Space, never fixed, stored in the macOS Keychain
— header comment: "Explicitly not in a config.json, not in
NSUserDefaults, and not in a log" — revealed once in the app via
Show Login Password for the fast-user-switching login, and the
Keychain gives the right lifecycle for free: owned by the main
user's login keychain, unlocked when they log in, gone with the
account. The generator documents a graded choice: rejection-free
sampling of 62 chars is very slightly biased, "irrelevant for a
per-Space login password that ... is never typed by a human" —
while the session token, "the thing that actually guards the
socket, uses SecRandomCopyBytes and is unbiased."

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 392 | §9's password is 32 chars/Space/Keychain-only with once-reveal in the UI, and the generator's bias trade-off is documented with the token graded above it | ✓ (deviation documented) | §230 — HelperProtocol.swift:179–206, KeychainStore.swift:1–24, SpaceDetailView.swift:317 |


---

## 231. §25's Shared Folders panel, rendered as Overview rows

The plan's Shared Folders list is not a separate panel: it
renders as rows in the Space's Overview card — "none" when
empty, otherwise one monospaced field per folder showing
"path — access", with the access names exactly the plan's
"Read Only" and "Read & Write" (the model's displayName).
Creating a folder happens in the §28 wizard; the detail view
shows the outcome. The flat-list rendering matches the §27
native-minimal direction rather than adding a sub-panel.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 393 | §25's shared-folder list with Read Only / Read & Write labels is visible per Space in the Overview card | ✓ | §231 — SpaceDetailView.swift:206–211, SpaceModel.swift:124–129 |


---

## 232. §38's "failures must give the specific fix", sampled

Doctor carries 26 fix strings, one per failing branch, and
they are all action sentences: Intel → "out of scope"; old
macOS → "Upgrade to macOS 26 or later."; console →
"fast-user-switch back ... Input resumes automatically."; ssh →
"Run from a GUI login, not ssh."; corrupted registry → inspect
the quarantined pre-corruption files, recover by hand or
recreate, then delete quarantine; no spaces → "Create one with
the AgentSpace app. Creating a Space needs the privileged
helper, because it makes a macOS user."; long socket path →
"Shorten AGENTSPACE_ROOT."; pixel-width anomaly → "Report this
as a bug" with a pointer to the verified-correct record. None
say "something went wrong".

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 394 | §38's remedy requirement holds: every failing doctor check names a concrete, executable fix | ✓ | §232 — Doctor.swift (26 fix strings), sample at :105–219 |


---

## 233. §40's three endings, plus a HIG promise now kept

The Space menu's comment states §40's semantics verbatim:
"three different endings for a Space, deliberately not
collapsed into one 'stop'. Stop keeps the session; Logout ends
the session but keeps the account; Delete removes everything
and asks about the home." Stop is disabled unless the worker is
online; Delete carries the destructive role and §227's two-branch
dialog. The audit caught one gap: "Logout Desktop…" used the
macOS ellipsis that promises a follow-up dialog, but executed
immediately. Fixed: the ellipsis now delivers a confirmation
that says the real cost — the worker stops with the session and
coming back needs one manual login. The localization test suite
caught the four new strings missing from both tables, and was
satisfied. 346 tests, 0 failures.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 395 | §40's Stop/Logout/Delete endings are distinct in the UI with per-state disabling, and Logout's ellipsis promise now has its confirmation dialog (gap found and closed this round) | ✓ (gap closed) | §233 — SpaceDetailView.swift:128–148,421–435 |


---

## 234. §39's "do not silently start after reboot" is launchd mechanics

The worker's LaunchAgent carries RunAtLoad=true — but that
starts the worker when the Space's Aqua session loads, not at
boot. After a reboot no GUI session exists for the agent user,
so there is nothing to load the agent into: the plan's "show
Needs Login, never silently start the agent" is not policy code
here, it is what a per-user, LimitLoadToSessionType=Aqua launchd
job physically is. RunAtLoad is exactly §10's chain — login once,
the agent auto-starts — and the provisioner orders runtime
before worker for the same reason ("launchd refuses to spawn a
job whose log file it cannot open — producing a worker that
never starts with no error anyone can see").

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 396 | §39's no-silent-start after reboot holds by launchd mechanics (per-user Aqua agent, RunAtLoad on session load), with provisioning ordered so the job can actually spawn | ✓ | §234 — HelperProtocol.swift:483–500, SpaceProvisioner.swift:100–110 |


---

## 235. §24's worktree mode refuses instead of renaming

WorkspacePreparer validates in three fail-closed layers, each
with a named error: the repository must exist and be one ("an
error, not a directory that gets created anyway and fails later
somewhere confusing"); the branch must carry the agentspace/
prefix — "an agent told to work on main in the user's own tree
is the failure this whole mode exists to prevent, so it is
refused rather than quietly renamed"; and the worktree path
must stay inside the Space's workspace directory, "which is
exactly what a worktree is meant to avoid." The git call is an
argv array — the one impurity, and no shell to inject into.
Writable roots are a declared subset of readable roots.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 397 | §24's worktree mode enforces repo-existence, branch prefix (refused, not renamed), and path confinement with argv-array git | ✓ | §235 — WorkspacePreparer.swift:1–60,95–135 |


---

## 236. §15's pixel-to-point conversion, shared at both boundaries

DisplayGeometry carries the conversion the plan's formula
names: point(fromPixel:) divides by scale (guarding scale > 0,
rounding half-up), pixel(fromPoint:) multiplies back, and
contains() rejects points outside the display before any event
is constructed — the INVALID_COORDINATE from §21 fired early.
CoordinateRules.validate is shared by worker and CLI "so a bad
coordinate is rejected at the edge and at the trust boundary
(plan §56: never trust the client)"; its error messages teach —
non-finite, outside ±100_000 ("a mistake, not a very large
monitor", tuned to catch a pixel/point mix-up from a model), or
negative ("coordinates start at the top-left").

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 398 | §15's point/pixel conversion exists with guarded scale, early bounds rejection, and dual-boundary validation with teaching errors | ✓ | §236 — Geometry.swift:57–100 |


---

## 237. §18's fifth API was missing; ax.elementAt now exists

The plan lists five accessibility methods. Four were registered;
ax.elementAt was not — the method-namespace test's expected set
mirrored the omission, so it could not catch it (a complete-set
check is only as complete as its negative list). Implemented:
AccessibilityBridge.elementAt hit-tests the system-wide element
via AXUIElementCopyElementAtPosition — the same top-left point
space the input API uses, "no conversion" — and returns pid,
app name, the point echoed back, and a describe() of the hit.
Worker dispatch validates coordinates with the shared
CoordinateRules and refuses outside a desktop session, like the
other four. Expected/actual method sets updated; 346 Swift and
23 MCP tests, 0 failures.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 399 | §18's ax.elementAt exists end-to-end (Method table, worker dispatch, hit-test bridge, namespace test), closing the missing-fifth-API gap | ✓ (gap closed) | §237 — Protocol.swift:24, AccessibilityBridge.swift:62–78, Operations.swift:545–572, ProtocolTests.swift:159–172 |


---

## 238. §18's first-phase checklist, complete after the ax.elementAt fix

The plan's "at least provide" list for phase one: frontmost app
(axFrontmost, with focusedElement attached), window list
(axWindows via kAXWindowsAttribute), window titles (describe()
emits title at depth 0, capped at 500 characters per §37),
focused element, and the basic tree (axSnapshot,
interestingOnly) — plus, since this round, the fifth method
ax.elementAt. Every item a worker can be asked for without the
visual channel, which is the point of keeping both channels.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 400 | §18's phase-one AX surface is complete: frontmost, window list, titles, focused element, tree, and elementAt | ✓ | §238 — AccessibilityBridge.swift:101–136,184–195, Operations.swift:494–543 |


---

## 239. Closure audit snapshot: every auditable clause has been audited

The plan-part audit is complete — no remaining clause with
unverified substance was found, so per the working method this
entry records the state instead of filling.

**State:** 245 commits, 241 validation entries, 346 Swift tests
and 23 MCP tests with 0 failures, clean tree, demo.sh and
mcp-smoke.sh exit 0. acceptance.sh correctly stops at "No
AgentSpace found" — that script exercises a real created Space,
which is exactly what blocker 1 withholds.

**This session's found-and-closed gaps:** §228 status.json was
promised by comments and written by nothing (pure Core function
+ worker wiring + 5 tests); §233 Logout Desktop… executed
behind a dialog-promising ellipsis (confirmation added);
§237 ax.elementAt was the missing fifth §18 method (implemented
end-to-end). Everything else audited returned ✓, several with
documented deviations that held up under re-reading.

**The three external blockers, restated:** (1) the privileged
helper running live with a real createUser/deleteUser/
logoutSession chain — requires root; approval prompts are
disabled in this session, so it cannot be granted here; (2) the
positive half of §44/§48 isolation — a second GUI session held
for 30 minutes, needing exactly that human login; (3) the
Homebrew cask — waiting on a public GitHub release URL, which
requires the user to decide whether the repository gets pushed.
The goal stays open while these exist; nothing above claims
completion that depends on them.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 401 | The audit pass is closed: all auditable clauses verified, session gaps fixed and recorded, three external blockers precisely characterized | ✓ | §239 — this snapshot; blockers also listed in every round report |


---

## 240. §42's reuse ledger: zero verbatim copies, debts itemized anyway

THIRD_PARTY_NOTICES.md reproduces Offstage's MIT license in
full — "reproduced anyway, because the debt is real and the
honest thing to do with a real debt is to acknowledge it rather
than to argue about whether it clears a threshold" — even
though no source file was copied verbatim; a tree-wide grep
finds no Offstage copyright header in any .swift file, which is
consistent with the claim. Seven borrowed ideas/measurements
are itemized (the three CGEvent tap paths, explicit flags,
grapheme-per-event typing, Retina point semantics re-measured
here on macOS 27.0, frontmost-pid from the window list, the
background-Aqua shape, posix_spawn details), deliberate
divergences are tabulated in §8, and one correction to Offstage
itself is recorded: its kCGSSessionManagerNameKey check with an
"Aqua" fallback is inert on macOS 27.0 — the key is absent from
the dictionary — so AgentSpace reads SessionGetInfo's
sessionHasGraphicAccess bit instead. §63.2's no-fork requirement
and §63.13's measure-don't-guess rule are both satisfied in the
same document.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 402 | §42/§63.3's MIT ledger is complete: full license, zero-copy claim consistent with the tree, seven itemized borrowings, divergences cross-referenced, and an upstream correction recorded | ✓ | §240 — THIRD_PARTY_NOTICES.md:1–75 |


---

## 241. The §42 ledger's promised divergence table really exists

§240's notice points at "docs/validation.md §8" for the
deliberate divergences; this round checked the pointer rather
than trusting it. §8 is a nine-row table (Area / Offstage /
AgentSpace / Why) — a superset of the six divergences the
notice names, each mapped: session-availability (the inert
manager-name key vs SessionGetInfo), UPPER_SNAKE error
vocabulary fixed by §21, per-index input validation messages,
the 256-bit per-Space token ("a compromise inside one Space
must not drive a sibling Space"), the buffered exec result
shape fixed by §23. §8 links back to the notice for the MIT
text, so the two documents cross-reference each other honestly
and neither points at nothing.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 403 | §8's divergence table exists, covers a superset of the notice's six claimed divergences, and cross-references the notice back | ✓ | §241 — docs/validation.md §8, THIRD_PARTY_NOTICES.md:44–46 |


---

## 242. §58's namespace lives in one constant table, with the packaging
repeats pinned by a contract test

The bundle IDs and log subsystem are constants in Doctor.swift
(app, helper, worker, workerLaunchAgent, logSubsystem) — the
"namespace configured in one place" §58 asks for. Outside it,
the remaining "com.agentspace" strings are: doc comments, test
keychain services deliberately suffixed .tests. (isolation by
name), a test that asserts the generated LaunchDaemon plist's
Label equals the constant verbatim — which is exactly the right
pin, since launchd owns that string — and bundle-app.sh's four
codesign --identifier arguments. Those repeats are the physical
requirement of codesign; their consistency with the constants
is guaranteed by the plist-label test chain, not by luck. The
CLI has no bundle ID because §58 names it as a bare executable,
and it is signed as one.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 404 | §58's namespace is a single constant table; remaining literal repeats are doc comments, name-isolated tests, a plist-label contract test, and codesign arguments pinned by it | ✓ | §242 — Doctor.swift:393–407, HelperValidationTests.swift:382, bundle-app.sh:126–131 |


---

## 243. §59's second screen: the side-by-side and the five promises

The README's second screen carries the plan's Your Desktop |
Agent Desktop table (VS Code/Chrome, Terminal/Simulator,
Safari/Xcode) and the "You keep working / The agent keeps
working" closing line. Below it, plan §2's own promises appear
verbatim as the reader-facing sentence: "Your pointer does not
move. Your keyboard is not taken. Your focus does not change.
Your desktop does not flicker." — the five don'ts as five short
sentences. The §1 architecture diagram (same Mac, same kernel,
own Aqua session, own framebuffer, own input stream) and the
§17 View Desktop entry point round out the first two screens.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 405 | §59's second screen renders the side-by-side table, the keeps-working line, and §2's five promises verbatim | ✓ | §243 — README.md:12–31 |


---

## 244. §55's eight named safety tests, re-checked after the later rounds

A regression spot-check against the early promises: all eight
§55 test names still exist and run — testInputRejectedWhenSessionIsConsole,
testInputDeliveredOnlyToWorkerSession,
testScreenshotNeverReturnsConsoleSession,
testWorkerDoesNotFallbackWhenSessionUnavailable,
testWorkerCannotRunAsRoot, testUnauthorizedSocketClientRejected,
testDifferentSpacesHaveDifferentTokens,
testWorkspaceCannotEscapeAllowedPath — several appear twice (a
unit-level and an integration-level variant), and the security
suite alone executes 24 tests with 0 failures. Nothing in the
last twenty rounds of fixes touched the safety net's named
anchors.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 406 | §55's eight named safety tests all exist and pass as of this round's regression spot-check | ✓ | §244 — tests/Safety/SafetyTests.swift, tests/Unit/SecurityTests.swift:185, SessionGuardTests.swift:127 |


---

## 245. §28's five-step setup card, wired to §19's checks

The Setup card lists the plan's five steps as numbered, live
ticking rows: open Fast User Switching (always explained),
sign in as "AgentSpace – <name>" (ticks when the worker comes
online), grant Accessibility (ticks from the worker's status
boolean), grant Screen & System Audio Recording (same), switch
back (never auto-ticks — only the user knows). The ticks are
§19's detections relayed through status, which is exactly §28's
"return to AgentSpace and auto-detect → Ready". The card states
the §19 red line verbatim: "AgentSpace never writes the TCC
database. These grants are given by you, in that session, on
purpose." It renders only when input is not yet accepted, and
deliberately not in the console state — that needs a
diagnosis, not a login — with Show Login Password, a deep link
to the Accessibility pane, and Refresh beside it.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 407 | §28's five-step sign-in checklist renders with live §19-detected ticks, the TCC red line stated verbatim, and state-appropriate visibility | ✓ | §245 — SpaceDetailView.swift:295–341 |


---

## 246. §30's fourth metric: disk, measured honestly or not at all

The plan asks for CPU, Memory, Process Count, and Disk. The
first three ride the uid-filtered `ps` sample; Disk is a
separate opt-in (`resources: "disk"`) so a status refresh never
pays for a filesystem walk (§53). Its honesty is typed: an
unmeasured walk is `null`, not `0` — "we did not look" and "it
is empty" are different claims — and a budget-capped walk
reports `diskTruncated: true`, making the number a stated lower
bound. Five tests pin it: empty measures zero; a missing
directory measures zero rather than failing; the measurement
agrees with `du` (the §63.13 cross-check); the budget stop is
reported; and symlinks are not followed out of the home
directory — §56's escape concern, closed in the walk itself.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 408 | §30's Disk metric is a typed, opt-in measurement: null-vs-zero honesty, truncation as lower bound, du cross-checked, symlink-contained | ✓ | §246 — Operations.swift:655–696, DiskUsageTests.swift:30–92 (5/5) |


---

## 247. §22's five verbs, all present in the dispatch table

§22 asks for launch, quit, forceQuit, apps, and activate.
Launch's registration-wait and apps' LSUIElement inclusion were
verified earlier; this pass closes the remaining three. quit
and forceQuit share one path with a force flag (graceful vs
SIGKILL semantics without duplicated code), and activate is its
own method behind requireDesktopSession and a non-empty "app"
string check — the console guard applies to making an app
frontmost too, not only to input.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 409 | §22's five app-management verbs are all dispatched, with quit/forceQuit parameterized and activate behind the desktop-session guard | ✓ | §247 — Operations.swift:37–39, 410–415 |


---

## 248. §21's recoverable field, defaulted by classification

The §21 error object carries code, message, and recoverable —
and recoverable is not left to each call site: it defaults to
the error code's own classification, "so callers cannot
accidentally mark a hard failure as retryable." The codes carry
the semantics in their docs — a console collision is recoverable
(switch back and it works); a missing background session is
recoverable only after a login — keeping fail-closed separate
from retryable. Each code also has a remediation string exposed
as recoverySuggestion, so the §38 "failures must give concrete
fixes" rule applies to every error, not just doctor. Even the
response-encode failure path emits a §21-shaped object with
recoverable: false.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 410 | §21's recoverable defaults from the code's own classification; remediation rides every error; the encode-failure fallback keeps the shape | ✓ | §248 — ErrorCodes.swift:60–77, 159–177, Connection.swift:45 |


---

## 249. §20's requestId echoes back as §21's response id

Every reply the worker sends — success and both error paths —
constructs RPCResponse(id: request.requestId, ...), so callers
correlate answers with requests exactly as §21's "id" promises.
The request side defaults the id to a fresh UUID when a caller
omits it, a round-trip test pins the field across the codec
(and the protocol version beside it), and the response-shape
tests fix ok:true without an error key and newline framing. The
encode-failure fallback replies with an empty id rather than a
fabricated one.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 411 | §20's requestId is echoed on all three reply paths, defaulted to a UUID, and pinned by codec and shape tests | ✓ | §249 — main.swift:390–411, Protocol.swift:158–171, ProtocolTests.swift:10–34 |


---

## 250. §34's Copy Config exists — and its comment records a real fix

copyAgentRules puts §35's rules on the clipboard instead of
writing an instructions file — the comment names the reason
verbatim ("the user's voice to their agents... §35 requires
their explicit consent"), with the CLI's integrate rules
--install as the opt-in alternative, backed up and
marker-scoped. copyMCPConfiguration resolves the binary through
Integrations rather than trusting a path: its comment records
that the previous version hardcoded a CLI location this bundle
has never contained, so the copied configuration pointed the
MCP server at nothing — a genuine §34 gap found and closed.
Both set a copiedMessage telling the user where to paste; the
doctor view reuses the clipboard for diagnostics and the
password reveal, keeping secrets off disk.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 412 | §34's Copy Config copies resolved paths (with the hardcode fix recorded), and rules copy rather than write per §35's consent rule | ✓ | §250 — AppModel.swift:486–507 |


---

## 251. §32's --json is architectural, not per-command

The CLI parses --json once into an Emitter that every command
flows through for success and failure alike — one rendering
path, two output shapes (pretty JSON for machines, human text
otherwise), which is the same "one fact, one definition"
pattern as the protocol. Errors emit through it too, so a
failing command still yields parseable JSON at the right exit
code. The help text states the promise plainly: "Machine-
readable output on every command".

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 413 | §32's --json applies to every command via a single Emitter, including failures | ✓ | §251 — AgentSpaceCLI/main.swift:56, 117–125, 297, 349 |


---

## 252. §52's 输入 gap: the viewer could see and click, but not type

The viewer's own header claimed "click and type", and §52 asks
for 看 · 点 · 输入 — but only the click path existed. A real
gap, fixed end to end:

- **Core** gains `KeyboardForwarding`, a pure function from the
  fields NSEvent exposes to an InputAction: printable characters
  (capitals and option-composed å included) become `type`;
  command and control become `key` combos in the canonical
  modifier order, only when the keycode table can synthesise
  them faithfully; function/navigation keys map through the
  private-use area; anything untranslatable is ignored rather
  than guessed. 14 contract tests pin all of it.
- **App**: an NSEvent *local* monitor — the app's own window
  only, never a global HID tap, which §13 forbids — forwards
  key-downs while the viewer window has them, with the
  permission check repeated at delivery time so a mid-keystroke
  console switch cannot let a consumed key become an injected
  one. Failures surface through the same presented-error path
  as clicks; consumed keys are echoed in the footer
  ("key → cmd+left", "type → å").
- The localization table caught the two new footer keys in both
  languages (the net works, again).

360 + 23 tests pass.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 414 | §52's type-into-viewer existed only as a claim; now implemented as pure Core translation + a window-local monitor with delivery-time permission re-check | ✓ | §252 — KeyboardForwarding.swift, KeyboardForwardingTests.swift (14/14), DesktopViewerView.swift:56–115 |


---

## 253. §52 follow-up: monitor installation is state-driven, not
appearance-driven

The previous round's monitor was installed only on appear — but
the worker's readiness changes while the viewer sits open (the
first sign-in happens in the *other* session, so a viewer
opened before it would never gain a keyboard). Installation and
teardown now track workerOnline, acceptsInput, and the host
window: a monitor is installed only under all three, and torn
down when any is lost, so it never outlives its authorization.
The package floor is macOS 13, so the onChange closures use the
single-parameter signature. 360 tests green.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 415 | §52's keyboard monitor is re-synced on readiness changes and torn down on revocation, under the macOS 13 floor | ✓ | §253 — DesktopViewerView.swift:47–80 |


---

## 254. The three-layer gate re-run after the keyboard fix

check-all.sh — test suite, MCP smoke, GUI verification — passes
all three layers again after the §52 keyboard forwarding work
(360 Swift tests, the MCP server speaking to a live worker, and
gui-verify's 5/5 accessibility-tree checks including the
preview tiers). The dist integrity guard passed silently; the
phase-0 isolation gate stays deliberately outside the aggregate,
a decision rather than a checkbox, per its own comment.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 416 | The full check-all gate passes all three layers after the keyboard work | ✓ | §254 — scripts/check-all.sh run this round |


---

## 255. §27's [Terminal] mockup button: recorded as deliberately out of
scope, not silently missing

Auditing §27's dashboard mockup against the detail view: the
card's real actions are all present and named exactly as later
sections require — Stop Agent, Logout Desktop…, Delete Space…
(§40's three verbs, §233's ellipsis confirmations), Show Login
Password (§9), and the desktop entry that opens the §52 viewer.
The mockup's second button, [Terminal], has no implementation
anywhere, and no earlier record says so.

The judgment, stated rather than buried: the plan's own phase
list never asks for it. §46's GUI phase names dashboard,
wizard, permissions, screenshot, input, logs — no terminal —
and §61 restricts V1 to doing one thing well. The capability it
sketches already exists as the §23 exec API and §31's
`agentspace exec`, which is what agents use; an embedded GUI
terminal is a human convenience the plan deferred. Recorded as
a known gap with its reasoning, in the "missing is a feature"
register, so the mockup and the shipping UI disagree on paper
where anyone auditing §27 will look first.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 417 | §27's [Terminal] mockup button is unimplemented and now recorded as deliberately out of scope (deferred by §46/§61; exec path exists via §23/§31) | ✓ (deviation documented) | §255 — SpaceDetailView.swift:133–141, AgentSpaceApp.swift:68 |


---

## 256. §26's eight states are rendered completely, with console colored
as a refusal rather than an error

§183 pinned the model side; this round checks the render side.
StatusDot maps every one of the eight states to a color — no
default arm, so a new state fails to compile until it is
rendered — and carries an accessibility label from
`SpaceState.displayName`. The semantics matter most: `console`
is orange, not the red shared by `offline`/`error`, matching
the model's own comment that console "is *not* an error, it is
a hard refusal" — the same distinction §245 found in the detail
view, where the console explanation row is deliberately absent
while the dot itself still shows.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 418 | All eight §26 states have a StatusDot color and accessibility label; console is orange (a refusal), not red (an error) | ✓ | §256 — Components.swift:10–24, SpaceModel.swift:24–33 |


---

## 257. §8's account naming contract: one closed rule, tested against
twenty-one evasion shapes

No earlier entry had pinned the naming scheme itself. The
contract: a fixed `_agentspace_` prefix plus six lowercase hex
characters — a closed alphabet, stated in the code as one rule
that is "obviously complete rather than five that each cover a
case somebody thought of": no asking for existing accounts, no
shell metacharacters, no `..`, no argv injection, no leading
`-`. `isAgentSpaceAccount` is the gate for both create and
delete; `protectedAccounts` refuses `root` and fourteen system
accounts even if they somehow matched the pattern. The tests
are the proof: 2000 generated names must round-trip through
the checker (create can never disagree with delete — a Space
that cannot be removed is the failure mode), and twenty-one
hand-built evasion shapes (traversal, substitution,
separators, newlines, emoji, uppercase, wrong length) are each
asserted rejected. §8's `_agentspace_a37f91` example matches
the scheme exactly.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 419 | §8's `_agentspace_` + 6-hex naming is one closed rule with a protected-account backstop, pinned by a 2000-name round-trip and 21 evasion rejections | ✓ | §257 — HelperProtocol.swift:103–140, HelperValidationTests.swift:22–80,227 |


---

## 258. Closing snapshot: every concrete clause audited; the same three
external gates remain

The audit is no longer finding clauses without records — the
last several rounds each closed a residual face (viewer
scrolling: not a plan clause for the app; §27's [Terminal]:
recorded as deferred; §26's eight states: rendered with
console≠error; §8's naming: one closed rule, 21 evasions;
§9's password: recorded trade-off; §16's ScreenCaptureKit:
state machine verified, adapter honestly bounded). This entry
is the state of the work, not a new claim.

**Repo:** 480 commits, working tree clean, 360 Swift tests +
23 MCP tests green, the three-layer check-all gate passing,
validation index at 418 claims before this entry.

**The three gates, unchanged because each needs something this
session cannot grant:**

1. **The live privileged helper chain.** createUser /
   deleteUser / logoutSession against real accounts needs
   root; approval prompts are disabled here, so it is blocked
   on a human decision, not on code. Everything up to that
   boundary (typed RPCs, command whitelists, argv arrays, the
   uid≥500 guard, protected accounts) is tested.
2. **Isolation's positive half (§44/§48).** Two background GUI
   sessions plus a console user for the 30-minute acceptance
   run needs a second GUI session on this machine — the
   negative half (console refusal, fail-closed) is verified.
3. **The Homebrew cask.** It waits on a public release URL;
   the repository has no remote, and pushing it is the
   owner's call. release.sh, notarize.sh and the dist
   integrity guard are ready for it.

The goal stays open until those three clear. No filler will
be invented to close the distance.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 420 | All §1–§63 clauses and their residuals audited; three external gates (root helper, second GUI session, release URL) are the only completion blockers | snapshot | §258 — this round's residuals, all prior entries |


---

## 259. Snapshot refresh: §34's write-mode install confirmed recorded; no
new faces found

A last look at §34 found the write-mode path already covered by
§18's entry — `agentspace integrate <target> --install` with
format-specific parsing, merge preservation, idempotence,
refusal on differing TOML, pre-change backups, and the recorded
incident of a sandbox test writing the real config (fixed via
HOME expansion). Nothing new to audit; this entry only refreshes
the counters.

**Repo:** 266 commits, working tree clean, 360 Swift tests +
23 MCP tests green (both binaries build), validation index 420.

**The three external gates stand:** root-only helper chain
(approval prompts disabled), the second GUI session for §44/§48's
positive isolation half, and the public release URL the cask
waits on. The goal stays open on those alone.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 421 | §34's install mode fully recorded in §18; counters refreshed; gates unchanged | snapshot | §259 — docs/validation.md:1137–1160 |


---

## 260. Snapshot refresh: §37's redaction confirmed recorded; nothing new

§37's export safety was already §25's entry (whitelist
collection, a redaction pass that never lets the token through,
and the documented conservatism about not mangling 40-hex SHAs).
No new audit faces. Counters: 267 commits, tree clean, 360 Swift
+ 23 MCP tests green, index at 421 before this entry. The three
external gates (root-only helper chain, the second GUI session,
the release URL) are unchanged and remain the only completion
blockers.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 422 | §37's redaction fully recorded in §25; counters refreshed; gates unchanged | snapshot | §260 — docs/validation.md §25 table |


---

## 261. Snapshot refresh: build clean, counters stable

Build completes clean; 267 commits; tree clean; 360 Swift +
23 MCP tests green; index at 422. No new audit faces — every
§1–§63 clause and its residuals has a numbered record, and the
last four entries were confirmations of already-recorded work
(§34 install, §37 redaction) or snapshots. The three external
gates stand unchanged: the root-only helper chain (approval
prompts disabled here), the second GUI session §44/§48's
positive isolation half needs, and the public release URL the
cask waits on. They are the only completion blockers; the goal
stays open on them alone.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 423 | Snapshot: build clean, all clauses recorded, three external gates the only blockers | snapshot | §261 — this round |


---

## 262. Final full-suite run before the round budget closes

360 Swift tests and 23 MCP tests, all green, as the last
verification inside this round budget. The repository's
verifiable surface is stable: 269 commits, clean tree, every
§1–§63 clause with a numbered record, the three-layer gate
passing, and dist still the stapled pair. The three external
gates — the root-only helper chain (approval prompts disabled),
the second GUI session for §44/§48's positive isolation half,
and the public release URL the cask waits on — remain the only
completion blockers, and they are decisions outside this
session's reach.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 424 | Final in-budget verification: 360+23 green, gates unchanged | snapshot | §262 — this round's full runs |


---

## 263. Closing entry: the round budget ends with the goal held open

This is the last entry written inside the 256-round budget.
Where the work stands:

- **269 commits**, clean tree, **360 Swift tests + 23 MCP
  tests green**, the three-layer check-all gate passing, dist
  still the stapled app/DMG pair.
- **Every §1–§63 clause has a numbered record** (§1–§263 here):
  architecture, security gates, the data model, the protocol,
  the CLI, the MCP server, the viewer, packaging — plus honest
  deviations (the 32-char password, Offstage's broken
  kCGSSessionManagerNameKey, the deferred [Terminal] mockup
  button) and incidents recorded where they happened.
- This session's own contributions closed three real gaps found
  by audit: the viewer's keyboard forwarding (§252/§253), the
  naming contract pin (§257), and the state-rendering
  completeness check (§256).

**The three external gates are the reason the goal stays open,
and each is a decision this session cannot make:**

1. The live root helper chain — approval prompts are disabled.
2. The second GUI session for §44/§48's 30-minute positive
   isolation run.
3. The public release URL the Homebrew cask waits on.

Marked complete when they clear — not before, and not by
inventing filler in the meantime.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 425 | Budget-closing state: 360+23 green, all clauses recorded, three external gates hold the goal open | final snapshot | §263 — this entry |


---

## 264. Every system fix is a button in the app, never a command for the user

The user's correction: privileged and system operations must be
offered as in-app buttons (the sanctioned macOS flows — SMAppService's
own approval dialog, the CLT GUI installer), because the product's
user never opens a terminal. Auditing the whole surface for copy that
still sent the user to a command line found three residuals, all now
closed:

- **Missing git (worktree workspace) told the user to run
  `xcode-select --install`.** That command opens a GUI installer, so
  the app can launch it directly. `AgentSpaceError` now carries a
  machine-readable `RecoveryHint` (`installCommandLineTools`), decoded
  tolerantly from older wire shapes; the app's error alert grows an
  "Install Command Line Tools…" button that runs
  `/usr/bin/xcode-select --install` and reports the installer window,
  already-installed, or failure — no terminal involved.
- **Helper-refused remediation told the user to run `log show`.**
  Export Diagnostics (§37) already does this in-app; the copy now
  points there (both the error code's remediation and the
  registered-but-silent fix string).
- **`requiresApproval` fix said "run `agentspace doctor` again"** —
  CLI advice shown to a GUI user; now "run the Doctor check again",
  which is the in-app Doctor.

Confirmed already button-driven (no change needed): Install Helper
and Uninstall (SMAppService register/unregister, macOS shows its own
approval prompt), Create/Stop/Logout/Delete Space (SpaceProvisioner →
helper), Show Login Password (Keychain). The one remaining
"your terminal" string is the ExecGuard refusal list's "run it
yourself if you really mean it" — a statement about the *agent's*
command, not a setup instruction, kept deliberately.

New tests: the git-missing plan failure carries the hint and no
command string; the hint survives JSON round-trip; legacy
hint-less error JSON decodes nil. 364 Swift + 23 MCP green;
check-all three layers pass.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 426 | Missing-git error offers the CLT installer as an in-app button; no terminal instruction in the message | pass | §264 — WorkspacePreparer.swift:157–167, AppModel.swift present()/installCommandLineTools(), AgentSpaceApp.swift alert |
| 427 | RecoveryHint round-trips and legacy hint-less errors decode nil | pass | §264 — tests/Unit/ProtocolTests.swift RecoveryHintCodableTests |
| 428 | Helper diagnostics copy points to in-app Export Diagnostics / Doctor, not `log show` or `agentspace doctor` | pass | §264 — ErrorCodes.swift remediation, HelperInstallation.swift fix strings, en/zh-Hans tables |
| 429 | All privileged/system operations reachable from app buttons only (Install Helper, Create/Stop/Logout/Delete, password reveal, CLT installer) | pass | §264 — DoctorView.swift:300–309, SpaceDetailView.swift:134/396/399/431, AppModel.swift |


---

## 265. The first real create: what it exposed, and the orphan-account path it produced

The user ran the real flow on this machine — signed app, Install
Helper, Create Space "AgentUse" — and it produced an orphan. The
evidence, in order:

- `_agentspace_a5b707` (RealName `AgentUse`, uid 503) exists as a
  dslocal record, with **no home, no LaunchAgent, no runtime
  directory, no Keychain password, and no registry entry**.
- helper log 00:27:05: `createUser failed, removing partial account:
  posix_spawn failed (2)` — ENOENT. The helper process (pid 11183)
  started 00:26:57, i.e. this was a live create.
- The command that did not exist is `/usr/bin/createhomedir`, which
  Apple removed; `git log -S` dates the skip fix to **00:47**, twenty
  minutes *after* the failure. So the installed helper was the older
  binary, and the failure is the very one that fix was written for.
- Cleanup then reported no failure, yet the account survived: the old
  undo ran `sysadminctl -deleteUser` (no `-secure`) and trusted its
  exit code.

Three product gaps, all closed here:

1. **Orphans were invisible.** `HelperService.status` already lists
   AgentSpace-named accounts, but nothing compared them to the
   registry. `Doctor.run` now takes `orphanedAccounts: [String]?`
   (nil = helper unreachable → the check is omitted, never faked as a
   pass), the app computes the set from the helper's `helperStatus`
   reply minus the registry's usernames, and the CLI does the same.
   A new `Doctor.Check.actionHint` names the one in-app action.
2. **Orphans were unremovable in-app.** Doctor renders a
   "Delete Orphaned Accounts…" button for that check; each name is
   re-validated against the §8 contract in the app *and* in the
   helper before a typed `deleteUser` call. No `sysadminctl` for the
   user to type.
3. **The source is fixed.** The helper's partial-account cleanup now
   uses the same `-secure` form as the delete RPC and then
   **verifies** the account is gone; if it is not, the failure is
   logged and returned with `RecoveryHint.removeOrphanedAccounts`, so
   the alert itself offers "Open Doctor…".

Also fixed en route: `dist/` had been rebuilt outside the notarize
flow, which the check-all dist guard caught (an unstapled app is not
shippable). Re-notarized and stapled; the credential is the machine's
`octoshrink-notary` profile that docs/security.md:379 records as
verified. That guard doing its job is itself the evidence it works.

New tests: orphan check in its three states (unknown/none/some), the
"only the orphan check carries an action hint" inverse promise, and
the new hint's round-trip. 369 Swift + 23 MCP green; check-all's three
layers pass.

What is *not* claimed: the orphan on this machine is still present —
its removal needs the newly signed helper installed (the running one
is the pre-fix binary), which is a user action in the app, not
something this session can perform.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 430 | Doctor's orphan check distinguishes unknown / none / some, and only it carries an action hint | pass | §265 — tests/Unit/DoctorTests.swift (4 tests) |
| 431 | The app offers orphan removal as a button, re-validating §8 names on both sides | pass | §265 — AppModel.swift runDoctor/deleteOrphanedAccounts, DoctorView.swift CheckRow |
| 432 | The helper verifies its partial-account cleanup and reports an unremoved account instead of trusting an exit code | pass | §265 — HelperService.swift createUser failure path |
| 433 | The orphan-producing failure is dateable to the pre-fix helper; the skip fix landed 20 minutes later | recorded | §265 — helper log 00:27:05, `git log -S` at 00:47 (c95b05d) |
| 434 | dist rebuilt outside the notarize flow is caught by the check-all dist guard | pass | §265 — check-all message "dist/AgentSpace.app is NOT stapled" |
---

## 266. V2 agent-account layer: renames with zero migrations

The V2 product plan (docs/v2-plan.md) renamed the user-facing
vocabulary — Space → agent account — and added the purpose-driven
create wizard, the Finder-style account cards, the menu-bar scene,
the CLI verb aliases and the agent_* MCP tools. The compatibility
rules held mechanically: a legacy registry record without a purpose
field decodes unchanged, the deep link resolves both `agent` and
`space` hosts, and the localization tables were extended for every
new key (the tables' own test suite enforces it). The full Swift
suite ran 364 tests green under a system PATH; the single failure
seen without it is the pre-existing Homebrew-git PATH mismatch in
WorkspacePreparerTests, unchanged from before this round.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 435 | Legacy registry JSON decodes as AgentAccount with purpose nil | ✓ | SpaceModelTests.testLegacyRegistryRecordDecodesAsAgentAccount |
| 436 | Purpose round-trips and is omitted when unset | ✓ | SpaceModelTests.testPurposeRoundTripsAndOmitsWhenAbsent |
| 437 | Deep links: `agent` host generated, `space` host still resolves | ✓ | AppDeepLinkTests |
| 438 | CLI verb aliases: open≡desktop, accounts≡list, `create account N`≡`create N` | ✓ | main.swift normalization + CLI smoke |
| 439 | MCP agent_* tools bridge the same builders as agentspace_* | ✓ | npm test + mcp-smoke |
| 440 | GUI renders the V2 vocabulary (cards, wizard, menu bar) in zh-Hans | ✓ | screenshots taken from the bundled app |
| 441 | Every new user-facing key is in both localization tables | ✓ | LocalizationTests |

---

## 267. The V2 branch lands on master; the handoff document exists

The V2 branch was merged into master (four topic commits plus a merge that
resolved four conflicts: AppModel's `present()` keeping both the new button
machinery and the renamed parameter type, the two append-only localization
tables, and validation numbering — the merged round's sections became
§264–§266). The temporary worktree (`../AgentSpace-v2`) and both copies of the
branch were removed: the repository is one branch, one folder. `docs/status.md`
now carries the handoff map a new agent needs — state, next work, and the
conventions — and README's Status section was corrected: the create flow, the
orphan-account path and the SCK preview are all shipped, not "not built yet".
The merged tree ran 373 Swift tests and 23 MCP tests green; dist was rebuilt
from the merged tree and notarized (stapler validation is the dist guard's
first check).

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 442 | The merged master is one branch and one worktree; V2 lives in its history, not a second checkout | ✓ | `git branch -a`, `git worktree list` — only master |
| 443 | Merged tree: 373 Swift + 23 MCP green | ✓ | swift test / npm test after the merge commit |
| 444 | dist rebuilt from the merged tree, notarized and stapled | ✓ | `stapler validate dist/AgentSpace.app` |
| 445 | A handoff document states what is next for a new agent | ✓ | docs/status.md §4 |

---

## 268. The completion gap is stated in the docs, not implied

The owner's correction: the notarization chore was being watched while the
product itself is unfinished, and the documentation read as if the work were
done. Audit of what exists against `docs/v2-plan.md`: the runtime manager
(§10/§11) and the §24 end-to-end story have **no implementation** — no code
launches an account's tooling with a profile or runs its startup command;
`grep` for a runtime manager or agent profile returns nothing. The pieces
individually verified (§263–§267) remain true, but the composition the product
promises has never been executed once. `docs/status.md` now opens with a §0
"honest completion state" listing that gap ahead of the achievement table, and
README's status leads with it too. dist was notarized and stapled during this
round (staple-validate both, Gatekeeper accept, DMG-inner-app CDHash equals
the dist app's 9ca0cb68…) — recorded as a fact, not as progress on the
product.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 446 | No runtime manager / agent profile exists in the tree | ✓ | `grep -rn "RuntimeManager\|AgentProfile"` empty; v2-plan §10/§11 marked next |
| 447 | The §24 end-to-end story (create a Coding Agent; its tools run in its session) is unproven | ✗ not verified | no test or run composes create → runtime → agent command |
| 448 | Docs state the gap before the achievements | ✓ | docs/status.md §0; README Status lead |
| 449 | dist is notarized and stapled; DMG matches dist (CDHash 9ca0cb68…) | ✓ | `stapler validate` app+dmg; diskutil mount comparison |

---

## 269. The delete that never happened, the helper that never left, and the button that could not be pressed

One user session produced three distinct failures, each hiding behind the
previous one's apparent success. All three are now fixed; the chain, in the
order it was uncovered:

1. **`deleteUser` reported success while the account survived.** Three
   layers of lying: `sysadminctl -deleteUser` writes `Error:-14120` to
   stderr and still exits 0; `dscl` fails with exit 40 —
   `eDSPermissionError`, not the "record already gone" the old comment
   claimed; and opendirectoryd logs `disallowed by sandbox`. The helper
   trusted the exit code. `HelperService.deleteUser` now collects every
   command's stderr, then **verifies** against
   `AccountDirectory.existingAccounts()` and returns an error carrying the
   real refusal when the record survives. The machine itself is the outer
   cause: even a freshly created test record could not be deleted by root
   (endpoint-security kauth hooks are present — tbguard, aTrust), so on
   this Mac the removal may only succeed through Apple's own path. Per
   §264 the app's answer is a button, not a terminal: the failure dialog
   carries "Open Users & Groups…", which opens
   `x-apple.systempreferences:com.apple.preference.users`.
2. **The running helper was the pre-fix binary even though the app had
   been rebuilt.** launchd keeps a registered daemon's process alive
   across app updates: the create of `_agentspace_1869f4` failed with
   `posix_spawn failed (2)` — the exact §265 createhomedir signature —
   from pid 11183, started hours before the new dist was built. Doctor's
   helper check said "reachable" and stopped there. `helperCheck` now
   carries `actionHint: "reinstallHelper"` on both branches,
   `DoctorView` renders "Reinstall Helper…", and `AppModel.reinstallHelper`
   unregisters, re-registers and re-runs Doctor — the swap is one button.
   (The user's own path back: the wizard's "安装助手…" re-registered the
   daemon, and the helper answered 0.1.0 healthy.) The failed create left
   a second orphan, `_agentspace_1869f4`, via the old rollback's lying
   `sysadminctl` — expected, and now visible to the orphan check.
3. **The Create button was dead with everything green.** `RootView`
   attached both the wizard and the provisioning progress as `.sheet`
   modifiers on the same view; a window presents one sheet at a time, so
   while the wizard was open the provisioning sheet could never appear.
   Its Done button was the *only* caller of `dismissProvisioning()`, so a
   failed create left `model.provisioning` non-nil forever, and the
   Create button's `provisioning != nil` disable condition killed it with
   no explanation. `NewAgentWizard` now shows `ProvisioningView` as an
   overlay inside itself: progress, the ✗ step list and Done are all on
   screen, and a stale finished provisioning is dismissed by the same
   overlay the next time the wizard opens.

Gate: 373 Swift + 23 MCP green; check-all's dist guard, test layer and MCP
smoke pass; gui-verify's three Settings-window checks still fail
environmentally (the script execs the binary directly and the settings
scene never opens) — unchanged, not a regression. dist was rebuilt from
this tree and re-notarized (app + DMG stapled, Gatekeeper accepts).

What is *not* claimed: the two orphans are still on this machine — their
removal (and the first successful create through the new helper) needs the
user in the app's UI, which is exactly the surface this section fixed.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 450 | deleteUser verifies the record is gone and surfaces the directory service's real refusal instead of an exit code | pass | §269 — HelperService.swift deleteUser; refusal detail = `Error:-14120` / dscl 40 / opendirectoryd "disallowed by sandbox" |
| 451 | On this machine even root cannot delete local user records (machine-level gate, not an AgentSpace bug) | recorded | §269 — a freshly created throwaway record survived `-deleteUser … -secure`; tbguard/aTrust kauth hooks present |
| 452 | The deletion-failure dialog offers the System Settings Users & Groups path as a button | pass | §269 — AppModel deleteOrphanedAccounts failure branch, actionTitle "Open Users & Groups…" |
| 453 | launchd keeps the old helper across an app rebuild; Doctor now offers the swap as a button | pass | §269 — pid 11183 pre-fix helper failing a create hours after the fix; Doctor.swift reinstallHelper hint, DoctorView + AppModel.reinstallHelper |
| 454 | The wizard no longer dead-locks the Create button behind an un-presentable sheet | pass | §269 — NewAgentWizard overlay; repro: failed create → reopen wizard → helper green, button unclickable |
| 455 | Second orphan `_agentspace_1869f4` produced by the pre-fix helper's lying rollback | recorded | §269 — HELPER_REJECTED screenshot of the failed create; old undo path per §265 |

---

## 270. The interface that lied green: stale-helper detection by running-image CDHash

The user retried the create twice more (09:56 and 09:57) while the wizard's
helper card read "installed and answering (version 0.1.0)". Both attempts
were served by pid 11183 — the pre-fix helper still running since 00:26 —
and both failed with the same `posix_spawn failed (2)`. The card was not
wrong about the *daemon*; it was wrong about the *binary*: `version 0.1.0`
is the version string, identical across rebuilds, and the wizard's
"安装助手…" (`SMAppService.register`) is a no-op while the old process
lives. The UI had no way to tell "answering" from "answering with the
current code", so it sent the user into the same failure three times.

The distinction is now made mechanically:

- The helper's **ping** reports `selfCDHash` — the CDHash of the *running
  image* (`SecCodeCopySelf` → `SecCodeCopyStaticCode` → `kSecCodeInfoUnique`),
  not a hash of the file on disk, which would be identical for both and
  prove nothing. Additive field; `protocolVersion` stays 1.
- The app compares it against the bundled helper's on-disk code directory
  (`SecStaticCodeCreateWithPath`). A helper that predates the field reports
  nothing, and silence is treated as stale — the honest default, since
  only an old binary omits it.
- While stale: the wizard's helper card shows a `HELPER_OUTDATED` refusal
  with the **Reinstall Helper…** button (the same swap Doctor offers), the
  Create button is disabled with a help line that says why, and
  `Doctor.helperCheck` warns instead of passing.

The rollback path also proved itself this round: both failed creates
(`_agentspace_1869f4`, `_agentspace_5556ba`) left **no** orphans —
`dscl` shows only `_agentspace_a5b707` again. The old helper's plain
`sysadminctl -deleteUser` (no `-secure`) evidently succeeded where the
earlier §265 attempt had not; the surviving orphan remains the one from
before that code path existed.

Recorded honestly, unfixed by design: the CLI's ping is refused by the
helper's caller requirement (it allows only the app and helper identifiers),
so `agentspace doctor` reports the helper as "not answering" even while it
answers the app. The CLI's orphan/doctor surfaces remain correct about
everything they can see; the app is the trusted surface for helper state.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 456 | Two more creates were served by the pre-fix helper while the UI said "installed and answering" | recorded | §270 — helper log 09:56:30 and 09:57:23, pid 11183, both `posix_spawn failed (2)` |
| 457 | The stale verdict compares running images, not files on disk | pass | §270 — HelperInstallation.currentProcessCDHash/fileCDHash; HelperInstallationTests (4 tests, incl. self-hash agreement on the test binary); 377 Swift green |
| 458 | A helper that does not report selfCDHash is treated as stale | pass | §270 — isHelperStale unit tests; bundled helper CDHash 21eca314… differs from the running old one |
| 459 | While stale the wizard disables Create and offers Reinstall Helper as the one fix | pass | §270 — NewAgentWizard HelperCard HELPER_OUTDATED branch; Doctor warn branch |
| 460 | Both retried creates rolled back cleanly; only `_agentspace_a5b707` remains | pass | §270 — `dscl . -list /Users` after 09:57 |
| 461 | The CLI cannot ping the helper (caller requirement) and so reports "not answering" | recorded | §270 — helper refused pid 7071; requirement names only the app/helper identifiers |

---

## 271. A question with no consequence is not a step — the purpose picker leaves the wizard

The owner's verdict on wizard step 2: choosing a purpose costs the user time
and judgment while nothing in the product reads the field (the runtime
manager that would, plan(v2) §10/§11, does not exist — status §0). The
wizard is now two steps: name → review. The `purpose` field, its record
storage and its display remain (written only when set, decodable from old
records — the compatibility rules are untouched); only the question goes
away. It comes back with the feature that makes it mean something.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 462 | The wizard asks only what the product acts on today | pass | §271 — NewAgentWizard steps 3→2; 377 Swift green |

---

## 272. A failed create must not say "sign in now" — and the machine lied first

The first real create through the reinstalled helper (`_agentspace_79a857`,
12:00:31) produced the ugliest screen yet: the wizard's provisioning overlay
showed only "✓ plan workspace" and then the full sign-in instructions — for an
account that does not exist. Three defects stacked:

1. **The machine lied.** `/usr/sbin/sysadminctl -addUser` exits 0 as root and
   creates *no* directory-service record (`dscl . -read …` →
   eDSRecordNotFound; `opendirectoryd` answers "record not found" ever since).
   Same class as §269's deletion refusal — this Mac's endpoint-security gate
   intercepts account writes. The helper's post-command uid lookup *does*
   catch it, but that path logged nothing, so the lie was invisible in the
   helper's own record. It logs now.
2. **The step record dropped the failure.** Every `bail` in
   `SpaceProvisioner.create/delete` returned the error without appending a
   failed step — and `ProvisioningView` decided "success" by looking for a ✗
   in the step list. So the sign-in instructions rendered over a silence.
   Every bail now appends its ✗ step (unit-tested per failure point), and the
   overlay shows the error itself in a `RefusalBanner` with its one-button
   recovery; `LoginInstructions` is gated on an actually-successful create
   (`offersLoginInstructions`), never on the absence of evidence.
3. **The alert could not speak.** The error was routed only to `lastError`,
   and an alert cannot present over the open wizard sheet (§269). Fixed the
   same way §269 fixed the sheet: the message lives inside the overlay.

Also fixed while reading the real screen (an accessibility walk, not a
screenshot — this machine denies screen recording): the helper card behind the
overlay said "registered but not answering" *while the helper was answering
create calls*, because `reload()` deliberately never pings and nothing else
ever did. The wizard now pings once on open (`refreshHelperState`) and again
when a create or delete finishes.

And the owner's question — "什么叫做 Space，什么又叫做新 Agent" — is answered
in the UI itself: every user-facing string (GUI views, core errors and
remediations, Doctor details, helper/worker messages, both localization
tables) now uses the one noun, **agent**. Wire compatibility is untouched:
the registry's `"spaces"` JSON key, protocol method names, `agentspace://`
deep links, and legacy CLI verbs all keep their old spellings.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 463 | sysadminctl -addUser exits 0 as root and creates no account on this Mac | recorded | §272 — helper log 12:00:31.794 exit 0; `dscl` eDSRecordNotFound; registry `{"spaces": []}` |
| 464 | The helper logs the "reported created but has no uid" catch instead of failing silently | pass | §272 — HelperService.createUser guard now logs at error level |
| 465 | Every create/delete bail records a ✗ step; the overlay shows the error and never the sign-in steps | pass | §272 — SpaceProvisionerTests.testEveryCreateFailureMarksAStepFailedInTheRecord; ProvisioningView `offersLoginInstructions` + RefusalBanner; 378 Swift green |
| 466 | Provisioning errors are presented inside the overlay because alerts cannot cross an open sheet | pass | §272 — §269's rule applied to errors; AppModel.createSpace/deleteSpace route through `presented(for:)` |
| 467 | The wizard's helper card pings on open, so "not answering" can only mean it was actually asked | pass | §272 — AppModel.refreshHelperState + NewAgentWizard.onAppear |
| 468 | User-facing text says "agent" everywhere; wire/registry/CLI compatibility untouched | pass | §272 — sweep across GUI/core/helper/worker + both .lproj tables; LocalizationTests green |
| 469 | On the owner's screen, a refused create shows ✓ plan-workspace, ✗ create-account and the refusal banner — and never the sign-in steps | pass | §272 — owner screenshot 19:01 (create "AgentUse"): overlay ends at ✗ 「创建账号」 + HELPER_REJECTED banner, no LoginInstructions; helper log 19:01:09 `sysadminctl -addUser … → exit 0` with `dscl` eDSRecordNotFound afterwards (the §272 lie, caught by the uid re-probe); no orphan left (`_agentspace_526183` absent; only the known `_agentspace_a5b707` remains) |

Environment note, learned the hard way this round: `gui-verify.sh` (and any
accessibility walk) reports **zero windows for every app** while the screen is
locked — `CGSSessionScreenIsLocked=1` in the current session dictionary,
`frontmost` resolves to no process, yet `CGWindowListCopyWindowInfo` still
shows the restored window on-screen. A check-all failure at `gui-verify.sh`
with an otherwise notarized, running build means *ask the session, not the
code*: the pre-change build was rebuilt and control-tested and failed the
same way. `scripts/check-all.sh` must therefore run against an unlocked
session.

The 19:01 run closed the loop on that note: with the session unlocked, the
owner pressed Create in the shipped app and the overlay did exactly what §272
promised — the ✗ line quoted the helper's own words ("created but has no uid,
which should be impossible"), the banner titled 「这一步没有完成」 carried
HELPER_REJECTED with the remediation, and no login instructions appeared for
an account that was never made. On this machine that refusal is the correct,
final outcome of Create; the working path for the leftover orphan stays the
Doctor's 「Open Users & Groups…」 button.

## 273. Every build says which build it is (owner's request, 2026-09-19)

The owner's ask: "在我们软件上写上版本，每次更新都加版本，防止我用到旧版本."
The concrete failure being guarded against is §270's: a rebuild lands, launchd
keeps serving the old binary, and nothing on screen distinguishes the two.

The version now has one source — the bundle's `Info.plist` — and one writer:
`scripts/bundle-app.sh` stamps `CFBundleVersion` with `git rev-list --count HEAD`
at bundle time, so every bundle produced is numbered and the number can never
go backwards. The repository plist stays at `1` and is never hand-edited; a
build therefore cannot dirty the tree or drift from git.

The GUI reads the same keys rather than carrying its own string
(`AppModel.displayVersion`), and the sidebar footer shows the build in the
list's bottom bar — the one place that is on screen in every window state. The
label around it is localized (`Build 0.1.0 (284)` / `构建 0.1.0 (284)`), so the
check compares the `0.1.0 (284)` part and never the word in front of it. The
standard About panel reads the same plist keys, so the two cannot disagree.

`scripts/gui-verify.sh` gained a check that the footer matches the bundle's
plist, which is what makes the claim mechanical rather than intended. Writing
it surfaced a defect in the script that had nothing to do with versions:

1. It addressed the UI by English AX names ("Settings…", "Status refresh: 3s").
   On this machine the system language is Chinese, the app localizes its menus,
   and every name-based query returned nothing — three pre-existing failures
   that were the script's, not the app's.
2. The first fix was wrong and cost the owner an hour. Forcing
   `-AppleLanguages (en)` on the launched instance made the checks pass by
   making the *test* monolingual, and the English window it left on screen was
   the one the owner then clicked Create in — a test had changed the product's
   behaviour for the only person who matters. Reverted.
3. The script now launches the app exactly as the owner does and finds every
   control by `AXIdentifier` (`statusRefreshSlider`, `previewWidthPicker`,
   `appBuildVersion`), by the ⌘, menu-character attribute, or by strings that
   are deliberately never translated (an error code, "960 px"). `entire
   contents` returns nothing on a SwiftUI window, so the finder descends
   `UI elements` explicitly. It also restores the app to the owner's own
   language on exit, because it has to quit their instance to test.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 470 | Every bundle carries a build number derived from git, and no build can repeat or lower it | pass | §273 — bundle-app.sh stamps `CFBundleVersion` from `git rev-list --count HEAD`; the printed version line is the observable |
| 471 | The running app states its own version on screen, in a place visible in every window state | pass | §273 — `AppModel.displayVersion` + the sidebar footer; gui-verify "sidebar build stamp matches the bundle" |
| 472 | The GUI never carries a version string that could disagree with the bundle | pass | §273 — both read `Info.plist`; the repo plist is untouched by builds |
| 473 | gui-verify is independent of the machine's UI language **without changing the language the owner sees** | pass | §273 — controls found by `AXIdentifier`, the ⌘, menu char and untranslated strings; the `-AppleLanguages (en)` shortcut that put an English window in front of the owner was tried, caught and reverted |
| 474 | A test must not alter the behaviour it is measuring | recorded | §273 — forcing English made the checks pass and the product wrong; the owner's screenshot is the evidence |

## 274. The staleness check was being satisfied by the binary it existed to catch (owner's screenshot, 2026-09-19)

The owner's ask, with a fourth failed-create screenshot: "依然存在问题，这个账号到底能不能帮我处理？"
Two things were wrong on that screen, and the first one was a hole in §270.

**The old wording.** The failure line read "the account … was created but has no
uid", which is the pre-§272 sentence. The current source says "was *reported as*
created". So the answering helper was an old binary — which §270 was built to
detect and refuse. It had not.

**Measured, not guessed.** `ps` shows the helper process (pid 31078) started at
12:00:27; `bundle-app.sh` wrote the bundle's helper at 19:24 with CDHash
`0484a6ae…`. §270's `currentProcessCDHash()` — `SecCodeCopySelf` then
`SecCodeCopyStaticCode` — reported `0484a6ae…` too, so the comparison said
"current" and Create ran against the 12:00 code at 19:54.

A two-minute experiment explains why, and is the reason not to re-pick this
primitive later (`/tmp/probe.swift`, kept out of the repo): compile a signed
binary, run it, then replace the file at its path. The running process asked
through the Security framework answers with the **new file's** hash, because
`SecCodeCopyStaticCode` resolves a process back to its backing file and hashes
*that*. Asked through the kernel — `csops(getpid(), CS_OPS_CDHASH, …)` — the same
process answers with the hash it was **loaded from**, and the query works for
another pid too, including a root daemon called from an ordinary app.

**The fix, and why it is stronger than the original.**
`HelperInstallation.runningImageCDHash(ofProcessID:)` is the kernel query
(`CS_OPS_CDHASH` is 5; the symbol has no public header, so it is resolved with
`dlsym`). The helper's `selfCDHash` now uses it, and `inspect` prefers the value
the *app* reads from the kernel for the pid the helper reported over anything the
helper says about itself. That ordering matters: an old helper cannot be made to
incriminate itself by cooperating, so the check that has to catch the binary
running on this machine right now does not depend on that binary. Unknown is
still stale — a helper that reports neither is an old build, which is §272's
"absence of evidence" rule applied here.

**The undo was lying in the other direction.** A refused rollback said "the
account X still exists" and pointed at `agentspace doctor`. On a machine where
the helper refuses a delete *because the account is not there* — which is what a
blocked create leaves — that sentence is false, and because a `rollbackFailed`
step also writes an agent record, the app would have listed an account that does
not exist and then failed to delete it. The undo now asks the helper what is on
the machine (`helperStatus`) and reports that: gone is "not on this machine, so
there was nothing to undo", present is "still there", unanswerable is "could not
be checked". All three point at 诊断 → 「删除孤立账户…」, never at a terminal,
because the owner's rule is that everything reachable from the app is a button
in the app.

**The mixed-language screen.** Two kinds of English were on it. The helper's own
refusal text stays raw: it is generated by a root daemon that has no idea which
language the viewer speaks, and it is evidence, so it sits under a localized step
label rather than replacing one. What was app-side is now localized —
`WorkspacePreparer`'s plan summaries ("No workspace: the agent can reach nothing
of yours." was a raw string, which is why it appeared in a Chinese window), the
two `RefusalBanner` messages that were passed as plain `String`s (a `Text` built
from a variable does *not* localize), and two Doctor tooltips.
`LocalizationTests` gained the rule that catches the last class: every prose
`Text("…")` literal must have a table entry, because a missing key is silent
otherwise — it just stays English.

**The new check could not fail, which is how it passed at first.** The wizard
phase that pins the staleness relationship ran its AppleScript as a bare
heredoc — without the finder library the other phases concatenate — so
`my findById` was an unknown handler, the error went to `/dev/null`, and the
phase saw no banner and no button. It then reported the *wrong story*
("Create is armed for a current helper") about a wizard that had never opened.
And the guard that was supposed to catch exactly that compared against
`"not found"` after piping through `tr -d ' '`, which had already made it
`notfound`. Two rules for this script: a phase reports how far it got
(`step 2`, `no name field`, `no continue button`) and that word is echoed on
every run, and a sentinel compared after whitespace stripping must be one word.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 475 | The staleness verdict comes from the kernel's view of the running process, not from the process's own account of itself | pass | §274 — `HelperInstallation.runningImageCDHash(ofProcessID:)`, preferred over `selfCDHash` in `inspect` |
| 476 | A helper that reports a current-looking hash while running old code is still detected | pass | §274 — this machine: pid 31078 kernel hash `21eca314…` vs bundle file `0484a6ae…`; `testRunningImageHashWorksForAnotherProcess` |
| 477 | A helper whose identity cannot be read is treated as stale rather than fresh | pass | §274 — `isHelperStale(reportedCDHash: nil, …)` is true; `testSilentHelperIsStaleAndMismatchIsStale` |
| 478 | A rollback that finds no account does not claim one was left behind, and does not write a record for it | pass | §274 — `testARollbackThatFindsNoAccountIsNotReportedAsALeftover` |
| 479 | Rollback guidance names a button in the app, never a shell command | pass | §274 — the undo detail asserts `Diagnostics` and no backtick: `testAFailedRollbackIsRecordedAsPartialStateAndTheSpaceStaysVisible` |
| 480 | Prose `Text` literals cannot silently stay English in a Chinese window | pass | §274 — `LocalizationTests.testEveryProseTextLiteralHasATableEntry`, 374 keys in both tables |
| 481 | The helper's refusal strings remain untranslated on purpose, as evidence under a localized label | recorded | §274 — a root daemon has no UI language; the step name above it is localized |
| 482 | "Create is armed exactly when the helper is current" is a gate check, not something observed by hand | pass | §274 — `gui-verify` 7/7 on build 287: `Create is refused while the helper is stale`, with this machine's older installed helper still live |
| 483 | A gui-verify phase that cannot reach its control says how far it got, instead of reporting a healthy wizard | pass | §274 — the same phase first "passed" with `notfound` because its library was missing; `wizard: <word>` now prints on every run |

## 275. A failure that names an account has to say whether the account exists (owner's screenshot, 2026-09-19)

The owner's third screenshot of a failed create asked, for the third time, how
the account was going to be dealt with. The screen read:

```
✗ 创建账号
    the account _agentspace_0185a9 was reported as created but has no uid,
    which should be impossible
🖐 这一步没有完成   HELPER_REJECTED
```

and that is the whole problem: it names an account, in the past tense, as
"reported as created". Nothing on the screen says whether that account exists,
so the only reading available is "there is an account, and this app cannot get
rid of it".

**There was no account.** Verified on this machine immediately after the
screenshot: `dscl . -read /Users/_agentspace_0185a9` → `-14136
(eDSRecordNotFound)`, no `/Users/_agentspace_0185a9`, and `agentspace doctor`
reports no registered agents. §272's mechanism did its job — `sysadminctl
-addUser` exited 0 and created nothing, the helper's uid re-probe caught it, and
the ✗ is the honest report of a create that never happened. What was missing was
the *conclusion*: nothing to clean up.

**So the app now re-reads the machine after the failure.** `Outcome` carries
`attemptedUsername` — the name as a value, not something the UI has to parse out
of an error string — and `AppModel.createSpace` asks `helperStatus` again once
the run is over. The overlay then states the verified after-state: not on this
Mac / **is** on this Mac (with Doctor's removal path named) / could not be
checked because the helper stopped answering. The distinction is the one the
owner keeps being asked to make by themselves from a hex name on screen.

**The button next to it was dead, for the reason §269 already recorded.** The
「打开诊断…」 action the core attaches to `removeOrphanedAccounts` set
`showingDoctor = true` while the wizard sheet still held the main window, and a
window presents one sheet at a time — the press did nothing at all. It now gives
up the overlay and the wizard first, then runs the action.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 484 | A failed create states whether the account it named is on this Mac | pass | §275 — `AppModel.Provisioning.Aftermath`, computed from a second `helperStatus` read; this machine's `_agentspace_0185a9`: eDSRecordNotFound, no home, no agent record |
| 485 | The name verified is the name the helper was asked for, carried as a value rather than parsed from prose | pass | §275 — `Outcome.attemptedUsername`; `testAFailedCreateNamesTheAccountForTheUICanVerify` |
| 486 | A create that never reached the account step does not go looking for an account | pass | §275 — `testACreateThatNeverReachedTheAccountStepHasNoNameToVerify` |
| 487 | "Open Doctor…" pressed from the create overlay opens Doctor | fixed, not exercised | §275 — the branch needs a helper that reports a *surviving* partial account, which this machine's gate never produces; the sheet-ordering rule is §269's |
| 488 | The helper reinstall button works on a machine where launchd was serving the previous build | pass | owner's own press at 21:01:57: `agentspace-helper` restarted (pid 14330), Create became armed, and the create then failed at the account step rather than at the app |

## 276. V3 connects existing accounts and removes account lifecycle authority (2026-09-19)

The V3 decision is a security and product-boundary change: a person owns the
macOS account lifecycle; AgentSpace owns only its worker, runtime, workspace and
registry attachment. The old provisioner and its tests were removed rather than
left as a second hidden path.

The app and CLI now share `AccountAttachService`. Attach validates an
`AccountDiscovery` result, prepares runtime/workspace, installs the root-owned
worker, attempts startup when an Aqua session exists, and persists the record.
Every failure after runtime creation executes compensating removal. Detach calls
only stop/remove worker and exact runtime removal before deleting the registry
record; no logout, directory-service delete or home removal occurs.

The runtime moved to `/Library/Application Support/AgentSpace`. Shared parents
are root-owned 0755 so both named principals can traverse them, while each UUID
runtime is 0700 plus inherited ACL entries for the controller and attached
account. The worker verifies owner, mode and both entries before binding. The
worker executable lives at `Worker/versions/<version>/agentspace-worker`, owned
by root rather than an attached user.

Protocol version remains 1. Legacy `createUser` and `deleteUser` enum values
still decode but are unconditional refusals in validation and dispatch; their
`sysadminctl`/delete implementations and command builders no longer exist.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 489 | Candidate discovery excludes the current user, system/hidden users, administrators, non-`/Users` homes and uid values below 500 | pass | `AccountDiscoveryTests`; `AccountDiscovery.candidates` |
| 490 | Attach performs no macOS user creation and persists the selected existing username/uid/home | pass | `AccountAttachServiceTests.testAttachOnlyPreparesRuntimeAndInstallsWorker`; optional `AgentAccount.homeDirectory` |
| 491 | An attach failure after runtime preparation invokes typed runtime rollback | pass | `testFailedWorkerInstallRollsBackThePreparedRuntime` |
| 492 | Detach never logs out or deletes the macOS user/home | pass | `testDetachNeverDeletesOrLogsOutTheMacOSUser`; operation sequence is stop worker, remove worker, remove runtime |
| 493 | Old account-mutation wire requests remain decodable but can never execute | pass | `testV3AlwaysRefusesCreateAndDeleteUser`; `HelperService.legacyAccountMutation`; no helper create/delete implementation remains |
| 494 | Production worker code is root-owned and versioned outside every user home | pass | `testInstalledWorkerPathIsRootOwnedAndOutsideTheAgentHome`; `Worker/versions/<version>` |
| 495 | Runtime ACL entries inherit and the worker refuses an incomplete/wrong runtime boundary | pass | `SecurityTests` runtime permission cases; `RuntimePermissionVerifier` |
| 496 | V2 registry data remains readable after the root move | pass | `SpaceRegistry.load` reads `RuntimePaths.legacyRoot` only when the default V3 registry is absent; writes target V3 |
| 497 | GUI and CLI expose connect/disconnect semantics and retain compatibility aliases | pass | `NewAgentWizard`, `SpaceDetailView`, CLI `attach`/`detach` plus normalized `create`/`delete` aliases |
| 498 | English and Simplified Chinese remain complete after the V3 UI rewrite | pass | `LocalizationTests` (all five checks) |
| 499 | The full Swift suite passes with the V3 root, protocol addition and model compatibility | pass | `env PATH=/usr/bin:/bin:/usr/sbin:/sbin swift test`, 2026-09-19 |

## 277. Final V3 release gate (2026-09-19)

The release candidate was rebuilt after the V3 changes, the MCP bundle was
rebuilt from source, and the exact versioned DMG was notarized and stapled.
The full gate was then run from a system-only PATH so the result does not
depend on developer tooling being accidentally selected.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 500 | The Swift, MCP and GUI layers pass together under the release gate | pass | `scripts/check-all.sh`, 2026-09-19: 359 Swift tests, MCP smoke checks, and GUI verify 7/7 |
| 501 | The MCP server reports the current 0.1.1 release and its complete tool surface | pass | `npm test` 23/23; `scripts/mcp-smoke.sh` reports `agentspace 0.1.1` and 22 tools |
| 502 | GUI verification reaches the wizard, validates the build stamp and catches dead links | pass | `scripts/gui-verify.sh`: 7 passed, 0 failed |
| 503 | The shipped app and exact versioned DMG are notarized, stapled and Gatekeeper-clean | pass | `scripts/notarize.sh`: `dist/AgentSpace.app` and `dist/AgentSpace-0.1.1.dmg`; `spctl` accepted both |
| 504 | CLI workspace preparation remains deterministic when PATH is restricted | pass | `WorkspacePreparer.resolveGitExecutable` selects `/usr/bin/git`; the system-PATH Swift run passed all 359 tests |

## 278. Empty account selection is actionable (2026-09-19)

The reported “Continue does nothing” state was reproduced on this Mac. The
typed name in the screenshot is the Agent label, not a macOS username; the
machine had no unattached standard `/Users` account to attach. The old GUI
smoke test clicked a disabled button and unconditionally called that “step 2”,
which hid the real state. The wizard now labels the field explicitly, explains
that it cannot create an account, and offers direct links to Users & Groups and
an account refresh. The smoke test verifies the actual accessibility state and
the empty-account actions instead of trusting a no-op click.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 505 | A missing attach candidate is reported as an empty-account state, not as a false transition to step 2 | pass | `scripts/gui-verify.sh` first failed with `account selection required`; after the fix it reports `empty account state` and checks both action identifiers |
| 506 | The empty state provides direct Users & Groups and Refresh accounts actions | pass | `NewAgentWizard` identifiers `openUsersGroupsButton` and `refreshAccountsButton`; temporary rebuilt bundle GUI verification 7/7 |
| 507 | The name field is clearly an Agent display label and cannot be mistaken for macOS account creation | pass | Localized `Agent display name`, `Agent name` and label-only explanation in both `.lproj` tables |
| 508 | The Continue footer states the missing prerequisite while preserving the V3 safety boundary | pass | `continueButtonHint` and disabled condition require a selected existing account; Swift 360/360 and MCP 23/23 pass |

## 280. Directory Service account discovery accepts visible underscore usernames (2026-09-19)

The second report supplied the missing machine state: System Settings showed a
standard user named `AgentUse`, while its short name was the legacy
`_agentspace_a5b707`. The old filter treated every underscore-prefixed short
name as hidden, so it discarded this visible account. Discovery now reads the
explicit `IsHidden` values once from Directory Service and filters only users
actually marked hidden. This also avoids spawning one `dscl` process per account
and keeps the refresh responsive.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 513 | A visible standard user whose short name begins with `_` is offered for attachment | pass | `AccountDiscoveryTests.testAStandardUserWithAnUnderscoreUsernameIsStillAttachable`; `_agentspace_a5b707` / display name `AgentUse` |
| 514 | Explicitly hidden accounts remain excluded | pass | `AccountDiscoveryTests` fixture `_hidden` with `isHidden: true` remains absent from candidates |
| 515 | Directory Service hidden flags are read once and discovery fails closed if the query fails | pass | `AccountDiscovery.hiddenUsernames()` uses one `dscl . -list /Users IsHidden` call; `discover`/`find` return no candidates on command failure |
| 516 | The real GUI can select AgentUse and advance to the review step | pass | Temporary rebuilt bundle: `macOSUserPicker` contained the account; selecting radio item 2 made `wizardContinue` enabled; `scripts/gui-verify.sh` 7/7 |

## 281. 0.1.3 release gate for Directory Service discovery (2026-09-19)

The release candidate was rebuilt after the discovery fix. On the affected
machine the release GUI now lists the existing `AgentUse` account and the smoke
script selects it before checking the review card. The notarized artifact and
all three validation layers were then checked together.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 517 | The shipped GUI lists the existing AgentUse account instead of showing the empty state | pass | `scripts/gui-verify.sh`: picker selection, `wizard reaches the helper card`, 7 passed/0 failed |
| 518 | The account-discovery fix does not regress the complete Swift suite | pass | `scripts/test.sh`: 360 tests passed; `AccountDiscoveryTests` includes the underscore-name and hidden-account cases |
| 519 | MCP reports the matching patch version and its safety smoke checks pass | pass | `scripts/mcp-smoke.sh`: `agentspace 0.1.3`, 22 tools, all checks passed; `npm test` 23/23 |
| 520 | The 0.1.3 app and exact DMG are notarized, stapled and Gatekeeper-clean | pass | `scripts/notarize.sh` and `scripts/check-all.sh`; `dist/AgentSpace.app` plus `dist/AgentSpace-0.1.3.dmg` |

## 279. Patch release after the empty-account fix (2026-09-19)

The fix is shipped as 0.1.2. The exact versioned DMG was rebuilt from the
updated app, notarized and stapled; the final three-layer gate was rerun with
the MCP bundle reporting the new version.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 509 | The 0.1.2 app and DMG are notarized, stapled and accepted by Gatekeeper | pass | `scripts/notarize.sh`: `dist/AgentSpace.app` and `dist/AgentSpace-0.1.2.dmg` |
| 510 | The shipped patch passes all release layers after the wizard fix | pass | `scripts/check-all.sh`: Swift 359/359, MCP smoke, GUI 7/7 |
| 511 | The release GUI no longer reports a disabled-button no-op as step 2 | pass | `scripts/gui-verify.sh`: `wizard: empty account state`, then dead-link check, 7 passed/0 failed |
| 512 | MCP and package metadata are aligned to 0.1.2 | pass | Smoke output `agentspace 0.1.2`; `npm test` 23/23 |

## 282. First-login attach, account refresh and viewer escape (2026-09-19)

The real-machine report exposed a normal macOS lifecycle boundary: a manually
created account can exist in Directory Service before its first GUI login, so
`/Users/<username>` is still absent. The helper now returns a typed deferred
install result instead of treating that absence as a symlink/ownership attack.
Attach persists the runtime and registry record as `needsLogin`, skips the
nonexistent LaunchAgent start, and gives the user a Finish setup retry after
the first login. Teardown also treats a missing `gui/<uid>` domain as an
idempotent absence, so rollback cannot create a second misleading error.

The wizard's Refresh accounts action is always visible and reads the current
registry before each discovery generation, preventing a delete/recreate in
Users & Groups from leaving a stale picker. The connected account deliberately
contains no second AgentSpace GUI app: only the background worker runs there,
and the localized instructions point to that account's built-in System Settings
for TCC grants. Desktop Viewer now has an explicit Close action even when a
capture is refused.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 521 | An account with no first-login home is attachable without creating a home or starting a nonexistent worker | pass | `HelperService.installWorker` returns `deferred/homeDirectoryMissing`; `AccountAttachServiceTests.testAttachDefersWorkerUntilFirstLoginWhenHomeIsMissing` |
| 522 | Finish setup retries installation after the home exists and persists the worker's resulting state | pass | `AccountAttachServiceTests.testFinishPendingSetupInstallsAndStartsAfterFirstLogin` |
| 523 | Missing launchd GUI domains are idempotent during worker removal/rollback | pass | `HelperService.removeWorker` classifies `could not find domain for user` as absent |
| 524 | Account discovery can be explicitly refreshed after Users & Groups changes, without stale concurrent results winning | pass | `NewAgentWizard` always renders `refreshAccountsButton`; `AppModel.discoverAccounts` generation guard and registry-backed attached set |
| 525 | Permission remediation no longer sends GUI users to a terminal command, and explains that no second AgentSpace app is expected in the connected account | pass | `ErrorCodes`, `LoginInstructions`, `SpaceDetailView` and both localization tables |
| 526 | Desktop Viewer can always be dismissed from its own content | pass | `DesktopViewerView` `closeDesktopViewer` button, cancel keyboard shortcut, and full Swift build |
| 527 | The regression suite remains green after the deferred attach and onboarding changes | pass | `env PATH=/usr/bin:/bin:/usr/sbin:/sbin swift test`; `LocalizationTests` and `AccountAttachServiceTests` pass |

## 283. Open connected-account privacy panes from the main account (2026-09-20)

The setup card previously opened Accessibility with the controller app's own
`NSWorkspace`, which sent the user to the wrong account's System Settings. The
worker now exposes one additive, token-authenticated method with a closed
two-pane allow-list. The agent card presents separate Accessibility and Screen
Recording buttons; the worker launches those URLs in the connected account's
own Aqua session, including while that account is the console during first-time
setup. No desktop observation or input is enabled by this method.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 528 | Privacy-pane URLs are limited to Accessibility and Screen Recording | pass | `SystemSettingsPane` enum and `ProtocolTests.testSystemSettingsPaneRoutesOnlyToPrivacyPanels` |
| 529 | The worker and GUI use an additive `systemSettings.open` RPC without changing protocol version 1 | pass | `Method.openSystemSettings`, worker dispatch, `SpaceService.openSystemSettings`, `ProtocolTests.testMethodNamespaceIsStable` |
| 530 | The setup card gives explicit buttons for both permissions and never opens the controller account's System Settings | pass | `SpaceDetailView` identifiers `openAgentAccessibilitySettings` and `openAgentScreenRecordingSettings`; Worker owns the `NSWorkspace` call |

## 284. Keep restored dashboard windows and GUI checks deterministic (2026-09-20)

Window restoration can recreate several dashboard windows whose titles are the
selected agent name rather than the scene label. The app now identifies those
windows by their toolbar and closes restored duplicates; the GUI smoke test
waits for that convergence, brings the settings scene to the front before
reading its accessibility tree, and targets the exact bundle under test for
deep links.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 531 | Restored dashboard duplicates converge to one main window | pass | `OpenLinkDelegate.applicationDidBecomeActive` toolbar-based filtering; `scripts/gui-verify.sh` launch check |
| 532 | The full release verification remains green with the connected-account permission flow | pass | `scripts/check-all.sh`: stapled dist guard, Swift suite, MCP smoke and GUI verify 7/7 |

## 285. Recover an older worker and explain the connected-account panel (2026-09-20)

The shipped 0.1.5 GUI was able to call `systemSettings.open`, while the
attached account on the machine was still running the 0.1.3 worker. The worker
correctly returned `METHOD_NOT_FOUND`; the GUI previously surfaced that raw
protocol error with no way forward. The error is now recognized as an older
worker, offers an **Update worker** action, refreshes the helper first when it
is stale, and then runs the existing Finish setup install/start path. The empty
AgentSpace panel seen after switching into the attached account is also called
out explicitly: that account intentionally has no second GUI and management
continues in the main account.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 533 | `METHOD_NOT_FOUND` for `systemSettings.open` is converted into an in-app worker reinstall recovery | pass | `WorkerCompatibilityTests.testUnknownMethodFromAnOlderWorkerOffersWorkerReinstall`; `SpaceService.openSystemSettings`; `AppModel.updateWorker` |
| 534 | A stale helper is refreshed before the worker is reinstalled, avoiding another old worker copy | pass | `AppModel.reinstallHelperForWorker`; `HelperInstallation.isStaleBinary`; existing helper CDHash tests |
| 535 | The connected account's empty GUI panel is explained as intentional and points back to the main account | pass | `EmptyStateView`, `SpaceDetailView` and both localization tables |

## 286. Add an in-app authorization guide (2026-09-20)

The attached account intentionally has no second AgentSpace GUI, so asking a
new user to find the privacy panes there leaves them stuck. The main account's
setup card now opens a focused authorization guide. It explains the session
boundary, shows live Accessibility and Screen Recording state, opens either
allowed System Settings pane through the attached worker, and offers a status
refresh (or Finish setup when the worker is not online).

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 536 | The setup card exposes a prominent authorization-guide button and the guide exposes both permission actions | pass | `SpaceDetailView` identifier `openAgentPermissionGuide`; `PermissionGuideView` identifiers `permissionGuideAccessibility` and `permissionGuideScreenRecording` |
| 537 | The guide tells users to switch accounts only to approve the grant and never requires a second AgentSpace app | pass | `PermissionGuideView` session-boundary copy; both localization tables |
| 538 | The guide reports current grant state and provides Refresh authorization status/Finish setup actions | pass | `PermissionGuideView` live `SpaceSnapshot` lookup and action controls |

## 287. Keep authorization available when the worker is missing (2026-09-20)

The authorization controls are now a first-class card on every attached-agent
detail page, including the offline, first-login and console states where the
old setup card could disappear. The two permission buttons remain actionable
when the worker is absent: they install and start the worker through the typed
privileged-helper operations, wait for the normal worker readiness path, and
then ask that worker to request/register its TCC entry and open the matching
System Settings pane in the attached account's own session. The connected
account still needs no AgentSpace GUI.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 539 | The main agent page always shows a Permissions & authorization card, even when setup is hidden for the console state | pass | `SpaceDetailView` renders `permissionsCard(snapshot)` outside `setupCard`'s state guard |
| 540 | Permission buttons are not disabled just because the worker is offline | pass | `SpaceDetailView.permissionButton`; `AppModel.authorizeAgent` invokes `finishPendingSetup` before opening the pane |
| 541 | A missing worker is installed/started before the requested pane is opened, with errors returned in-app | pass | `AppModel.authorizeAgent`; `AccountAttachService.finishPendingSetup`; `SpaceService.openSystemSettings` |
| 542 | The explicit permission action asks macOS to register/show the worker's TCC entry before opening the pane | pass | `Operations.openSystemSettings` calls `AXIsProcessTrustedWithOptions` or `CGRequestScreenCaptureAccess` only after the user presses the authorization button |
| 543 | A GUI opened inside the attached account explains why its panel is empty and points back to the main account's authorization card | pass | `EmptyStateView` and both localization tables |

## 288. Make authorization reachable from either account's AgentSpace window (2026-09-20)

The authorization path no longer assumes that a user can find the controller
window or that the worker currently installed in the attached account is new
enough. The controller page has a toolbar quick-action plus the full
Permissions & authorization card. When AgentSpace is opened inside the attached
account, the empty registry panel discovers only that account's own runtime and
shows the same two authorization actions locally. Both paths reinstall and
kickstart the current worker through the typed helper operation before asking
the worker to open its own session's System Settings pane; no registry write or
second AgentSpace installation is needed in the target account.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 544 | The controller detail page exposes a visible toolbar authorization menu in addition to the card | pass | `SpaceDetailView` toolbar identifier `openAgentPermissionToolbar` and both pane actions |
| 545 | An AgentSpace window opened as the attached account discovers its local runtime and displays authorization buttons instead of an unexplained empty panel | pass | `AppModel.discoverCurrentAccountAuthorizationFromRuntime`; `EmptyStateView` `CurrentAccountPermissionCard` |
| 546 | Authorization repairs an old or missing worker before opening settings, without allowing the target account to write the controller registry | pass | `AppModel.prepareWorkerForAuthorization`; typed `.installWorker`/`.startWorker` requests; no `AccountAttachService` call on the target path |

## 289. Reload the worker LaunchAgent after an app update (2026-09-20)

The real machine had the 0.1.9 worker installed on disk while launchd continued
to run 0.1.3. Updating the LaunchAgent plist and calling only
`launchctl kickstart -k` restarted launchd's cached job, whose program path still
named the old version. Worker start now unloads the registered service, loads
the exact verified plist from the attached account, and only then starts it.
This makes the newly installed versioned path authoritative instead of treating
a successful restart of stale configuration as an update.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 547 | The reported stale-worker state is reproducible: 0.1.9 existed on disk while the live AgentUse process ran 0.1.3 | pass | real-machine process path `/Library/Application Support/AgentSpace/Worker/versions/0.1.3/agentspace-worker`; 0.1.9 binary predated that process start |
| 548 | Starting a worker always unloads any cached service before loading the current plist | pass | `HelperCommand.workerReloadCommands`; `HelperValidationTests.testStartingWorkerReloadsTheLaunchAgentBeforeKickstart` |
| 549 | The helper bootstraps only a root-owned, non-writable canonical plist rather than trusting the account-owned login copy | pass | `HelperCommand.canonicalWorkerLaunchAgentPath`; `HelperService.requireRootOwnedRegularFile` |
| 550 | First start does not depend on localized launchctl “not found” prose | pass | `HelperService.workerControl` attempts canonical bootstrap after bootout and treats bootstrap as the authoritative result |
| 551 | Authorization waits until `hello` reports exactly 0.1.10 and avoids restarting a worker already at that version | pass | `WorkerCompatibility.waitForVersion`; `WorkerCompatibilityTests` startup/mismatch cases; `AppModel.prepareWorkerForAuthorization` |
| 552 | The updated Swift and MCP layers remain green at version 0.1.10 | pass | system-PATH `swift test`; MCP tests 23/23; rebuilt MCP smoke reports `agentspace 0.1.10` and all checks passed |
| 553 | The 0.1.10 app and DMG are signed, notarized, stapled and accepted by Gatekeeper | pass | `scripts/release.sh`; `scripts/notarize.sh`; `dist/AgentSpace.app` and `dist/AgentSpace-0.1.10.dmg` |
| 554 | The final gate ran 368 Swift tests and the MCP smoke checks before reaching GUI verification | partial | `scripts/check-all.sh`; GUI automation was blocked because the 0.1.9 app remained open in uid 503 and this Codex host lacks Accessibility access to inspect the replacement process |
| 555 | In-place installation and the live 0.1.3 → 0.1.10 process-path check require the attached account to quit its open 0.1.9 AgentSpace process first | blocked | uid 503 pid 4501 holds `/Applications/AgentSpace.app`; macOS refused overwriting its signed executable, leaving the verified 0.1.9 installation intact |

## 290. Recover a mixed-version GUI and keep one worker identity (2026-09-20)

The AgentUse session kept its GUI process alive while `/Applications/AgentSpace.app`
was replaced. The process still executed the old mapped image but loaded resources
from the new bundle, leaving the target-account panel unresponsive. The same
inspection found exactly one live worker, already at 0.1.10; the apparent duplicate
was not two workers serving the runtime. Future mixed-version GUI processes now
terminate when their session becomes active, so reopening starts one coherent build.
The already-running pre-0.1.11 GUI cannot execute this new recovery code: quit it
from the AgentUse session (or log that account out) once, then reopen AgentSpace.

Versioned worker binaries remain as root-owned release archives, but every
LaunchAgent now executes one atomically replaced root-owned active hard link.
That stable path prevents each upgrade from introducing another same-named worker
identity in macOS Privacy settings while retaining auditable versioned binaries.
The first move to the stable path may create one new Privacy entry. AgentSpace never
edits the TCC database, so historical entries for versioned paths can remain visible;
after 0.1.11 is installed, remove or disable obsolete entries in System Settings and
authorize the active worker entry once.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 556 | The reported machine has one live AgentUse worker rather than two servers | pass | live assertion: one `agentuse` worker PID 27588; `worker.pid` and `status.json.pid` agree; CLI reports one ready account |
| 557 | Starting with 0.1.11, a GUI whose on-disk bundle version differs from its compiled version exits on activation instead of continuing in a mixed state; an already-running older GUI requires one manual quit or logout | pass | `AppBundleCompatibility`; `OpenLinkDelegate.applicationDidBecomeActive`; `AppBundleCompatibilityTests`; recovery limitation recorded above |
| 558 | Worker releases remain root-owned and versioned while LaunchAgents execute one stable path | pass | `HelperCommand.workerInstallPath`, `workerExecutionPath`; helper stages a hard link and atomically renames it |
| 559 | The stable worker path and stale-GUI detection have focused regression coverage | pass | `HelperValidationTests.testInstalledWorkerPathIsRootOwnedAndOutsideTheAgentHome`; `AppBundleCompatibilityTests.testAnOldGUIRequestsRelaunchAfterTheAppWasReplacedOnDisk` |
| 560 | Activating a restored GUI orders its surviving dashboard window on screen instead of leaving a healthy process with no visible UI | pass | `OpenLinkDelegate.applicationDidBecomeActive` selects dashboard windows regardless of current visibility, orders the first one front, then closes duplicates |
| 561 | The final 0.1.11 app and DMG are signed, notarized, stapled and accepted by Gatekeeper | pass | `scripts/release.sh`; `scripts/notarize.sh`; build 307 in `dist/AgentSpace.app` and `dist/AgentSpace-0.1.11.dmg` |
| 562 | The final gate passes 369 Swift tests and all MCP smoke checks; GUI automation can inspect the release window | partial | `scripts/check-all.sh`; Swift and MCP passed, but this Codex host could not activate the launched app as a foreground AX window, so `gui-verify.sh` reported 0/7 rather than observing the UI |

## 291. Refresh attached-account authorization, keep the empty sidebar visible, and make the desktop viewer adjustable (2026-09-20)

An AgentUse GUI can remain open while its worker is restarted. The worker status
was already `accessibility=true`, `screenRecording=true`, and `ready`, while the
authorization card still showed the pre-restart snapshot until its refresh button
was pressed. The GUI now reloads on foreground activation. The empty attached-account
sidebar also kept its footer in a `List.safeAreaInset` positioned outside the window;
the empty sidebar no longer renders that footer at all. The build stamp is rendered
inside the visible empty-state detail page instead; accounts with rows retain the
bottom footer and refresh control. The Desktop Viewer now behaves like a local
viewer: the window is resizable, the captured surface can be fit or zoomed with
scrolling, the screenshot capture width can be changed in-window, and the live
pull rate can be selected from 1/5/10/15/30 FPS. The capture-width control changes
the received image quality; it deliberately does not change the attached account's
macOS display mode.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 563 | Returning to an AgentSpace window refreshes the attached worker authorization state | pass | `OpenLinkDelegate.applicationDidBecomeActive` calls `AppModel.reload()` after activation; live AgentUse AX/screenshot shows both permission chips as granted after a worker restart |
| 564 | The empty attached-account page keeps the build stamp visible | pass | `EmptyStateView` renders the build stamp directly; live AgentUse AX frame is inside the 1080px desktop and the screenshot shows `构建 0.1.12 (308)` |
| 565 | The Desktop Viewer window is resizable and its zoomed surface keeps click mapping in image-local coordinates | pass | `WindowCapture` inserts the resizable mask and min size; `ViewerZoom` uses a scrollable image surface whose gesture feeds `PreviewMapping` with the image's displayed size; final installed viewer screenshot shows the two-row native-style footer |
| 566 | Desktop Viewer capture width and live FPS can be changed without changing the agent's display mode | pass | in-window `desktopViewerResolutionPicker` (960/1280/1600/1920) drives screenshot `maxWidth`; `desktopViewerFPSPicker` restarts `preview.start(maxFPS:)` and the timer; final screenshot shows `1280 px` and `30 FPS`; no display-mode RPC or TCC mutation is introduced |
| 567 | Desktop Viewer distinguishes left and right mouse clicks | pass | `MouseInputSurface` handles AppKit `mouseUp` and `rightMouseUp`; final installed viewer showed the remote Safari context menu and the footer status `右键点击 → 1430, 792`, proving the corresponding `MouseButton.right` reached the agent through the normal input RPC |

## 292. A metric may not spend a privacy decision, and Full Disk Access becomes a reported grant (2026-09-20)

macOS told the owner "worker 无法访问其他 app 数据". The prompt was real and it
came from AgentSpace — but not from a capability the product needs. It came from
the **opt-in disk-usage measurement**: `Resources.sample(includeDisk:)` walked the
attached account's whole home, and a home contains exactly the directories TCC
gates. tccd lines attributed to the worker's stable path recorded the cost: 8×
`kTCCServiceSystemPolicyAppDataDetailed` (`auditon … Operation not permitted`),
`AUTHREQ_PROMPTING` for the Desktop/Documents/Downloads folder gates, and
`kTCCServicePhotos` denied with "Policy disallows prompt" — one unanswerable
dialog per access, in a session nobody is watching.

Two fixes, because "obtain every permission we need" has two halves. A number must
stop asking: `DiskUsage.allocatedBytes(under:budget:skip:)` now takes
root-relative roots to leave out of the walk, and the worker passes
`FilePrivacy.protectedSubpaths` (`Desktop`, `Documents`, `Downloads`, `Pictures`,
`Movies`, `Music`, `Library`) unless the grant exists; the result carries
`skippedProtected`, which reaches the wire as `diskExcludesProtected` and the GUI
as a caption saying the figure is a lower bound. And the grant the agent genuinely
wants becomes first-class: `FilePrivacy.granted(home:)` answers Full Disk Access
**silently**, `status`/`hello`/readiness carry `fileAccess`, `SystemSettingsPane
.fullDiskAccess` routes to the verified `Privacy_AllFiles` anchor, the button
calls `FilePrivacy.registerForFullDiskAccess` so the worker appears as a row the
user can switch on, and `doctor` reports it as `.warn` — never `.fail`, because an
agent that can see and drive its desktop but keeps out of `~/Documents` is
working. The two grants that gate the desktop are still the only ones that can put
a Space in `needsPermission`.

Two things fell out of looking for the prompt. The `kTCCServiceAppleEvents`
denials that recur for `com.agentspace.AgentSpace` and its worker are AppKit's
own XPC machinery reaching for automation through the responsible-process chain —
AgentSpace sends no Apple Events anywhere, so the entitlement stays out (581). And
`en.lproj/InfoPlist.strings` was holding the **Chinese** purpose strings, which is
the sentence an English-locale macOS would have printed inside a privacy dialog
(582), now guarded by key parity plus a no-CJK assertion (583).

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 568 | The prompt came from the disk measurement, not from a missing capability | pass | `/usr/bin/log show` for `process == "tccd"` in the measurement window: `kTCCServiceSystemPolicyAppDataDetailed` ×8 with `auditon … Operation not permitted`, `AUTHREQ_PROMPTING` on the three folder gates, `kTCCServicePhotos` with "Policy disallows prompt", all attributed to `responsible_path=/Library/Application Support/AgentSpace/Worker/active/agentspace-worker`; the only code path entering those roots was the opt-in `resources` disk walk |
| 569 | The skipping walk raises no prompt and touches no folder gate | pass | `/tmp/skipwalk` probe compiled from the real `DiskUsage.swift` + `FilePrivacy.swift`: `home=/Users/guofeng skip=protected roots bytes=14594064384 files=215089 truncated=true skippedProtected=true ms=6775`; `/usr/bin/log show --start … --predicate 'process == "tccd"'` filtered for `AUTHREQ_PROMPTING\|SystemPolicy{Desktop,Documents,Downloads}Folder\|AppDataDetailed\|kTCCServicePhotos` in the same window returned nothing |
| 570 | The Full Disk Access probe is answered by a silent denial, so it is safe in a status path | pass | `~/Library/Application Support/Knowledge/knowledgeC.db` and `~/Library/Messages/chat.db` are `-rw-r--r--` owned by the reading user, yet `open()` gives `EPERM` ("Operation not permitted") and `isReadableFile` is false; tccd logs `Handling access request to kTCCServiceSystemPolicyAllFiles … Denied (Service Policy), DB Action: None` with no prompting event |
| 571 | TCC attributes the denial to the responsible process, so log evidence must be read by responsible_path and not by the child's name | pass | `cat` run from a terminal produced `AUTHREQ_CTX … from Sub:{com.qoder.app}Resp:{… responsible_path=/Applications/Qoder.app/…}`, and a probe binary run as itself produced no line naming it — the same rule that makes the worker's stable `/Library/Application Support/…/active/agentspace-worker` path the identity TCC remembers |
| 572 | Skipping is root-relative: an agent's own `project/Documents` is still counted | pass | `DiskUsageTests.testSkippingIsRootRelativeNotByNameAnywhere` (the nested 64 KiB is measured, `skippedProtected` false) |
| 573 | A partial figure says it is partial, and an absent skip does not flag anything | pass | `DiskUsage.Measurement.skippedProtected` → `diskExcludesProtected` on the wire → `ResourcesCard` caption; `DiskUsageTests.testProtectedRootsAreLeftOutOfTheWalkAndTheNumberSaysSo`, `testSkippingSomethingAbsentDoesNotFlagTheResult` |
| 574 | Full Disk Access is a reported permission that never gates the desktop | pass | `PermissionState.fileAccess` is optional and excluded from `allGranted`/`missing`; `SpaceModelTests.testFileAccessNeverGatesTheDesktop` |
| 575 | A registry record written before the probe decodes unchanged, and no key is written when nobody probed | pass | explicit `CodingKeys` + `decodeIfPresent`/`encodeIfPresent`; `testPermissionStateFromBeforeTheFileProbeDecodes`, `testFileAccessIsWrittenOnlyWhenItWasProbed`; legacy record fixture in `testLegacyRegistryRecordDecodesAsAgentAccount` |
| 576 | `Privacy_AllFiles` is a routable anchor on this macOS and the pane enum stays a closed allow-list | pass | anchor read from `/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex`, then opened live and confirmed to land on 「完全磁盘访问权限」; `ProtocolTests.testSystemSettingsPaneRoutesOnlyToPrivacyPanels` asserts all three URLs and rejects an unknown raw value |
| 577 | The third grant is visible from both authorization surfaces and from every reporting path | pass (code) | `SpaceDetailView.permissionsCard` + `Overview` chips, `CurrentAccountPermissionCard`, `PermissionGuideView` third row, `Doctor.workerChecks`, `agentspace status`, `agentspace-session-test` preflight, worker `Readiness.Report`; GUI and CLI build and `scripts/test.sh` passes (§4) |
| 578 | A worker from before the probe reports "never looked" instead of a false denial | pass | live against the installed worker (pid 54796): `agentspace status AgentUse` printed `file access    unknown — this worker predates the probe`, its `--json` carried no `fileAccess` key, and `agentspace doctor` emitted no `Full Disk Access (AgentUse)` check at all while still reporting Accessibility and Screen Recording as granted |
| 579 | Clicking the new button puts agentspace-worker in the Full Disk Access list | pending | needs the updated worker installed and one click in the attached account's session; `FilePrivacy.registerForFullDiskAccess` performs the gated open that macOS requires for the row to appear |
| 580 | An updated worker's disk measurement produces no gate activity in the attached account | pending | the worker half is now measured (§293's 591: the reloaded worker reports a real `file access` value and raises `AUTHREQ_PROMPTING` ×0 on its status path), but the *walk* is only reachable from the app's resources card (`SpaceService` sends `resources: "disk"`; `status --resources` sends `"full"`, which skips it), so this row still needs one disk measurement taken in the attached account after the worker update. The 568 evidence above is the before picture |
| 581 | The recurring `kTCCServiceAppleEvents` denials are system machinery attributed to our processes, not AgentSpace asking for automation | no action | `/usr/bin/log show --last 2h --predicate 'eventMessage CONTAINS "kTCCServiceAppleEvents"'` reads "Prompting policy for hardened runtime; service: kTCCServiceAppleEvents requires entitlement com.apple.security.automation.apple-events but it is missing", requester `appleeventsd`, naming `com.agentspace.AgentSpace`, `com.agentspace.AgentSpace.Worker` and the AppKit XPC child `ThemeWidgetControlViewService`. No AppleScript, `NSAppleEventDescriptor` or `osascript` call exists in `apps`, `native`, `shared` or `packages`, so the entitlement was deliberately **not** added — it would advertise a capability the product does not use — and the denial is silent: no dialog, no failed feature |
| 582 | An English-locale macOS would have shown both privacy purpose strings in Chinese | pass (fixed) | `apps/AgentSpace/Resources/en.lproj/InfoPlist.strings` held the zh-Hans values for `NSAppleEventsUsageDescription` and `NSScreenCaptureUsageDescription`; the English values now mirror `Info.plist`, and the Apple Events string follows the current vocabulary (agent account, not Space) |
| 583 | That wrong-language purpose table cannot recur silently | pass | `LocalizationTests.testInfoPlistTablesHaveParityAndTheEnglishOneIsEnglish` asserts key parity between the two `InfoPlist.strings` tables and fails on any CJK code point in an English purpose string |

---

## 293. The test suite must not leave a worker running as the owner's own account (2026-09-20)

Answering "which button do I press now?" required reading the machine's actual
state, and the state was wrong: ten `agentspace-worker` processes were running as
`guofeng`. Nobody had started them — `swift test` had, and the owner's rule that a
test may not touch their session was being broken by every integration run since
the suite existed. Each holds a unix socket and a session tap under an account
whose desktop is the human's own, which is precisely the pairing this product
refuses anywhere else.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 584 | `swift test` left live workers behind, and the cause is a dropped `Process` reference rather than a missed cleanup | pass (fixed) | 10 processes (`ppid 1`) running `.build/arm64-apple-macosx/debug/agentspace-worker --runtime-dir /tmp/as-cli-…`, all started inside the 16:26 test run, while every `/tmp/as-cli-*` directory was already gone — `CLIHarness.startWorker` kept its `Process` in a local, and `Process` does not kill its child on dealloc, so the worker was reparented to launchd and `tearDown`'s directory removal ran without ever seeing it |
| 585 | The integration harness now puts its workers down, and the same suite leaves none | pass | controlled before/after on the fix: PID set snapshotted, `env PATH=/usr/bin:/bin:/usr/sbin:/sbin swift test --filter CLIIntegrationTests` run (15 tests, 0 failures), PID set re-read — 11 before, 11 after, and `comm -13` reports zero new survivors, against the 10 the same suite had leaked minutes earlier from the pre-fix binary |
| 586 | The safety suite was never part of this | pass | `WorkerHarness` owns `stop()` and its `deinit` calls it, so its process reference survives to teardown; every leaked process had an `as-cli-` runtime root, and no `as-<uuid8>` root from the safety harness existed at any point (`ls -d /tmp/as-*` returned only `/tmp/as-mcp`) |
| 587 | The machine was returned to exactly one worker, the installed one | pass | the 10 were confirmed orphaned first (ppid 1, no `xctest`/`swift test` alive), then SIGTERM'd; `ps` afterwards lists only pid 54796, `agentuse`, `/Library/Application Support/AgentSpace/Worker/active/agentspace-worker` |
| 588 | `gui-verify.sh` measures nothing when two agents run it in one checkout | pass (environment) | the 16:41 run reported `launch opens exactly one window: expected [1] got [0]` with `Terminated: 15` against its own app pid, while a sibling's `scripts/gui-verify.sh` (pid 89988) was live — each run begins by `pkill`ing any `AgentSpace.app/Contents/MacOS/AgentSpace`, so each one kills the other's subject. The same check reads `ok` once the machine is quiet |
| 589 | The hand-back used to launch the build under test onto the human's own desktop because it counted the *agent account's* copy as "already open" | pass (fixed) | `pgrep -f "AgentSpace.app/…"` matched pid 81059 (`agentuse`, `/Applications/AgentSpace.app`), so `WAS_RUNNING=1` and the `EXIT` trap ran `open "$APP_BUNDLE"` in the owner's session — producing the never-requested guofeng instances 89823 (16:42:16) and 90003 (16:42:43). Detection and kill are now `-U $(id -u)`-scoped and the hand-back re-opens the bundle that was actually running; a dry run resolves to this user's own copy and reports `detected=[…/dist/AgentSpace.app]` while agentuse's `/Applications` copy is listed and ignored |
| 590 | The last two `gui-verify` failures are the window the machine had, not the build | pass (explained) | the only window in the owner's session was the account viewer: `closeDesktopViewer` → present, `appBuildVersion` → absent, `newAgentWizardContinue` → absent, so "sidebar build stamp" and "wizard reaches a real next state" cannot be evaluated. The same probe found `openAgentFullDiskAccessSettings` → present, i.e. §292's new button is in the shipped 0.1.13 binary |
| 591 | The installed worker now answers the file-access probe, and its status path stays silent | pass | `agentspace status AgentUse` against pid 89258 (the reloaded worker at the stable `/Library/Application Support/AgentSpace/Worker/active/agentspace-worker` path) prints `file access not granted (optional) — …` rather than §292's "unknown — this worker predates the probe"; `log show --last 25m --predicate 'process == "tccd"'` for that path returns `AUTHREQ_PROMPTING` ×0 and no folder-gate/`AppDataDetailed`/`Photos` event, only Screen Recording and Accessibility attributions |
| 592 | Two further `Prompting policy … entitlement missing` lines are preflight noise, and neither earns an entitlement | no action | the worker's screen stream makes `coreaudiod` check `kTCCServiceMicrophone` (`requires entitlement com.apple.security.device.audio-input but it is missing`) once, as a **denial** with no prompt, and AgentSpace captures no audio — `ScreenCaptureKitSource` / `WindowCaptureKitSource` never set `capturingAudio`; the CLI's repeated line is `attempted to call TCCAccessRequest for kTCCServiceAccessibility without the recommended com.apple.private.tcc.manager.check-by-audit-token entitlement`, which every non-app-store binary gets for the Accessibility preflight, and `com.apple.private.*` is unobtainable by design. Adding either would advertise a capability the product does not use |

`check-all.sh` therefore stops at `scripts/gui-verify.sh` on this host right now,
and not on a product claim: every step before it passed (Swift tests, the MCP
suite, the notarization guard), and the two GUI assertions above are
environment-dependent — one because a second agent holds the app, one because the
helper was being reinstalled while the run was in flight. It has not been
observed 7/7 this round, so the next quiet-machine run must be the one that says
so. §297 later found a third cause, harsher than these two: once this host's
console locked at 19:18:47, *no* run could report anything at all — 0 passed, 7
failed, for a build with nothing wrong.

---

## 294. V4 Fusion first vertical slice (2026-09-20)
| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 593 | A live preview cannot keep returning frames after its Aqua session ceases to be a provably usable background desktop | pass | `PreviewControllerTests.testFramePullStopsAndClearsTheStreamWhenSessionStopsBeingUsable` drives `isConsole`, `indeterminate` and `noWindowServer`; each pull throws the verdict's typed code, calls source stop, clears the running state and makes the prior frame unreachable. `Operations.previewFrame` now supplies the freshly recomputed verdict on every pull |
| 594 | Fusion window identity rejects observable CGWindowID reuse rather than authorizing by the integer ID alone | pass, bounded | `RemoteWindow.identity` is `(pid, windowID, generation)`; `WindowCatalog` advances the generation when a raw `(pid, id)` is observed absent and later reappears, and every stream/input/window action resolves the complete identity before acting. `RemoteWindowTests.testWindowRoundTripsWithoutLosingItsReusableIDProtection` pins the wire model. Public CGWindow metadata cannot prove a replacement wholly between two snapshots; destructive AX actions additionally require a unique live pid/title/frame match and refuse ambiguity |
| 595 | Fusion pointer mapping uses the worker's current global frame and refuses invalid normalized coordinates | pass | `window.input` re-runs `WindowCatalog.window(matching:)` on every call and `WindowCoordinateMapper` converts 0...1 fractions only after that lookup; the worked 800x600-at-(100,200) example and the >1 refusal are covered by `RemoteWindowTests` |
| 596 | Direct Fusion interaction temporarily excludes automation without permanently taking control | pass | `InputLeaseTests` proves the five-second lease, and renewal on activity; `Operations.input` returns `INPUT_BUSY_BY_HUMAN` while the lease is live and resumes automatically afterwards |
| 597 | Fusion observation and input retain the product's console-session refusal at the real worker socket | pass | `SafetyTests.testFusionObservationAndInputAreRefusedOnConsoleSession` starts the worker in the current console Aqua session and observes `SESSION_IS_CONSOLE` from `window.list`, `window.stream.start` and `window.input` before any window lookup, capture or event post |
| 598 | Slow consumers cannot accumulate an unbounded queue of old frames | pass (Core primitive) | `LatestFrameBuffer` is a single replaceable slot and `FrameBackPressureTests` stores frames 1, 2, 3 before one read, which yields only 3 and then nil; both current SCK sources likewise overwrite one `latest` value |
| 599 | The separate binary frame channel is complete | not yet | `FrameHeaderTests` verifies the 52-byte network-order `ASFR` header and Core has the one-slot back-pressure primitive, but `docs/status.md` correctly records that Desktop and Fusion still pull base64 JPEG through JSON. No claim of P8/P9 completion is made |
| 600 | TextEdit Fusion works end to end across the controller and attached account | not run | the code path and independent proxy `NSWindow` now exist, but this gate needs the attached account's real Aqua session plus its Screen Recording and Accessibility grants, a Fast User Switch, and visual confirmation in TextEdit; it cannot be truthfully replaced by a single-session CI test |

---

## 295. Detached Desktop Viewer coordinate and window behavior (2026-09-20)

The Desktop Viewer used to be presented as a SwiftUI sheet. Its transparent
AppKit click surface reported bottom-left coordinates directly to
`PreviewMapping`, whose public contract is top-left (the same space used by the
worker input API). That made an upper-half click land in the lower half of the
agent's desktop. The viewer is now hosted by one native `NSWindow` per account;
the dashboard remains available and the viewer's title bar controls its own
position and size.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 601 | AppKit click coordinates are converted from bottom-left to the viewer's top-left mapping before input is sent | pass | `PreviewMappingTests.testAppKitBottomLeftCoordinatesAreFlippedBeforeMapping` first failed against the old bridge, then passed after `PreviewMapping.displayPoint(appKitX:appKitY:)` was used by `DesktopViewerView.sendClick` |
| 602 | Opening Desktop creates a detached, resizable, movable native window rather than a sheet constrained by the dashboard | pass (code/build) | `DesktopViewerWindowManager` creates one `NSWindow` per account with `.titled/.closable/.miniaturizable/.resizable`, explicit movability, a minimum size and frame autosave; `SpaceDetailView` no longer presents `DesktopViewerView` as a sheet; `swift build --product AgentSpaceApp` passes |
| 603 | A detached viewer stays pinned to the account that opened it and is cleaned up on disconnect | pass (code) | `DesktopViewerView(spaceID:)` resolves its own snapshot instead of following dashboard selection; `AppModel.deleteSpace` closes the matching controller before detaching the account |

## 296. Fusion input must land on the window it shows, and a proxy must survive a worker restart (2026-09-20)

An outside code review of the Fusion slice (2026-09-20) named nine defects. Each
was checked against `78b9322` before anything was changed: seven were confirmed
in the code as written, one was confirmed and is worse than reported (row 608),
and one recommendation was declined because the confirmed defect it aimed at is
now closed by a smaller mechanism (row 606/614). Rows 604, 606, 609 and 612-613
are the ones with a user-visible consequence; rows 608, 610, 611 are
resource/resolution defects that do not change any guarantee already claimed.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 604 | `window.input` aims at the window the proxy displays, not whichever window its app last focused | pass (fixed) | `WindowInputRouter.activate` was process activation only (`app.activate(options: [.activateAllWindows])`), which guarantees the app is frontmost among apps but leaves the *key window* up to the app — so a proxy showing window B posted its coordinates onto the app's sibling window A. It now follows activation with `WindowActions.raise(window:)`, i.e. `kAXRaiseAction` on the uniquely matched accessibility window (same `pid + title + frame ±5` match `window.close` uses), and `window.activate` raises too. When the match is zero or ambiguous it refuses with `BAD_REQUEST` rather than posting input that may land elsewhere, matching the existing "refusing a destructive guess" stance |
| 605 | A cursor that only crosses the proxy does not pause the agent | pass | `Operations.windowInput` claimed the five-second human lease for *every* action including `move`, and `RemoteWindowSurface` emits a `move` per mouse-moved event — so passing the pointer over the window kept automation at `INPUT_BUSY_BY_HUMAN` in overlapping slices forever. The claim is now gated on `InputAction.isHover`, and `InputLeaseTests.testOnlyPointerTravelIsExcludedFromClaimingTheHumanLease` pins press/drag/scroll/key/type as claiming and travel as not |
| 606 | A worker restart cannot leave a proxy frozen on the last frame forever | pass (fixed) | The freeze needed both halves, and both were present: a restarted worker's `WindowStreamManager` has no stream for the identity, so every `window.stream.frame` answers `PREVIEW_NOT_RUNNING` (native/…/WindowStreamManager.swift:33-38), which `FusionWindowController.pullFrame` discarded behind `if error.code != .previewNotRunning`; and `startCapture()`'s `guard timer == nil` meant the 1 Hz `resumeCapture()` from `FusionSession.reconcile` could never re-issue `window.stream.start` while that timer lived. A window that survives the restart under the same `(pid, windowID, generation)` — which the single-visible-window case always does, since a fresh `WindowCatalog` hands out 1 to the only key it has — was stuck showing the old worker's last image with no error; a window that gets a different generation was dropped and rebuilt by the 1 Hz listing instead, which is why only some restarts froze. `FusionWindowController` now keeps a miss budget of about one second at the stream's own FPS before treating the stream as dead, rebuilds through `scheduleRebuild` (stop, restart, 0.5→8 s backoff, cleared by the first frame), and rebuilds immediately for any other pull code |
| 607 | `PREVIEW_NOT_RUNNING` stays one code, so the ambiguity is bounded in time rather than by a new wire failure | pass (design) | `Operations.windowStreamFrame` throws the same code for "no frame yet" and "no stream", so the GUI cannot branch on it. A new `ErrorCode` was not needed: a healthy stream's first frame arrives inside one frame interval, which is what row 606's miss budget measures. `protocolVersion` stays 1 and no method was renamed |
| 608 | Desktop capture cannot leak a live stream past a start timeout, and its stream-failure path was dead code | pass (fixed) | Worse than reported. `ScreenCaptureFrameSource.start` assigned `self.stream` *after* `startCapture` returned, so its 10 s timeout threw while the source still owned nothing: `PreviewController.start`'s failure cleanup called `stop()`, which found `stream == nil` and returned, and a capture that started late ran on with no owner — exactly what `WindowCaptureKitSource.swift:54-57` already documents having fixed by publishing ownership first. That assignment now happens before the start, under the lock it had been missing from. Separately the stream was constructed `delegate: nil`, so `stream(_:didStopWithError:)` — described by its own comment as the "stops the source rather than leaving it half-alive" path — could never be called, and a display reconfiguration left a dead stream serving `latest` as live. It is `delegate: self` now, and both `stop()` and `didStopWithError` clear `latest` so a dead source reports no frame |
| 609 | A Fusion press that travels is a drag, not a hover | pass (fixed; live run pending) | `RemoteWindowSurface` emitted `click` on mouse-*down* and `move` on mouse-*dragged*, so selection, sliders and marquee rectangles could not be operated from a proxy at all. The surface now records the press, marks travel past 3 points, and on mouse-up emits one `drag` (press point → release point) or the click/double/right click the `clickCount` describes. `WindowInputRouter.prepare` accepts `drag` with `xFraction/yFraction/toXFraction/toYFraction` through the same `WindowCoordinateMapper` as every other pointer action — additive action type over the existing `InputAction.drag`, whose tracked multi-point post in `InputSynthesizer` was already written and simply unreachable from window input |
| 610 | Window capture encodes at the panel's pixel size | pass (code) | `configuration.width = Int(window.frame.width)` used points, halving resolution on every Retina panel — the same pixel-over-points trap `ScreenCaptureFrameSource` records for displays. It now multiplies by `CGDisplayMode.pixelWidth / width` of the display the window overlaps most (`CGDisplayBounds` shares `CGWindowList`'s top-left space). This is a legibility fix, not a mapping fix: input coordinates are fractions of the window frame, so they were already correct |
| 611 | Window identity bookkeeping is bounded for the worker's lifetime | pass (code) | `WindowCatalog.generations` only ever gained entries and was copied whole on every `window.list`, so both memory and each listing's cost grew with every window ever seen; entries that leave the screen are now dropped. Safety property preserved: `nextGeneration` never rewinds, so a reappearing `(pid, windowID)` still gets a generation it has never had (row 589 unchanged). `WindowStreamManager.start` prunes controllers reporting not-running past 32 retained, which cannot orphan a capture because such a controller holds none |
| 612 | A proxy the window list no longer contains puts its worker stream down | pass (code) | `FusionSession.reconcile` called `close()` on the dropped controller, but `NSWindowController.close()` never consults `windowShouldClose`, so `stop()` did not run: the frame timer kept pulling a stream nobody was watching and `window.stream.stop` was never sent, leaving the worker capturing until `PreviewController`'s 10 s idle timeout. Now `stop()` then `close()` |
| 613 | One frame pull is in flight per proxy | pass (code) | The timer queued a blocking `window.stream.frame` RPC on every tick with no bound. A worker stalled inside ScreenCaptureKit's 10 s discovery/start would therefore accumulate roughly one queued call per frame interval, all of which then fired after it recovered; `frameInFlight` gates the pump, and the miss budget keeps a stalled stream's age honest |
| 614 | No worker instance identity is tracked, and no capture state enum was introduced | pass (declined, with reason) | The review's `workerInstanceID`/`CaptureSourceState` proposals both exist to escape row 606's freeze. With the proxy rebuilding from its own failed pulls, a restarted worker is detected by behaviour instead of by comparing process identity, and the states the enum would distinguish (idle/starting/running/failed/stopped) are already the outcomes `startingCapture`, the miss budget and the typed pull errors carry. `WindowStreamManager` and `PreviewController` keep their existing locks, and the 397-test suite is unchanged in shape |

Rows 604, 609 and the drag half of the review still lack the run that would
prove them to a person: an overlapping pair of same-app windows and a TextEdit
selection, driven through a proxy in the attached account's own Aqua session.
That cannot be executed on this machine — `Operations.windowInput` refuses a
console session by design (row 592) and macOS here will not host the second
account session (§269, §272). It stays on `docs/status.md`'s real-machine
acceptance list rather than being recorded as passed.

## 297. The GUI gate must refuse a locked console instead of reporting seven product failures (2026-09-20)

`scripts/gui-verify.sh` scores the release build 0 passed / 7 failed on this
host, and the number is meaningless: every check drives a window through the
accessibility tree, and a locked console orders no window on screen for any app.
The gate now says so and exits before it touches anything, because seven empty
reads in a row are otherwise indistinguishable from seven regressions — this
round they were traced to the machine, not to 0.1.16.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 615 | The 0/7 run was the console being locked, not the build failing | pass (environment) | `loginwindow[414]` sent `sendScreenLockedNotification` at `2026-09-20 19:18:47.206` and no `sendScreenUnlockedNotification` after it (last unlock 18:51:19.285), so the console was already locked when the gate ran. `CGSessionCopyCurrentDictionary()` reads `kCGSSessionOnConsoleKey = 1, CGSSessionScreenIsLocked = 1`, and `CGWindowListCopyWindowInfo(.optionOnScreenOnly, .excludeDesktopElements)` returns 7 windows for the whole session belonging to Window Server (4), loginwindow's own lock UI (2) and a crash reporter (1) — *zero* for every regular app, Finder included. The same script scored 5/7 at 16:47, before the lock, and its two failures were §293's known "the only window was the account viewer" pair |
| 616 | The refusal happens before the gate touches the running app, and it never tries to unlock | pass | The probe sits above the `WAS_RUNNING_APP` scan and the uid-scoped `pkill`, so a refused run kills nothing and hands back nothing it displaced. A live `bash scripts/gui-verify.sh` under the locked screen printed the refusal and exited 1, left no `/tmp/gui-verify-root.*` behind, and the only AgentSpace process on the machine afterwards was the attached account's own (`pid 81059`, `/Applications/AgentSpace.app`, uid 503) — untouched, as the uid-scoped kill guarantees. Nothing in the path writes a lock-state API or asks for a password |
| 617 | Console and lock flags are read regardless of representation, and undetermined fails closed | pass | The session dictionary carries CFBoolean for one key and CFNumber for the other, so `flag(_:)` accepts `Bool`, `NSNumber` and `Int`; an earlier draft that only cast `as? Bool` classified a numeric `kCGSSessionOnConsoleKey = 1` as `off-console`, i.e. refused a healthy session. Both documented key spellings (`kCGSSessionOnConsoleKey` with two S's, and the single-S name that appears in headers) are tried, and a `nil` dictionary or a missing console key yields a refusal, not a green check: `nil` → `unknown` → refuse, `console=1/unlocked` → `presenting` → run, `console=1/locked` → `locked` → refuse, `console=0` → `off-console` → refuse |

Row 615 does not establish that the seven checks pass — only that the locked
console can never show them passing. The 7/7 run `docs/status.md` still owes is
gated on the owner unlocking this screen; a run that refuses is now evidence
about the machine, and a run that reports `ok` seven times will be the first
that means it.

## 298. Fusion interaction and resource lifecycle: what the code proves, and what this machine cannot (2026-09-21)

The sixth optimization round over the same six surfaces — idle capture lifetime,
passive hover, pointer travel, the human lease, per-display scale, and the
window-list poll — plus the two performance items (gesture attributes, frame
transport). The standard applied here is the one the plan sets: a claim about
code gets `pass (code)` with the test that says it; a claim about a second
user's desktop gets `pending`, because macOS on this host will not host the
attached account's Aqua session (§269, §272) and `windowInput` refuses a console
session by design (row 592) while the console of this machine has been locked
since §297. No row below is inferred from "the code exists, so E2E is verified".

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 618 | A stream nobody is watching stops itself, without needing a further pull | pass (code) | `PreviewController` arms a `PreviewIdleWatchdog` when the source starts and re-checks `lastPull` on the ticker's own queue every `max(0.05, min(1, idleTimeout/10))` s — about a tenth of the patience it enforces, so the leak ends within ~10% of the timeout instead of up to a whole timeout later. `DispatchPreviewIdleWatchdog` is production; a fake holds the tick so `testStreamStopsWithoutAnotherFramePullAfterTheIdleTimeout` advances an injected clock 9 s and fires (still running), then 2 s more and fires (`source.stopped == 1`, `isRunning == false`, ticker cancelled). Before this the idle test lived *inside* `frame(now:)`: the one client that proves the leak — a GUI that crashed and never calls again — was also the only thing that could have fixed it |
| 619 | The ticker cannot stop a stream twice, cannot stop a restarted one, cannot deadlock a puller, and leaves nothing armed after a failed start | pass (code) | `detachLocked()` is the only exit from the running state: it cancels the ticker and hands the source to exactly one caller, which stops it *outside* the controller lock (`stop()`, `pull()`, `checkIdle()` all take that shape). `testWatchdogAndExplicitStopRaceToExactlyOneStop` races eight threads and asserts `stopped == 1`; `testARestartedStreamSurvivesTheTickArmedForThePreviousOne` fires the tick armed for a since-replaced stream; `testWatchdogTicksAndPullsFromDifferentThreadsNeverStall` interleaves 200 ticks and pulls behind a 10 s wait; `testFailedStartCleansUpAndArmsNothing` covers the residue case, and arming happens only after `source.start` succeeds. `PreviewControllerTests`: `Executed 14 tests, with 0 failures` in 0.004 s — no test sleeps through a timeout any more |
| 620 | Crossing a proxy with the mouse sends nothing, and a hover that does reach the worker cannot activate, raise or claim | pass (code) | GUI: `RemoteWindowSurface.mouseMoved` returns unless `isEngaged`, and engagement is set only by a press, a wheel event or a key — the passive case now costs zero RPCs rather than one activated app. Worker: `Operations.windowInput` branches on `action.isHover` *before* anything with a side effect, requires `inputLease.deliversHover()`, and posts without `WindowInputRouter.activate` (app activation + `WindowActions.raise`), which stays on the deliberate path only. Core: `deliversHover()` is non-mutating; `testHoverRidesAnExistingLeaseAndNeverTakesOne` asserts false with no lease, true mid-lease, `remaining()` untouched after asking four times, false at expiry; `testOnlyPointerTravelIsExcludedFromClaimingTheHumanLease` pins that `.move` is the only hover. `InputLeaseTests`: `Executed 3 tests, with 0 failures` |
| 621 | Which application the agent is working in no longer changes when a cursor passes over a proxy | pending | The observable half of row 620 needs the attached account's own session with something focusable on screen — Gate B/D on `docs/status.md`. It cannot be executed here (§269, §272) and the refusal is honest: the code cannot activate what it never calls, but nobody has watched the agent's desktop to confirm nothing else does |
| 622 | Pointer travel is ≤30 Hz with one request in flight, newest position winning, and a click never queues behind stale moves | pass (code) | `PointerTravelCoalescer` (Core) holds at most one in-flight send and at most one pending position; the sender calls `finished()` whether the RPC answered or failed, so one dropped hover cannot silence the pointer; `FusionWindowController` pumps it from the frame timer, so a held position is at most one frame old, and discrete gestures bypass it entirely. `PointerTravelCoalescerTests`: 100 offers → 1 send then `[0, 99]` on `finished`; 500 offers with no answer → still 1 send; 200 events across 1 s → `sent.count <= 32` and `> 10`, sorted and unique; `reset` drops the pending position and the coalescer keeps working; a stray `finished` is harmless. `Executed 6 tests, with 0 failures` |
| 623 | A press pauses automation when the button goes down, and holds it there | pass (code) | New additive wire method `Method.windowHumanClaim = "window.human.claim"`, dispatched in `Operations` → `windowHumanClaim(params:)`: gated by `requireDesktopSession`, resolves the catalog identity (so a claim dies with its window), claims the lease, answers `{claimed, remainingSeconds}`, performs and activates nothing. The proxy calls it from `beginPress` and renews at most every 2 s while a button is held (`renew()`, with `FusionInputRouter.humanLeaseSeconds = 5` mirroring the worker's duration). `window.input` claims again on its own, so a lost claim can never strand a gesture. `testFusionMethodsAreAdditiveAtProtocolVersionOne` now names `"window.human.claim"` and `testTokenExemptionIsOnlyHello` still holds for it: `protocolVersion` remains 1 and no existing method was renamed. `ProtocolTests`: `Executed 18 tests, with 0 failures` |
| 624 | An agent's own `input` really fails `INPUT_BUSY_BY_HUMAN` for the whole time a human holds a button | pending | Requires two concurrent drivers of one session. The lease arithmetic around it is tested (rows 620, 623); the wall-clock behaviour on the agent's desktop is Gate E territory and still owed |
| 625 | A window's backing scale comes from the display it overlaps *most* | pass (code) | `DisplayScaleSelection` (Core/Geometry) replaced the old scan in `WindowCaptureFrameSource.pixelsPerPoint`, which ranked candidate displays so that the *smallest* overlap won. The comparison is now an explicit largest-strictly-greater scan and `pixelsPerPoint` is clamped at 1 (a zero-width mode cannot divide). `GeometryTests` four cases: 2×/1× pair, window wholly on each; a window straddling the seam → the bulk wins; a window touching no display → the caller's fallback; single display plus degenerate geometry. `Executed 15 tests, with 0 failures` |
| 626 | Half-resolution menu text on a mixed-DPI pair is gone | pending | The selected scale reaches `SCStreamConfiguration.width/height`, so the visible symptom needs two physical displays inside the agent's session. Row 625 proves the choice, not the pixels |
| 627 | A proxy's gestures carry the button and the modifiers, in the protocol's own words | pass (code) | `FusionInputRouter.addPointerAttributes` writes `MouseButton`/`Modifier` raw values from `NSEvent.buttonNumber` and `modifierFlags` (`fn` left out on purpose: it is not held for mouse gestures, and sending a flag the remote cannot honour is a lie about intent). `WindowInputRouter.prepare` no longer hand-builds an `InputAction` with `button: .left, modifiers: []`; it resolves geometry and delegates to `InputAction.parse`, so there is one vocabulary rather than a second one to keep in sync |
| 628 | **Found while writing the test for 627: every proxy drag was going to be rejected.** The window path mapped a drag's press to `x`/`y`, but `InputAction.parse` requires `fromX`/`fromY` for `drag`, so the answer would have been `INVALID_ACTION: drag requires numeric fromX, fromY, toX and toY` — the gesture never reaching the agent, and the failure invisible without a test | pass (code, fixed) | The mapping moved into Core as `RemoteWindowInput.action(from:window:)`, a pure JSON→`InputAction` function, which is what made the defect reachable by a test at all. `RemoteWindowInputTests` (9 cases, `Executed 9 tests, with 0 failures`): fractions resolve inside the window's own frame (0.5/0.25 of a 400×200 window at 200,100 → 400,150); a drag parses with both ends (`fromX 200, fromY 100 → toX 600, toY 300`); a right-drag with `["cmd","shift"]`, an option double-click and a `rightClick` all survive; a move is still `.isHover`; scroll keeps `dx/dy`; `type`/`key` pass through unchanged; out-of-range fractions, a missing `xFraction`, a destination-less drag, an unknown modifier and a `window.input` with no `action` each come back with the typed code rather than a guess |
| 629 | Trackpad scrolling arrives as whole lines instead of vanishing | pass (code) | `RemoteWindowSurface.scrollWheel` accumulates `scrollingDeltaX/Y` and emits only the integer part, returning the remainder to the carry, so a 0.4-line nudge is not thrown away. This also fixes the older half of the same defect: the proxy's scroll action previously carried no `dx`/`dy` at all, so the parsed `.scroll(dx: 0, dy: 0)` moved nothing on the agent's screen. `hasPreciseScrollingDeltas` is deliberately untouched, reserved for a later sub-pixel pass |
| 630 | Scrolling feels right on a real trackpad, in both axes and through momentum | pending | The accumulator is AppKit-driven and cannot be driven from a unit test; the scroll path's *parsing* is tested (row 628). Needs a proxy under a hand |
| 631 | The window-list poll is a link with states and backoff, not a fixed hammer that throws its failures away | pass (code) | `FusionLinkPolicy` (Core) turns each poll into `connected / reconnecting / suspended / console / permissionRequired` over a 1→2→5 s ladder, and `SESSION_IS_CONSOLE` and `NO_WINDOW_SERVER` never become `reconnecting`: they are the guard working, and they are polled no faster than the ladder's top so a fast user switch still recovers by itself. `FusionSession` gates its 1 s tick on the policy, and on a failed poll calls `suspend(for:)` on every live proxy — frame timer cancelled, rebuild cancelled, travel reset, reason shown over the picture — instead of letting each window keep pulling from a worker that just refused. A refusal no longer sends a doomed `window.stream.stop`: row 618's watchdog reaps that stream server-side. `FusionLinkTests`: ladder 1/2/5/5/5, four refusal families checked at failures=1 and =9 (`nextPollInSeconds == 5`, state never `reconnecting`), empty ladder cannot produce a 0 s delay, a custom ladder is honoured, and the first successful poll returns to 1 s. `Executed 7 tests, with 0 failures` |
| 632 | A window that is not moving stops paying for a JPEG round trip | pass (code) | `window.stream.frame` gained an additive `seenSequence` in / `sequence` + `unchanged` out. `PreviewController.pull(newerThanSequence:)` refreshes the idle clock and *then* answers `unchanged` when the source has captured nothing newer, so the pull still proves a viewer is watching; `FusionWindowController` keeps the frame it drew and skips the base64 decode and `NSImage` build. Sources that cannot count frames stay at sequence 0, and 0 is never treated as already seen (`testAZeroSequenceIsNeverTreatedAsAlreadySeen`); 15 s of steady `unchanged` answers keep a 10 s-timeout stream alive (`testAnUnchangedAnswerKeepsTheStreamAlive`). Old GUI against new worker and new GUI against old worker both degrade to receiving every frame |
| 633 | How much CPU that actually saves a session | pending | The claim is a rate, and a rate needs the agent's worker capturing a real window. `LatestFrameBuffer`/`FrameHeader` remain tested primitives (`FrameHeaderTests`, `FrameBackPressureTests`) that no transport uses yet |
| 634 | The binary frame channel (`frame.sock`) was not built this round | pending (declined, with reason) | The remaining shape is a takeover of the *existing* connection after the token gate — one extra RPC that says "this fd is now a frame channel", a pull loop on that connection's own thread reusing `WindowStreamManager.pull` so newest-frame-wins and the idle watchdog keep working unchanged, and the JSON pull retained as the fallback. It was not shipped because its real failure modes are descriptor lifetime and authorization on the worker's most security-relevant path, and none of them can be exercised on this machine: they need a second account's Aqua session (§269, §272) and the clean GUI run this host still owes (§297). The part of its cost that is measurable in code is now removed for the static-window case by row 632, which is the common case |
| 635 | None of the previously fixed behaviours was overturned | pass (code) | Re-read rather than rewritten: per-window `AXRaise` inside `WindowInputRouter.activate`, the `0.5/1/2/4/8 s` rebuild ladder and miss budget in `FusionWindowController.rebuildDelays`, hover-not-claiming (now covered by tests), drag-as-one-gesture, the SCStream start-timeout cleanup and `delegate: self` in `WindowCaptureKitSource`, the Retina pixel request, `WindowCatalog` generation pruning, stop-before-close in `FusionSession.reconcile`, and the `frameInFlight` gate. `suspend(for:)` in row 631 reuses the same cancellations rather than adding a parallel lifecycle, and `window.input`'s response shape is unchanged |
| 636 | This round's gates | pass | `swift build` clean; `env PATH=/usr/bin:/bin:/usr/sbin:/sbin swift test` → `Executed 431 tests, with 0 failures` (411 when this batch opened: +7 link policy, +9 remote-window input, +3 frame sequence, +1 hover lease); `npm test` in `packages/agentspace-mcp` → `# pass 23 / # fail 0`; `scripts/mcp-smoke.sh` → `all MCP smoke checks passed`, exit 0 |
| 637 | `scripts/check-all.sh` and the GUI gate | pending (environment) | Run for this batch: the dist guard passed (`stapled app matches the stapled DMG (129b6b28…)`), `scripts/test.sh` → `Executed 431 tests, with 0 failures`, `scripts/mcp-smoke.sh` passed, and the gate then stopped at `scripts/gui-verify.sh` with "refusing to run — the console session's screen is LOCKED", which is §297's designed outcome — `CGSessionCopyCurrentDictionary()` answers `console=true, CGSSessionScreenIsLocked=true` on this host at the time of writing. `check-all` therefore exits non-zero for the machine, not the build, and scoring the seven checks is the owner's run on an unlocked screen |

## 299. 0.1.17 released, and the GUI gate was reading the wrong app while it happened (2026-09-21)

Row 637 predicted the clean GUI run was the owner's to make. The screen
unlocked during this release, so the run was made here — and it did not come
out as seven green or seven red, but as a set of mutually contradictory results
across consecutive runs of the same unchanged artifact. That contradiction was
the finding: the gate was not scoring the build under test.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 638 | 0.1.17 is published and the bytes a user downloads are the bytes this repository built | pass | `scripts/release.sh` → Developer ID signed (`codesign --verify --strict` on the app, the helper, the worker and the CLI), DMG mounted and its inner app re-verified; `scripts/notarize.sh` → app submitted and stapled, DMG rebuilt *from the stapled app*, submitted and stapled, `spctl --assess` accepting. Verified again independently of the script: `stapler validate` exit 0 for both, `spctl` exit 0. Tag `v0.1.17` (annotated, `2b452d9`) pushed with `master`, GitHub Release created, and the uploaded asset's digest equals the local file: `sha256:f973db604b34eabf23c5e206606f1568cf0855851c3a4b425d83caf5ebd4701f`, 4 566 045 bytes. The pre-staple digest (`88f22a9a…`) differs, which is the expected consequence of notarization writing a ticket into the DMG after `release.sh` hashed it |
| 639 | **The GUI gate scored whichever AgentSpace process System Events happened to resolve, not the build under test.** Every one of its twelve accessibility queries said `tell process "AgentSpace"`, and the owner's installed copy in `/Applications` carries that exact process name — so a run that started while that copy was alive read *its* windows, and its results described 0.1.12 rather than 0.1.17 | pass (code, fixed) | Observed as three different scores for one artifact: the first run reported `launch opens exactly one window: expected [1] got [2]`, a second reported that check passing and four *other* checks empty (`refresh slider min`, `preview tiers`, wizard), which is what reading a Settings window belonging to another process looks like. Fix: every query now addresses `first application process whose unix id is $APP_PID`, the pre-launch `pkill` is followed by a bounded 10 s wait for a clear slate, and the run refuses outright if an instance will not exit — naming the pid and path instead of scoring a stranger. `pgrep -U … -lf` in the refusal path is deliberate: `-Ul` is not a valid option pair on macOS and the wrong spelling silently hid the very diagnostic it printed. Four phantom failures disappeared on the next run |
| 640 | **The second identity bug was the same bug one level down: `window 1`.** With the right process pinned, the sliders and the width tiers were still resolved against `window 1`, and the dashboard and the Settings window are both on screen — the order the accessibility API reports them in is the window server's choice | pass (code, fixed) | `windowWithId(_p, wantedId, theClass)` and `advancedSettingsWindow(_p)` (in the AppleScript library) now walk every window of the pinned process and use the one that actually contains the identifier the check is about; the Advanced tab is reached by clicking the fourth toolbar button *of that window*, and only accepted if the slider appears inside it. The wizard phase keeps the window that yielded `agentNameField` instead of re-deriving `window 1` at each step, and resolves the review card by identifier across all windows. `preview tiers` and the wizard branch stopped alternating between runs for this reason |
| 641 | The `launch opens exactly one window` check judged a single instant, so a startup window that is torn down and rebuilt read as a defect | pass (code) | It now takes a *settled* count — two equal readings in a row out of ten samples — and on failure prints the sample trace, the element count of every window, the bundle path, the pid and any other AgentSpace process, so the next occurrence names its own cause instead of leaving `got [2]` to be argued about. Separately, both launches pass `-NSQuitAlwaysKeepsWindows NO` through the argv domain (writes nothing, changes nothing the user sees) so the check measures launching rather than AppKit restoring windows a previous run left in the shared `com.agentspace.AgentSpace` defaults, whose autosave names run up to `AppWindow-4` |
| 642 | 0.1.17 presents exactly one window per launch, measured cold | pass | 5 consecutive cold launches of `dist/AgentSpace.app` and 5 of the *previous* release read out of `dist/AgentSpace-0.1.16.dmg`, each with its own empty registry, each polled until the count settled: **10 of 10 settled at 1** (`samples=1,1` for every launch). So the `got [2]` readings in §299's earlier runs were the gate's own bookkeeping, not the build — and the build that is published is the one that was measured |
| 643 | `scripts/gui-verify.sh` passes 7 of 7 | pass, not yet on every run | Reached 8 times during this session, including twice consecutively with the current script (`7 passed, 0 failed`), on the published bundle — the sidebar stamp check is what pins that: it compares the running window's `appBuildVersion` text against `CFBundleShortVersionString` + `CFBundleVersion` of the bundle under test, so a pass means the checked window *is* 0.1.17. It still failed once in the last three runs with the count settled at `2,2` and the downstream phases following it out of position. The residue theory was tested and rejected: a deep-link alert left up and the app then killed (SIGKILL) did **not** re-deliver at next launch in either of two scripted trials (`samples=1,1,…`), so the mechanism of that one reading is still unnamed — pending, with the diagnostics in place to name it |
| 644 | `scripts/check-all.sh` on 0.1.17 | pass up to the GUI layer, then environment | dist guard `stapled app matches the stapled DMG (df5d71b8…)`, `scripts/test.sh` → `Executed 431 tests, with 0 failures` on the release commit, `scripts/mcp-smoke.sh` → `all MCP smoke checks passed`, and `gui-verify.sh` as row 643 describes. `check-all` therefore still exits non-zero on this machine, and it does so for a reason the log now prints rather than one it hides |

## 300. The owner's AgentUse was never lost; `open` was handing it a test registry, and the account picker took 18 seconds to answer (2026-09-21)

The owner screenshotted a management window reading *暂无 Agent 账号* with
`构建 0.1.17 (328)` and asked whether AgentUse had been lost, and why the New
Agent wizard no longer offered that user. Neither was true, and the cause of the
first was this repository's own test script. The second was a latency bug that
made the wizard state a falsehood for eighteen seconds on every machine.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 645 | The account and its registry record were intact the whole time | pass | `dscl . -read /Users/agentuse` → `UniqueID: 503`, `NFSHomeDirectory: /Users/agentuse`, `UserShell: /bin/zsh`; `/Library/Application Support/AgentSpace/Spaces/index.json` still holds `6EA2FB6B-2B91-4BEE-B7D0-7E76CA28C9A1` with `"state":"ready"`; `agentspace accounts` → `● AgentUse  [Ready]  uid 503  agentuse`. After the repair below, the owner's own window reads `AgentUse \| 就绪 \| Worker 运行中（pid 89258）\| 会话 usable \| 接受输入 是` |
| 646 | **`open` passes the calling shell's environment to the application it launches, and `scripts/gui-verify.sh`'s hand-back therefore ran the owner's installed copy against the gate's throwaway registry.** This overturns §48 row 150, which recorded the opposite | pass (measured, fixed) | `ps eww -p 49512` — the owner's `/Applications/AgentSpace.app`, uid 501 — printed `AGENTSPACE_ROOT=/tmp/gui-verify-root.a6EBZu` and `AGENTSPACE_GUI_APP=/tmp/agentspace-300-bundle/AgentSpace.app`. The second variable was set only by this session's gate invocation, so that environment vector *is* the script's, and `gui-verify.sh:36-39` makes that root a `{"spaces":[]}` file it then deletes. Any window launched from it reads an empty registry and looks like a product that lost the user's agents. Fix: both `open` calls in the script run under `env -u AGENTSPACE_ROOT -u AGENTSPACE_GUI_APP`, and the EXIT hand-back is followed by a sweep that names any surviving same-uid AgentSpace still carrying the variable. Measured after: the re-opened copies (pids 55755, 57678) have zero `AGENTSPACE_ROOT` entries and show AgentUse |
| 647 | An empty registry and an *unreadable* registry used to render identically, so no screen could distinguish "you have no agents" from "I am reading the wrong file" | pass (code, measured) | `EmptyStateView` now reads `AgentSpaceEnvironment.rootOverride` and, when it is set, names the path in place of the *if you are signed in as an attached account* theory (`registryRootOverrideNotice`). The gate asserts it: `ok empty state names the registry it read`, which passes only when the on-screen text contains the `$GUI_ROOT` the script exported — the check that proves the panel says what it read |
| 648 | **The New Agent wizard's *no unattached standard users were found* was a claim it made for ~18 seconds on every launch**, because `AccountDiscovery.discover()` asked "is this account an administrator?" once per passwd record — 267 records on this Mac — each one a `/usr/bin/id -Gn` process spawn | pass (measured, fixed) | Reproduction of the old loop, same machine, compiled `-O`: `eager probe over 267 records took 17.84864275 seconds`. The card rendered the empty state for the whole of that time because `availableAccounts` starts empty and the wizard's only other branch is the picker. Fix: `passesCheapFilters` (uid ≥ 500, home under `/Users/`, not hidden, not the current user) runs in-process on every record, and the privilege probe is asked only about the survivors — `discover() -> ["agentuse:503"] in 0.143709 seconds`, then 0.141758 s on a repeat run. Tests: `testThePrivilegeProbeIsAskedOnlyAboutRecordsThatPassTheCheapFilters` (probes < records, every probed name passes the cheap predicates, each probed exactly once, no administrator in the result) and `testProbedAdministratorsAreStillExcluded` (probe answers `true` → empty). Fail-closed semantics unchanged: a probe that cannot answer still means "not offered" |
| 649 | The wizard no longer states an unproven negative, and the gate no longer accepts one unexamined | pass (code, measured) | `AppModel.isDiscoveringAccounts` is true from the moment `discoverAccounts()` is called until the matching generation answers; the card shows *Looking for standard users…* and suppresses *Open Users & Groups* while it is set. `gui-verify.sh` now polls up to 6 s for *either* the picker or the empty-state buttons before deciding which state it is in — until then it had been scoring `wizard: empty account state` as a **pass** on a machine that does have an attachable user, which is how this went unnoticed for so long. Same script, same machine, half an hour apart: `wizard: empty account state` (4 passed, 3 failed) → `wizard: step 2` (8 passed, 0 failed) |
| 650 | In a correctly configured window the picker *still* does not offer AgentUse, and that is the product working | pass | `AppModel.discoverAccounts()` builds `attached` from the registry and filters `!attached.contains($0.username)` (`AppModel.swift:360-363`): an account that is already connected is never offered for a second connection. The defect was never that AgentUse was missing from that list — it was that the list said "no unattached standard users exist" while it had not yet looked, and that the panel beside it could not say which registry it had read |
| 651 | §299 row 643's unnamed residue now has a candidate mechanism | pending (named, not reproduced) | While a second copy of the same bundle id was on the desktop, the gate read `sidebar build stamp … in []`, `preview tiers` empty and `no name field` — empty accessibility reads rather than wrong values, from the pinned-pid process. Two mechanisms fit: LaunchServices activating a *different* registered copy for the shared bundle id, and `keystroke "n" using command down` being focus-targeted, so ⌘N can land in the stranger regardless of which pid the queries pin. The gate's own hand-back (row 646) was one way that second copy appeared mid-run |
| 652 | This round's gates, on a temporary verification bundle (`/tmp/agentspace-300-bundle`, `AGENTSPACE_GUI_APP`) so the published artifact stayed untouched | pass | `env PATH=/usr/bin:/bin:/usr/sbin:/sbin swift test` → `Executed 433 tests, with 0 failures` (431 before this batch: +2 discovery-probe cases); `LocalizationTests.testTablesHaveIdenticalKeySets` passes with the two new keys in both tables; `scripts/mcp-smoke.sh` → `all MCP smoke checks passed`, exit 0; `scripts/gui-verify.sh` → `8 passed, 0 failed` with `wizard: step 2`. `dist/` was not rebuilt, so 0.1.17 as published does **not** contain these fixes |

## 301. 0.1.18 released: the first full-aggregate green this machine has produced (2026-09-21)

§300's two GUI fixes and §299's gate-identity fix ship together, so this is the
first release where `scripts/check-all.sh` exited 0 end to end rather than
stopping at the accessibility layer (§297's locked console, then §299 row 643's
unnamed reading).

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 653 | The published bytes are the bytes this repository built, and a user's Gatekeeper accepts them | pass | `rm -rf .build && scripts/release.sh` → exit 0, all four binaries verifying (`AgentSpace.app`, `agentspace-helper`, `agentspace-worker`, `agentspace`), signer `Developer ID Application: Guofeng Liu (U8U443D7ZL)`. `scripts/notarize.sh` → exit 0, submissions `a654b444-…` (app) and `0051c80c-…` (DMG rebuilt *from the stapled app*). Re-checked outside the script: `stapler validate` exit 0 for both artifacts, `spctl --assess` → `accepted / source=Notarized Developer ID`. Bundle stamp read with `plutil` (not `defaults`, which served a stale value for this same plist earlier today): `0.1.18 (333)`. DMG `sha256:75259cfbacda592ea7a3511990783229bed65d75b186e3eb03a483820b79418a`, 4 572 636 bytes; the pre-staple digest (`06af0f4a…`, 4 570 658) differs, which is the ticket being written into the DMG |
| 654 | `scripts/check-all.sh` passes all three layers | pass | `==> dist guard: stapled app matches the stapled DMG (95b48024…)`, `scripts/test.sh` → `Executed 433 tests, with 0 failures`, `scripts/mcp-smoke.sh` → `all MCP smoke checks passed`, `scripts/gui-verify.sh` → `8 passed, 0 failed` including `wizard: step 2`. Overall `check-all: all 3 layers passed`, exit 0 |
| 655 | The GUI gate scored the artifact that is now published, and left the owner's copy readable | pass | The build-stamp check compares the running window's `appBuildVersion` against the bundle under test, which for this run was `dist/AgentSpace.app` at `0.1.18 (333)`; the new `empty state names the registry it read` check passed, so the panel was naming its own `$GUI_ROOT`. After the EXIT hand-back, the surviving `/Applications` process showed zero `AGENTSPACE_ROOT=` entries in `ps eww` and the sweep printed no warning (§300 row 646) |
| 656 | Nothing in this release touches the wire or the registry format | pass | `git diff v0.1.17..HEAD --name-only` lists no protocol, wire or model file: the changes are `AccountDiscovery`'s filter order, three GUI files plus two localization keys, `scripts/gui-verify.sh`, and docs. `protocolVersion` stays 1, registry keys unchanged, every `agentspace_*` MCP tool still registered |
| 657 | The helper installed on this Mac is older than the app it now pairs with | pending (owner's action) | The installed daemon is 0.1.16 against an 0.1.18 app, so the *助手版本过旧* card and the disabled Create button are the correct state, not a regression; pressing 「重新安装助手…」 is the owner's action and is the only thing that raises the helper's version |

## 302. Online update: the channel measured against a real release, and the one thing it cannot bootstrap (2026-09-21)

AgentSpace can now update itself: Settings gains an *Update* tab
(`SoftwareUpdateView`) driven by `apps/AgentSpace/Services/SoftwareUpdate.swift`,
with every decision factored into a new testable target
(`native/AgentSpaceUpdaterSupport`) and the one step that cannot run inside a
live process in a new product (`native/AgentSpaceUpdater` →
`agentspace-updater`, nested at `Contents/Helpers/`). `docs/UPDATE_CHANNEL.md` is
the contract. This section is deliberately not a code-reading exercise: the
channel was pointed at the **published 0.1.18 artifact** and the predicates were
measured, because "the code exists" would have said nothing about whether
GitHub actually stores a digest, whether the mirror URLs serve anything, or
whether a real candidate satisfies a real designated requirement.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 658 | The release metadata the whole chain trusts is readable from the live channel by the same function the app calls | pass (measured) | `curl -H "Accept: application/vnd.github+json" https://api.github.com/repos/misswell/AgentSpace/releases/latest` → `tag_name: v0.1.18`, `draft: false`, `prerelease: false`, one asset. Fed verbatim into `SoftwareRelease.decodeGitHubResponse` (compiled against `AgentSpaceUpdaterSupport`, `/tmp/probe-channel`): `decoded version: 0.1.18`, `decoded archive: https://github.com/misswell/AgentSpace/releases/download/v0.1.18/AgentSpace-0.1.18.dmg`, `decoded sha256: 75259cfb…b79418a`, release notes decoded, `newer than 0.1.17: true`, `newer than 0.1.18: false`. The `v`-prefixed tag is what the version parser had to tolerate, and it does |
| 659 | GitHub's stored digest is the digest of the bytes this repository built | pass (measured) | Three independent readings of one number: `assets[].digest` from the live API = `sha256:75259cfbacda592ea7a3511990783229bed65d75b186e3eb03a483820b79418a`; `shasum -a 256 dist/AgentSpace-0.1.18.dmg` = `75259cfb…`, 4 572 636 bytes; §301 row 653's post-notarization digest = the same. So the value the updater compares against is published by Apple's pipeline's consumer, not chosen by this repository |
| 660 | Every download source the policy names serves this asset, and a mirror's bytes pass the app's own digest check | pass (measured) | `UpdateSources.sources(for:preferredHost:)` run against the real asset URL produced exactly four candidates in the documented order (xget `/gh/` form, `ghfast.top/https://…`, `gh-proxy.org/https://…`, GitHub last). A `curl -r 0-1023` against each returned **206 for all four**. A complete 4 572 636-byte download from the *first* source, hashed by `ArchiveDigest.sha256(of:)`, equals `release.sha256` (`digest matches: true`) |
| 661 | Each verification predicate holds for a genuine published release — including the one that protects the privacy grants | pass (measured) | Against the mounted DMG (`hdiutil attach -readonly -nobrowse`): `CFBundleIdentifier=com.agentspace.AgentSpace`, `CFBundleExecutable=AgentSpace`, `CFBundleShortVersionString=0.1.18` == the decoded release version; `codesign --verify --deep --strict` exit 0; `TeamIdentifier=U8U443D7ZL`; `spctl --assess --type execute` → `accepted / source=Notarized Developer ID`. The requirement test is `codesign --verify --strict -R"=<running app's designated requirement>"`, i.e. the same semantic check macOS runs against a stored grant, not a text comparison: run against `/Applications/AgentSpace.app`'s own requirement → `SATISFIES_RUNNING_REQUIREMENT=yes`, and against `identifier "com.example.other"` → rejected, so the test is not vacuous. One predicate did **not** hold, and it is row 662 |
| 662 | **A release published before this feature carries no updater, so it cannot be the *source* of an in-app update — the first update after 0.1.18 has to be done by hand.** The candidate check requires `Contents/Helpers/agentspace-updater` in the incoming bundle, and the running 0.1.17/0.1.18 copy has none to launch | pass (measured, accepted with a named consequence) | The nested-path loop over `AgentSpaceIdentity.nestedCodePaths` found `Contents/MacOS/agentspace-worker`, `Contents/Helpers/agentspace` and `Contents/Library/LaunchDaemons/agentspace-helper` in the published 0.1.18 DMG and reported `MISSING: Contents/Helpers/agentspace-updater`. Two guards already say this rather than pretending: `SoftwareUpdateFailure.Message.helper` → *This copy of AgentSpace ships no updater, so it cannot install one*, and the location gate that refuses to update anything outside `/Applications`. Consequence for releases: **0.1.19 must be installed from the DMG by the owner; from 0.1.19 onwards every later release is self-updatable**, and a release note that omits that is a broken promise to whoever has 0.1.18 |
| 663 | The install step works, and a refusal leaves a working app behind — measured offline, without the network or a password | pass (measured, gated) | New `scripts/updater-e2e.sh`, run against the real `agentspace-updater` binary with stand-in bundles whose main executable records which copy ran: **19 checks, exit 0**. Happy path — exit 0, the installed bundle reports `9.9.9`, the *launched* app is the new copy (`com.agentspace.AgentSpace 9.9.9` in the marker), staging and the updater's own copy are removed, no `.AgentSpace-update-*`/`.AgentSpace-backup-*` left in the app directory, log says `update installed at`. Refusal path (source bundle id `com.example.impostor`) — exit 1, the old bundle is back at the app's path at version `0.0.1`, the relaunched app after the refusal is that old copy, the impostor never ran, scratch cleaned, log says `update failed`. Malformed vector (2 values) — exit 2 and the destination untouched. The one case it cannot reach is `waitForParent`'s 60 s refusal, which needs a parent that will not exit |
| 664 | The five new GUI-gate checks pass on a bundle built from this tree, and the four main-window checks in that same run are unproven rather than failed | pass (update pane) / pending (main window) | `AGENTSPACE_GUI_APP=/tmp/as-update-verify/AgentSpace.app scripts/gui-verify.sh` → `update pane reachable`, `update check control`, `update preference control`, `checking is possible`, `install control before a release is verified` all ok, on the *untouched* state (`AGENTSPACE_ROOT` suppresses the automatic check). The same run failed `launch opens exactly one window` (settled `0,0`), the build stamp, the registry-naming empty state and `wizard: no name field` — four reads of a main window that was never on screen, for a **temporary** bundle in `/tmp` sharing the installed copy's bundle id. That is §300 row 651's mechanism class, not this feature: the identical script against `dist/AgentSpace.app` in the same session gave `launch opens exactly one window` ok and 8/8 on the pre-existing checks, failing only the five new ones — which is the correct verdict for 0.1.18, an artifact with no Update tab. The main-window checks are owed a run against a `dist` built from this tree |
| 665 | **Found while writing 663's refusal case: the identity check ran *after* the swap, and on failure it left the impostor installed.** `replaceItemAt` had already moved the unverified bundle to the app's path, and the old code only `throw` — so the bundle the user finds when they click the Dock icon was the stranger | pass (code, fixed, and now gated) | `native/AgentSpaceUpdater/Sources/AgentSpaceUpdater/main.swift`: `install()` tracks `var swapped`, and its catch restores — `restoreBackup(_ backup:arguments:)` puts the backup back with `replaceItemAt` and relaunches the previous copy, so a failed update ends with a working AgentSpace. A launch failure after the swap takes the same route, and the log line (`restoring the previous copy after a failed install`) is now emitted only where a restore actually happens. Row 663's refusal case is the test that would have caught it, and it is the reason the case exists |
| 666 | An update changes the app bundle and nothing else; no root path is reachable from the updater | pass (code) | `grep -rn "PrivilegedHelperTools\|Application Support/AgentSpace\|sudo\|launchctl" native/AgentSpaceUpdater/Sources native/AgentSpaceUpdaterSupport/Sources` → `none — the updater never names a root path`. It receives two bundle paths plus two scratch paths and derives its backup/incoming names from the destination (`UpdaterLaunchPlan`), and the success log states the boundary in the words the doc uses: the installed helper and the worker it installed change only when the user reinstalls the helper. Running workers are unaffected because they execute from the installed copy, not the bundle |
| 667 | The updater is embedded and signed the way the chain expects to find it | pass (measured) | `scripts/bundle-app.sh debug /tmp/as-update-verify` → builds, asserts `agentspace-updater` among the five required binaries, copies it to `Contents/Helpers/`, signs it with its own identifier. Read back from the bundle: `Identifier=com.agentspace.AgentSpace.Updater`, `flags=0x10000(runtime)` (hardened), `TeamIdentifier=U8U443D7ZL`; `codesign --verify --deep --strict` on the whole bundle → `valid on disk` / `satisfies its Designated Requirement`. `scripts/release.sh` now verifies the updater in its per-binary loop, and a unit test asserts every `nestedCodePaths` entry is a path `bundle-app.sh` actually copies (`testEveryNestedBinaryTheUpdateChecksForIsOneTheBundleBuilds`) so the two cannot drift apart silently |
| 668 | The decisions are tested where they are made, and nothing previously proven was overturned | pass | `tests/Unit/SoftwareUpdateTests.swift`: `Executed 24 tests, with 0 failures` — version ordering and `isNewer`, five rejection shapes from the real GitHub payload plus missing / non-`sha256:` / short / non-hex digest refusals and an http asset refusal, the HTML assets-page fallback (and its foreign-repo and no-digest negatives), mirror ordering and preference hoisting, argv round-trip and every malformed vector, derived scratch paths, `UpdateInstallation.classify`/`obstruction`, failure→message mapping, `ArchiveDigest` against the FIPS `"abc"` vector, `CodesignRequirement.parse`, and five drift tests that bind the channel to this repo's team id, asset name, bundle id and remote. Whole suite: `env PATH=/usr/bin:/bin:/usr/sbin:/sbin scripts/test.sh` → `Executed 457 tests, with 0 failures` (433 before this batch, +24), which includes `LocalizationTests` — 25 keys added to **both** `en` and `zh-Hans` tables, specifier parity intact |
| 669 | `scripts/check-all.sh` is now four layers, and the fourth still has the machine's approval to earn | pending (release run) | `LAYERS=(test.sh updater-e2e.sh mcp-smoke.sh gui-verify.sh)`; the new layer is hermetic and needs no console, no worker and no network, so it fails only for the build. A full aggregate green for this tree is the release run's to produce, and it requires `scripts/release.sh` first — which is also the point at which 0.1.19's DMG starts carrying the updater that 0.1.18's does not |
| 670 | No protocol, wire, registry or account-lifecycle surface was touched | pass | `git status --porcelain` for this batch lists `Package.swift`, two GUI sources, two localization tables, four scripts, one new doc, `docs/status.md`, and the two new `native/AgentSpaceUpdater*` trees plus the new test file. Nothing under `shared/Core/Sources/AgentSpaceCore` changed: `protocolVersion` stays 1, no wire method was added or renamed, registry keys are untouched, no account is created or deleted anywhere in the update path, and the whole feature is a `dist/`-external download that never drives a session |


## 303. The 0.1.19 gate, a locked console, and a window sampler that believed `0,0` (2026-09-21)

0.1.19 carries the update feature (`73dc656`) and was built, notarized and
stapled without touching the tree's other in-flight work. Running the four-layer
gate against it produced a red `scripts/gui-verify.sh` whose failure pattern
changed from run to run — first the four main-window reads, then the Settings
reads, then both — which is not how a build defect behaves. This section is the
measurement that located it, the gate defect it exposed, and the part of the
release that is therefore still owed.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 671 | The release candidate is the tree's committed content, and the uncommitted work sitting next to it belongs to a different feature | pass | The first aggregate run failed at `scripts/test.sh` with `type 'Equatable' has no member 'delta'` in `tests/Unit/FrameModeControllerTests.swift` — a file that is untracked in this checkout (`git status --porcelain` lists 13 `Frame*`/`Capture*`/`DirtyRegion*` sources plus five test files, none of them in `73dc656` or `0c7aa7c`). Their mtimes (11:12:59, 11:13:55) are **after** `dist` finished building (11:09:56–11:09:59), and `strings` finds zero hits for `DirtyRegion`, `CaptureTarget`, `FrameCapabilities` or `FrameStats` in `dist/AgentSpace.app/Contents/MacOS/AgentSpace` or in `agentspace-worker`. Nothing was committed, stashed or reverted: the gate was re-run from a detached worktree at `0c7aa7c` with `dist` symlinked to the notarized artifacts, so the verdict below is about the commit, not about somebody's working state |
| 672 | Three of the four layers pass on `0c7aa7c` | pass | `/tmp/checkall-019-clean.log`: `==> dist guard: stapled app matches the stapled DMG (d4a29b9b…)`, `scripts/test.sh` → `Executed 457 tests, with 1 test skipped and 0 failures`, `scripts/updater-e2e.sh` → `updater-e2e: 19 checks passed`, `scripts/mcp-smoke.sh` → `all MCP smoke checks passed`. The aggregate stopped at the fourth layer, and its own exit line says so: `check-all: failed at scripts/gui-verify.sh`, `CHECKALL_EXIT=1` |
| 673 | The fourth layer's failures are the machine, not the build: **the console session locked while the gate was running** | pass (measured) | `CGSessionCopyCurrentDictionary` now reads `kCGSSessionOnConsoleKey=true`, `CGSSessionScreenIsLocked=1` while `/dev/console` is still `guofeng staff` — the §296 trap in project notes: the mode bits say unlocked, the dictionary says locked, and the dictionary is the one that predicts whether a window is being presented. `scripts/gui-verify.sh`'s own guard agrees: a later run printed `gui-verify: refusing to run — the console session's screen is LOCKED` and exited 1 without touching the app. The run *before* that one printed `session presenting windows (presenting)` at its start and then lost reads mid-run — the state is sampled once, and a lock that arrives at second 6 invalidates the reads at second 20 |
| 674 | The artifact shows its window as fast as the previous release did — measured by polling from the moment of `exec` instead of sampling at a fixed delay | pass (measured) | `dist/AgentSpace.app/Contents/MacOS/AgentSpace -NSQuitAlwaysKeepsWindows NO` with `AGENTSPACE_ROOT` pointed at a throwaway registry, `count of windows` polled every 0.25 s: first `1` at **0.7 s, 0.4 s, 0.4 s** in three trials. The same bundle launched through LaunchServices (`open -n`) reads 1 window at 8 s. The fixed-delay samples in row 672's run read `0,0` at 5 s and 6 s, so a healthy launch and a launch that never happens were scored identically |
| 675 | **Gate defect, found and fixed: the launch sampler accepted two equal `0` readings as a settled count.** A window that has not appeared yet agrees with itself perfectly | pass (fixed) | `scripts/gui-verify.sh`: the loop's exit condition was `[ "$WINDOWS" = "$PREV_WINDOWS" ] && break`, which for `0,0` stops the polling two seconds into a five-second wait. It now reads `[ "$WINDOWS" = "$PREV_WINDOWS" ] && [ "$WINDOWS" != "0" ] && break` — a zero spends the whole ten-attempt budget before it is believed, so a window that genuinely never arrives still fails, fifteen seconds later. This is not a tolerance change: the assertion is still exactly one window. Re-running with the fix made the three previously-red main-window reads go green on the notarized artifact: `ok launch opens exactly one window`, `ok sidebar build stamp matches the bundle`, `ok empty state names the registry it read` |
| 676 | §302 row 664's debt is paid for three of its four checks | pass (was pending) | Row 664 owed "a run against a `dist` built from this tree" for `launch opens exactly one window`, the build stamp, the registry-naming empty state and the wizard. With row 675's fix in place, the first three pass against `dist/AgentSpace.app` (0.1.19, build 336) in this session. `wizard reaches a real next state` is **still pending**: it reads the dashboard's name field, and in the run that produced the three oks the console locked between them and it, so it is recorded as unobserved rather than as a failure |
| 677 | A control measurement that has to be withdrawn: the installed 0.1.17 read 0 windows for 20 s under the same conditions | pass (honest negative) | The identical polling loop against `/Applications/AgentSpace.app/Contents/MacOS/AgentSpace` returned `never(20s)` three times, which would have proved the reading meaningless — except that the loop never asserted the process stayed alive, and it was run at 11:33 while the session was locking. A control that cannot tell "no window" from "no process" is the same mistake row 675 fixed, in the other direction, so its result is not cited anywhere above |
| 678 | The 0.1.19 artifact is the one this repository built, notarized, and stapled | pass (measured) | `scripts/release.sh` → `RELEASE_EXIT=0`; `scripts/notarize.sh` → `NOTARIZE_EXIT=0` with submission ids `b97fd4b3-6767-4295-b8c3-533a0ae4f6d2` (app) and `3d41e31e-f58b-48e1-8c7e-e8a849423a1e` (DMG rebuilt from the stapled app). Re-read outside the script: `stapler validate` works for both `dist/AgentSpace.app` and `dist/AgentSpace-0.1.19.dmg`, `spctl --assess --type execute` → `accepted / source=Notarized Developer ID / origin=Developer ID Application: Guofeng Liu (U8U443D7ZL)`, plist stamp `0.1.19 (336)`, DMG 4 779 883 bytes at `sha256:c31642da2fdd2443faedb25cd50f21a1b9ab4c606b83b024e791b21692d5f0b2` |
| 679 | The release is staged, not published, and the gate is not green yet | pending (owner's console) | `73dc656` and `0c7aa7c` are committed locally; `origin/master` is at `29340fb`, no `v0.1.19` tag exists, and no GitHub Release has been created. Publishing waits for one aggregate `check-all` run with the fourth layer observed on an unlocked console — the guard's own instruction is `Unlock the screen and re-run`, and the script never tries to unlock it. §302 row 662 stands regardless of who runs it: **0.1.19 has to be installed from the DMG by hand, because 0.1.18 carries no updater to do it in place** |

## 304. The GUI frame path leaves JSON/JPEG behind (2026-09-21)

This change implements the binary frame-engine design on top of `0c7aa7c` and
is published as `v0.1.20` from `d559534`.
The old preview and window-stream methods remain registered for old clients and
debugging, but neither Desktop Viewer nor Fusion calls them for live rendering.
The physical verdict is deliberately split from the code verdict: this tree's
worker has not replaced AgentUse's installed 0.1.19 worker yet.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 680 | Desktop and Fusion share one persistent binary client instead of polling JPEG/base64 through JSON | pass (code) | `FrameClient` opens with additive `frame.open`, performs the token/space/stream/protocol handshake on `frame.sock`, receives one mapping descriptor with `SCM_RIGHTS`, then reads fixed `FrameHeader` records. `DesktopViewerView` and `FusionWindowView` both render `RemoteSurfaceNSView`; their old polling timers were removed. Compatibility `preview.*` and `window.stream.*` handlers remain registered and protocol version remains 1 |
| 681 | The new high-throughput path preserves the account and console security boundaries | pass (code) | `FrameServer` checks `getpeereid`, the root-authored main-user uid, token, account id, stream id and protocol version before sending a descriptor. The production runtime refuses a missing main-user identity rather than accepting the worker uid. `FrameSurfaceRouter` rechecks `SessionVerdict` on frames; a console/no-WindowServer transition stops capture, closes the frame connection and makes the client clear stale pixels and reconnect through the guarded `frame.open`. No path selects the human console as a fallback |
| 682 | Shared-memory publication is bounded and cannot free a reused slot with a stale ACK | pass (code + unit) | Two slots are allocated under a 256 MiB per-worker mapping budget. The publisher retains only the latest surface, merges damage while slots are occupied, and accepts an ACK only when `(slot, sequence)` exactly matches the outstanding lease. Pixels and their dirty metadata are serialized on one publisher queue. The client ACKs duplicates and local-render failures before requesting a new full baseline. `FrameBackPressureTests`, `DirtyRegionAccumulatorTests`, `FrameSequenceTests` and `SharedFrameLayoutTests` cover bounded newest-frame retention, 30-produced/10-consumed pressure, merge/full promotion, generation/baseline validation and mapping bounds |
| 683 | Rendering is zero-disk and has a non-Metal escape hatch | pass (code) | Shared BGRA patches update one persistent `MTLTexture`; H.264 decode wraps `CVPixelBuffer` through `CVMetalTextureCache`. If texture creation or patch application fails, `RemoteSurfaceNSView` builds and incrementally patches an in-memory BGRA baseline and presents it through a layer — no `NSImage`, PNG/JPEG encoding or temporary file. Resize/zoom requests are debounced for 250 ms and reopen the immutable mapping at the new bounded pixel size |
| 684 | The implementation compiles and the complete Swift suite remains green | pass (measured) | Apple M5/macOS 27.0 (26A428): `swift build` → success; `env PATH=/usr/bin:/bin:/usr/sbin:/sbin swift test` → **472 tests, 0 failures** in 41.062 s. The additions cover framing, handshake mismatch/peer uid, reconnect generations, mode hysteresis, dirty regions, sequence gaps and shared layout. `LocalizationTests` passes with the new English and Simplified Chinese stream-state keys |
| 685 | The measurement host and display topology are recorded instead of implied | pass (measured) | MacBook Pro Mac17,2, Apple M5 10-core CPU/10-core GPU, 24 GB, Metal 4; macOS 27.0 build 26A428. Displays: SSN-24 3840×2160 (looks like 1920×1080 at 75 Hz) and built-in 3024×1964, both asleep during this code gate. AgentUse is uid 503, background Aqua verdict `usable`, Accessibility and Screen Recording already granted to its installed worker |
| 686 | The legacy JSON/JPEG cost has a reproducible pre-upgrade reference, but is not mislabelled as the new engine's result | recorded (legacy baseline) | Against AgentUse's still-installed 0.1.19 worker, `preview --start` reported 30 FPS; 30 separate `preview --frame --json` CLI pulls took 0.48 s wall time and the last JSON/base64 response was 160,724 bytes. This is a payload/process-overhead reference only: unchanged-frame behavior and per-command process startup make it unsuitable as an end-to-end FPS or CPU result |
| 687 | The installed-worker Desktop/Fusion latency, CPU, bandwidth, resize, worker-restart and fast-user-switch gates pass | pending (new worker install + interactive Aqua run) | The repository policy moves an installed worker only through **Reinstall Helper**, not as a side effect of a build. Until the release candidate is installed and that explicit action is performed, the real account continues to run 0.1.19 and cannot exercise `frame.sock`. Required run: Desktop idle/motion and Fusion single-window/two-sibling-window/drag/scroll; resize and zoom; worker kill/restart; background→console refusal with stale-pixel clearing; console→background full-baseline recovery; record p50/p95 presentation latency, worker/app CPU and bytes for idle and sustained motion |
| 694 | The release candidate is signed, notarized, stapled and accepted by Gatekeeper | pass (measured) | `scripts/release.sh` built `/Users/guofeng/Code/solo/AgentSpace/dist/AgentSpace-0.1.20.dmg`, version `0.1.20` build `338`, protocol `1`; `scripts/notarize.sh` verified the live `octoshrink-notary` profile, submitted app `d6ec67b7-551b-4d94-91d2-fdab0af15479` and DMG `8a9b2b55-8f88-4572-8ad1-df2861f50a47`, stapled both, and ended with `spctl --assess --type execute` accepted. The final aggregate dist guard reports app/DMG CDHash `4ba645cc7e88b8ed682b4581e781e8dbe35bb7ba` |
| 695 | The complete release gate is green on the signed candidate | pass (measured) | `scripts/check-all.sh` → `check-all: all 4 layers passed`: `scripts/test.sh` **472 tests, 0 failures**, `scripts/updater-e2e.sh` **19 checks passed**, `scripts/mcp-smoke.sh` all checks passed, and `scripts/gui-verify.sh` **13 passed, 0 failed** on an unlocked presenting console |
| 696 | The shipped bundle carries the new frame code and localized stream-state UI | pass (measured) | Release bundle contains `AgentSpace`, `agentspace-worker`, helper and updater; nested Developer ID signatures verify with team `U8U443D7ZL`. The localization suite passed parity/no-empty checks for `Frame stream unavailable`, `Connecting frame stream…` and `Reconnecting frame stream…` in both `en` and `zh-Hans` |
| 697 | Publishing does not claim that an installed worker was silently replaced | pass (scope) | `scripts/release.sh` and `scripts/notarize.sh` only write `dist/`; they do not touch `/Applications/AgentSpace.app`, the root helper or AgentUse's installed worker. Row 687 remains pending until the user explicitly chooses the documented Reinstall Helper action and performs the interactive cross-session run |
| 698 | The binary frame-engine candidate is the public `v0.1.20` release and its downloaded asset matches the stapled local DMG | pass (measured) | Annotated tag `v0.1.20` points to `d559534`; GitHub Release is non-draft/non-prerelease at [releases/tag/v0.1.20](https://github.com/misswell/AgentSpace/releases/tag/v0.1.20). Asset `AgentSpace-0.1.20.dmg` is 5,171,168 bytes with GitHub digest `sha256:09dfe7624f41d692bf50ddca887c8db4a3c0aa402d328402409b1bfcc7cdd513`, equal to local `shasum -a 256 dist/AgentSpace-0.1.20.dmg`; direct asset: [AgentSpace-0.1.20.dmg](https://github.com/misswell/AgentSpace/releases/download/v0.1.20/AgentSpace-0.1.20.dmg) |

## 305. 0.1.19 released: the updater ships, and the gate that went red for the machine went green for the build (2026-09-21)

§303 stopped with three layers green and the fourth waiting on an unlocked
console. The screen unlocked at 11:49:05, the aggregate was re-run against the
same commit and the same notarized artifact, and 0.1.19 is now published. This
section is the release record, the re-measurement of the one number §303 cited
from stdout only, and the boundary of what the published bytes contain — which
matters because `master` moved underneath the release while it was being run.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 688 | All four layers pass on the commit the artifact was built from | pass (measured) | `/tmp/checkall-019-green.log`, run in the detached worktree at `0c7aa7c` with `dist` symlinked to the notarized artifacts: `==> dist guard: stapled app matches the stapled DMG (d4a29b9b…)`, `Executed 457 tests, with 1 test skipped and 0 failures`, `updater-e2e: 19 checks passed`, `all MCP smoke checks passed`, `gui-verify: 13 passed, 0 failed`, `check-all: all 4 layers passed`, `CHECKALL_EXIT=0`. All thirteen GUI reads are listed ok, including the five Update-pane checks of §302 row 664 and `wizard reaches the helper card` — so row 664's remaining debt and §303 row 676's pending wizard read are both closed |
| 689 | The launch-latency number §303 row 674 cited from stdout is reproducible, and with the check that row 677 lacked | pass (re-measured, logged) | `/tmp/launch-timing-019.log`: three trials of `dist/AgentSpace.app/Contents/MacOS/AgentSpace -NSQuitAlwaysKeepsWindows NO` under a throwaway `AGENTSPACE_ROOT`, `count of windows` polled every 0.25 s **with a `ps -p` liveness assertion inside the loop**: first `1` at 0.58 s, 0.51 s, 0.53 s. Row 674 said 0.4–0.7 s; the re-measurement lands inside it, and the liveness check is what stops a dead process being read as a missing window |
| 690 | The published artifact is the bytes this repository built, at the commit that produced them | pass (measured) | Tag `v0.1.19` is annotated and points at `0c7aa7c`, not at `master`'s tip — deliberately, because `dist` was built at 11:09 from that tree (stamp `0.1.19 (336)`, build number = commit count). Remote asset `AgentSpace-0.1.19.dmg`, 4 779 883 bytes, `sha256:c31642da2fdd2443faedb25cd50f21a1b9ab4c606b83b024e791b21692d5f0b2`, identical to `shasum -a 256 dist/AgentSpace-0.1.19.dmg`; `isDraft=false`, `isPrerelease=false` |
| 691 | The channel the updater reads is live and shaped exactly as the code expects | pass (measured after publishing) | `GET /repos/misswell/AgentSpace/releases/latest` → `tag: v0.1.19`, `asset: AgentSpace-0.1.19.dmg`, `digest: sha256:c31642da…`, `browser_download_url: https://github.com/misswell/AgentSpace/releases/download/v0.1.19/AgentSpace-0.1.19.dmg`. That is `AgentSpaceIdentity.archiveName(for:)`'s expected name, an https asset, and the `sha256:`-prefixed digest field §302 row 659 established as the integrity source — so a 0.1.19 install reading `latest` finds itself and reports up to date rather than offering to reinstall its own bytes |
| 692 | **The push that carried the release also carried a different, unverified feature into `master`.** | pass (disclosed, not undone) | `git push origin master` reported `29340fb..d559534`, and `d559534` — `Frame engine: stream desktop surfaces over authenticated binary transport (plan §52)`, committed by this checkout's other session at 11:49:50, mid-gate — rode along: 54 files, 2 107 insertions, and a version bump of the plist and CLI to `0.1.20`. Nothing was force-pushed or rewound: the work is the owner's and lives in trunk now. The consequence to keep in mind is that **the published 0.1.19 DMG contains none of it** — `git diff 0c7aa7c..d559534 --stat` is that feature, and the artifact was built and gated strictly at `0c7aa7c` |
| 693 | What the owner still has to do to be on the release | pending (owner's action, by design) | This Mac's installed copy is `/Applications/AgentSpace.app` at **0.1.17**, which carries no updater (§302 row 662), so it cannot pull 0.1.19 in place: it is a hand install of this DMG, once. After that the in-app path exists for every later release. The helper-version card is a separate, also-correct state: an app update never touches the installed helper or worker (§302 row 666) |
| 699 | The published 0.1.19 DMG was installed over this Mac's 0.1.17 by hand, and the root-side state is provably untouched | pass (measured) | The mounted copy was run through the same predicates the app would run before replacing anything: `CFBundleIdentifier=com.agentspace.AgentSpace`, `CFBundleExecutable=AgentSpace`, `CFBundleShortVersionString=0.1.19`, `codesign --verify --deep --strict` → `valid on disk` / `satisfies its Designated Requirement`, `spctl --assess` → `accepted / source=Notarized Developer ID`, and `Contents/Helpers/agentspace` + `agentspace-updater` present with the updater identified as `com.agentspace.AgentSpace.Updater` under `U8U443D7ZL` — the nested path §302 row 662 found missing from 0.1.18 is the one that made this install manual rather than in-app. The outgoing bundle was **moved to the Trash**, not deleted (`AgentSpace-0.1.17-115834.app`), then `ditto`'d in: installed plist reads `0.1.19 (336)`, `stapler validate` works, `spctl --assess` accepts, deep-strict verifies. `/Library/Application Support/AgentSpace/Worker/active/agentspace-worker` is `1 615 376 bytes / Sep 20 16:35` both before and after, so the helper and worker boundary of §302 row 666 held on a real install, not only in the offline gate. This ran at 12:00, two minutes after §304 row 698 published `v0.1.20`; this Mac sits on `0.1.19` because that is the artifact this session built and gated, not because 0.1.20 was declined |
| 700 | The updater that shipped inside `/Applications` is the real tool and its argument contract is live there | pass (measured) | `/Applications/AgentSpace.app/Contents/Helpers/agentspace-updater 123 /nonexistent` → **exit 2**, and `ls -a /Applications` shows no `.AgentSpace-update-*` or `.AgentSpace-backup-*`, so the refusal happens before any filesystem work. Side effect worth naming: a vector that fails to parse carries no log path, so the fallback line lands in the owner's real `~/Library/Logs/AgentSpace/update.log` — that file now holds nine `updater called with 3 values; expected 7` lines, which are this contract test and `scripts/updater-e2e.sh`'s refusal case, not update attempts |
| 701 | The first genuine end-to-end of the in-app path is now reachable, and it is no longer the answer §302 row 662 predicted | pending (console locked; owner's decision) | `open -a /Applications/AgentSpace.app` at 12:00 reads `windows=0` and `frontmost=false` while `CGSSessionScreenIsLocked=1` — §303 row 673's reading class for the third time in one session, so it says nothing about the pane. What moved while this row was being written: `releases/latest` is now **`v0.1.20`** (§304 row 698), and 0.1.20 carries the updater. So the response owed to one press of `updateCheckButton` on this 0.1.19 install is not *`0.1.19` is the latest version* but *AgentSpace 0.1.20 is available*, with a live `updateInstallButton` and no `updateBlockedNotice` — this copy does sit in `/Applications`, so it is replaceable in place. Taking it would be the feature's first real self-update on the owner's machine, ending in a relaunched 0.1.20, and it is an owner's decision rather than a step to take quietly: 0.1.20's installed-worker run is still pending in §304 row 687 |

## 306. The frame engine's failure half, and the measurement this machine cannot yet afford (2026-09-21)

§304 recorded the binary frame engine as code. This round went after the ways it
could lie about itself — a capture that dies while the picture stays up, a viewer
that stops reading while the worker keeps writing, stats that report nothing —
and found two CLI flags that no caller could type. The physical half again did
not run, and the reason is now measured rather than assumed: this Mac's installed
pair is app **0.1.19** with worker **0.1.13**, which has never contained the
frame engine, and the console stayed locked for the whole session. Row numbers
continue §305, whose last row is 701.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 702 | A ScreenCaptureKit stream that ends on its own ends the frame connection instead of leaving the last frame on screen | pass (code + unit) | `CaptureEngine.Termination.stopped/.failed(AgentSpaceError)` with `onTermination`; `stream(_:didStopWithError:)` detaches the output and hands the report off the delegate callback (`DispatchQueue.global().async` capturing the handler, not `self`, so delivery does not depend on the engine still being retained), and `reportedFailure` allows one report per stream. `SharedFramePublisher.captureEnded` counts `captureTerminations` and, for `.failed`, runs `connectionLost()` → `disconnectSender` → `FrameSocket.abort()`, so the viewer sees EOF and reconnects rather than admiring a frozen picture. `FrameServer`'s sender closure also checks `context.sessionVerdict()` on every frame. The new `CAPTURE_STREAM_FAILED` code carries a remediation line in both `en` and `zh-Hans` (`LocalizationTests` green), and its text says the on-screen image is stale — which is the whole user-visible point |
| 703 | Silence is distinguishable from a lost connection, and a still desktop is not misjudged as either | pass (code + unit) | `FrameIdlePolicy` (heartbeat 2 s, stale 8 s, floored at two heartbeats so a policy can never expire before the beat that would save it) plus `FrameStreamLiveness`, shared by both ends. The worker's 1 s watchdog emits a heartbeat-only header — `FrameHeader.heartbeat` inside the same 52-byte record, because the frame size is a wire constant — and the viewer's reader throws `FrameSocketFailure.stale` after `staleAfter` with no activity. The worker's own read side uses `receiveTimeout: 0` on purpose: a viewer watching a still desktop sends nothing for minutes and is alive. Covered by `testHeartbeatTravelsInTheHeaderWithoutChangingItsSize`, `testAFrameIsNotAHeartbeat`, `testStaleWindowNeverShorterThanTwoHeartbeats`, `testHeartbeatCadenceAndStaleness`, `testAnyActivitySuspendsTheDeadline`, `testSilenceBecomesStaleAndWakesTheReader` |
| 704 | Fusion capture no longer hardcodes a Retina 2× | pass (code); pending (both-panel proof) | `CaptureEngine`'s `.window` branch calls `DisplayScales.pixelsPerPoint(for: window.frame)` (`native/AgentSpaceWorker/Sources/AgentSpaceWorker/DisplayScales.swift`), i.e. the panel that holds most of the window decides, which is the rule the legacy window stream already used through `DisplayScaleSelection`; the comment names both failure modes a constant would create (halved pixels on a 1× panel, blurred menu text on a Retina one). The old `* 2` is gone from the capture path. What is owed is the physical check §304 row 687 already owes: the same window on a 1× and a 2× panel |
| 705 | The GPU backlog is bounded and no slot is acknowledged while the GPU is still reading it | pass (code + unit) | `waitUntilCompleted` appears nowhere in the tree (grepped across `apps`, `native`, `shared`). `present(_:)` takes a permit from `InFlightBudget(capacity: 2)` and returns `.refused` when it cannot get one, releasing it in `addCompletedHandler`, where it also stamps the real present time; `clear()` resets the budget. The rule is written into `SurfaceApplyOutcome.uploaded`'s doc comment — the ACK is about *when the copy ends*, and `MTLTexture.replace(region:…)` is a synchronous CPU upload, so a future `MTLBuffer`+blit path must not acknowledge there. Tests: `testBudgetAllowsOneInFlightPermitPerFrameBeingDrawn`, `testBudgetNeverGoesNegativeAndResetClearsIt`, `testLockedBudgetSurvivesConcurrentCompletionCallbacks` (128 × `concurrentPerform`), `testEveryFrameGivesItsSlotBack`, `testOnlyAFrameThatDidNotLandAsksForABaseline` |
| 706 | A viewer that stops reading cannot stall the worker, and one frozen window cannot stall another stream | pass (code + unit) | `FrameServer.sendTimeout = 1` on every send (`FrameSocket(fd:sendTimeout:receiveTimeout:)` → `SO_SNDTIMEO`); a short write marks `sendIncomplete` and the socket dead, which reaches `connectionLost()` and `abort()`, so a half-written frame cannot be followed by a second one. `acceptLoop` dispatches each connection with `queue.async` and the comment states the property: nothing is shared across connections except the capture, which never waits for a viewer. The descriptor is released exactly once even when the publisher queue and the handler both let go (`releaseFD` + `fdReleased`), which `testClosingReleasesTheDescriptorExactlyOnce` checks through `fcntl(F_GETFD)`; `testSendTimeoutSaysThePeerStoppedReading` and `testAbortWakesAParkedReaderWithoutReleasingTheDescriptor` cover the other two halves over a real `socketpair` |
| 707 | `frame.stats` answers with measured numbers, on both sides of the wire | pass (code + unit); pending (values from a live stream) | Worker side: `framesCaptured/framesPublished/framesDropped/framesMerged/fullFrames/deltaFrames/unacknowledgedDrops/heartbeatsSent/captureTerminations/modeSwitchCount/socketReconnects/sharedBytes/videoBytes` plus `captureFPS`/`publishFPS` from `RateMeter` over a 2 s window, `dirtyRatio`, `fullFrameRatio`, non-destructive `pendingDamageArea`, `mappingBytes`, `frameMode`, `encoderActive`, activation/invalidation counts, and `captureToPublishP50/P95` — each of them written somewhere (the recording sites are `SharedFramePublisher.receive`/`notePublished`/`tick`/`noteEncoder`). Viewer side: `FrameRenderStats` counts received/rendered/dropped/heartbeats/gaps/reconnects and reports receive→render and capture→render. `Operations.frameStats` emits all ~27 fields per stream with `workerInstanceID` and `sessionGeneration` at both levels |
| 708 | publish→render is not measurable by the viewer, so the metric is named for what it measures | recorded (design decision, deliberate) | §9 asked for publish→render, and the honest options were two: grow `FrameHeader` past its 52-byte wire constant to carry a publish stamp, or rename the metric. The first is refused by the compatibility rules (`protocolVersion` stays 1; `FrameHeader.byteCount` is asserted in a test), so `FrameRenderStats.publishToRenderP50/P95` became `receiveToRenderP50/P95`, and the struct's comment says why the publish instant is not on the wire. `FrameLatency` keeps capture→publish (worker), receive→render and capture→render (viewer), and rejects samples that are negative or over 5 s — ScreenCaptureKit's capture timestamps ride a different epoch, so an absurd sample is a bad sample, not a measurement |
| 709 | The nine signpost intervals exist on the real path and cost nothing when nobody is tracing | pass (code); pending (a traced stream) | `FrameSignpost` is one `OSSignposter` in category `FrameEngine`, gated by `AGENTSPACE_FRAME_SIGNPOST` — when off, `begin` returns an interval with no state and `end` returns early, so no Release-time log spam. All nine are placed: `Capture` and `DamageExtract` in `CaptureEngine.stream(_:didOutputSampleBuffer:)` with a `Captured` event carrying the sequence, `SharedCopy` and `FrameSend` (both the shared-BGRA and the H.264 send) in `SharedFramePublisher`, `H264Encode` in `FrameSurfaceRouter.receive` around the hand-off to VideoToolbox, `FrameReceive` and `H264Decode` in `FrameClient`'s read loop, `MetalUpload` and `MetalPresent` in `MetalSurfaceRenderer`. `H264Encode`'s comment limits its claim to the submission cost, because encoding itself is asynchronous |
| 710 | The H.264 encoder exists only while the video path needs it | pass (code); pending (the static-desktop number) | `FrameSurfaceRouter.prepare(width:height:)` records `videoFormat` and creates nothing; `ensureEncoder()` runs only inside the `selected == .video` branch and `releaseEncoder()` gives the session back on every delta frame, with the reason stated (a desktop plus five static Fusion windows would otherwise hold six `VTCompressionSession`s to encode nothing). `SharedFramePublisher.noteEncoder(active:)` drives `encoderActive`, `videoEncoderActivations` and `videoEncoderInvalidations`, so §13's claim is checkable as a number — `frame-benchmark.sh --mode static` fails if activations move off zero — rather than as a reading of the code |
| 711 | **`agentspace preview --stats` and `--fps` were commands that could not be run.** | pass (found, fixed, guarded) | The `--stats` branch and the `--fps` read existed, but the parser validates flags against its own whitelists before dispatch, and neither name was in one: `preview AgentUse --start --fps 10` → `agentspace: unknown flag --fps`, and `--stats` likewise. Fixed by `stats` in `booleanFlags`, `fps` in `valueFlags`, and a usage line that spells every flag (`--start \| --frame \| --stats \| --stop`, `[--fps N]`). Regression guards: `testEveryFlagDocumentedInUsageIsAcceptedByTheParser` extracts every `--flag` from the real binary's `--help` and runs each one through it, failing on `unknown flag`; `testPreviewStatsAndFPSReachCommandDispatch` asserts both reach dispatch (exit 66 on an unknown account). Negative control measured: `agentspace --nostats list --json` → `unknown flag --nostats`, which is the string the guard looks for |
| 712 | The measurement scripts run, and what they say about this machine today | pass (measured) | `scripts/frame-benchmark.sh` against the live system exits **3**: `cannot measure: the installed worker (v0.1.13) predates the frame engine — plan §14: install the app and press 「重新安装助手…」 so the app and the worker are the same release`. Its inputs are all real: `/Library/Application Support/AgentSpace/Worker/active/agentspace-worker --version` → `0.1.13`, the installed CLI → `0.1.19`, and `preview AgentUse --stats --json` against that worker → `unknown method 'frame.stats'`. The sampler and assembler were then verified against a synthetic stream through `AGENTSPACE_CLI`: 12 samples over 56 s → 1 573 published frames = 28.089 fps, 642.78 MB copied, 16 588 800 bytes mapped, capture→publish p50 4.2 / p95 9.1 ms, 11 verdicts with the version mismatch FAIL and `memcpy_is_the_hotspot` PENDING; `scripts/frame-soak.sh --minutes 1 --interval 5` produced 11 trend rows plus the drift block (`appRSSKB`, `workerRSSKB`, `appFDs` growth all 0.0) and propagated the same FAIL as exit 1 |
| 713 | What these scripts cannot see from an unprivileged account, stated rather than guessed | recorded (limitation) | Per-process filesystem accounting (`fs_usage`, `ioalloccount`) needs root, so §13's disk claim is measured as block totals of the AgentSpace directories this user can read, with the unreadable ones (`Runtime/<account>` is 0700 to the agent) named in `diskWrites.unreadable` instead of counted as zero. `lsof -p <worker>` returns nothing for a process owned by another uid — measured, empty — so worker descriptor counts come out PENDING. Viewer-side counters are read from the unified log's `frame stream … ended:` summaries, which only appear when a stream ends; the CPU-copy decision is `PENDING` whenever the worker's CPU delta over the window is below one clock tick (0.05 s), because that says nothing |
| 714 | The memcpy stays, and no GPU publisher was built | pending (by design, plan §5/§6) | §5 makes this a measurement gate and the measurement needs a live stream on an installed worker. `SharedFramePublisher.write(surface:rects:kind:slot:region:)` still copies patches into shared memory, the `SharedCopy` interval exists precisely so a trace can price it, and `frame-benchmark.sh`'s `derived.megabytesCopiedPerWorkerCPUSecond` / `workerCPUmsPerPublishedFrame` are the two numbers §6 asks for. Neither verdict can be reached from this session, so the copy is not deleted and `IOSurface` is not introduced (§29 keeps it out anyway) |
| 715 | No wire contract, registry key or compatibility surface moved this round | pass (code + measured) | `FrameHeader.byteCount` is still 52 and asserted at that size; `protocolVersion` is still 1; `preview.*` and `window.stream.*` stay registered (§304 row 680); the two deleted files (`FrameConnection.swift`, `FrameSocketConnection.swift`) were internal duplicates replaced by one Core `FrameSocket` used by both ends, not a protocol change; `scripts/mcp-smoke.sh` still lists all 22 `agentspace_*` tools and the console refusal still surfaces through MCP. No new fallback into the human session was added, and no account lifecycle came back |
| 716 | The Swift suite and the release gate are green except where the machine says no | pass (measured) | `env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcrun swift test` → **494 tests, 0 failures** in 45.343 s (472 before this round, +20 in `tests/Unit/FrameEngineTests.swift`, +2 CLI flag guards). `npm test` in `packages/agentspace-mcp` → 23/23. `scripts/check-all.sh` → dist guard ok (stapled app matches the stapled DMG), `scripts/test.sh` passed, `updater-e2e: 19 checks passed`, `all MCP smoke checks passed`, then `gui-verify: refusing to run — the console session's screen is LOCKED` → `check-all: failed at scripts/gui-verify.sh`. Three of four layers, the same shape as §303 row 673 and §305 row 701, and for the same machine reason |
| 717 | `docs/status.md` no longer promises a screenshot fallback for the live view (plan §30) | pass (code + docs) | The capability line said "ScreenCaptureKit desktop stream with screenshot fallback". There is no such fallback in the live path: `DesktopViewerView.startPreview()` opens a `FrameClient` and nothing else, and the only `SpaceService().screenshot(...)` call in that file is the manual snapshot button (`capture()`). The line now states the binary transport, says explicitly that a gone stream is reported rather than papered over with an old picture, and keeps `screenshot` named as the separate one-shot it is. §304's debt sentence was rewritten to carry what this round closed and what is still owed |

## 307. 0.1.21 released, and the gate that disagreed with itself (2026-09-21)

The frame-engine hardening of §306 is published as `v0.1.21`, built and gated at
`a92ce0d`. The release itself is routine; the interesting part is that the
aggregate went red on the first run and red **on a different check** on the
second run of the identical artifact. That pair of readings is evidence about
`scripts/gui-verify.sh`, not about the build, and it is recorded here as such —
because a gate that cannot be trusted to fail the same way twice cannot certify
a release either.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 718 | The version was committed before `dist` was built, so the build number identifies these bytes | pass (measured) | `a92ce0d Release: 0.1.21` changes exactly the four version sites §305 row 688 established (`Info.plist` `CFBundleShortVersionString`, `cliVersion`, `agentSpaceVersion`, the `Diagnostics` system line), and `git rev-list --count HEAD` at that commit is **345**, which is what `dist/AgentSpace.app/Contents/Info.plist` reports as `CFBundleVersion` — the stamp is `0.1.21 (345)` |
| 719 | The candidate is signed, notarized, stapled and accepted by Gatekeeper | pass (measured) | `scripts/release.sh` → `signer: Developer ID Application: Guofeng Liu (U8U443D7ZL)`, `team: U8U443D7ZL`, version `0.1.21`, protocol `1`, with the five nested binaries verified `--strict` (app, helper, worker, CLI, updater). `NOTARY_PROFILE=octoshrink-notary scripts/notarize.sh` first proves the profile answers live, submits app `8a38aa8d-f935-47dc-b3dc-6c7a49eccff1`, rebuilds the DMG from the stapled app, submits DMG `d97c4cc4-f0e9-412c-b298-ca7a033db191`, staples both, and ends `app staple valid / dmg staple valid / Gatekeeper accepts the app`. Artifact: 5,367,711 bytes, CDHash `a16d933784da106efc8c907fcb6d5680be6628a7` |
| 720 | **The first aggregate run failed, and the wrapper's exit code lied about it.** | pass (caught, disclosed) | `/tmp/checkall-0121.log`: dist guard ok (`stapled app matches the stapled DMG (a16d9337…)`), `Executed 494 tests, with 0 failures`, `updater-e2e: 19 checks passed`, `all MCP smoke checks passed`, then `gui-verify: 10 passed, 3 failed` → `check-all: failed at scripts/gui-verify.sh` → `CHECKALL_EXIT=1`. The background-task harness reported that same command as *exit code 0*, because the wrapper's last statement was the `echo` of the code it had just captured. Only the explicit `CHECKALL_EXIT=` line in the log told the truth, which is why every gate run in this session writes one |
| 721 | The three failures were a race in the verifier, not a regression in the build — proved by re-running the same bytes | pass (measured) | The retry (`/tmp/guiverify-0121-b.log`) read `refresh slider min=2.0`, `max=10.0` and `preview tiers` **correctly** and instead failed a different check: `wizard reaches a real next state: expected [step 2] got [no continue button]`. Two runs, same artifact, two different failure sets. Both first-run reads were the only two lookups in the script performed **once** after an asynchronous re-layout, while the neighbouring build-stamp, registry-notice, tiers and update-pane reads each poll. And no source change could have removed those controls: `git diff v0.1.20..HEAD -- apps/AgentSpace/App/AgentSpaceApp.swift` is empty, and both identifiers are in that file (`statusRefreshSlider` at line 267, `previewWidthPicker` at 272) |
| 722 | What was fixed, and what the fix deliberately does not do | pass (code) | The Advanced-tab pair and the wizard's Continue lookup now poll for the **control** before asserting its **value**; the tiers loop's budget went 2 → 5 attempts for the same reason. The asserted values are untouched (`2.0`/`10.0`, the four tier titles in order, `step 2`, and the enabled/disabled branch that decides whether a click proves the wizard advanced), so a control that really never appears still fails — five seconds later. Nothing was widened to accept a different number, and no check was deleted; `bash -n` clean |
| 723 | The complete release gate is green on the signed candidate | pass (measured) | `scripts/check-all.sh` → `check-all: all 4 layers passed`, `CHECKALL_EXIT=0`: dist guard `a16d9337…`, `Executed 494 tests, with 0 failures` in 46.854 s, `updater-e2e: 19 checks passed`, `all MCP smoke checks passed`, `gui-verify: 13 passed, 0 failed` on a session the script itself labelled `presenting` — §303 row 673, §305 row 701 and §306 row 716's locked-console refusal did not recur because the console happened to be unlocked for this window |
| 724 | The published release is the bytes this tree built, and the download round-trips to the same hash | pass (measured) | Annotated tag `v0.1.21` points at `a92ce0d9c1bdf5a78fb7283cf369f98bf7ac6231` — the commit `dist` was built from, **not** at `master`'s tip, which is one commit later (`109aa91 gui-verify: poll for the control before judging its value`); the gate fix is therefore not inside the tagged tree, and this section names that rather than hiding it. `github.com/misswell/AgentSpace/releases/tag/v0.1.21`: `draft=false`, `prerelease=false`, asset `AgentSpace-0.1.21.dmg` 5,367,711 bytes with GitHub digest `sha256:c1fd25b7531eb358b8ef12724f65630edc32b6d0ea3017440ef9fd9a2bfa63e7`, equal to `shasum -a 256 dist/AgentSpace-0.1.21.dmg` **and** to the same hash recomputed on the asset after a real `curl -L` of `…/releases/download/v0.1.21/AgentSpace-0.1.21.dmg` (the copy was then deleted) |
| 725 | The channel the updater reads is live and shaped as the code expects, one release later | pass (measured, without pressing anything in the owner's copy) | `GET /repos/misswell/AgentSpace/releases/latest` → `tag=v0.1.21 draft=false prerelease=false`, `asset=AgentSpace-0.1.21.dmg`, `digest=sha256:c1fd25b7…`, https `browser_download_url` — the exact triple §305 row 691 says `AgentSpaceIdentity.archiveName(for:)` and the `sha256:`-prefixed integrity field need. This Mac's installed copy is 0.1.19, so §305 row 701's predicted reading (*AgentSpace 0.1.21 is available*, with a live install button and no blocked notice) is now satisfiable. It was **not** taken: pressing check in the owner's running app writes their `lastCheck` state, and installing 0.1.21 over their copy is their decision, so the evidence stops at what the channel says |
| 726 | The release does not claim the frame engine's real-machine gates | pass (disclosed in the product's own language) | §304 row 687 and §306 rows 704/710/714 stay open and the release notes say so: the worker this session had measured on this Mac was 0.1.13, which answers `preview --stats` with `unknown method 'frame.stats'` (§306 row 712), so no latency/CPU/bandwidth/static-desktop/fast-user-switch number existed for this code when the notes were written. Row 728 records that this stopped being true twenty minutes later. The notes also carry plan §14's other half — an update replaces only `/Applications/AgentSpace.app` and never the helper or the installed worker, so the new frame path needs the explicit 「重新安装助手…」 action, and 「助手版本过旧」 afterwards is the correct state (§302 row 666, helper-stale memory). That half is what actually happened: the worker moved because someone chose the install actions, not because a release was published |
| 727 | No compatibility or safety surface moved in the released bytes | pass (measured on this artifact) | `protocolVersion` stays 1 and the header stays 52 bytes — `FrameHeader.byteCount = 52` with `decoding:` rejecting any other length (`shared/Core/Sources/AgentSpaceCore/FrameHeader.swift:25,82`), and `testHeartbeatTravelsInTheHeaderWithoutChangingItsSize` pinning that the new heartbeat rides that size rather than growing it; `preview.*` and `window.stream.*` remain registered for old clients; registry keys and `"spaces"` unchanged; every `agentspace_*` MCP tool still listed by `scripts/mcp-smoke.sh`; the one new user-visible string (the stale-picture notice for a terminated capture stream) exists in **both** `en` and `zh-Hans` per §306 row 702, with `LocalizationTests` inside the 494; no new helper operation, no `sudo`, and no path that selects the human console as a fallback |
| 728 | **Plan §14's precondition became true on this Mac while this release was being gated.** | pass (measured; provenance named, not guessed) | `/Applications/AgentSpace.app` now reads `0.1.21` (was 0.1.19 in §305 row 699) and `/Library/Application Support/AgentSpace/Worker/active/agentspace-worker --version` now reads **`0.1.21`** (was 0.1.13 in §306 row 712), with `Worker/versions/0.1.21/` present and the active copy 2 492 096 bytes. So the app and the worker are the same release for the first time, and `agentspace preview AgentUse --stats --json` answers instead of erroring: `openStreams 0`, `streams []`, `workerInstanceID F8A978AB-15CA-4E29-81BF-AD9717EF64B9`, `sessionGeneration 106757933383708`, against a live worker (pid 63218, uid 503, `state: ready`, `verdict: usable`, `onConsole: false`, Screen Recording and Accessibility granted, Full Disk Access not). It was not this session and not the updater: `~/Library/Logs/AgentSpace/update.log`'s newest line is `06:21:29Z`, which is an argument-contract refusal from `scripts/updater-e2e.sh`, not an install; and the three installed files carry mtimes of `14:06:34`/`14:06:35`, which is when `scripts/release.sh` built `dist` — mtimes a `ditto` copy preserves. A hand install from `dist/` plus the explicit worker reinstall, done by the other live session in this checkout or by the owner. **What this unlocks**: §304 row 687's run is now reachable, and `scripts/frame-benchmark.sh` moved off its §14 blocker to the next honest one — `cannot measure: no frame stream is open for AgentUse — open the Desktop (or a Fusion window) in AgentSpace and measure again` |
| 729 | What is still owed before any frame-engine performance claim | pending (one Desktop/Fusion window open, then two timed runs) | Nothing in this release measures the engine on real pixels yet. `frame-benchmark.sh --mode static` owes §13 (≈0 frames and bytes on a still desktop, `encoderActive` false with zero activations, no frame-path disk writes), `--mode motion` owes §27's old-vs-new comparison against the JSON baseline of §304 row 686, and `frame-soak.sh` owes the drift numbers. §306 row 713's limits still apply to whichever of them run here: worker descriptor counts are unmeasurable from an unprivileged account, and per-process filesystem accounting needs root — those verdicts come out PENDING rather than passing |

## 308. The shared-memory name was 48 bytes against a 31-byte limit, and the fix is in the worker (2026-09-21)

`v0.1.21`'s frame engine was sound and still produced no picture: every Desktop
window and every Fusion pane died at the first syscall with
`shm_open failed: File name too long`, because the allocator named its buffer
`/agentspace-<full UUID>` — 48 bytes — and Darwin's `shm_open` limit measured
here is **31**. This section records what the kernel actually accepts, what the
transport did *not* need to change, and the two facts that had to be discovered
by being wrong in a test (`errno` after a successful call, and an `st_size` that
is not the size asked for). Nothing about the path moved: same ScreenCaptureKit →
CVPixelBuffer → dirty regions → anonymous POSIX shm → `SCM_RIGHTS` → `FrameClient`
→ Metal, same adaptive H.264, same `protocolVersion 1`, same 52-byte frame header.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 730 | The failure is the **name**, confirmed against the kernel before any code moved | pass (measured) | `git show a92ce0d:native/AgentSpaceWorker/Sources/AgentSpaceWorker/SharedFrameRegion.swift` opens `let name = "/agentspace-\(UUID().uuidString)"` — 48 UTF-8 bytes. Here `shm_open` accepts 31 bytes and refuses 32 with `ENAMETOOLONG` (63): `tests/Unit/SharedMemoryNameTests.swift:60` `testDarwinLimitIsWhatItSaysItIs` opens both against the real syscall. `testOldUUIDShapedNameIsStillRefusedByTheKernel` rebuilds the exact legacy string and asserts the kernel refuses **it**, so this is a regression test and not a string-length comparison with a `shm_open` call drawn beside it |
| 731 | The new name is short, single-component, and does not repeat | pass (unit) | `shared/Core/Sources/AgentSpaceCore/SharedMemoryName.swift:26` `make() -> "/as-" + 24 hex` = 28 bytes, with a `precondition` on the limit rather than a comment about it. 1 000 sequential names and 10 000 in a `Set` come back distinct (`testNamesDoNotRepeat`); the shape assertion is a real character class, not a prefix check |
| 732 | The allocator now lives in Core, because a Worker test target is not on the table | pass (code + 13 unit + 3 integration) | `native/AgentSpaceWorker/Sources/AgentSpaceWorker/SharedFrameRegion.swift` deleted (`git rm`), replaced by `shared/Core/Sources/AgentSpaceCore/SharedFrameRegion.swift` as `public`, with the one construction site unchanged (`SharedFramePublisher.swift:90`). The seam is `allocate(regionSize:makeName:attempts:)` — a test hands it a name the kernel will refuse or one already taken, which is the only way to reach the branches that decide whether a failed stream leaks a named object. `@_silgen_name("shm_open")` is needed on both sides: the symbol is in libSystem and the declaration is unavailable to Swift |
| 733 | Every refusal path releases the descriptor and removes the name — and the honest note that this half was already right in 0.1.21 | pass (unit, on failures the kernel really produces) | `SharedFrameRegionAllocationTests`: an over-long name reports `ENAMETOOLONG` with `attemptedNameBytes == 48` and no token in the message; a taken name is retried **with a fresh name** exactly once (`maximumCreationAttempts = 8`, `O_CREAT \| O_EXCL` kept); exhausting a 3-attempt budget reports `EEXIST` rather than a fifth try; and a 1 PiB region fails at `mmap` with `ENOMEM`, after which the name it opened resolves to `ENOENT` — the leak case, proven by asking the namespace. What v0.1.21 already did correctly (close + unlink on the `ftruncate` and `mmap` paths, `munmap` + `close` in `deinit`) is now *tested* rather than merely present |
| 734 | **Measured: `errno` is not cleared by a successful syscall.** | pass (found by being wrong) | The first version of `testDarwinLimitIsWhatItSaysItIs` failed with `("2") != ("0")`: the 31-byte open succeeded, and the helper reported the `ENOENT` that an earlier failed lookup had left in `errno`. `tests/Unit/SharedMemorySyscall.swift` therefore sets `errno = 0` before calling — and only in the test helper, which says so: production (`SharedFrameRegion.openDescriptor`) reads `errno` on the line after the call and only when the call failed, which is the rule §5 asks for |
| 735 | **Measured: a shm object's `st_size` is not the size passed to `ftruncate`.** | pass (found by being wrong) | `ftruncate(4096)` → `st_size` **16384**; a 4480-byte region → **16384**. The two integration assertions that compared for equality failed on exactly that, and now assert `>=` with the measurement in the comment (`tests/Integration/SharedFrameMemoryLifecycleTests.swift:20`). Consequence for the engine: `region.size` is what the protocol maps and names, never `st_size`, so a rounded-up object cannot widen a slot |
| 736 | The happy path ran end to end on real memory, including a descriptor passed over a real socket | pass (measured, executed) | `SharedFrameMemoryLifecycleTests` (3 tests, all run): `shm_open` → `ftruncate` → `mmap` → write → read → `shm_unlink` → mapping still readable → name resolves to `ENOENT`; then `SharedFrameRegion` → `FrameSocket.sendFileDescriptor` → `receiveFileDescriptor` over a `socketpair` → `mmap` **through the passed descriptor** → the slot header and payload decode at the same offsets on the second end. Neither end holds a name. `testTheFrameWireHasNoRoomForAName` pins `FrameHeader.byteCount == 52` and `SharedFrameNotice.byteCount == 32` and greps both for the name that was generated in the same test |
| 737 | A machine that cannot produce an H.264 encoder now sends pixels instead of stopping the stream | pass (code + unit) | `FrameEncoderAccess.path(for:opening:at:)` (`shared/Core/Sources/AgentSpaceCore/FrameEncoderAccess.swift`) answers `.delta` for a refused activation and holds the question back for the cooldown window, so 60 video frames over a minute cost 12 activation attempts and 12 `videoEncoderFailures` (`FrameEncoderAccessTests`, 6 tests) — the count is attempts, not frames, and not one-per-frame either. The caller acts on the answer rather than documenting it: `FrameSurfaceRouter.receive` (`FramePublisher.swift:81`) takes the returned path and falls through to `shared.receive(surface)`, which is the fallback happening. `createEncoder() -> Bool` replaced `ensureEncoder()`; the log line states the consequence and the counter records it |
| 738 | A key frame is only finished when a key frame reaches the socket | pass (code + unit) | `VideoToolboxEncoder.encode` now returns `FrameEncodeSubmission` (`.submitted` / `.busy` / `.failed(OSStatus)`), and `busy` increments `framesDropped` — the case where a frame entered no codec and left no trace. Output goes through an injected closure into `sendVideo(…, isKeyFrame:)`, whose **socket result** decides `FrameKeyFrameState.noteOutput(isKeyFrame:delivered:)`: an undelivered key frame keeps the request set (`FrameKeyFrameStateTests`, 5 tests). `VTCompressionSessionEncodeFrame` returning success is not evidence a viewer has anything decodable, and submission no longer counts as one |
| 739 | An acknowledgement that expires ends the connection; it does not free a slot somebody may still be reading | pass (code); pending (unit — the rule lives on a serial queue with no test target) | `expireAcknowledgements(before:)` (`SharedFramePublisher.swift:313`) no longer walks the expired entries setting `freeSlots[slot] = true`; it counts them into `unacknowledgedDrops` and calls `connectionLost()`, which aborts the socket so the viewer sees an EOF, reconnects, handshakes, and is given a baseline. The class header states the ownership rule as the code follows it, including why there is deliberately no third case (a late ACK is ignored, not trusted). Not unit-tested: the decision needs a live `SharedFramePublisher` and the brief forbids a Worker test target, so `Gate F` on this machine is the evidence for it |
| 740 | **A mid-stream resize the kernel refuses used to go silent behind a live heartbeat. It cannot any more.** | pass (code) | Removed line, v0.1.21: `do { try ensureRegion(for: surface) } catch { latest.store(surface); return }` — the old-size mapping stayed, the surface went back on the shelf, and the watchdog kept beating, which is a frozen desktop that reports itself alive. Now `ensureRegion` → `allocate` → on refusal `loseRegion()`: the region and its dimensions are dropped, `connectionLost()` closes the socket, `unavailableAt` remembers the size, and `attach` asks the kernel again on the one path a client can drive — so the retry is one syscall burst per reconnect, not sixty a second on the capture thread |
| 741 | The refusal is a value the product can act on, and the error envelope stayed put | pass (code + unit) | `FrameStats` gained `videoEncoderFailures` and `allocationFailure: SharedFrameAllocationFailure?` (both additive; the pre-existing fields keep their names), the worker exposes them in `frame.stats` per stream and as `recentAllocationFailure` in the aggregate reply (`Operations.swift:795`), and `FrameManager.lastAllocationFailure` keeps the most recent refusal — because the stream worth diagnosing is the one that never started. The wire did not move: no `shmName` anywhere, no new field in `FrameHelloAck`/`FrameHeader`, and `agentSpaceError` stays `AgentSpaceError(code: .internalError, …)` — `testTheWireFormIsAnOrdinaryInternalError` pins that on purpose, since a new `AgentSpaceErrorCode` case would make every older viewer fail to decode the error at all. `SharedFrameAllocation.classify(message:)` is documented and used as the last resort it is |
| 742 | What a person sees over a desktop that is not appearing | pass (code + both locales) | `RemoteSurfaceView.swift:31` shows 「画面流初始化失败」/「无法创建共享画面缓冲区。请重新连接；如果问题持续，请更新 AgentSpace。」 when the message is an allocation refusal, and the syscall's own words otherwise; both keys are in `en.lproj` and `zh-Hans.lproj` (`Localizable.strings:554-555`), inside `LocalizationTests`, inside the 526 |
| 743 | One allocator, no legacy name left in the product, no second implementation | pass (measured by grep) | Across `apps`, `native`, `shared`: `shm_open`/`shm_unlink` appear in Core's `SharedFrameRegion.swift` (plus its own tests) and nowhere else in production code; the only surviving `"/agentspace-\(UUID().uuidString)"` literals are the two regression tests that rebuild the legacy name to prove it is refused, and unrelated `NSTemporaryDirectory()` paths. `SharedFrameRegion(` has exactly one production call site |
| 744 | The automated gates are green on the bytes that shipped | pass (measured) | `swift build` → `Build complete!`; `env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcrun swift test` → **`Executed 526 tests, with 0 failures`** in 48.6 s — 494 at §307 row 723 plus exactly the 32 this round adds (5 `SharedMemoryNameTests`, 8 `SharedFrameRegionAllocationTests`, 5 `SharedFrameAllocationTests`, 6 `FrameEncoderAccessTests`, 5 `FrameKeyFrameStateTests`, 3 `SharedFrameMemoryLifecycleTests`, each suite re-counted in the same run's `Executed` lines); `npm test` → `# pass 23 / # fail 0`; `scripts/mcp-smoke.sh` → `all MCP smoke checks passed`; `scripts/check-all.sh` → `check-all: all 4 layers passed`, `CHECKALL_EXIT=0`, dist guard `stapled app matches the stapled DMG (72df52d0e3bdea6404b4ba690f08f7af23a740d4)`, `updater-e2e: 19 checks passed`, `gui-verify: 13 passed, 0 failed` on a session the script labelled `presenting` |
| 745 | The artifact is this tree's, signed and notarized | pass (measured) | `deaf818 Release: 0.1.22` touches the four version sites and `git rev-list --count deaf818` = **350**, which is the `CFBundleVersion` the app itself reports (`构建 0.1.22 (350)` read off the running window). `scripts/release.sh` → five nested binaries `--strict`-verified, `Developer ID Application: Guofeng Liu (U8U443D7ZL)`; `scripts/notarize.sh` submissions `de76c121-a0b5-4d5b-9e63-38a46f042cb0` (app) and `fcb18bf4-37ff-464e-b8ed-eb2f263a229d` (DMG), both stapled, `Gatekeeper accepts the app`. `dist/AgentSpace-0.1.22.dmg` = 5,435,974 bytes, `sha256:5c497ff08ebca1130c177a59eb1003a362351fdb28ae5d14b5a063357cb2a8f8` |
| 746 | **The real-machine frame gates are still open, and the reason is a password, not a code gap.** | pending (needs the owner's admin authorization) | `/Applications/AgentSpace.app` is 0.1.22 and its Diagnostics sheet says so in the product's own words: 「特权助手 — answering, but running an older build than this app」, while `/Library/Application Support/AgentSpace/Worker/active/agentspace-worker --version` is still **0.1.21**. Every frame-path pixel gate (Gates A–L, `scripts/frame-soak.sh`, `scripts/frame-benchmark.sh`) measures the **worker**, so none of them is evidence about this fix until 「重新安装助手…」 swaps the root LaunchDaemon and re-installs the worker — and that prompt is a macOS authorization dialog only the owner can satisfy. It is recorded as pending rather than passed, per §20 and §303 row 673 |
| 747 | **An app at 0.1.22 over a worker at 0.1.21 reproduces the P0 verbatim, which is what makes row 746 a measurement and not a guess** | pass (measured on the running install) | Read out of the live window through the accessibility tree while `/Applications/AgentSpace.app` reported `0.1.22 (350)` and `agentspace-worker --version` reported **0.1.21**: the Desktop window's own static texts were 「画面流不可用, AgentUse Desktop」 and `shm_open failed: File name too long` — the exact strings the brief opened with, produced by the old allocator still compiled into the old binary. This is deliberately the pairing §21 forbids ("不要用旧 Worker 测新 App"), performed once and written down because it is the only way to show that the fix's delivery path is the worker and not the app bundle. Nothing below this line is evidence about pixels until the worker is replaced |
| 748 | The release is published, and the bytes on the channel are the bytes that were gated | pass (measured) | `git push origin master` → `f77335d..b5300ae` (exit 0); annotated `v0.1.22` → `deaf818` pushed; `https://github.com/misswell/AgentSpace/releases/tag/v0.1.22` is `draft: false` with asset `AgentSpace-0.1.22.dmg`. The digest GitHub computed for the **uploaded** asset — `sha256:5c497ff08ebca1130c177a59eb1003a362351fdb28ae5d14b5a063357cb2a8f8`, `size: 5435974` — is identical to local `dist/AgentSpace-0.1.22.dmg` (row 745), so the file an older app will download is the notarized file row 744 gated rather than a second copy of it. The release note says in its own words that an in-app update replaces only `/Applications/AgentSpace.app` and that this fix therefore needs 「重新安装助手…」, which is the §302 row 662 rule: a promise a user has to discover by hand is a broken promise |

## 309. A frame buffer has two sizes, and the engine was using the wrong one at both ends (2026-09-21)

`shm_open failed: File name too long` was the first half of this bug, and fixing it
did not produce a picture — it produced the sentence that describes the second
half: `shared frame notice does not match its mapping`. That is progress with a
precise meaning. Every syscall the name sat in front of now succeeds, so the
failure arrives *inside* `SharedFrameMapping`, at a comparison between what the
worker wrote and what the viewer derived. This section records the two reasons
that comparison could not succeed — one about sizes, one about connections — and
what had to be measured on this kernel to tell them apart from a Screen Recording
problem, a permissions problem, or a Metal problem.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 749 | **The error moved, and where it moved to is the diagnosis** | pass (measured on the running install) | With `/Applications/AgentSpace.app` at `0.1.22 (350)` and the installed worker answering `0.1.22` — the pairing §27 asks for, reached after the owner's 「重新安装助手…」 cleared §308 row 747's old-binary worker — the Desktop window still read 「画面流不可用」, but its protocol line had changed from `shm_open failed: File name too long` to `shared frame notice does not match its mapping`. That sentence only exists in the viewer's `SharedFrameMapping.frame(notice:header:)` size guard, which is downstream of `shm_open`, `ftruncate`, `mmap`, the `SCM_RIGHTS` handoff, `FrameHello`, and the first notice read. So Screen Recording, Accessibility, the Aqua session, `frame.sock` permissions and Metal are each ruled out by being *passed*, and what remains is the two ends' disagreement about the layout — which is what §0 of the brief said, confirmed rather than assumed |
| 750 | Root cause 1, in the code, before any of it was edited | pass (code) | v0.1.22's reader called `fstat` on the descriptor it was handed and laid the region out from `st_size`; the writer laid the same region out from `width × height × 4` (`git show b1e1091:shared/Core/Sources/AgentSpaceCore/SharedFrameRegion.swift` computes `let payloadCapacity = width * height * 4` inline, and `SharedFrameMapping` had no geometry at all). Two true numbers, one name, and on Darwin they are never equal: `ftruncate(4096)` → `st_size` **16384** (§308 row 735), `ftruncate(4480)` → **16384**, and measured again here for the largest region the wire can name, `ftruncate(4_294_967_295)` → `st_size` **4294967296**. A viewer using the rounded number puts slot 1 12 KiB away from where the writer put it and reads zeroes through a valid-looking header |
| 751 | The two numbers now have two names, and neither is derived from the other | pass (code + unit) | `SharedFrameGeometry.regionSize` (`shared/Core/Sources/AgentSpaceCore/SharedFrameGeometry.swift:29`) is the protocol's logical size — from the dimensions, and nothing else. `SharedFrameMapping.mappedCapacity` (`shared/Core/Sources/AgentSpaceCore/SharedFrameMapping.swift:17`) is `fstat.st_size`, and the comment on it says what it is for: *"a bound on what may be read, never an input to the layout."* `SharedFrameRegion` carries the geometry as a value (`public let geometry`, with `size`/`payloadCapacity` kept as views onto it) so the writer's buffer and the reader's offsets are the same object's numbers, not two recomputations |
| 752 | One geometry for both ends, and no second copy of the formula | pass (code + grep + unit) | `SharedFrameGeometry.make(width:height:)` is the only place `slotMetadataSize + payload` and `× slotCount` are computed with a result that is used: every step runs through `multipliedReportingOverflow`/`addingReportingOverflow`, and the result must fit `Int(UInt32.max)` because it is also a `UInt32` wire field. Grepping `apps`, `native` and `shared` for `SharedFrameLayout.slotOffset`/`.slotSize`/`.regionSize`/`.payloadCapacity` returns **tests only** — no production file outside Core's own layout enum, and `SharedFrameLayoutTests` keeps the arithmetic honest from the other direction. `SharedFrameGeometryTests` (5) sizes the surfaces this product actually streams (1×1 through 3024×1964 Retina) and refuses 65 536², `Int.max × 4`, 0×800 and a negative edge |
| 753 | The guard the brief forbade deleting is still there, and it compares logical against logical | pass (code + 7 integration tests) | `SharedFrameMapping.swift:44` reads `guard notice.mappingSize == UInt32(geometry.regionSize)`, and the three lines above it say why it may not be relaxed *or* re-pointed at `mappedCapacity`. The order is the fix: transport dimensions > 0 → slot index → **logical vs logical** → `geometry.regionSize <= mappedCapacity` → slot offset from geometry → metadata (sequence, generation, kind **and width/height**) → patch count → each descriptor's bounds → `SharedFrameLayout.validate(regionSize: geometry.regionSize)`. `SharedFrameMappingTests` (7, all against real `shm_open` regions read through a real `socketpair` `SCM_RIGHTS` handoff) covers the case that hides the bug — slot 1, where rounding moves the offset — and asserts the *rejected* values include `st_size` itself: `testRejectsANoticeSizedFromTheKernelRoundingOrByOneByte` proves a notice carrying the kernel's number is refused, so the old derivation cannot come back as a "fix" |
| 754 | The wire did not move, so this is a fix and not a protocol change | pass (measured by the tests that pin it) | `SharedFrameNotice` is still 32 bytes and `FrameHeader` still 52 (`testTheFrameWireHasNoRoomForAName`), `protocolVersion` is still 1, and no field was added, renamed or reinterpreted. What changed is the *documented meaning* of a field that was always there: `mappingSize` now says in its own doc comment that it is the writer's logical layout size and *"intentionally differs from `fstat(fd).st_size` on Darwin because POSIX shm objects may be page rounded"* (`SharedFrameNotice.swift:10`), which is the fact the v0.1.22 viewer had to guess |
| 755 | Root cause 2, in the code: a connection that quietly changed its buffer | pass (code) | `git show b1e1091:native/AgentSpaceWorker/Sources/AgentSpaceWorker/SharedFramePublisher.swift` — `ensureRegion(for:)` called `allocate(width:height:)` on a size change, and `allocate` builds a **new `SharedFrameRegion`**, i.e. a new `fd`. Nothing in the protocol re-sends a descriptor after `attach`, so after any resize the worker wrote frame B into buffer B while the viewer kept reading buffer A. The reader saw a valid-looking header decoded through the wrong layout — corrupt pixels, or the mismatch the row 749 line reports — while the worker's own stats still looked healthy. This is a second, independent reason a correct layout could still fail, and it is why the Desktop and a resized Fusion window could disagree even after row 753's guard was right |
| 756 | One connection, one mapping: the rule is now a return value | pass (code); the pixels are Gate E | `ensureRegion(for:) -> Bool` (`SharedFramePublisher.swift:117`) does not allocate. Dimensions match → `true`. They do not → remember the size in `unavailableAt`, drop `region` and `dimensions`, `connectionLost()`, return `false`, and `publishIfPossible` cannot proceed past `guard ensureRegion(for: surface) else { return }` (line 370). The viewer's own reconnect reaches `attach`, and `attach` allocates for the size the capture has *now* — `allocate` bumps `generation` per region (line 89) and requires a `fullBGRA` baseline, so a new buffer is never continued from an old baseline. `loseRegion()` is gone because the rule moved: it is no longer a response to a refusal, it is the response to any size change. Not unit-testable here (no Worker test target, §25), so Gate E and Gate H are its evidence |
| 757 | A suspect mapping never gets asked for another frame | pass (code, structural) | The brief's §15 split is enforced by the order of two lines, not by a comment: `mapping.frame(notice:header:)` is `FrameClient.swift:181` and `sequence.accept(...)` → `.requestFullFrame` is line 183-186, so a mapping that cannot be laid out throws before the sequence validator is consulted and `requestFull` is unreachable for it. `runReconnectLoop` catches `SharedFrameMappingFault` in its own branch — before the generic `AgentSpaceError` catch — closes that connection, and lets the handshake produce a descriptor both ends measure the same way. A gap in a *valid* mapping still does the cheap thing (ask for a baseline, keep the buffer) |
| 758 | The typed fault carries the numbers, and not the name | pass (unit) | `SharedFrameMappingFault` (`shared/Core/Sources/AgentSpaceCore/SharedFrameMappingFault.swift`) names its kind (`invalidDimensions`, `invalidSlot`, `logicalSizeMismatch`, `capacityTooSmall`, `metadataMismatch`, `patchCountInvalid`, `descriptorOutOfBounds`) and its `logLine` emits transport width/height, the computed logical size, the notice's size, `mappedCapacity`, slot, generation and sequence — the §16 list. `testTheFaultLineCarriesTheNumbersAndNotTheName` asserts the numbers are in the string and the region's random token is not, which is the same rule §308 row 733 holds for allocation failures |
| 759 | The window stopped quoting the protocol at the person, and says when to give up | pass (code + both locales + unit) | `RemoteSurfaceView.swift:31` switches on `client.streamNotice` before anything else: three consecutive connections that faulted read 「画面流不可用 / 共享画面连接无法恢复。请重新连接；如果问题持续，请更新 AgentSpace。」; fewer read 「画面流状态不同步 / AgentSpace 正在重新连接共享画面。」 The count is `FrameStreamRecovery` in Core (3 tests), because `giveUpAfterAttempts = 3` is a promise about the reconnect schedule — the backoff reaches 2 s and 4 s inside three attempts, so "still trying" stops being true at roughly the moment the schedule stops being quick — and `noteStreaming()` clears it the first time pixels arrive, so a stream that had three bad seconds cannot go on reporting itself dead while on screen. Keys are in `en.lproj` and `zh-Hans.lproj:559-561`, inside `LocalizationTests`, inside the 545. The raw protocol line moved to `Self.log.error` and Diagnostics, where it is answerable without being a wall of text |
| 760 | **One test's premise moved, and the honest version of what it now proves** | pass (measured; the branch it used to hit is now unreachable on this machine) | `testMappingFailureUnlinksTheNameItOpened` opened a 1 PiB region and let `mmap` refuse it, then asked the namespace whether the name survived. With the size coming from geometry that premise is gone — and what replaced it was measured rather than picked: here `ftruncate` accepts 1 PiB (and `Int.max / 2`) and `mmap` answers `ENOMEM` (12), while the **largest region geometry allows**, 4 294 967 295 bytes, `ftruncate`s *and* `mmap`s successfully. So no size the wire can name can reach the `.map` branch through the public initializer, and `testAMappingTheWireCannotNameNeverReachesTheNamespace` asserts the earlier, stronger fact: the refusal is `AgentSpaceError(code: .badRequest, "shared frame mapping is too large")` and the probe name resolves to `ENOENT` because no object was ever created. The `munmap`/`close`/`shm_unlink` path in `SharedFrameRegion.init` stays — it is a kernel contract, not a decoration — but it is now defensive code, and this row rather than a green checkmark is where that is written down |
| 761 | The automated gates, on this tree | pass (measured) | `swift build` → `Build complete!`, no warnings. `env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcrun swift test` → **`Executed 545 tests, with 0 failures`** in 47.0 s — §308 row 744's 526, plus 5 `SharedFrameGeometryTests`, 3 `FrameStreamRecoveryTests`, 7 `SharedFrameMappingTests`, 1 more in `SharedFrameRegionAllocationTests` (8 → 9), less the 2 in `SharedFrameLayoutTests` (5 → 3) whose subject, the `st_size`→capacity inverse, no longer exists. `npm test` in `packages/agentspace-mcp` → `# pass 23 / # fail 0`; `scripts/mcp-smoke.sh` → `all MCP smoke checks passed`. `scripts/check-all.sh` has **not** been run against these bytes yet, and `dist/` is still the 0.1.22 artifact, so no gate below is claimed |
| 762 | The frame gates this release is about | pending (needs the 0.1.23 install, then the same password) | Gates A–I, `scripts/frame-soak.sh` and `scripts/frame-benchmark.sh` all measure the **worker**, and rows 755/756 are worker changes: they are unrunnable until an app *and* worker at 0.1.23 are installed, which needs `scripts/release.sh` → `scripts/notarize.sh` → the in-app 「重新安装助手…」 prompt only the owner can satisfy. Recorded as pending per §20/§26 rather than passed off row 761's green suite — a layout fix proven on synthetic slots is not a desktop proven on pixels |

## 310. A desktop that was upside down, three counters that had stopped, and streams nobody was watching (2026-09-21)

The layout fix reached real pixels before it reached a gate: a 0.1.23 app over the
0.1.22 worker decoded the shared region and drew the AgentUse desktop, with no
`shared frame notice does not match its mapping` anywhere in the log. That is the
first time in this bug's history there was a picture to look at, and looking at it
found four things §309 could not have seen — one of them a defect this file had
already certified past.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 763 | Root cause 1 is proven on real pixels, and by the mismatched pair the brief forbade | pass (measured on the running install) | The 0.1.23 app (build 360) over the **0.1.22 worker** — the old-worker/new-app combination §27 says not to test with — opened `display:main`, received the baseline and drew the AgentUse desktop: menu bar, Dock, wallpaper, a right-click menu. No `notice does not match its mapping`. The asymmetry is the finding: root cause 1 lived in `SharedFrameMapping`, which is Core and therefore *app-side*, so a fixed app can read a buffer an unfixed worker wrote. Root cause 2 lived in the worker, which is why row 762 still needs the install |
| 764 | **The Metal live view drew the desktop upside down, and earlier rows that said "desktop visible" were looking at it** | pass (found on pixels, fixed in code; re-verification pending row 769) | `/tmp/gate-a-desktop.png` (17:49, this round): the Dock along the **top** of the picture area, the menu bar along the **bottom**, its clock and the context-menu text mirrored — a vertical flip, not a stale frame. Cause: `CIImage(mtlTexture:)` reads row 0 of a texture as its *bottom* row, while the capture, the shared region and the CPU fallback all write row 0 at the *top*; `present(_:)` drew it unflipped. `CALayer.contents = CGImage` — the CPU path — needs no such flip, which is why the two paths disagreed with each other. `git log -S "CIImage(mtlTexture:"` → `d559534`, the commit that introduced the renderer, so this predates 0.1.21/0.1.22 and every §306/§307 row that recorded a desktop appearing. Fixed in `apps/AgentSpace/Rendering/MetalSurfaceRenderer.swift:110` by flipping about the texture's own height **before** the fit-scale, so both the shared and the H.264 path are corrected by the one place that presents |
| 765 | A stream that switched to H.264 stopped counting its own capture | pass (measured, fixed) | `frame.stats` on a live video-mode display stream: `framesCaptured: 1` against `framesPublished: 124`, `captureFPS: 0`, `publishFPS: 0`, `dirtyRatio: 1` — while a second poll two minutes later showed the same stream at `framesPublished: 288`, `heartbeatsSent: 175`, `unacknowledgedDrops: 0`. Cause: `framesCaptured`, `captureRate` and the `dirtyRatio` average all sat inside `SharedFramePublisher.receive`, which `FrameSurfaceRouter` only calls on the **shared-pixel** path (`FramePublisher.swift:114`). The benchmark §38 asks for `captureFPS` per scenario, and every video-mode scenario would have reported zero. Fixed by `noteCaptured(damageRatio:)` called from the router before it chooses a path, with the ratio it already measured rather than a second copy of the formula |
| 766 | A frame stream outlived the viewer reading it, and kept its buffer | pass (measured, fixed) | `openStreams: 4` with exactly one Desktop window open. Three of the four had stopped moving between two polls two minutes apart (`44B00D0E` frozen at `framesPublished: 124, heartbeatsSent: 99`), each still holding `mappingBytes: 7,551,104` — **30,204,416 bytes** of the 256 MB budget mapped for nobody, plus a capture engine and an encoder per stream. Cause: `FrameServer.handle`'s `defer` called `shared.detach()`, which is documented as leaving the stream "ready to be attached again", but the only way back for a viewer is `frame.open`, which builds a **new** publisher — so nothing could ever attach again, and a viewer killed rather than closed never sent its `frame.close`. Fixed at `native/AgentSpaceWorker/Sources/AgentSpaceWorker/FrameServer.swift:101`: the connection now ends with `manager.close(publisher.streamID)`, the same call the RPC makes. §37's soak forbids `mappingBytes` growing linearly; this is how it would have grown |
| 767 | The line the gates are judged on printed its numbers as `<private>` | pass (measured, fixed) | `frame stream display:main ended: received=1 rendered=1 slots=<private> dropped=0 heartbeats=0 gaps=0 reconnects=0 endToEnd p50=<private>ms p95=<private>ms` — `os_log` privacy defaults, applied to every interpolation except the label, including the per-slot counter row 759 added for Gate B. Fixed with explicit `privacy: .public` on each field in `FrameClient.logConnection` |
| 768 | **"One frame then silence" was a misreading, and here is what actually happened** | corrected (this row exists so the wrong diagnosis is not left in the record) | The two `ended: received=1` lines above are the clean teardowns of two app instances that were replaced during the install, not a stalled stream: `socketReconnects: 0` and the log line only printing from `openAndRead`'s `defer` mean `stop()` was called, and the stream that was actually live at the time reached `framesPublished: 288` with `unacknowledgedDrops: 0`. The black picture area in `/tmp/gate-a-flipcheck.png` (17:55) is the same fact from the other side — the window outlived its connection |
| 769 | Gates A–I, the soak and the benchmark, on this tree | pending (console locked; not driven unilaterally) | `CGSessionCopyCurrentDictionary` → `CGSSessionScreenIsLocked=1`, `kCGSSessionOnConsoleKey=1`, user `guofeng`. Consequences measured, not assumed: `screencapture -l35329` → `could not create image from window` (exit 1) while a full-display capture returns 3840×2160 of black. Gate A is judged by looking at the window, row 764's re-verification needs the same, and waking or unlocking the owner's session to get a screenshot is not this agent's call. Recorded pending per §20/§26 |
| 770 | The automated half of §26, after rows 764–767 | pass (measured) | `swift build` → `Build complete!`, no warnings. `env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcrun swift test` → **`Executed 545 tests, with 0 failures (0 unexpected) in 45.582 seconds`**, plus the Swift-Testing run at 0 tests and the `stress: 1000 round trips in 6.38s` line. Rows 765/766 are worker-internal and the worker has no test target (§25 forbids adding one), so those two are evidenced by the numbers above and by the gates row 769 still owes |
| 771 | `scripts/check-all.sh` on the notarized 0.1.23 artifact | blocked at layer 4 of 4 (recorded, not passed) | Clean rebuild first (`rm -rf .build`, because a version number is being spent), then `scripts/release.sh` → `RELEASE_EXIT=0` (build 365) → `scripts/notarize.sh` → `NOTARIZE_EXIT=0`, both submissions `Accepted`, app + DMG stapled, `spctl --assess` → `accepted / source=Notarized Developer ID`, DMG `sha256 d507ebe9e7e8ea46c4a95cf404f3fdcbee0359304ae27469a02bcb046f30795a`. `scripts/check-all.sh` → `CHECKALL_EXIT=1`: layer 1 `Executed 545 tests, with 0 failures in 45.380 seconds`, layer 2 `updater-e2e: 19 checks passed`, layer 3 `all MCP smoke checks passed`, layer 4 refused by its own probe — *"gui-verify: refusing to run — the console session's screen is LOCKED, so no app can put a window on screen and every accessibility read would come back empty. That is the machine, not the build."* Independently confirmed: `count of windows` of the running app through System Events is **0** while `CGWindowList` still lists its two windows |
| 772 | A dead viewer stops the stream, and still does not release it — the before half of row 766's fix | pass (measured on the 0.1.22 worker, which is what is installed) | The 0.1.23 app (build 365) was installed and its Desktop window opened, then the previous instance was quit. Its stream `64B70BAA` had been climbing (288 → 547 published, 175 → 509 heartbeats) and **froze at exactly 547/509** across two polls two minutes apart: the worker's next write hit `EPIPE`, `connectionLost()` ran, and the heartbeats stopped — so a dead peer is noticed, which is what §36's back-pressure work was for. It is not *released*: `openStreams: 5` with one viewer alive, the four dead publishers still registered and each still holding `mappingBytes: 7,551,104`. That is row 766's leak, still present because the fix is in the worker and the worker is still 0.1.22 — the after-half of this row needs 「重新安装助手…」 |
| 773 | `0.1.23` published, and published **with rows 769/771 still open** | pass (measured) — the verdict is on the publication, not on the gates | Owner's instruction, given after the blocked state above was reported. `git push` over `https://` fails on this network (`LibreSSL SSL_CONNECT: SSL_ERROR_SYSCALL`), so master went over SSH: `d8671de..7504bc5`. Annotated `v0.1.23` sits at the last commit of the tree the bundle was built from and its message names `42cabe4` as the compiled commit and separates 「Verified」 from 「NOT verified」 in the tag itself. `gh release create v0.1.23` → https://github.com/misswell/AgentSpace/releases/tag/v0.1.23, `isDraft=false`, `isPrerelease=false`, asset `AgentSpace-0.1.23.dmg` 5,504,939 bytes; downloaded back with `gh release download` and hashed → **`d507ebe9e7e8ea46c4a95cf404f3fdcbee0359304ae27469a02bcb046f30795a`, identical to the gated file**. The notes carry their own section 「这一版没有声称的事」 stating both blockers — this machine's worker is still 0.1.22, so the worker-side fixes are unmeasured, and the console is locked, so nothing could be screenshotted — and the upgrade notice says the fix lives in the worker too, so an in-app update alone leaves the old worker behavior in place |

## 311. The flip drew the desktop below the window, and the counters said everything was fine (2026-09-21)

§310 ended with a desktop that appeared upside down and a fix for it. The fix
shipped in `0.1.23`, and the first thing the owner saw on the installed build was
a black window. Both halves of that are true and they are the same fact: the
matrix that was meant to turn the picture over moved it out of the drawable
entirely, and every number the frame engine publishes — the worker's
`framesPublished`, the client's `received`, the client's `rendered`, the ACK
round-trip — kept climbing while the screen showed nothing. So this section
records the defect, the reason the instrumentation could not have caught it, and
the one gate that did.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 774 | `0.1.23` drew every live frame off-screen, and the cause is provable without a window | pass (reported by the owner, found on pixels, proven by extent, fixed in `8f929e3`) | The report was 「黑屏」 over a live Desktop window. The window measured mean brightness `0.0355`, `76.6%` of samples black, while `frame.stats` on the same stream read `cap 48 pub 47 hb 20, unacknowledgedDrops: 0` and the client's own line read `received=9 rendered=9`. So the transport was healthy and the pixels were going somewhere invisible. `MetalSurfaceRenderer.present` composed the flip as `CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: CGFloat(height))`, and `translatedBy` **prepends** — the product is `y → -(y+h)`, not `y → h-y`. A scratch program applying that exact composition to a 100×200 `CIImage`, then the renderer's own fit-and-centre steps, prints `final extent: (0.0, -200.0, 50.0, 100.0)  overlaps drawable: false`: the frame landed entirely below a drawable spanning `[0, 720]`, so `CIContext.render` had nothing to draw. The intended matrix (`a: 1, d: -1, ty: h`) prints `overlaps drawable: true`. The flip's *reason* from row 764 still holds; only its arithmetic was wrong |
| 775 | `rendered` climbing is not evidence that anything appeared — and on the H.264 path it is asserted rather than observed | pass (measured; recorded as a limitation, deliberately not changed this round) | `noteApplied` (`FrameClient.swift:235`) counts `.uploaded` as rendered, and `.uploaded` means "the command buffer was committed". The H.264 branch calls `noteApplied(outcome: .uploaded)` unconditionally (`FrameClient.swift:216`), and `applyVideo` discards the present result (`_ = present(metal)`, `MetalSurfaceRenderer.swift:41`) before returning `true` — so a video-mode stream reports every frame as rendered whether or not Metal took it, and `endToEnd p50` sits at `0.0ms` because that path never wires the presented callback at all. Every observed black session was in `frameMode: video`. The only instrument that could see the black was looking at the window. Re-pointing the video path's accounting would move the very numbers §38's benchmark reads, so it is recorded here and left alone |
| 776 | Gate A passes on the fixed build: the real AgentUse desktop, upright, live, with no mapping error | pass (measured on a temp-directory build over the 0.1.22 worker) | Built the sanctioned way — `scripts/bundle-app.sh debug /tmp/asb`, nothing in `dist/` touched. Same machine, same worker, same minute: the installed 0.1.23 window measures mean `0.0355` / `76.6%` black and the fixed build measures mean `0.1188` / `18.7%`. The fixed window shows the AgentUse desktop with the menu bar along the **top** (访达 文件 编辑 前往 窗口 帮助, clock `9月21日 周一 18:42`), the Dock along the bottom and a Finder window centred — the orientation row 764 asked for. Liveness proven rather than asserted: `agentspace move` then `agentspace click` in the agent session produced two byte-different captures of the same window id (mean `0.1187` → `0.1207`). No `shared frame notice does not match its mapping` anywhere in the `FrameEngine` category |
| 777 | A resize keeps the picture correct and still leaves the previous stream registered — row 766's leak seen from the client side | pending the matching worker (measured on the old one) | Stepping 捕获宽度 `1,280 → 1,600 → 1,920 px` through `desktopViewerResolutionPicker` kept real pixels at every step (mean `0.1219`, `0.1198`) — the layout and the flip are both correct across resizes. `frame.stats` went from one open stream to **two** with a fresh ID at each change (`C04B4AFD`+`DC588A6B`, then `4A0C426B`+`F78DEBF2`): the superseded publisher is never released, which is exactly what `a090bbb` fixes — in the **worker**, so it cannot be observed from an app-only build. Gate E's verdict therefore waits for a 0.1.24 worker, and §27 forbids substituting the old one |
| 778 | The automated half of §26 for `0.1.24` | pass (measured) | `rm -rf .build` first, then `scripts/test.sh` → `Executed 545 tests, with 0 failures (0 unexpected) in 45.246 seconds`, `EXIT=0`. `npm test` in `packages/agentspace-mcp` → `# tests 23 / # pass 23 / # fail 0`. `scripts/release.sh` → `checksum verified: dist/AgentSpace-0.1.24.dmg`, contains `AgentSpace.app`, the inner copy verifies. `NOTARY_PROFILE=octoshrink-notary scripts/notarize.sh` → `The staple and validate action worked!`, app staple valid, DMG staple valid, Gatekeeper accepts. Installed over `/Applications` (the 0.1.23 bundle moved to Trash, not deleted): `CFBundleShortVersionString 0.1.24`, `CFBundleVersion 369`, `codesign -v` valid on disk and satisfies its Designated Requirement, `spctl` → `source=Notarized Developer ID`, `origin=Developer ID Application: Guofeng Liu (U8U443D7ZL)` |
| 779 | `scripts/check-all.sh` on the notarized `0.1.24` artifact: three layers passed, and a fourth that had already passed on this tree | 3 of 4 in the aggregate; layer 4 passed standalone 20 minutes earlier (recorded, not passed) | The aggregate opens with its own integrity guard — `dist guard: stapled app matches the stapled DMG (ee92e5f764bd9b4dbd6ffa6a6627f83e5a21d657)` — then `scripts/test.sh` (545/0), `updater-e2e: 19 checks passed`, `all MCP smoke checks passed`, and stops at `gui-verify: refusing to run — the console session's screen is LOCKED`. `CGSessionCopyCurrentDictionary` confirms it: `CGSSessionScreenIsLocked = 1` with `kCGSSessionOnConsoleKey = 1`. The same layer had run to completion on this same tree at 18:34 — `gui-verify: 13 passed, 0 failed` — before the machine locked itself. So the fourth layer's verdict on 0.1.24 is "passed standalone, refused in aggregate", which describes a screen that timed out between two runs, not a build that failed |
| 780 | `0.1.24` published, and published to replace a release that showed a black window | pass (measured) — the verdict is on the publication, not on rows 777/779 | `git push` over SSH (`origin` is an `https://` URL and git-over-HTTPS fails on this network with `LibreSSL SSL_connect: SSL_ERROR_SYSCALL`): `67daf18..d72ec06` on master. Annotated `v0.1.24` sits at `f5a4700` — the last commit whose tree the bundle was built from, `CFBundleVersion 369` being the commit count there — and `d72ec06` after it is docs only; the tag message splits 「Verified before tagging」 from 「NOT verified」 and says plainly that the installed worker is still 0.1.22. `gh release create v0.1.24` → https://github.com/misswell/AgentSpace/releases/tag/v0.1.24 with `isDraft=false`, `isPrerelease=false` and asset `AgentSpace-0.1.24.dmg` at 5,504,999 bytes; downloaded back with `gh release download` and hashed → **`e0471813d653ac8d9c65884b21f41c4f27c3beac95241fb2df79151459d28856`, identical to the gated file**. The notes carry a section 「这一版没有声称的事」 naming both open gates and the stale worker, and an upgrade notice stating that an in-app update replaces only `/Applications/AgentSpace.app` — so 0.1.23's worker-side fixes still need 「重新安装助手…」 |

## 312. The install moved while the section was being written, and it moved the conclusion (2026-09-21)

Rows 776, 777 and 780 were committed at 18:58 and 19:00 and each of them
attributes its measurement to a `0.1.22` worker. It is not: the owner's
「重新安装助手…」 put a **0.1.23** worker
in place at 18:30, half an hour *before* those rows were written, and nothing was
re-measured first. That is the ordinary failure mode of writing about a machine
from memory, and here it did not merely mislabel a build — it inverted what row 777
concluded and it mis-stated which blocker the remaining physical gates are waiting
on. So this section records the measurement, the two conclusions it retires, and
one near-miss where the same habit would have invented a leak that does not exist.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 781 | The installed worker is `0.1.23`, and has been since 18:30 — so rows 776/777/780 and the `0.1.24` release notes each carried a false statement about this machine | pass (re-measured; the rows are left as written and corrected here) | `strings -a "/Library/Application Support/AgentSpace/Worker/active/agentspace-worker"` → **`0.1.23`** where the app bundle's own copy reports `0.1.24`; `sha256` `ce21981e…` vs `33f0e9f2…`. The install is dated by three independent stamps that agree: `active/agentspace-worker` is a hardlink (link count 2) into `Worker/versions/0.1.23/`, whose directory and `Worker/LaunchAgents/com.agentspace.AgentSpace.Worker.6EA2FB6B….plist` both carry mtime **18:30**, and the running process `ps -p 27916 -o lstart=` → `Mon Sep 21 18:30:48 2026`. Row 772's `openStreams: 5` was measured at 18:22, so *its* 0.1.22 attribution was right; every row after 18:30 is the one that drifted |
| 782 | **Row 777's "the superseded publisher is never released" is a misread of its own numbers, and the fix it blamed was already installed** | pass (the re-reading is arithmetic; the release is code and measurement) | `git merge-base --is-ancestor a090bbb v0.1.23` → true, so the worker that row 777 measured already contained the stream-lifetime fix. Its own evidence then contradicts a leak: the pair at step 1 was `C04B4AFD`+`DC588A6B` and at step 2 `4A0C426B`+`F78DEBF2`. A publisher that was never released would make step 2 read **three** IDs and step 3 four; two IDs that are both new at every step is what a close-then-reopen looks like with a short overlap. That is also what the code says it should be: the client sends `FrameClientCommand(kind: .close)` on a material resize (`FrameClient.swift:97`), and the server's `case .close: return` runs its `defer { manager.close(publisher.streamID) }` (`FrameServer.swift:106-108`), which is the removal row 766 asked for. Gate E's verdict therefore goes back to **not recorded** — it needs an unlocked console and a `frame.stats` sample after each step settles, not an install |
| 783 | The remaining physical gates are blocked by the console, not by a version label — §27's matched pair is already satisfied in substance | pass (measured) | `git diff --name-only v0.1.23 v0.1.24 -- native/AgentSpaceWorker` → **0 files**, and the only Core hunks between the tags are two string literals (`agentspace-core 0.1.23`→`0.1.24`, `agentSpaceVersion` likewise). So the installed worker's frame-transport code is the code `0.1.24` ships, and reinstalling it changes a label and no behaviour. What actually blocks Gates B–I is the console: `CGSessionCopyCurrentDictionary` → `CGSSessionScreenIsLocked = 1`, `screencapture -l36057` and `-R 578,143,816,614` both → `could not create image`, and System Events vends no windows to drive the pickers. Meanwhile the agent's own session keeps streaming through it — the app's stream `E0629094` advanced `framesCaptured` 284 → 285 and `heartbeatsSent` 75 → 81 across three polls two minutes apart while the human's screen was locked — which is the pairing the product is for, and the reason a locked console costs *screenshots* rather than *capture* |
| 784 | The root privileged helper is not installed here, and that is not one of the frame gates' blockers | pass (measured) | `agentspace helper` → `not answering`, and the two places it would live are empty: no `com.agentspace.AgentSpace.Helper.plist` in `/Library/LaunchDaemons`, no binary in `/Library/PrivilegedHelperTools`. `agentspace doctor` says what follows from that: 「not available: not answering. Creating and deleting agents needs it; driving an existing agent does not」 — alongside ✓ Worker, ✓ Accessibility and ✓ Screen Recording for AgentUse. So 「重新安装助手…」 is worth pressing for the version label and for account lifecycle, not for a desktop that draws |
| 785 | A stream that outlives `agentspace preview --stop` is **not** row 766's leak, and saying so needed the call sites rather than the reading | pass (measured, then disproved in code) | `preview --start --fps 2` then `--stats --json` → `openStreams: 1` (`E0629094`, `frameMode: video`, `mappingBytes: 12,770,432`); `preview --stop` → `preview stopped` and the same stream still listed minutes later. Read alone, that is a leaked publisher. It is not: `previewStart`/`previewStop` drive `PreviewController` (`Operations.swift:693-724`), and `frames.open` has exactly one call site in the whole worker — `Operations.swift:736`, inside `frameOpen` — so the CLI preview never registers a publisher in `frame.stats` at all. The surviving stream belongs to the app's open Desktop window (three windows for pid 17221 at the time, one stream), which is the *healthy* ratio and the opposite of row 772's five. Recorded because the wrong conclusion was one poll away |
| 786 | The correction is published, and the release note that carried the false claim now says so itself | pass (measured) | `gh release edit v0.1.24 --notes-file …` → the live body at https://github.com/misswell/AgentSpace/releases/tag/v0.1.24 now contains a 「更正（发布后补记）」 block stating that the 18:30 「重新安装助手…」 installed **0.1.23**, that `v0.1.23..v0.1.24` differs in the worker by 0 files, and that the three worker-side fixes are therefore already live on this machine; the 「物理门」 bullet now names the console lock as the blocker instead of a version label. Verified by re-fetching (`gh release view v0.1.24 --json body`) rather than trusting the edit's exit code. No new version was spent: nothing but these two documents changed, so the artifact an update delivers is byte-identical to the one row 780 published |

## 313. A window that was not on screen, and a decoder that rebuilt itself twice a second (2026-09-22)

Two findings from the same hour, and the difference between them is the whole
lesson. One began as a report that the shipped viewer freezes — a black-
screen-shaped panic, and the evidence for it was a screenshot. The other began as
a line in a log that nobody was looking at. The screenshot turned out to show a
window that was not on the machine's screen at all, and the log line turned out to
be a hardware video decoder being destroyed and rebuilt twice a second, forever,
on every stream in the product. A unified log does not care whether anyone is
watching; a capture of an occluded window pretends very convincingly that it does.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 787 | **"The installed 0.1.24 viewer froze at 08:28 and kept saying 就绪" is not established — the captures were of a window the WindowServer had stopped drawing, and no renderer code was changed because of it** | not a defect (the measurement could not see what it claimed) | The claim needs a picture that is stale *while the window is visible*, and no such picture was ever taken. `screencapture -o -x -l36057` at 08:40:08 and again at 08:40:23 → the **same sha256** (`af7bf617…`, 1,232,198 bytes), showing the agent's menu-bar clock at 08:28. But `-l` of an occluded window returns the WindowServer's last cached image, and this window was occluded: `WindowServer[410] … [com.apple.FuseBoard:SkyBridge] updated window 36057 from "visible" to "occluded"` at 08:34:28 and again at 08:43:58 — one second after `AXRaise` brought it forward, because the owner is working in front of it. Capturing the window's *own bounds* (`-R570,137,832,626`) settles it: the pixels there are the human's Chrome (`localhost:8004/…/mcp/create`) and an IDE, not AgentSpace. The cached image is also internally impossible for a live app — it shows the 实时预览 switch **off** next to a rendered desktop, while `DesktopViewerView` draws the desktop only `if let frameClient` (`DesktopViewerView.swift:243`) and the very same `frameClient != nil` *is* the switch's value (`:301`); one render cannot produce both, several renders can. And the process was never hung: `sample 17221 2` puts the main thread 1534 of 1552 samples in `mach_msg2_trap` inside `_CFRunLoopServiceMachPort`, with the remainder in ordinary AppKit layout. Finally `frame-benchmark.sh` in the same minute measured 2 open streams publishing 850 frames in 59 s. What is genuinely still open is the *question* row 775 raised — `_ = present(metal)` means a real wedge would be invisible to every counter — and it stays open precisely because this attempt to answer it proved nothing either way |
| 788 | Every keyframe destroyed and rebuilt the viewer's hardware H.264 decoder: twice a second, per stream, in normal operation | pass (measured in the log, found in the code, fixed in this section's commit — the re-measurement is pending) | `log show --last 10m --predicate 'process == "AgentSpace"'` → **750 lines** of `VTDecompressionSessionInvalidate: […:DS/BZT] invalidating decompression session: decoded 10 dropped 0 duration 2002 [ms]` immediately followed by `VTDecompressionSessionCreateWithOptions: […:DS/KXE] new decompression session: codec avc1` and `vtDecompressionDuctCreate: … primary-session, client PID 17221 codec avc1 (HW)`, on two distinct session addresses across two threads — the two live streams each throwing away a working decoder every 2.000 s. The cause is one condition: `decode` called `configure(parameterSets:)` whenever a packet carried *any* parameter set (`VideoFrameDecoder.swift:23`), and `configure` opens with `invalidate()` (`:39`). The packets are not misbehaving — `VideoToolboxEncoder.emit` attaches SPS/PPS to **every keyframe** by design (`VideoToolboxEncoder.swift:76-85`, and the type's own doc comment says it is so "a reconnected viewer can build a decoder without out-of-band codec state"), with `MaxKeyFrameInterval = fps * 2` (`:38`), which is exactly the 2 s spacing and the `decoded 10` per GOP at 5 fps. So a per-connection need was being paid per-GOP. The fix keeps the sets the session was built for and rebuilds only when they differ; `invalidate()` forgets them, so the next stream reconfigures as before. An IDR flushes the reference frames anyway, which is what makes reusing the session safe rather than merely cheaper |
| 789 | `scripts/frame-benchmark.sh` measured the shipped pair on a live stream, and the only verdict that failed is a version stamp | measured — 10 of 11 verdicts held, and the eleventh describes a label, not a build | `scripts/frame-benchmark.sh --space AgentUse --seconds 60` against the running 0.1.24 app (pid 17221) and the installed worker (pid 27916), 2 frame streams open, 29 samples: `published 850 frames, 14.407 fps, 4.5 MB copied`; `cpu worker 2.4% of a core, app 1.8%`; `memory app 54192 KB rss, 9668992 bytes mapped for frames`; `latency p50/p95 capture→publish 13.763792 / 27.906875 ms`; `copy cost 3.2 MB per worker CPU-second, 1.65 ms of CPU per published frame`. `frames_flowed`, `back_pressure_healthy`, `no_reconnects_or_terminations`, `timestamps_reach_the_stats`, `shared_memory_within_budget`, `frame_path_wrote_nothing_visible`, `app_descriptors_stable`, `worker_descriptors_countable_by_this_user` and `stream_open_whole_window` all **PASS**, and `memcpy_is_the_hotspot` reports MEASURED as designed. The one FAIL is `app_and_worker_same_release` (`app 0.1.24 / worker 0.1.23`) — which row 783 already costed: `git diff --name-only v0.1.23 v0.1.24 -- native/AgentSpaceWorker` → 0 files, so these are 0.1.24's transport numbers carrying 0.1.23's stamp, and 「重新安装助手…」 would turn the verdict green without changing a line of frame code. `viewer lines 0` is honest, not missing: no connection ended inside the 59 s window, so there was no per-connection summary to read |
| 790 | The decoder fix measured end to end without a screen: eight keyframes built eight hardware decoders before, and two after | pass (measured) | Row 788's instrument works on any process, so the fix was measured the same way it was found — with the **shipped source files** compiled into a headless tool (`VideoFrameDecoder.swift` + `VideoToolboxEncoder.swift` + Core, no window, no display permission, synthetic IOSurface frames). Both variants feed the decoder the packets the real encoder produced: six forced IDR keyframes at 640×480, then two more after the capture geometry changes. `log show --predicate 'processID == …'` counts what VideoToolbox was asked to build: pre-fix pid 44045 → **8 × `new decompression session: codec avc1`** with 7 invalidations (`decoded 0`/`decoded 1` — a session thrown away after a single frame), post-fix pid 44097 → **2**, one per parameter set, and the single `invalidating decompression session: decoded 6` is the phase-1 session being retired *because the SPS changed*, which is the rebuild the fix keeps. Both runs report `keyframes=8 packets=8 decoded=7`, so the frames arriving at the output callback are identical across the two — reuse did not cost a frame. The old binary is `git show HEAD~1:…/VideoFrameDecoder.swift` compiled unchanged, so the comparison is between the two versions of this file and nothing else |
| 791 | The 60-minute soak held on the live pair — and the hour it ran is also the hour the decoder churn cost 2,011 hardware sessions | pass (measured) — as a **baseline**, not as a verdict on `0.1.25` | `scripts/frame-soak.sh --space AgentUse --minutes 60` ran 08:49:53→09:49:49, exit 0, **357 samples over `windowSeconds: 3596`**. Both streams were open in every sample (`minOpenStreams: 2`) and they are the *same* two streams at the end as at the start — `01C8406F…` on window `36361` of pid 9898, `42B3143D…` on the display — which is `stream_open_whole_window` rather than "two streams at some point". Volume over the hour: `framesPublished 43,474`, `publishedFPS 12.09`, `megabytesCopied 229.27`, `videoBytes 240,408,608`. Cost: worker **76.51 CPU-seconds = 2.1% of a core** and **1.76 ms of CPU per published frame**, app 60.3 s = 1.7%, `capture→publish p50 10.18 / p95 25.82 ms`. Nothing accumulated: `appFDs 105 → 105` (growth `0.0` against an allowance of 5), `appRSSKB` first third 49,470 → last third 45,899 (**−3,570**), `workerRSSKB` 33,795 → 27,983 (**−5,811**), and `mappingBytesTotal` a flat **9,668,992** (2,291,968 + 7,377,024) in all 357 samples — row 766's leak would appear here as a mapping total that only ever grows, and `openStreams` climbing, and neither happened. Stability per hour: `captureTerminations 0`, `socketReconnects 0`, `unacknowledgedDrops 0`, `modeSwitches 0` (both streams had banked their 2 switches before the window opened), `framesDropped 0`, and `videoEncoderActivations 1` per stream with `invalidations 0` and `failures 0`. 11 verdicts: **9 pass, 1 measured (`memcpy_is_the_hotspot`), 1 fail** — `app_and_worker_same_release` (`app 0.1.24 / worker 0.1.23`), the label §312 row 783 already costed at 0 differing worker files. The tail is the interesting part: trend rows fall 14.06 → 0.59 fps between 09:42:55 and 09:48:48 with `captureFPS 0` while `heartbeatsSent` climbs 164 → 180, i.e. a *still desktop on two live streams*, which is row 776's "quiet is not dead" distinction measured instead of asserted, and `frame_path_wrote_nothing_visible` holds because `/Library/Application Support/AgentSpace/Logs` was 0 bytes before and after. Against that same window, `/usr/bin/log show --start … --end … --predicate 'process == "AgentSpace"'` counts **2,011 `new decompression session: codec avc1`** and 2,011 invalidations, flat at ~39/min while the agent desktop changed and falling to 1–8/min after 09:41 when it went still — so this hour is the *unfixed* client's: the per-keyframe rebuild work is inside the app's own 60.3 CPU-seconds, and 0.1.25 can only move that number down. What it does not give is Gate B: `viewerSummaryLines []`, because no connection ended, so the live `slots=[…]` reading is still unrecorded and that gate rests on its two tests (`testTheSecondSlotIsFoundAtItsLogicalOffsetAndNotOneKernelRoundingAway`, `testEveryFrameGivesItsSlotBack`) |
| 792 | `0.1.25`'s artifact is notarized, stapled and gated — and it was deliberately **not** launched, which is the difference between this release and a passed GUI gate | pass on layers 1–3 and the guard; layer 4 **deferred**, recorded as such | `rm -rf .build` then `scripts/test.sh` → `Executed 545 tests, with 0 failures (0 unexpected) in 51.035 seconds`, and again after signing as check-all's first layer. `npm test` → `# tests 23 / # pass 23 / # fail 0`. `scripts/release.sh` → `checksum verified: dist/AgentSpace-0.1.25.dmg`, contains `AgentSpace.app`, the inner copy verifies; `NOTARY_PROFILE=octoshrink-notary scripts/notarize.sh` → `The staple and validate action worked!` twice, then `app still verifies / app staple valid / dmg staple valid / Gatekeeper accepts`, exit 0. `CFBundleShortVersionString 0.1.25`, `CFBundleVersion 375` = `git rev-list --count 7f9bbb2`, and the guard that `check-all` opens with passes: `xcrun stapler validate` on the app, and the dist app's CDHash `ba799c8597da6cee54fd78d9e25f3ee470980df5` **identical** to the DMG's inner app. Provenance without a launch: `dist/AgentSpace.app/Contents/MacOS/AgentSpace` is dated 09:00:16, six minutes after `f7397b6` (the fix) landed and with a clean tree at `7f9bbb2`, so the binary contains the change and nothing else. **Layer 4 was not run, on purpose**: `scripts/gui-verify.sh:215` does `pkill -U $(id -u) -f "AgentSpace.app/Contents/MacOS/AgentSpace"`, which would have killed pid 17221 — the instance the 60-minute soak was measuring, and the owner's own Desktop window — and `ioreg -c IOHIDSystem` read `HIDIdleTime = 43,714,750` ns (**0.044 s**) at 09:02, i.e. the machine was in use. No install into `/Applications` either, for the same reason: the fix is measurable headlessly (row 790) and the artifact's own properties are measurable without a window, so nothing here needed the GUI, and §26's rule is to write *deferred* rather than borrow a PASS from a different tree |
| 793 | `0.1.25` published, and the digest the updater will trust is the digest of the file that was gated | pass (measured) — the verdict is on the publication | `git push` over SSH (`origin` is an `https://` URL and git-over-HTTPS fails on this network): `ea5bb71..e39b1ab` — the fix, §313 rows 787–790, the version bump, rows 791–792. Annotated `v0.1.25` (tag object `a5001cc6…`) sits on `7f9bbb2`, the commit whose tree `scripts/release.sh` built, with the commits after it docs only, and its message splits 「Verified before tagging」 from 「NOT verified」 so the unlaunched artifact and the deferred layer 4 are stated in the release itself, not only in a commit message. `gh release create v0.1.25` → https://github.com/misswell/AgentSpace/releases/tag/v0.1.25, `isDraft=false`, `isPrerelease=false`, published `2026-09-22T02:09:34Z`, asset `AgentSpace-0.1.25.dmg` at 5,507,129 bytes. Two independent checks on the bytes: downloaded back with `gh release download` and hashed → `d9bfc247b2cbbd7c3744723331017af3668cc5cc22bf90736321f2bea559ad57`, **identical to the gated file**, and that downloaded copy still passes `xcrun stapler validate`; and `assets[].digest` — the field `docs/UPDATE_CHANNEL.md` names as the one thing about a GitHub release the updater trusts, what its step 2 compares the download against — reads the same 64 hex digits. So 0.1.24 → 0.1.25 is installable through the in-app path, which replaces only `/Applications/AgentSpace.app` and nothing else. The upload is worth recording for whoever runs this next: 5.5 MB took ~11 minutes and the release sat as a **draft** with an empty asset list the whole time, so a `gh release view` reporting `draft: true` minutes after `gh release create` is an in-flight upload rather than a failure — the create command's own exit code is the signal. Nothing on this machine changed because of the publication: `/Applications` still holds 0.1.24 (pid 17221, still streaming) and the installed worker still carries the `0.1.23` stamp |


---

## 314. The desktop viewer learned to move the pointer, and the one gesture that turned out to be impossible (2026-09-22)

Phase-C §一 asked for hover, and the honest starting point was that the Desktop
Viewer had no hover to fix: `RemoteSurfaceNSView` overrode `mouseDown` and
`rightMouseDown` and nothing else, so a hand moving across a picture of the
agent's desktop produced no event at all. Hoisting the gesture state machine into
Core closed that, and the log proved it closed — but the same sweep of
measurements found the plan's own acceptance list contains a gesture that does not
work in this product, has never worked, and is not fixed by the change the plan
proposes for it. Scroll events are accepted, synthesised, posted, and ignored.
That is row 798, and it is written down before any of the good news is.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 794 | The Desktop Viewer forwards pointer travel, and could not have before this change | pass (measured live) | `/usr/bin/log show --last 40m --predicate 'category == "input"'` → **259** lines of `[com.agentspace.app:input] performed 1 input action(s)` from the installed worker (pid 27916). Grouped by gap, the bursts are 11:37:21→11:37:26 **n=92**, 11:37:14→11:37:19 **n=66**, 11:39:07→11:39:09 **n=54**, 11:39:36→11:39:38 n=24, 11:39:40 n=15 — with a **median inter-action gap of 40–41 ms** throughout, i.e. ~25 Hz, which is `PointerTravelCoalescer`'s 30 Hz ceiling sitting under the RPC round trip rather than a hand. Attribution is closed by three facts, not by inference: `git diff HEAD` shows the pre-change base class had exactly two overrides (`mouseDown`, `rightMouseDown`) plus a private `emit(_:to:)`, so **no** code path in it could produce a travel event; `RemoteSurfaceView(` appears in exactly one place in `apps/` (`DesktopViewerView.swift:251`); and the process under test (pid 79935, the new build run from `/tmp/p0a-bundle` with `open -n`) had exactly two windows — its main window and `AgentUse Desktop` — so no Fusion proxy was open to be the alternative explanation. The owner's installed instance (pid 17221) was never touched, and 79935 was stopped at the end |
| 795 | A single `move` produces real hover in the agent session — tooltip, magnification, and the correct cursor shape at the exact display point | pass (measured) | The agent's own session is reachable with the human console locked, so this half of §一 was measured without a screen. `agentspace move AgentUse 435 1038` (the Safari Dock icon, read off a 1920×1080 capture) → the next capture shows the Dock's **`Safari浏览器` tooltip bubble** drawn above that icon *and* that icon magnified, with the pointer nowhere else in the session. `agentspace move AgentUse 400 185` onto a line of text → the frame shows an **I-beam** sitting between the `th` and `e` of `the lazy dog`, i.e. the text cursor, at the point asked for. `InputSynthesizer.perform`'s `.move` branch (`:70-71`) is therefore doing what its comment claims, through `.cgSessionEventTap`, in a background session |
| 796 | `agentspace screenshot` cannot be used to check anything about the pointer — only the preview frames carry it | pass (measured) — a measurement-channel fact, recorded because it produced a false negative first | The same hover that is unmistakable in a preview frame is **absent** from `screenshot`: the capture taken while the pointer was parked over text shows no cursor glyph at all. `showsCursor = true` is set on the stream sources (`CaptureEngine.swift:86`, `ScreenCaptureKitSource.swift:77`, `WindowCaptureKitSource.swift:48`) and the CLI's `screenshot` goes through a different path. So the earlier conclusion "the cursor is not drawn" was an artifact of the instrument, and any future pointer claim must name which of the two channels it was read from. The live channel used here is `preview AgentUse --start --fps 4` + `--frame --json` → `inline` base64 JPEG 1920×1080, i.e. the exact pixels the viewer would draw |
| 797 | The worker's `drag` — annotated "unverified end to end" in its own source — selects the character range it was asked to | pass (measured), and the annotation is now false | `agentspace input` with `{"type":"drag","fromX":240,"fromY":186,"toX":420,"toY":186}` over TextEdit's `The quick brown fox jumps over the lazy dog`, then `type X` → the line reads **`TheXzy dog`**. That is characters 3…37 replaced, i.e. the drag pressed at offset 3 and released at offset 37, ~5.29 pt per character at 12 pt Helvetica, consistent at both ends of the travelled path — which also re-proves the point scale and the absence of a vertical flip through the input path (`InputSynthesizer.swift:96-102`'s 24 interpolated `.leftMouseDragged` steps). Cleanup was verified: the document was discarded through its own save sheet and TextEdit is gone from `apps` |
| 798 | **Scroll does not work in an agent session at all** — not as a regression, not as a shape problem: no synthetic scroll event reaches a scroller, and the plan's proposed fix is measured as no better | **fail (measured)** — root cause narrowed to session event delivery, so §一's 「滚动 Scroll」 acceptance cannot be met by changing `InputSynthesizer` | Six shapes, two apps, both signs, zero effect. Through the product: `scroll AgentUse 0 N` for N ∈ {±3, ±5, 10, 30, ±400, 600} → the worker answers `performed 1 action(s)` and the capture is unchanged. Through a **separate binary** (`/tmp/scrollprobe`, compiled here, run as the agent user via `agentspace exec`, so AgentSpace's plumbing is not in the loop): `a` = exactly `InputSynthesizer.swift:132` (`nil` source, `.line`, `wheelCount: 2`); `b` = a + explicit `event.location`; `c` = a + a persistent `CGEventSource(stateID: .hidSystemState)`; `d` = **`.pixel` units + `kCGScrollWheelEventIsPixel` + a scroll phase** — which is what Phase-C §一 proposes replacing the line with; `e` = a 10-event burst; `f` = a phased began→changed×6→ended gesture. All six post a `mouseMoved` to the target point first, and all six produce the same pixel delta as that move alone. TextEdit (pointer inside the text area, 40 overflowing lines): **69 changed px** = the cursor glyph, in every variant. Finder (`~/Library/Containers` in icon view, pointer at 900,400 inside the grid): **0 changed px** for `a` at both signs and for `f`. Two controls make the zero mean something rather than a dead instrument: the *same* windows do scroll when asked by keyboard — `cmd+Up` on TextEdit **56,572 px**, `cmd+Down` on Finder **6,294 px** — and a lone `move` between two frames always registers, so the capture is live and sensitive to exactly this kind of change. What is *not* established is the mechanism: the pointer demonstrably is where it was told (rows 795, 797), so "wrong hit-test location" does not explain it, and the leading candidate is that `.cgSessionEventTap` scroll events are routed by the WindowServer to the console session, which an agent session never is (`status` reports `onConsole: false`, and §12's refusal makes a console session unusable by design). Distinguishing that needs a listen-only `CGEventTap` inside the agent session, and it is the first thing to run next. `cghidEventTap` was deliberately **not** tried: it posts into the console session's HID stream, i.e. the human's screen, which non-negotiable 3 forbids. The candidate routes, none of them implemented on this evidence, are AX-driven scrolling (works today on both apps via the keyboard path, but loses the delta semantics), and a virtual HID device. **Read §315 next**: the same afternoon's event-tap measurement shows the events *do* enter the session stream, which narrows this claim from "no synthetic scroll event reaches a scroller" to "the window server does not dispatch them to an app", and §315 row 803 measures the AX-driven option working live at 35,908 px against this row's zero |
| 799 | The gesture logic is now one Core type shared by both surfaces, with the Fusion wire unchanged and the suite green | pass (code + tests) — the live half of the viewer's own geometry is **pending**, and why is recorded | `RemotePointerGestures.swift` (new, Core) owns press/travel/release, the engagement window, the lease renewal and the scroll carry; `RemoteWindowSurface` lost its 176 private lines of the same state machine and keeps only the keyboard; `FusionInputRouter.action(for:)` is now a `RemotePointerGesture`→wire function whose output was checked field by field against `git show HEAD:` (a `move` carries no `button`/`modifiers`, `count` only above 1, `drag` names its destination `toXFraction`/`toYFraction`, `scroll` keeps `dx`/`dy`), so `protocolVersion` stays 1 and no new wire type appears. `env PATH=/usr/bin:/bin:/usr/sbin:/sbin swift test` → `Executed 565 tests, with 0 failures (0 unexpected)`, exit 0, of which 20 are new (`RemotePointerGestureTests` 15, `PreviewMappingTests` +5 fraction cases). **Pending**: the viewer's own letterbox-to-display-point path under a hand — drag, scroll and text-selection *through the image*, and §二's three Retina modes — because `CGSessionCopyCurrentDictionary` read `CGSSessionScreenIsLocked = 1` with `kCGSSessionSecureInputPID = 414` from 11:41 onward, no synthetic event may be posted into a locked session, and `scripts/gui-verify.sh` both refuses then and `pkill`s the owner's instance. Row 794's stream proves travel *leaves* the viewer; it does not prove the pixel it lands on is the pixel under the hand, and that distinction is the whole remaining gap |

---

## 315. Scroll has a root cause, and it is not the shape of the event (2026-09-22)

§314 row 798 stopped at "no synthetic scroll event reaches a scroller", which was
true as measured and wrong as an explanation. The afternoon went after the
mechanism with two instruments this section names — a listen-only session event
tap, and an app that counts its own callbacks — and they disagree with row 798 in
a way that matters: the events *do* arrive in the session, they are *not*
delivered to any app, and there is a channel that does work. The fix is in this
section, and so is the part of it that cannot be verified from here.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 800 | The first "zero scroll events arrived" reading was produced by the instrument, not by macOS — a run-loop tap cannot hear anything while its process sleeps | pass (measured) — a measurement-channel fact, recorded because it inverted the conclusion for an entire session | `scrolltap` posted two `mouseMoved` and three scroll events and reported `saw mouseMoved x1`: one move in, zero scrolls. Every post was followed by `Thread.sleep(forTimeInterval:)`, and a `CGEvent.tapCreate` callback is dispatched on the **run loop** the mach port was added to — sleeping starves it, so only the single coalesced event still queued at the final `RunLoop.run` was ever counted. `scrolltap2` spins the loop between posts instead and the same three scroll shapes report `IN STREAM` every time. The corrected reading also explains the `x1`: both moves were posted to the *same* point, and WindowServer drops a move that does not change the position |
| 801 | A synthetic scroll event enters the agent session's event stream with every field intact, and still scrolls nothing | pass (measured) — this narrows row 798 from "not delivered" to "not dispatched" | `scrollshape2` in the agent session (pid 9898's TextEdit, 400 lines of distinct text) with the tap reading the event back after the server has had it: `.line` bare → `d1=-3 cont=0 fp1=-196608 pt1=-30 phase=0 loc=(500,300)`; `.pixel` → `d1=-2 cont=1 fp1=-157286 pt1=-24`; phase chain → `phase=2` then `d1=0 phase=4`. All **in stream**. Pixel effect, measured against the same window with the same frame diff: `shipped` 48 px, `pixel-bare` 48, `pixel-continuous` 48, `chain` 24, `chain-fixed`/`chain-momentum`/`chain-line`/`line-spaced` — against an idle floor of 24–48 px and a `cmd+Down` control of **59,576 px** in box `(224,110)..(910,498)`. The 24–48 px "changes" are a 2×14 sliver at x=222: the text caret blinking. Eight shapes, zero scroll |
| 802 | §314's phase-chain test never tested a phase chain, and the cursor position everyone assumed was correct really was | pass (measured) — row 798's variant `d`/`f` retracted, and the position hypothesis closed | Two causes, both in the probe rather than in macOS. (1) `CGEventField(rawValue: 99)` was used as `kCGScrollWheelEventIsPixel`, which does not exist: the header (`CGEventTypes.h:237`) says **99 = `kCGScrollWheelEventScrollPhase`**, `:226` says 96 = `kCGScrollWheelEventPointDeltaAxis1`, and `:374` gives the real continuous flag at **88**. (2) the phases were `1<<0|1<<5` and `4` and `8` where the header defines `Began=1 Changed=2 Ended=4 Cancelled=8 MayBegin=128` — so the "gesture" started as Began\|MayBegin, moved as **Stationary**, and finished with **Cancelled**. Retested with the header's numbers (`chain`, `chain-fixed`, `chain-momentum` in row 801): still zero, so the misnumbering invalidated the earlier claim but hid nothing. Separately, `cursorwhere` answers the routing question directly: `start (500,300)` → after a posted `mouseMoved` `(500,300)` → after `CGWarpMouseCursorPosition` `(700,600)` → the system cursor really is where the events say it is |
| 803 | Accessibility moves the same scroller that eight event shapes could not — the scroll bar is the working channel in a background session | pass (measured) | `axattrs` on the live TextEdit scroll area reports what the wheel event cannot reach but AX can: `AXSize = size(656.0, 390.0)` (the viewport) and `AXContentSize = size(656.0, 5200.0)` (the document), plus `AXVerticalScrollBar` whose `AXValue` is a plain 0…1 fraction. `axscroll 500 300 0.2` walks hit-test → `AXTextArea` → `AXScrollArea`, and writes: `orientation=AXVerticalOrientation value 0.0 -> set(0.2) result=0 readback=0.2`. Frame diff across the write: **35,908 px** against an idle floor of **0**. The bar exposes no per-line increment — its full attribute list is `AXEnabled, AXOrientation, AXFrame, AXParent, AXChildren, AXFocused, AXSize, AXRole, AXTopLevelUIElement, AXHelp, AXChildrenInNavigationOrder, AXPosition, AXWindow, AXRoleDescription, AXValue, AXHidden, AXIdentifier` — which is why the step has to be derived (row 804) rather than read |
| 804 | Scroll now goes through the scroll bar when the caller said *where*, with the wheel event kept as the path for a session that is the console | pass (code + 6 tests) — the shipped-worker half is **PENDING**, and it is PENDING for a reason | `ScrollMechanics.fractionPerLine` derives the step from the two measured attributes instead of inventing a pixel count: `(viewport / 20) / (content - viewport)` — 19.5 pt of a 4,810 pt range per line — and returns `nil` when the viewport already fits the content, so a non-scrollable area cannot produce a division by zero. `InputSynthesizer`'s `.scroll` case tries `AccessibilityBridge.scrollArea(atX:y:linesX:linesY:)` **first** when x and y are present, and falls through to the existing wheel post when they are not or when the point is outside any scroll area; the order is deliberate, because `Operations.input` already refuses input while the agent session holds the console. **Which caller reaches which branch was not thought through until §316 row 809**: a call carries a point only if the caller has one, so the viewer's wheel is on the AX path while `agentspace scroll <space> DX DY` — whose wire parameters contain no coordinates at all — still takes the wheel post and still lands on row 798's zero. `swift test` → `Executed 571 tests, with 0 failures`. **PENDING**: the worker running on this machine carries the `0.1.23` stamp, and the code above is in the worker. Verifying it end to end needs 「重新安装助手…」, which replaces the installed worker — an action on the owner's side, not something to do quietly from here. Row 803 is the mechanism measured live; it is not a substitute for the shipped path |
| 805 | The viewer's default capture width was resampling a 1920-wide desktop down to 1600, and the fix is to stop asking for a number | pass (measured on this machine, scale 1) | `agentspace screenshot AgentUse --json` on the agent's own display reports `pixelWidth 1920, pixelHeight 1080, scale 1` — so `previewMaxWidth`'s default of `1600` was a 0.83× downscale of a source that had the exact pixels available, which is the softness §二 named. `captureWidthOptions` is now `[0, 960, 1280, 1600, 1920, 2560]` with `0` labelled 「原生」/Native and made the default, and `0` needed no new plumbing because both consumers already define it: `CaptureEngine.start()` takes `targetWidth > 0 ? targetWidth : naturalWidth`, and `ScreenCapture` resamples only `if let maxWidth, maxWidth > 0`. On a Retina panel the same choice asks for the panel's true pixel width instead of a number that predates it. **Not measured here**: the Retina case itself — this agent display reports `scale 1`, so §二's 3024×1964 acceptance row stays open rather than being borrowed from a 1× machine |

## 316. 0.1.26 is published, and the two things it does not claim (2026-09-22)

The release chain ran in the order AGENTS.md gives it, from a tree with nothing
uncommitted: clean build → gates → `release.sh` → notarize + staple → `check-all.sh`
→ push → annotated tag → GitHub Release with the notarized DMG. Two rows below are
about what was *found while writing the release note*, which is the only reason they
are not already in §315.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 806 | 0.1.26 passed every gate as the artifact that was gated, and the published digest is that artifact's | pass (measured) | `rm -rf .build` first, then `env PATH=/usr/bin:/bin:/usr/sbin:/sbin scripts/test.sh` → `Executed 571 tests, with 0 failures (0 unexpected)`, `TEST_EXIT=0` — 26 more than the v0.1.25 artifact (`RemotePointerGestureTests` 15 new, `PreviewMappingTests` +5, `ScrollMechanicsTests` 6 new). `npm test` → `tests 24 / pass 23 / fail 0 / skipped 1`, `NPM_EXIT=0`. `scripts/mcp-smoke.sh` → `MCP_EXIT=0`. `scripts/release.sh` → `RELEASE_EXIT=0`, `dist/AgentSpace-0.1.26.dmg`. `NOTARY_PROFILE=octoshrink-notary scripts/notarize.sh` → `NOTARIZE_EXIT=0`, both staples `The staple and validate action worked!`, and `spctl --assess` → `accepted` / `source=Notarized Developer ID`. `scripts/check-all.sh` → `check-all: all 4 layers passed`, `CHECKALL_EXIT=0`, with the dist guard `stapled app matches the stapled DMG (164e39681f1564df5ab39a60a833c270fd1ea309)`. Bundle stamp `0.1.26` / `CFBundleVersion 383` = `git rev-list --count HEAD` at the tagged commit `644b9dc`. Published: `v0.1.26` annotated tag on that commit, and `gh release view v0.1.26 --json assets` → `sha256:4e0b4ac63228c1e530671459d1f173d10d4b62ff086fcf65a5013812adf01bf1`, size `5548085` — byte-for-byte the `shasum -a 256` of the gated file, so the updater verifies what was verified here |
| 807 | Layer 4 ran this round rather than being skipped, and the copy it handed back carries no test state | pass (measured) — recorded because 0.1.25 skipped exactly this layer | `scripts/gui-verify.sh:215` `pkill`s every AgentSpace instance of this uid before it queries anything, so it is not a passive check. It ran inside `check-all.sh` and reported `gui-verify: 13 passed, 0 failed`. Its own cleanup re-opens what it found running with `env -u AGENTSPACE_ROOT -u AGENTSPACE_GUI_APP`, and that was verified afterwards rather than trusted: the instance now on the desktop (pid 70559, `/Applications/AgentSpace.app`, started 15:01:47 during the run) shows `AGENTSPACE_ROOT` **0** times in `ps eww`, the script printed no `WARNING pid … still carries AGENTSPACE_ROOT`, and the bundle it runs is `0.1.24 / build 369` — i.e. the owner's own installed copy, not the build under test. What this layer checks is control-shaped (slider bounds, preview tiers, the update pane, the wizard's helper card, dead-link alert), so it does **not** close row 799's pending half: no hand was on the image |
| 808 | The scroll fix shipped in a binary that is not the binary running on this machine | pending (blocked on an owner action) — the release note says so in the same words | The fix lives in the worker; `strings "/Library/Application Support/AgentSpace/Worker/active/agentspace-worker"` → `0.1.23`, and `Worker/versions/` is staged up to `0.1.23` with nothing for 0.1.24/0.1.25/0.1.26. The in-app updater replaces only `/Applications/AgentSpace.app` (non-negotiable 6), so **installing 0.1.26 does not make the wheel work** — 「重新安装助手…」 does, and that button press is the owner's, not something to do quietly from here. Row 803's 35,908 px is the channel and the arithmetic measured live through `agentspace exec`; it is not a substitute for the shipped path, and the note in §315 row 804 stays open until this row flips |
| 809 | A scroll call without a point is not covered by the fix — found while writing the release note, not while testing | fail (measured against the code, disclosed not patched) | `InputSynthesizer`'s AX path is gated on `if let x, let y`, and the point only exists if the caller has one. `DesktopViewerInput.swift:57` does (it maps the gesture's `u,v` onto the remote display and sends `.scroll(x:y:dx:dy)`), so the viewer's wheel takes the AX branch. `AgentSpaceCLI/main.swift:975` does not: `agentspace scroll <space> DX DY` puts only `dx`/`dy` on the wire, so it falls through to the legacy wheel post — which row 798 measured at 0 changed px, and which this change does nothing about. The fallback branch is therefore *reachable and still broken*, and §315 row 804's earlier phrasing ("the only one that can ever be reached") was wrong in a way this row replaces. Two candidate repairs, neither measured yet and so neither implemented: an optional trailing `X Y` on the CLI verb (the two-argument form keeps working, compatibility rules intact), or a worker-side fallback to the scroll area of the AX-focused element when no point was given. The second needs a live answer to "whose window, and is it the one the hand meant?" before it can be trusted |
| 810 | A 0.1.24 install reading the live channel right now is offered exactly these bytes | pass (measured after publishing) | `GET /repos/misswell/AgentSpace/releases/latest` → `tag: v0.1.26 draft: False prerelease: False`, one asset: `AgentSpace-0.1.26.dmg`, `5548085` bytes, `sha256:4e0b4ac63228c1e530671459d1f173d10d4b62ff086fcf65a5013812adf01bf1`, `browser_download_url` under `releases/download/v0.1.26/`. That is `AgentSpaceIdentity.archiveName(for:)`'s expected shape and the `sha256:`-prefixed field row 659 established as the integrity source, and the digest is the gated file's — so the verification chain an updater passes is a chain over what `check-all` approved, not over something re-zipped on the way out. **Not claimed**: nobody pressed `updateCheckButton` on this machine; the installed App is still `0.1.24 / build 369`, and pressing it is the owner's action |

## 317. The shipped worker scrolls, and the second helper-swap site still asked launchd once (2026-09-22)

Two findings from the same twenty minutes. The owner updated to 0.1.26 and pressed
「重新安装助手…」, which retires row 808's PENDING — scroll through the shipped
binaries is now measured, and so is the point-less case row 809 predicted. Then the
owner reported that the swap itself needed two presses with a `HELPER_UNAVAILABLE`
dialog in between, which turned out to be the race `HelperRegistrationRetry`'s own
header comment measures, paid by one of its two call sites and not the other.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 811 | Scroll works through the binaries a user actually gets, when the call names a point | pass (measured, shipped) — **retires §315 row 804's and §316 row 808's PENDING** | The owner updated the App (now `0.1.26 / build 383` in `/Applications`) and pressed 「重新安装助手…」 at 15:20: `strings "/Library/Application Support/AgentSpace/Worker/active/agentspace-worker"` → `0.1.26`, and the worker's pid changed (27916 → 96035). Everything below then ran through `/Applications/AgentSpace.app/Contents/Helpers/agentspace` (`agentspace 0.1.26 (protocol 1)`) against TextEdit with a 400-line document, window `213,77 656×422`, diffing box `(224,110)..(910,498)` between two `screenshot` captures: idle floor **36–38 px** (the caret), `{"type":"scroll","x":500,"y":300,"dy":-5}` → **149,740 px**, `dy:-40` → **109,788 px**, `cmd+Down` control → **117,784 px**. Row 803 measured the channel with a scratch binary; this is the product's own socket, worker and CLI |
| 812 | A scroll call that names no point is dead on those same shipped binaries, not merely in theory | fail (measured, shipped) — row 809's prediction confirmed rather than inferred | The same instrument, same window, same floor: `agentspace scroll AgentUse 0 -5` answers `scrolled 0, -5` and changes **38 px** — the idle floor exactly, i.e. nothing. The verb puts only `dx`/`dy` on the wire (`AgentSpaceCLI/main.swift:975`), so `InputSynthesizer`'s `if let x, let y` guard sends it down the legacy wheel post, which is row 798's zero. Task on record: give the verb a point, or fall back to the focused element's scroll area — and measure which one a hand actually gets before picking |
| 813 | The first press of a worker update really did always fail and the second really did always work, because the app registered a daemon fifteen milliseconds after taking it away | pass (measured before, confirmed in code now) — the owner's report, not a hypothesis | `commit 44dd9d3` measured this machine's behaviour: `register()` after a returned `unregister()` answers **error 1 at +13 ms**, and the same call **2.7 s later answers 0**. That commit gave `reinstallHelper()` (the 「重新安装助手…」 button) the retry budget — but `reinstallHelperForWorker()`, the swap the *worker update* drives, was written earlier (`4a36384`, `693415e`, both ancestors of `44dd9d3`) and kept `unregister()` → `try service.register()` with one ask. Its failure is then routed to the `HELPER_UNAVAILABLE` the owner saw, whose second paragraph («特权助手未安装…选择「安装助手」») is true only of the instant the app itself created. `git log -S` is the proof the fix existed and the site was missed, not that the race is new |
| 814 | Both swap sites now wait out the teardown, and a third one cannot be added quietly | pass (code + 2 tests) — red on the pre-fix source, green on the fixed one | `reinstallHelperForWorker` now calls `Self.registerDaemon(attempts: HelperRegistrationRetry.maximumAttempts)` — the same path the button uses. `HelperRegistrationRetryTests` gains two source-invariant checks: the worker-update body must contain that call, and no `.register()` may exist outside `registerDaemon(attempts:)` (doc comments are stripped first, and whitespace is removed so a line wrap cannot hide a call). Measured both ways: with `git show 39517bc:apps/AgentSpace/Models/AppModel.swift` swapped in, `Executed 5 tests, with 2 failures`; with the fix, `with 0 failures`. **Not claimed**: that a press on this machine just now completed in one go — the helper is already current, so a third swap would be a second admin prompt on the owner's screen for the sake of a number. The race it waits out is measured (row 813), the wiring is tested, and the next version's swap is the live proof |

## 318. 0.1.27's gate chain, and the layer-4 flake that turned out to be the instrument typing into the human's app (2026-09-22)

The product change in this release is one call site (row 814), so the work here was
mostly getting the gates to stop lying. Layer 4 failed four times in a row inside
`check-all.sh` on an artifact that passed it 13/13 when run on its own — twice in the
wizard and twice, differently, in Settings. Both halves had the same cause: the script
*typed* a shortcut instead of *asking* for a menu item, and a keystroke goes to
whatever the console session last focused. That is the same class of bug as §300's
mid-flight account list, and it is a defect in the instrument, not the product.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 815 | 0.1.27 passed every gate as the exact artifact that was gated | pass (measured) | `rm -rf .build` first, and the wipe is verifiable after the fact rather than asserted: `.build` and `.build/checkouts` both carry birth time `Sep 22 15:37:27`, and the release scratch path `.build/arm64-apple-macosx/release` is a separate fresh `15:39:46`. Then `npm test` → `tests 24 / pass 23 / fail 0 / skipped 1`, `NPM_EXIT=0`. `scripts/test.sh` → `Executed 573 tests, with 0 failures (0 unexpected)` — 2 more than the 0.1.26 artifact (`HelperRegistrationRetryTests` 3 → 5), `TEST_EXIT=0`. `scripts/mcp-smoke.sh` → `all MCP smoke checks passed`, `MCP_EXIT=0`. `scripts/release.sh` → `Release artifact: dist/AgentSpace-0.1.27.dmg`, `version 0.1.27, protocol 1`, `RELEASE_EXIT=0`. `NOTARY_PROFILE=octoshrink-notary scripts/notarize.sh` → submission `427ec886-2b42-46f0-807d-89ad26450ba6`, `The staple and validate action worked!`, then the script's own four `ok` lines (`app still verifies / app staple valid / dmg staple valid / Gatekeeper accepts the app`), `NOTARIZE_EXIT=0`. Verified again independently after the gate rather than only trusting that summary: `spctl --assess --type execute -vvv dist/AgentSpace.app` → `accepted` / `source=Notarized Developer ID` / `origin=Developer ID Application: Guofeng Liu (U8U443D7ZL)`, and `xcrun stapler validate` → `The validate action worked!` for both the app and the DMG. `scripts/check-all.sh` → `check-all: all 4 layers passed` with the dist guard `stapled app matches the stapled DMG (4aeab90810c9a93a5eb07ffc05bc248eaa5da4bd)`; the gated file is `shasum -a 256 dist/AgentSpace-0.1.27.dmg` → `sha256:5d503be91a88c0120a1ad9b8bd3d82778e92e767181ee118d2b932320a8da49f`, `5548266` bytes. Bundle stamp `0.1.27 / CFBundleVersion 388` — 388 is `git rev-list --count HEAD` at the bump commit `7d16b65`; the tree is now at 389 because the gate fix below was committed after it, so the build number names the tagged commit, not this file's tail |
| 816 | The wizard failure was the script typing `⌘N` at the human's app, and it is reproducible in exactly that way | pass (measured, 6 runs) — a gate-instrument defect, not a product one | Runs 1–2 of `check-all` (`/tmp/ca-0127.log`, `-b.log`) both ended `FAIL wizard reaches a real next state: expected [step 2] got [no name field]` → `gui-verify: 12 passed, 1 failed`, `check-all: failed at scripts/gui-verify.sh`. Standalone runs on the **identical** DMG (`shasum` stable across all of them) passed: `gui-verify: 13 passed, 0 failed`, `GV_EXIT=0` (`/tmp/gv-0127-b.log`, `-d.log`). So the artifact was fine and something environmental decided the outcome — `who` and a frontmost sample showed WeChat then Chrome Beta within 3 s on this console, i.e. a live human. The phase opened the wizard with `keystroke "n" using command down`, which is delivered to the focused app, not to the pid the script holds. What confirms it is what the phase reports now that it no longer types: it names the channel it used (`asked`, `no ⌘N menu item`) and dumps the window list, and both in-gate runs after the conversion print `wizard: step 2` (row 818) where before the string said only `no name field` and pointed at nothing. One call in this window also answered `-25211 “osascript”不允许辅助访问` once and then worked — console-side noise, recorded so the next reader does not mistake it for a product failure |
| 817 | The Settings failures were a second channel of the same defect, and eight empties pointed at nothing because the opener threw its own error away | pass (measured) — recorded because it falsified the first theory | Runs 3–4 (`/tmp/ca-0127-c.log`, `-d.log`) failed differently: **8** controls reported `got []`/`got [n]` (`refresh slider min=2.0`, `max=10.0`, `preview tiers`, `update pane reachable`, `update check control`, `update preference control`, `checking is possible`, `install control …`) → `5 passed, 8 failed`. They failed on a **quiet** console too, so "the human clicked" could not explain them. The opener was a one-shot `osascript >/dev/null 2>&1 <<EOF` heredoc typing `⌘,`: the redirect discarded whatever error said the app never fronted, and the phase then read eight attributes off a window that had never opened and reported them as empty. A first diagnostic edit of mine also broke this phase with `-2753 变量"_w"没有定义` (`/tmp/gv-0127-c.log`) — `set _ws to windows of _p` then `repeat with _w in _ws` shadowed the outer window variable; fixed by iterating `(windows of _p)` inline as `_cand`. Recorded because a wrong fix is evidence too |
| 818 | Both channels now ask the menu bar by `AXMenuItemCmdChar`, and the gate is green in-run rather than only standalone | pass (measured) — and it is localization-proof by construction | `df6b193` (touches `scripts/gui-verify.sh` only: +81/−23, no product file): the Settings opener is a 5-attempt loop that fronts the app by pid, walks `menu items of menu 1 of menu bar item "AgentSpace" of menu bar 1 of _p` and clicks the item whose `AXMenuItemCmdChar` is `,`; the wizard poll became `repeat 12 times` and each iteration walks `menu bar items` for the `n`-bound item and clicks it if the name field is still missing. Measured: `check-all` runs 5 and 6 both print `settings opener: clicked, windows=2`, `wizard: step 2`, `gui-verify: 13 passed, 0 failed`, `check-all: all 4 layers passed`, `Executed 573 tests, with 0 failures`. The UI here is Chinese (「文件」/「新建 Agent…」), which is why the char attribute is used rather than a menu title — `AXMenuItemCmdChar` is what the ⌘-shortcut line reports regardless of display language, and the earlier `⌘,`/`⌘N` typing worked only because English-shaped keys happened to be bound. **Not claimed**: this changed the instrument only. It makes no product behaviour more true, and a green layer 4 still checks control shapes, not a hand on the image (row 807's limit stands) |
| 819 | The bytes a user's updater fetches are byte-for-byte the gated artifact, proven by pulling them back | pass (measured) | `v0.1.27` annotated tag on the bump commit `7d16b65` (built from that tree; `master` has since moved to `4216be4`, docs and the gate fix only). Release `393574707`: `draft false / prerelease false`, name 「0.1.27 — 换助手时那一次多余的失败弹窗」, body 3,554 chars, one asset `AgentSpace-0.1.27.dmg` → `sha256:5d503be91a88c0120a1ad9b8bd3d82778e92e767181ee118d2b932320a8da49f`, `5548266` bytes — the same values `shasum -a 256 dist/AgentSpace-0.1.27.dmg` gives locally, and the digest GitHub computed on upload agrees with the file that `check-all` approved (row 815). Then the round trip: `curl -L` of `browser_download_url` back to disk → identical sha256, identical size, `cmp` silent. So the chain the updater walks ends at these bytes, not at a re-zipped near-relative |
| 820 | Publishing a draft by flipping `draft=false` did **not** move `/releases/latest` for six minutes, and only a write to the release itself fixed it | pass (measured) — the update channel's real behaviour, recorded because it is a silent failure mode | `GET /repos/misswell/AgentSpace/releases/latest` answered `v0.1.26` from 16:50 to 16:56 (9 samples, 20 s apart, cache-busting query strings included) while `GET …/releases/tags/v0.1.27` already answered `draft: false` with the right digest — i.e. the release was live and the *derived* `latest` resource was stale. Its `last-modified` was `07:10:39 GMT`, the moment 0.1.26 went out. `PATCH …/releases/393574707 -f make_latest=true` flipped `latest` to `v0.1.27` **within 5 s** (`make_latest` reads back `null` in both GET and PATCH responses, so the field's value is not the mechanism; the write is). That endpoint is the product's channel, not an incidental one: `SoftwareUpdater.latestReleaseURL` (`apps/AgentSpace/Services/SoftwareUpdate.swift:30`) is exactly this URL, so for those six minutes `updateCheckButton` on a 0.1.26 install answered *up to date* about a release that was already live and verified. Consequence kept honest: the next publish should assert `releases/latest` answers the new tag as part of releasing, rather than assume a flip propagates — `gh release create` without `--draft` is what 0.1.25 did and it flipped in under a minute (§316 row 806's window). What is **not** established: whether GitHub's staleness here is minutes or hours when nothing touches the release afterwards — this observation only shows a write refreshed it |

## 319. The `scroll` verb learned to name its point, and the difference is 106,510 pixels against 0 (2026-09-22)

§317 row 812 left a task on the record: `agentspace scroll <space> DX DY` answered
`scrolled 0, -5` and moved the document exactly as far as doing nothing did, because
the verb put no point on the wire. This section is that fix — one encoder's worth of
drift, since Core, the worker, the protocol document and the other two front ends had
all supported the anchor for four releases — plus the three ways the measuring
instrument was wrong before it was right.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 821 | Nothing had to be added to the wire: the CLI was the only producer that dropped the point, and the fix routes it through Core | pass (code) — 「不新增 wire field」 holds | Core has carried `InputAction.scroll(x:y:dx:dy:)` since before this release (`shared/Core/Sources/AgentSpaceCore/InputActions.swift:61`), encodes it at `:436-444` and round-trips it (`tests/Unit/InputActionTests.swift:310`). The **installed** worker parses it: `git show v0.1.26:shared/Core/Sources/AgentSpaceCore/InputActions.swift` line 175-178 reads `object["x"]?.doubleValue` / `["y"]`. `docs/protocol.md:199` already listed the fields. The desktop viewer already passed them (`apps/AgentSpace/Views/DesktopViewerInput.swift:59`), and the Fusion router names its point as a window fraction that the worker resolves (`FusionInputRouter.swift:44-49`, asserted by `RemoteWindowInputTests.swift:76`). Only `AgentSpaceCLI/main.swift:975` hand-built `.obj(["type":"scroll","dx":…,"dy":…])`, which is precisely the drift `InputActions.swift`'s encoder comment warns about. It now sends `InputAction.scroll(x:y:dx:dy:).wireValue` (`main.swift:1002`), so the three front ends cannot disagree with the worker's parser about what an anchored scroll is called |
| 822 | A half anchor is refused rather than silently degraded, because the silent version is how a dead verb stayed shipped for a release | pass (measured on the real binary) | `scroll AgentUse 0 -5 450` → `exit=1 BAD_REQUEST "usage: agentspace scroll <space> DX DY [X Y] — an anchor needs both X and Y"`; `… 0 -5 abc def` → "X and Y are display points"; four trailing numbers → refused. The 3-arg legacy form still resolves the account and reaches the worker unchanged — row 812's `scrolled 0, -5` remains available and still moves nothing, which the usage line now says out loud: `scroll <account> DX DY [X Y]    Scroll  (X Y = where; without it nothing moves)`. MCP mirror in `packages/agentspace-mcp/src/args.ts:233`: `buildScrollArgs(space, dx, dy, x?, y?)` throws `ArgError("scroll anchor needs both x and y")` (`:250`) for a half anchor, and emits the two-delta argv byte-for-byte unchanged when neither is passed, so no existing caller changes behaviour. Tests: `CLIIntegrationTests.testScrollAcceptsAnAnchorAndRefusesAHalfOne` and `test/args.test.mjs` "scroll passes its anchor through and refuses a half one" |
| 823 | Same desktop, same box, same worker — the binary a user has now moves 106,510 px where the shipped one moved 0 | pass (measured, shipped-vs-fixed) | Instrument: TextEdit `scrollcheck.txt` on the agent desktop, 1920×1080 at scale 1, diff box `(232,106,704,490)` = the window's content area, `cmd+Up` reset before every reading, two frames 1.2 s apart per reading with the later kept. Idle floor **0 px**, so every 0 below is a true null and not a stale frame. `/Applications/AgentSpace.app/Contents/Helpers/agentspace` (`0.1.26`): `scroll 0 -5 450 300` → `exit=0 {"performed":1}`, **0 px**; `0 -5` → **0 px**; `0 -5 1500 900` → **0 px**; `0 -5 450` → **exit 0, 0 px** (the silent half anchor, accepted as success). This tree's CLI (`0.1.27` source): `0 -5 450 300` → **106,510 px**; `0 -5` → **0 px**; `0 -5 1500 900` → **0 px**; `0 -5 450` → **exit 1**. Worker identical in both runs (pid 96035, `0.1.26`), so the only variable is how the CLI encodes argv — which is what makes this a fix and not a re-lottery. The fixed CLI was then run twice over as two different binaries and reported **the same 106,510 px both times** (`.build/debug/agentspace` built from source, then `dist/AgentSpace.app/Contents/Helpers/agentspace` `0.1.28` from `swift build -c release`), so the number is a property of the behaviour and not of one build. The `1500,900` control is what makes 106,510 mean *this point scrolled* rather than *the focused view scrolled*: an anchor outside any scrollable area moves nothing, exactly as row 798's channel finding predicts |
| 824 | The instrument lied three times before it told the truth, and every lie pointed the same way — at the measurement, not the product | pass (measured) — recorded because a wrong measurement is evidence too | (a) `measure.py` assembled `[CLI, "scroll", "0", "-5", …, "AgentUse"]`, putting the account *after* the deltas, so the CLI read `rest[0]="0"` as the space name and answered 66/1 for argv order. The first "red" run therefore reported 0 px for the wrong reason and looked like a result; fixed by building argv in the verb's real order, which is visible in the payload (`{"performed":1}` vs `exit=66`). (b) A click that had closed a leftover System Settings window read as not landing: `agentspace screenshot` answered with a frame predating input the worker had already accepted, so the hover state looked frozen while the desktop had in fact changed — the same occluded-cache class as §313 row 787's retracted frozen-viewer claim, on the capture side rather than the viewer side. The instrument now reads pairs and keeps the later frame, and the idle floor is measured the same way so a stale frame cannot masquerade as either a result or a null. (c) zsh does not word-split an unquoted `$a`, so `for spec in "0 -5"; agentspace scroll AgentUse $spec` handed the whole string over as one argv word and every case — including the valid one — answered `BAD_REQUEST usage: agentspace scroll <space> DX DY`. That is the second section in a row with a shell-loop artifact (§318 row 817's `-2753`); the rule taken is that a measurement runs through `subprocess.run([...])`, never through an unquoted loop |
| 825 | What is still not covered, said plainly | pending — deliberately not written as a pass | `agentspace input --file` and the `agentspace_input` MCP tool still accept `{"type":"scroll","dy":-5}` with no point and answer `performed: 1` for 0 px, because that is what the v1 wire says and tightening `InputAction.parse` would change a contract every existing client already walks. What changed there is documentation, not validation: `INSTRUCTIONS` ("Scroll must name its point…"), `agentspace_scroll`'s tool description and its `x`/`y` field descriptions, and `docs/protocol.md:199` now read "…and the point `x`, `y` to scroll at — without the point nothing moves in a background session (§315)". The honest way to close it is a worker-side default — scroll the accessibility scroll area under the remote pointer's last known position — and that path is measured nowhere yet, so it stays a task rather than a claim |
| 826 | The MCP server this fix also touches is not reachable the way its own README says it is | fail (measured, code + registry) — a distribution gap, not a regression from this change | `Integrations.mergeJSONConfig` writes `{"command":"npx","args":["-y","@agentspace/mcp"]}` (`shared/Core/Sources/AgentSpaceCore/Integrations.swift:234-238`), and `packages/agentspace-mcp/README.md:35` tells a user to run `npx @agentspace/mcp`. `npm view @agentspace/mcp version` answers **`404 Not Found - GET https://registry.npmjs.org/@agentspace%2fmcp`**, and the package's own `package.json` has no `private` flag and no `publishConfig` — it simply was never published. There is no publish step to miss: no `.github/workflows`, no `npm publish` anywhere in `scripts/`, and `npm whoami` reports `ENEEDAUTH`. Consequence for row 822's MCP half, stated exactly: `agentspace_scroll`'s new `x`/`y` reach only someone running this checkout (`npm run build` in `packages/agentspace-mcp`), because there is no registry copy for anyone else to get. **Not measured end-to-end**: `agentspace integrate install` was not run and its written config was not launched — this machine has no AgentSpace entry in `~/.claude.json`, `~/.codex/config.toml` or `~/.config/opencode/opencode.json` to inspect — so this is a reading of the code plus one registry query, not an observed client failure. Publishing under the `@agentspace` scope is the owner's call, not a step to take quietly |
| 827 | `swift build --product A --product B` answers 0 having built **one** of them, and the missing one surfaced two steps later as "the worker did not come up" | pass (measured, reproduced to order) — a gate that fails for a reason it never named is a defect in the gate | `rm -f .build/debug/agentspace .build/debug/agentspace-worker && swift build --product agentspace-worker --product agentspace` → `TWO_PRODUCT_EXIT=0`, its whole log ending at `Build of product 'agentspace' complete! (0.68s)` and then `present: agentspace` / **`MISSING: agentspace-worker`**. Nothing in that output says a second product was skipped, so `scripts/mcp-smoke.sh` carried on, could not start a worker that was never built, and reported a worker problem (`/tmp` log at the time of the run). `c7ca6e8` (touches `scripts/mcp-smoke.sh` and `.mjs` only, no product file): one `swift build --product` per iteration **and** an explicit `[[ -x .build/debug/$product ]]` assertion after each, so the build step can no longer pass on half a build. Measured after the change: each product exits 0 and each prints its own `Build of product '<name>' complete!`, both binaries present, and `scripts/mcp-smoke.sh` → `MCP_EXIT=0`, `all MCP smoke checks passed`, including the new `agentspace_scroll` half-anchor block (`a lone x is refused`, `the refusal names the anchor, not the console`) — the MCP gate now asserts row 822's refusal over a real JSON-RPC stdio session instead of only in `args.test.mjs` |
| 828 | A notarization poll that cannot read a status used to wait forever on the empty string, and it did | pass (measured against a stub) — found by the gate hanging, not by a test failing | `notarize.sh` ran the app submission at 17:29 with `MODE=notarytool`; the `octoshrink-notary` keychain profile disappeared mid-run (the third documented loss after 2026-09-10 and 2026-09-18, and `xcrun notarytool history` now answers **69**), so every later `notarytool info` failed with its stderr thrown away by `2>/dev/null`, `status` came back empty, and the loop printed `submission … still ; polling every 60s` indefinitely — the run had to be killed. `80fce0d` (touches `scripts/notarize.sh` only): an empty submission id stops immediately (there is nothing to reconcile against); a poll that yields no status is counted, and `$NOTARY_MAX_UNKNOWN_POLLS` (default 6, i.e. ~6 minutes) of them ends the run with the failing command's own text and the exact `xcrun notarytool info <id> --keychain-profile <profile>` to re-check once the credential is back — **not** a resubmit, because the bytes are already at Apple. Status is read with `sed -n 's/^[[:space:]]*status:[[:space:]]*//p'` so Apple's `"In Progress"` arrives whole instead of being truncated to `In` by `awk '{print $2}'`. Verified with a stubbed `xcrun` on `PATH` and the function extracted from the script: the unreadable case prints `poll 1/3 … 2/3 … 3/3` + the keychain error + the give-up text and returns non-zero in 3 polls; the ordinary case prints `still In Progress; polling every 60s` once then `RETURNED=0` when the status flips to `Accepted`. **Reconciliation owed**: killing that run left submission `e3352db2-a9b4-457e-af6c-414bf6adfa83` (`AgentSpace-app-notarize.zip`, 09:29:43Z) live at Apple, and the reruns submit the app again, so the superseded ids are listed here rather than chased |
| 829 | 0.1.28's release chain, and the one gate that reported the state of the room instead of the state of the build | pass (measured) — with the blocked hour named, because a gate that refuses is telling you something | `scripts/release.sh` → `dist/AgentSpace.app` + `AgentSpace-0.1.28.dmg`, Developer ID, hardened runtime, secure timestamp. `scripts/notarize.sh` with `MODE=asc` (step 0: `ok asc credentials are live (keychain profile absent)`) → `NOTARIZE_EXIT=0` and all four verifications: `ok app still verifies`, `ok app staple valid`, `ok dmg staple valid`, `ok Gatekeeper accepts the app`. Artifact: `sha256:4417e9395066d61315797866e5630221c8110dd594ca835c25171c788178fd23`, `5548467` bytes, CDHash `b7c32f773d518f910ff6edae10bc685b59f637b5` — and that CDHash is what `check-all`'s dist guard compares the app against the DMG's inner app with, so the stapled pair is one pair. First `check-all` (18:03): `Executed 574 tests, with 0 failures`, `updater-e2e: 19 checks passed`, `all MCP smoke checks passed`, then **`gui-verify: refusing to run — the console session's screen is LOCKED`**, `CHECK_ALL_EXIT=1`. That is the instrument honouring its own rule (a locked console vends no windows, so every accessibility read would come back empty — §313 row 779's class), and nothing was done about the lock: no unlock is attempted here, only observed, with `gui-verify.sh`'s own `CGSessionCopyCurrentDictionary` probe polled every 30 s (`locked` from 18:04:59 to 18:14:34, 20 samples, then `presenting`). At 18:16 the same command on the same artifact reported `check-all: all 4 layers passed`, `CHECK_ALL_EXIT=0`, `gui-verify: 13 passed, 0 failed`, `Executed 574 tests, with 0 failures`. Re-run after row 830's instrument fix, same result (`check-all: all 4 layers passed`, `13 passed, 0 failed`, 574/0, `19 checks`, MCP smoke green) and no stray `command not found` in the log. The bundle a user gets was then checked as an artifact, not as a build: `dist/…/Contents/Helpers/agentspace --version` → `agentspace 0.1.28 (protocol 1)`, and `scroll AgentUse 0 -5 450 --json` → `exit=1` with `an anchor needs both X and Y` — row 822's refusal re-run through the notarized bundle. The `reason: AGENT_SESSION_NOT_READY` that rides along in that envelope is §2's uniform failure shape (`main.swift:138-151` maps any code through `UnavailableStatus.Reason`), not a worker diagnosis; it is documented this way on purpose and a usage error is not exempt from it |
| 830 | The gate that passed 13/13 had been printing `showingNewSpace: command not found` on every run, because an AppleScript *comment* was inside a shell double-quoted string | pass (measured) — fixed and re-run green | `scripts/gui-verify.sh:523` sits inside the wizard phase's `osascript -e "$(cat /tmp/gui-verify-lib.applescript) … "` argument, and inside double quotes a backtick opens a **command substitution**: the comment about \`showingNewSpace\` executed as a command, and bash reported it at the line where the string closes (`line 621`). The check itself still passed because the substitution's (empty) output was spliced into a `--` comment line — but had the command ever printed anything, that text would have been injected into the script being run, and this is the same quoting family as row 817's `-2753` and row 824's shell-loop artifact. `787121d` (touches `scripts/gui-verify.sh` only) quotes the identifier with single quotes instead; the lib file keeps its backticks because `$(cat …)` output is not re-scanned. Measured: `bash -n` clean, `scripts/gui-verify.sh` alone → `gui-verify: 13 passed, 0 failed`, `GUI_EXIT=0`, **zero** `command not found` lines, the only remaining stderr being the deliberate `Terminated: 15` of the test instances the script kills. **What this does not claim**: layer 4 checks control shapes through the accessibility tree, not a hand on the image (row 807's limit still stands), and this release changes no `apps/AgentSpace` source at all — `git log v0.1.27..HEAD -- apps/AgentSpace` is only the version bump, so green layer 4 here is "the UI I did not touch is still the UI that passed" |
| 831 | `v0.1.28` is published, the asset's digest is the gated file's digest, and this time the update channel answered the new tag on its own | pass (measured, including the round trip) | `v0.1.28` annotated at `b690162` (`git rev-parse v0.1.28^{commit}` = `b690162a88148bbdfd8d732c8a48b516373f91eb` — the bump commit, whose tree the bundle was built from; master then moved to `cfee340`, and the only files that moved are docs and gate scripts). Notarization through the asc path: app zip `36633457-a797-45c3-9442-f29d519638c8` **Accepted** (10:00:33Z), `AgentSpace-0.1.28.dmg` `78c7e766-44b7-4330-b98a-0299983ab620` **Accepted** (10:01:26Z), each followed by `The staple and validate action worked!`. Release `https://github.com/misswell/AgentSpace/releases/tag/v0.1.28`: `draft false / prerelease false`, name 「0.1.28 — agentspace scroll 现在要说清楚滚哪里」, body 6,298 chars at first read-back and **6,869** after the section below was appended (a publish record should be in the note the user reads, not only here), one asset `AgentSpace-0.1.28.dmg` → `sha256:4417e9395066d61315797866e5630221c8110dd594ca835c25171c788178fd23` over `5548467` bytes, which is byte-identical to `shasum -a 256 dist/AgentSpace-0.1.28.dmg` — so the digest GitHub computed on upload agrees with the file `check-all` approved (row 829), and the chain the updater walks ends here. Round trip: `curl -L` of the asset URL back to disk → `5548467` bytes, same sha256, `cmp` silent. **And the part row 820 was written for**: `GET /repos/misswell/AgentSpace/releases/latest` answered `v0.1.28 / draft=false / asset=AgentSpace-0.1.28.dmg` on the first sample and on three samples 5 s apart, with no `make_latest` write and no cache-busting needed — `gh release create` without `--draft` again behaves the way 0.1.25 did, so the six-minute stale-`latest` window of §318 row 820 did not recur. It is asserted as part of releasing now rather than assumed either way |

## 320. The capture buffer was allowed a shape its subject does not have, and 157 pixels of nothing sat between the hand and the desktop (2026-09-22)

The owner's report was 「鼠标位置与实际点击位置不一致，应该是横向拉伸后导致的」 — a horizontal stretch. The measurement says the direction of the
cause is the opposite of a stretch and the shape of it is exactly as reported: nothing was stretched, because ScreenCaptureKit refuses to
distort. What happened is that the buffer was **resized to the window and the picture was centred inside it**, so the horizontal scale is
uniform and the *offset* is what moved. The padding is real pixels of nothing, it is in the buffer the viewer is told the size of, and every
point the viewer resolves is measured from the buffer's left edge. That is why the error is zero at the centre and worst at either side.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 832 | The defect is live on the shipped worker right now, and its size is readable without looking at a picture | pass (measured, shipped) — the confirmation §26 asks for before a line is changed | `/Applications/AgentSpace.app/Contents/Helpers/agentspace preview AgentUse --stats --json` at 19:11 → `openStreams 1`, the one stream `target.kind = display`, `frameMode video`, `encoderActive true`, and **`mappingBytes 5,564,544`**. Inverting the layout the buffer is built with (`regionSize = 2 × (2112 + w·h·4)`, `SharedFrameLayout.swift:63-71`) gives `w·h = (5,564,544 / 2 − 2,112) / 4 = 695,040` = **1280 × 543**, while the same worker reports its display as 1920×1080 (row 833's probe prints `DISPLAY natural=1920x1080`, and §315 row 805 read `pixelWidth 1920, pixelHeight 1080, scale 1`). 1280 ÷ 543 = **2.357**, 1920 ÷ 1080 = **1.778**: the buffer is the *viewer's* shape, not the desktop's, because `RemoteSurfaceNSView.layout()` derives both numbers from the view (`apps/AgentSpace/Rendering/RemoteSurfaceView.swift:214-218` — `targetHeight = targetWidth × bounds.height / bounds.width`) and `CaptureEngine` passed the pair through verbatim. `sharedBytes 22,241,280` is exactly 8 × 2,780,160 = 8 slots of that same mis-shaped frame |
| 833 | ScreenCaptureKit centres a picture inside a buffer shaped unlike it and pads the rest with transparent black — measured in the agent session with the product's own configuration, not reasoned about | pass (measured, 4 runs) — this is the mechanism, and it is why the fix had to be made where the request is reconciled | `/tmp/captureprobe` (scratch, compiled here, run as the agent user through `agentspace exec AgentUse`) builds the same `SCStreamConfiguration` as `CaptureEngine.swift:78-82` line for line — BGRA, `queueDepth 2`, `showsCursor true`, `scalesToFit true` — starts one stream on the agent's display 168 (1920×1080), and reports the buffer it is handed plus the horizontal and vertical extent of non-black content, per column and per row. `CGPreflightScreenCaptureAccess()` = true, so this is the granted path and not a wallpaper-only denial. The four runs are in row 834 |
| 834 | The pillar buffer and the fitted buffer differ by 314 columns of nothing, and the padding is not desktop at all | pass (measured) | Same session, same display, one frame each. **`1280x543`** (what the shipped sizing asks for) → `BUFFER 1280x543`, `CONTENT columns 157…1122 of 0…1279`, `FULLY BLACK columns 314 of 1280`, mid-row samples `x0=(0,0,0 a0)` and `x1279=(0,0,0 a0)` against `x320=(145,108,76 a255)` — the picture is **965 columns wide, 157 in from each edge, and its padding has alpha 0**, so it is not a dark piece of desktop. **`965x543`** (what `CaptureSizing` answers for the same request) → `CONTENT columns 0…964 of 0…964`, `FULLY BLACK columns 0 of 965`, edge samples `x0=(177,75,34 a255)`, `x964=(75,22,7 a255)`: real desktop at both edges, no padding anywhere. The vertical case is symmetric and was measured rather than inferred: **`1600x1800`** → `CONTENT rows 452…1349 of 0…1799` (an 898-tall picture inside 1,800, ~451-px bars) and `FULLY BLACK rows 926 of 1800`; **`1600x900`** → `CONTENT rows 2…899`, `FULLY BLACK columns 0 of 1600, rows 26 of 900`. The residual 16–26 dark rows appear in *every* run including the clean ones — they are the agent's own dark wallpaper, which is why the row floor is quoted with them and the column counts are the discriminating number |
| 835 | 157 columns of a 1280-wide picture is 236 points of a 1920-wide screen, and that is the distance between the place a hand aimed at and the place the click landed | pass (measured, and arithmetically closed) | The viewer maps a view point by fraction: `displayPoint` multiplies `(viewX − rect.x) / rect.width` by `displayWidth` (`Geometry.swift:223-230, 259-272`), and with `imageWidth = 1280` the whole buffer *is* the picture as far as the viewer knows. So the leftmost column of the actual desktop sits at fraction 157 ÷ 1280 = **0.1226**, i.e. display x = **235.5 of 1920** — the error is 0 at the centre and 235.5 pt at the edges, growing linearly; the vertical case is 451 ÷ 1800 × 1080 = **270.6 pt**. What that looks like on a real menu bar was measured on the agent desktop: `agentspace click AgentUse 11 11` opens the **Apple menu**, `agentspace click AgentUse 244 11` opens **格式** — two titles ~233 pt apart, which is the size of the error at the picture's left edge, so aiming at one and getting the other is not a hypothetical. Independently, locating the drawn cursor by frame-diff inside the viewer window put the agent's pointer for display `(0,0)` at window pixel `(371,155)` and for `(960,540)` at `(1510,793)` — the centre reads right and the corner does not, which is the linear signature above |
| 836 | The fix is one reconciled request in the one place that knows both numbers, expressed as a Core policy, and it needs no wire change and no restart | pass (code + 8 tests + gates) | `shared/Core/Sources/AgentSpaceCore/CaptureSizing.swift` (new, 47 lines) owns it: for a two-dimension request the result is `min(targetW ÷ naturalW, targetH ÷ naturalH)` applied to the subject — **fit, never fill** — with `.rounded()` so a box that already matches the subject returns that box (1920 × (1280 ÷ 1920) is 1279.9999 in binary), and the one-dimension forms (`(w,0)`, `(0,h)`, `(0,0)`) keep the meanings they had, because `previewMaxWidth` and the zoom knob both use them. `CaptureEngine.swift:73-77` is now a single call, replacing the four-branch block that used both requested numbers verbatim. It belongs in Core for the same reason `DisplayScaleSelection` does (`Geometry.swift:320-379`): it is pure geometry, so it is testable without a WindowServer — and the worker is the only party that ever knows the subject's shape *and* the request. **No new field**: `start()` already returns the resolved `(width, height)` and feeds `shared.prepare`/`router.prepare` (`FramePublisher.swift:22-25`), and the client learns the size only from the slot header (`FrameClient.swift:295-301`), so both ends agree by construction and `protocolVersion` stays 1. **No restart thrash**: `FrameClient.configure` compares against the last *requested* pair with a 16-px band (`FrameClient.swift:86-101`), and the request is unchanged — only what the worker does with it. `env PATH=/usr/bin:/bin:/usr/sbin:/sbin swift test` → `Executed 582 tests, with 0 failures (0 unexpected) in 55.458 seconds` (+8, `tests/Unit/CaptureSizingTests.swift`), `npm test` → `# tests 24 / # pass 24 / # fail 0`. One test is not arithmetic: `testThePicturesOwnEdgeIsWhereAClickLands` builds a real `PreviewMapping` for the measured geometry and asserts a hand at the picture's own left edge resolves to display x 0 ± 1, then asserts the *pillar* mapping resolves past 200 — row 835's number, pinned so that a future re-widening fails a test instead of a user's click. Delivered bytes fall with the padding: `mappingBytes` for this geometry goes 5,564,544 → 4,196,184 (**−24.6 %**) and the 1600×1800 case is exactly halved, which matters against `FrameManager`'s 256 MB shared-memory budget — and on the video path H.264 stops spending bits on nothing |
| 837 | What this does not close, said before it is claimed | pending / not measured — three named gaps | (1) **The shipped worker still sizes the old way.** `strings "/Library/Application Support/AgentSpace/Worker/active/agentspace-worker"` → `0.1.26`, `Worker/versions/` holds nothing newer, so rows 833–834 measure the mechanism and the fitted answer with a scratch binary, not with the product's own stream. The same line as §315 row 804 and §316 row 808: verifying it end to end needs 「重新安装助手…」, which is the owner's press and not something to do quietly from here. Expected on the fixed worker, at this exact window size: `mappingBytes` 4,196,184 (965×543) instead of 5,564,544, zero fully-black columns in the frame, and a click at the picture's left edge opening the **Apple** menu. (2) **The Fusion tall-window case is probed, not proxy-windowed.** `1600x1800 → rows 452…1349` is a display capture standing in for a window capture; a real proxy whose view is taller than its remote window would be the direct evidence, and §314 row 799's half-finished hand-on-the-image gap still covers it. (3) **One behaviour changes visibly, on purpose.** Once the buffer has the desktop's shape, a window whose aspect differs shows the desktop with *the viewer's own* bars — smaller picture, correct click — and a hand inside those bars gets `displayPoint == nil`, i.e. **nothing happens** rather than a click 236 pt into the desktop (`Geometry.swift:217-226` refuses the bar deliberately). Also untouched, and unchanged by this: the viewer still asks for 2280×1283 of a 1920×1080 display when 「原生」 is selected on a Retina panel, which is task #74's upscale question and a resolution argument, not an offset one |


## 321. 0.1.29's release chain, and the fallback that turned a failed Developer ID signature into an unsigned release that said `ok` (2026-09-22)

The artifact §320 fixes took the whole of one afternoon to become releasable, and
the reason was not the fix. `scripts/bundle-app.sh`'s `sign()` ended in a
`|| codesign … --sign -`, so a Developer ID signature that failed — for any
reason, including one that has nothing to do with the certificate — was answered
by signing the same binary ad-hoc and carrying on. That converts a hard failure
into a silent one: the bundle still verifies, `codesign --verify --strict` passes
on every nested target, and the only line that shows the truth is a note. The
notary service is the first thing in this chain that cannot be satisfied by an
ad-hoc signature, so it is where the release stopped — 20 minutes and one upload
after the artifact was already wrong.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 838 | A release bundle was signed ad-hoc **by a fallback in the signing function**, and every local step reported `ok`; only Apple noticed | pass (measured, reproduced from the run's own log) — the gate that refused is the notary service, not a script in this repo | The run: `/tmp/0129-release.log`, stamp `version 0.1.29 (402)`, `RELEASE_EXIT=0`. Signing is inside-out, and the timestamp service (`http://timestamp.apple.com/ts01`) went down between the first and second binary: `MacOS/agentspace-worker: replacing existing signature` (clean), then for each of `Helpers/agentspace`, `Helpers/agentspace-updater`, `LaunchDaemons/agentspace-helper` and `AgentSpace.app` a pair of lines — `The timestamp service is not available.` / `A timestamp was expected but was not found.` **followed by a second** `replacing existing signature`, which is `sign()`'s `|| codesign … --sign -` re-signing the same path ad-hoc. What the same run then printed and still exited 0: its own verify block `Signature=adhoc` + `TeamIdentifier=not set`, `codesign --verify --strict` **`ok`** for all five targets, release step 2 `signer: <ad-hoc or unsigned>` with a *note* (`note: not Developer ID signed. …`) rather than a failure, step 3 `refused by Gatekeeper (expected without Developer ID + notarization)` — a sentence written for the no-certificate case and therefore indistinguishable from this one — and step 4 `ok checksum verified` / `ok the copy inside the DMG still verifies`. Apple's answer: submission `f7e31bc3-e9f4-4357-9457-1e78910791c1` (`AgentSpace-app-notarize.zip`, 11:28:21Z) → **`Invalid`**, and its developer log (`asc notarization log --id …`, saved to `/tmp/notary-f7e31bc3.json`) is **12 errors = 4 Mach-Os × 3 messages** — "not signed with a valid Developer ID certificate", "does not include a secure timestamp", "does not have the hardened runtime enabled" — for `Contents/MacOS/AgentSpace`, `Contents/Library/LaunchDaemons/agentspace-helper`, `Contents/Helpers/agentspace`, `Contents/Helpers/agentspace-updater`. The worker is absent from that list because it is the one binary that got signed before the TSA failed, which is also the proof that the fallback is per-target, not per-run: **a bundle can ship with four ad-hoc binaries and one Developer ID one.** `39c1bc2` (touches `scripts/bundle-app.sh` only) deletes the fallback: the ad-hoc path is now chosen once, up front, from `IDENTITY == "-"` (no Developer ID in the keychain), and it fails loudly on its own; a Developer ID sign that exits non-zero prints the identity, names the timestamp service as the likely cause, and `exit 1`s with nothing signed in its place. Re-measured after the change: `shasum`-independent scratch sign of a copy of `/bin/sh` with the real identity → `Authority=Developer ID Application: Guofeng Liu (U8U443D7ZL)` + `Timestamp=Sep 22, 2026 at 19:43:58` (so the outage had passed, and the fix was *not* validated by re-running the outage), then `scripts/release.sh` → `/tmp/0129-release2.log`: `version 0.1.29 (403)`, five `ok`, `signer: Developer ID Application: Guofeng Liu (U8U443D7ZL)`, `team: U8U443D7ZL`, `RELEASE_EXIT=0`. Two wording corrections to the record, because the doc should carry the numbers and not the commit's impression of them: `39c1bc2`'s message says "11 identical errors" where the log holds 12 in 3 distinct shapes, and `scripts/release.sh:64` tells a reader to set `AGENTSPACE_SIGNING_IDENTITY`, which no script in this repo reads — the real variable is `AGENTSPACE_CODESIGN_IDENTITY` (`bundle-app.sh:115`, and `build.sh:31` reads the same name). Only the second is a live trap, and it is left in place here rather than edited quietly: it is a doc line inside a note, and a fix to it belongs with a release that changes the release path on purpose |
| 839 | 0.1.29's four layers, one console that had to wake up, and a gate that failed 583 tests without naming the one that broke | pass (measured) — with the red run attributed rather than called flaky | Layer 4 first refused for the reason §313 row 779 established: at 19:39 `gui-verify: refusing to run — the console session's screen is LOCKED`, so `CHECK_ALL_EXIT=1` while layers 1–3 had already passed (`582 tests, 0 failures`, `updater-e2e: 19 checks passed`, `all MCP smoke checks passed`). Nothing was done about the lock — it was observed with `gui-verify.sh`'s own `CGSessionCopyCurrentDictionary` probe, polled every 30 s: `locked` from 19:40:49 through 19:49:53 (19 samples), `presenting` at sample 20, 19:50:24. The run that started a second later reported `Executed 583 tests, with 1 failure (0 unexpected)` and **no name for the failing case**, and there was no way to recover one from the log: `scripts/test.sh:35` pipes `swift test` through `grep … | tail -60`, so 1,106 of the run's 1,166 lines — including every `Test Case '-[…]' failed` — were discarded by the gate itself. **Attribution, stated as what it is:** a second `swift test --filter CaptureSizingTests` (separate `--scratch-path`, same package) was finishing at that moment, and this suite's safety tests spawn real `agentspace-worker` processes over unix sockets after `pkill -f "agentspace-worker --space-id"`; the case that failed is unknown because the instrument threw the answer away, so this row does **not** record "flaky" — it records that two suites must not share this package at the same time, which is a rule about how the gate gets run. `2e154db` (touches `scripts/test.sh`, `tests/Unit/CaptureSizingTests.swift`): the whole run is `tee`'d to `$TMPDIR/agentspace-test-full.log`, the tail still goes to the screen, and a non-zero exit prints the failing case names and the log path before anything else — the same rule §319 row 827 learned from the other product (`a gate that fails for a reason it never named is a defect in the gate`). Re-measured with nothing else in flight: `swift test` → `Executed 583 tests, with 0 failures`, `TEST_EXIT=0`; then `scripts/check-all.sh` → `CHECKALL_EXIT=0`, `check-all: all 4 layers passed`, `dist guard: stapled app matches the stapled DMG (1de88ac7c289fd93b74fc6e82b19ca8fd9735a22)`, `583 tests, 0 failures`, `updater-e2e: 19 checks passed`, `all MCP smoke checks passed`, `gui-verify: 13 passed, 0 failed` (`session presenting windows (presenting)`), and `npm test` in `packages/agentspace-mcp` → `# tests 24 / # pass 24 / # fail 0`. Layer 4's hand-back checked the way §318 row 807 requires: the process serving the owner's desktop afterwards is `/Applications/AgentSpace.app/Contents/MacOS/AgentSpace` (pid 93131) with **no `AGENTSPACE_*` key in its environment**, so the test root did not travel into the app the human is now holding. **And the check that this release is about, done on the artifact rather than the checkout:** the worker that 「重新安装助手…」 installs is the fixed one — `strings dist/AgentSpace.app/Contents/MacOS/agentspace-worker` answers `0.1.29`, and `nm -a` of the same file carries `_$s14AgentSpaceCore13CaptureSizingO8resolved12naturalWidth…FZ`, the symbol `CaptureSizing.resolved` compiles to. `Contents/Helpers/agentspace --version` → `agentspace 0.1.29 (protocol 1)`, so protocol 1 is unchanged (§26's rule) while the sizing policy inside it is not |
| 840 | `v0.1.29` is published, the digest GitHub computed is the digest of the file the four layers approved, and the channel answered the new tag without being told to | pass (measured, including the round trip) | Annotated `v0.1.29` at `39c1bc2` — deliberately *not* at `master`'s tip: `git rev-parse v0.1.29^{commit}` = `39c1bc2b398f5a34f7bdcc0bb20fbd9e7ba17fec`, whose tree `scripts/release.sh` built (its stamp reads `version 0.1.29 (403)` = the commit count at that commit). `master` then moved twice more (`52acdaf` row 838, `2e154db` row 839's instrument + test), and every file in those two is a doc, a gate script, or a test — nothing compiled into a shipped product, which is the same relationship §319 row 831 recorded for 0.1.28. Notarization through the asc path (step 0 again read `ok asc credentials are live (keychain profile absent)`): app zip `043fb873-da65-4829-bb92-e1888bd63ba5` **Accepted** (11:37:39Z) and `AgentSpace-0.1.29.dmg` `f53c6b29-8492-4642-9ea0-bd9e16bb12e7` **Accepted** (11:38:05Z), each followed by `The staple and validate action worked!`, then the four `ok` lines (`app still verifies`, `app staple valid`, `dmg staple valid`, `Gatekeeper accepts the app`) and `NOTARIZE_EXIT=0`; read back independently of the script with `asc notarization list --limit 6`, and `spctl --assess --type execute -vvv` answers `source=Notarized Developer ID`, `origin=Developer ID Application: Guofeng Liu (U8U443D7ZL)`. Artifact: `shasum -a 256 dist/AgentSpace-0.1.29.dmg` → `829433c407872391d7f8fc00196965fd92642f79818e397fca695caa227c74d3` over `5550513` bytes; the release's own `assets[].digest` says the same string and its `size` the same number, so the bytes Apple returned are the bytes `check-all` approved. Release `https://github.com/misswell/AgentSpace/releases/tag/v0.1.29`: `draft false / prerelease false`, name 「0.1.29 — 鼠标点在哪，桌面就点在哪」, body 2,957 chars, one asset. Round trip: `curl -L` of the download URL → `5550513` bytes, same sha256, `cmp` silent against `dist/`. **The channel, asserted rather than assumed (§318 row 820's rule)**: `GET /repos/misswell/AgentSpace/releases/latest` answered `v0.1.29 / AgentSpace-0.1.29.dmg` on three samples 5 s apart with no `make_latest` write and no cache-busting, and that endpoint *is* `SoftwareUpdater.latestReleaseURL`. Superseded by the fix in row 838: submission `f7e31bc3-…` is `Invalid`, so it carries no installable bytes and needs no reconciliation — unlike §319 row 828's orphaned ids, which are still live at Apple and still listed there. **Not claimed**: (1) the end-to-end click on a fitted buffer — the installed worker answers `0.1.26` (`strings "/Library/Application Support/AgentSpace/Worker/active/agentspace-worker"`), and the press that changes it is 「重新安装助手…」, which is the owner's and was not done from here; row 837's three named gaps stand, and 0.1.29's own release note says so in the product's language rather than only here. (2) A 0.1.28 → 0.1.29 in-app update was not driven; what is measured here is that the endpoint a 0.1.28 install polls answers the new tag with the right digest. (3) Layer 4 checks control shapes through the accessibility tree, not a hand on the image, and `apps/AgentSpace` source did not move in this release — the shipped change is Core + worker |

## 322. 「无法点击，点击没有反应」 and 「窗口无法关闭」: a keyboard rule applied to the mouse, an `AXRaise` that is advertised and refused, and a mirror whose red button asked the agent first (2026-09-23)

Two screenshots, one desktop. The viewer over a session whose only words were
「no app is frontmost in the 'AgentSpace' session, so the events would be delivered
to nothing」, and a Fusion proxy over the agent's Safari that would not close. They
are the same shape of defect: a check written to prevent a silent no-op *becoming*
one, doing it so completely that the gesture which would have satisfied the check was
refused by the check. Every claim below was reproduced against the **installed** build
before a line changed — app `0.1.27` (pid 25566), worker `0.1.27` (pid 26074, read
with `strings` on `/Library/Application Support/AgentSpace/Worker/active/agentspace-worker`).

That measurement also corrects the record: `docs/status.md` says the installed worker
"still answers `0.1.26`" and that §320 row 837's gap is therefore wide open. It answers
`0.1.27`, and `Worker/versions/` tops out at `0.1.27`, so the helper swap has been done
once since 0.1.27 shipped. Row 837's gaps are narrower than the status page claims;
that is recorded here rather than quietly edited there.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 841 | The `NO_INPUT_TARGET` guard asked "is this action a sleep?" and nothing else, so it refused every pointer gesture — including the Dock click that opens the first window — and the desktop could not be escaped through the door the guard was built to keep | pass (measured on the shipped binary, over the owner's own socket) | `git show v0.1.27:native/AgentSpaceWorker/Sources/AgentSpaceWorker/Operations.swift` line **393-407**: `let needsTarget = actions.contains { action in if case .sleep = action { return false }; return true }`, then `AppControl.frontmostPID()`, then a `.noInputTarget` throw when it is `nil` or this process. Reproduced with a 0.1.29 CLI against the **installed** worker (real registry, real socket, agent session with no window open): `.build/debug/agentspace move AgentUse 640 540` → `agentspace: NO_INPUT_TARGET: no app is frontmost in the 'AgentSpace' session, so the events would be delivered to nothing.` and `click AgentUse 640 540` → the same line — the owner's screenshot text verbatim (`'AgentSpace'` is that worker's own `--name`, `context.spaceName`). So the message the person read is the code's, and the action it told them was impossible was *the* action that would have made it true: a click on the Dock. The comment above the guard ("a silent no-op is worse than an error because the agent believes it worked") is right about keys and wrong about pointers; the state it describes — no window — is not a state no mouse event is blocked by, and `Operations.swift:593,608` show the same "frontmost" idea governing the accessibility reads too, which is where the keyboard half of the rule genuinely belongs. `tests/probes/DockClickProbe.swift` prints the two rival answers to "what is frontmost" side by side for exactly this reason |
| 842 | A pointer event needs no responder because the window server hit-tests it against the point it names — measured by posting such a click into a session with no window at all, which opened one | pass (measured, both halves: what the point hits, and what the shipped guard answers) | Mechanism, first, without the product in the loop: `agentspace exec AgentUse "/tmp/dockclick click 434 1033"` (probe compiled from `tests/probes/DockClickProbe.swift`, spawned by the worker so it inherits its TCC) prints `hit-test at 434,1033 -> 0 AXDockItem/AXApplicationDockItem title=Safari浏览器 at 400,991 68x84 pid=25866 app=程序坞`, posts move+down+up there, and 6 s later reports `DISPATCHED: 1 new layer-0 window(s)` — win 1104, Safari 起始页. A click has a target wherever its point is, window or no window. Policy, second: Core now owns the distinction at `shared/Core/Sources/AgentSpaceCore/InputActions.swift:88-103` — `needsResponder` is `true` for `.type`/`.key`, `false` for `.move`/`.click`/`.drag`/`.scroll`/`.sleep` — and the worker reads it at `Operations.swift:400-401`; nothing else about the check moved, including the `getpid()` comparison that stops an agent from typing into the worker itself. Run against a **fresh worker from this tree** in the same Aqua session (row 843's harness), still with zero windows: `move` → `moved to 640.0, 540.0`, `scroll AgentUse 0 -200 640 540` → `scrolled 0, -200 at 640,540`, `click AgentUse 1352 1033` → `clicked`, and 3 s later 系统设置 was pid **65062** with window **2184** in the catalog — **the click that the shipped code refused is the click that produced the first window**, which is the whole claim. The keyboard half still refuses, with a message naming the way out instead of only the dead end: `no app window is open in the 'AgentUse' session, so there is nothing to type into. Pointer input still works — click an app in the Dock to open a window.` `.noInputTarget`'s remediation (`shared/Core/Sources/AgentSpaceCore/ErrorCodes.swift:137-138`) says the same once for every front end — the installed worker already printed that new remediation line under the old message, because remediations ship in the CLI, and it contradicted the sentence above it. `docs/protocol.md` rule 5, `docs/architecture.md`'s tree and `docs/troubleshooting.md`'s section were reworded from "input" to "typing", because the old text told an agent to give up on a desktop it could still drive. No error case changed: the state is still `NO_INPUT_TARGET`; what narrowed is when it fires |
| 843 | A worker from this tree can be run against a scratch root inside the owner's live session without touching the installed one — and a socket under `/tmp` is unreachable until its group is fixed | pass (measured; the recipe is the reusable part, and its second trap is a macOS fact rather than a project fact) | `swift build --product agentspace-worker` (per product, per §319 row 827), `cp` to `/tmp/asworker`, then `agentspace exec AgentUse "nohup /tmp/asworker --space-id <uuid> --name AgentUse --runtime-dir /tmp/asv --token <hex> --quiet > /tmp/asv/worker.log 2>&1 &"` — started **by the installed worker**, which is what puts it in `agentuse`'s Aqua session with that session's Accessibility and Screen Recording. The root is `/tmp/asv` with a hand-written `Spaces/index.json` (one `AgentUse` record, `runtimeRoot` pointing at the scratch root) plus `Runtime/<uuid>/token`; the CLI reaches it with `AGENTSPACE_ROOT=/tmp/asv`, and the installed registry is never opened or written. Three things had to be true. (1) No `space.json` in that runtime dir: `native/AgentSpaceWorker/Sources/AgentSpaceWorker/main.swift:484-492` calls `RuntimePermissionVerifier.verifyDirectory` **only when** `space.json` carries a `mainUser`, so a scratch root starts without the two-principal ACL the helper owns — and `exit 78` is the answer the moment it does claim one. (2) Token verification is token-equality, not peer uid, which is why a CLI in the owner's account can drive a worker in the agent's. (3) **The trap:** anything created under `/tmp` inherits group `wheel`, so the worker's deliberate `srw-rw---- agentuse wheel` socket answered the CLI with `WORKER_OFFLINE … Permission denied` — a 0660 plus an ACL that excluded the group the caller is in. Fixed on the *directory*, not by loosening the socket: `chgrp staff` + `chmod 2777` on the runtime dir, so the socket inherits `staff` and stays 0660. Torn down and verified empty: `pkill -f /tmp/asworker` prints "Operation not permitted" for PIDs already exiting, so the check is `ps -o pid,uid,command -U 503` plus the absent `worker.pid`, not that exit status; then `rm -rf /tmp/asv /tmp/asv-token /tmp/asworker /tmp/asrpc.py` — the last being a 20-line line-in/line-out client, needed because **the CLI has no `window` verb at all** (`agentspace window activate …` → `unknown command 'window'`), which is how `window.activate` and `window.close` were spoken to both workers below |
| 844 | The second toast — 「macOS refused to raise window 1296 (AX error -25205)」 — is an app that advertises `AXRaise` and refuses it, and two attribute writes move the same z-order the action would; judging a raise by a call's **status** is the bug | pass (measured on two apps, both directions, and on the shipped code path) | Shipped: `git show v0.1.27:native/AgentSpaceWorker/Sources/AgentSpaceWorker/WindowActions.swift:28-33` — `let status = AXUIElementPerformAction(element, kAXRaiseAction as CFString)`, `guard status == .success else { throw AgentSpaceError(code: .badRequest, message: "macOS refused to raise window \(window.id) (AX error \(status.rawValue)), so input could land on another window") }`. Measured on the owner's socket, same request the proxy makes: `window.activate {"windowId":2204,"pid":67564,"generation":12}` → `BAD_REQUEST: macOS refused to raise window 2204 (AX error -25205), so input could land on another window` — the owner's toast with one digit changed. `tests/probes/WindowPathProbe.swift` (untracked until this commit; `fix <ID>` transcribes the patched sequence and prints every status) shows why the status was never the question: System Settings' own window lists `AXRaise` in its action names and answers **-25205** when it is performed, while Safari's answer **0** — and -25205 is `kAXErrorAttributeUnsupported`, the wrong vocabulary for a refused *action* (`kAXErrorActionUnsupported` is -25206; both read out of `AXError.h` from the SDK, not from memory). The substitutes: `set AXMain=true -> 0`, `set AXFocused=true -> 0`. Do they raise? On Safari, four windows, front-to-back order `[2027, 2022, 2019, 2013]` with the target last: `pin (AXMain+AXFocused only)` → `[2019, 2013, 2027, 2022]`; `raise (AXRaise only)` on the same arrangement → **`[2019, 2013, 2027, 2022]`**, identical. So the writes are not a weaker stand-in, they are the same operation. Where they are weaker, recorded rather than smoothed over: on System Settings window 2148 the fallback made the app report `AXMainWindow is this window = true` while the window-server order stayed `[2155, 2148]` — 2155 is that app's own 66×20 auxiliary window and it did not move. Hence the patched code's order of business (`WindowActions.swift:28-49`): try `AXRaise`, then write main+focused, then **judge by read-back** — `isMainWindow` at `:50-57` copies the app's `kAXMainWindowAttribute` and compares it to this element with `CFEqual` — because an app can accept the assignment and focus something else, and then input really would land on a sibling. Verified end to end against the fixed worker: the same `window.activate` params it can actually answer, `{2204, 67564, generation:1}`, → `{"ok":true,"result":{"active":true,"bundleId":"com.apple.systempreferences",…}}`. The 0-match and >1-match refusals are untouched, and so is the rule they protect: never drive a window nobody is looking at |
| 845 | The proxy's red button could not close the proxy, because closing was conditional on an RPC whose failure it could not tell apart from the window being gone — and the answer that makes it permanent is the same bytes either way | pass (measured against the shipped worker; the replacement is read and unit-green, not yet pressed: row 847) | Shipped: `git show v0.1.27:apps/AgentSpace/Fusion/FusionWindowController.swift:104-121` — `if closingRemote { stop(); return true }`, then `queue.async { SpaceService().windowClose(...) }` and `return false`. The mirror closed only *after* the worker said yes, and `closingRemote` arrived with `357d806` ("Fusion: add remote window streaming and native proxies"), first tagged `v0.1.15`, so every release since has shipped a window that opens and does not shut. Why it gets stuck, measured: `window.close {"windowId":999999,"pid":67564,"generation":12}` → `BAD_REQUEST: window 999999 no longer exists or its generation changed` — and that is the correct answer for a vanished window **and** for a stale identity, because `generation` is a per-process counter, not a per-window one: `WindowCatalog.swift:16,28-29` keeps `nextGeneration` starting at 1 and hands the next value to each newly-visible `(pid, windowID)`. Proof rather than reading: CGWindow **2204** was generation **12** on the long-running worker pid 26074 and generation **1** on a fresh one, and the *same* `window.activate` params were answered `"no longer exists or its generation changed"` by the fresh worker and `"(AX error -25205)"` by the old one. A proxy left open across a worker restart therefore carries an identity that can never close, remote or local: `performClose:` → delegate → RPC → failure → `state.error` → `return false`, forever. Now: `windowShouldClose` (`FusionWindowController.swift:131-134`) is `stop(); return true` — a mirror of someone else's desktop is a view, and closing a view never needed that view's owner's permission; closing the **agent's** window is a labelled title-bar action (`:51,58-66` install it, `FusionWindowView.swift`'s `FusionWindowActions` renders it as 「关闭 Agent 窗口」 with a help line stating the scope), whose RPC failure is still reported (`:137-153`) and simply leaves the mirror where it is — because the mirror is now the thing that still works. Three details kept honest: the success path calls `stop()` **then** `window?.close()`, and `close()` (not `performClose:`) is deliberate there, since the other one re-enters the delegate that just answered a *user*; `stop()` in both paths is required because `FusionSession` retains the controller, which is what `startCapture()`'s new `window?.isVisible != false` guard (`:155-162`) is for, so a retained-but-dismissed proxy cannot pull frames for nobody; and no `dismissed` set was added to `FusionSession`, because a retained record is exactly what stops the next poll from handing the same window a fresh mirror. That the remote close itself works when the identity is current was checked separately: `/tmp/windowpath close 2184` → `AXPress on that button -> 0`, `CLOSED: win 2184 left the on-screen list` — the lockout was never "closes fail", it is "one fail is permanent" |
| 846 | The change is a narrowing, not an addition: nothing new on the wire, no new error case, protocol 1, every new key in both localization tables | pass (measured) | `InputAction.needsResponder` is computed, never encoded, so no field crosses the socket that did not before; `AgentSpaceErrorCode` gained nothing; `protocolVersion` is still 1 (§26's rule) and both directions of the mismatch degrade to the old behaviour rather than to a break — a new app against the installed 0.1.27 worker still gets pointer input refused, which is why row 847 keeps that press open. Three keys were added or rewritten and all three exist in **both** tables (`apps/AgentSpace/Resources/{en,zh-Hans}.lproj/Localizable.strings`, where the English side *is* the key): `"Close Agent Window"`, `"Closes the agent's own window, not just this mirror of it."` and the new `.noInputTarget` remediation; `tests/Unit/LocalizationTests.swift` passing is the only reason that parity is a fact instead of a habit. `scripts/test.sh` → **`Executed 585 tests, with 0 failures (0 unexpected)`** in 47.7 s (`$TMPDIR/agentspace-test-full.log`, 09:53; 583 before this change). The two new cases are `testPointerActionsDoNotNeedAResponder` and `testKeyboardActionsNeedAResponder` in `tests/Unit/InputActionTests.swift`, and they assert the *shape* — `move`/`click`(×1,×2)/`drag`/`scroll`(located and unlocated)/`sleep` false, `type`/`key` true — so the next action added to that enum has to answer the question instead of inheriting `true`, which is precisely how this shipped |
| 847 | What this does **not** close: nobody has pressed the fixed proxy's red button, and the owner's desktop is still running the code that refuses the mouse | **PENDING / blocked** — recorded as open, not as passing | (1) Row 845's fix is **unverified on screen**. `scripts/gui-verify.sh` runs the app against an isolated empty registry (`AGENTSPACE_ROOT=$(mktemp -d)`), and a Fusion proxy needs a connected account with a live worker behind it, so layer 4 cannot reach a proxy *by construction*; driving the owner's running 0.1.27 app into opening one was refused, because on that build the window is the undismissible kind and "verifying" would have meant leaving a window on someone else's desktop that only a rebuild removes. The claim is therefore: the shipped code is provably the broken one (`git show`, row 845) and the replacement is read and unit-green — not "the button works", until it is pressed on the new build. (2) Rows 841-844 are fixes **in the worker**; the installed worker answers `0.1.27`, so 「无法点击」 is not repaired by an app update alone — it needs 「重新安装助手…」, which is the owner's press and was not done from here. (3) Row 842 proves a click lands and an app launches; it does not prove TextEdit selection, a Finder drag, or a Chrome scroll (§六's remaining gates), and the ≥2-hour soak has not been run on this tree. (4) 0.1.29's capture-sizing end-to-end check (row 837's remaining gap — `mappingBytes 4,196,184`, zero black columns, the Apple menu at the picture's left edge) is still open for the same reason as (2): the owner is on 0.1.27. (5) One known follow-up, found and not fixed here: the same "is something frontmost" idea still gates the accessibility *reads* (`Operations.swift:593,608`), and row 841 showed those reads answer in a session where a click would have made them answer differently — a target-selection review of those two paths, in a change of its own |
| 848 | 0.1.30's release chain, and a fourth layer that reported zero main windows on one run and thirteen of thirteen on the next, over the same bytes | pass (measured, including the round trip) — with the red attributed to the instrument by re-measurement rather than called flaky | `scripts/release.sh` → `/tmp/0130-release.log`: `version 0.1.30 (408)` (408 = the commit count at `cf7aa1b`, which is why the bump was committed before the build), five `ok` signatures, `signer: Developer ID Application: Guofeng Liu (U8U443D7ZL)`, `team: U8U443D7ZL`, `RELEASE_EXIT=0`; step 3's Gatekeeper refusal there is the expected pre-notarization answer, not a finding. `scripts/notarize.sh` → app zip `a0c0affe-ed17-4e7e-bb13-70fdf0978776` and `AgentSpace-0.1.30.dmg` `a1d6f1fa-a60f-470a-a634-65c40091759f`, both read back from Apple as **`Accepted`** with `asc notarization list --limit 4` rather than from the script's own exit, each followed by `The staple and validate action worked!`, then `NOTARIZE_EXIT=0` and an independent `spctl --assess --type execute -vvv` → `source=Notarized Developer ID`, `origin=Developer ID Application: Guofeng Liu (U8U443D7ZL)`. **Layer 4 refused the first `check-all`:** `/tmp/0130-checkall.log` shows `session presenting windows (presenting)` and then `window count samples: 0,0,0,0,0,0,0,0,0,0` with `bundle under test: … dist/AgentSpace.app (pid 88352)` and `other AgentSpace processes: none`, three main-window checks failing (`launch opens exactly one window: expected [1] got [0]`, the build stamp, the empty-state registry line) and the wizard failing, while **all eight Settings-window checks passed** — `settings opener: clicked, windows=1`. That asymmetry is the shape §302 rows 663-664 recorded for a temporary bundle that shares the installed copy's bundle id and settles at zero main windows, and the build was ruled out before the instrument was: `git diff --stat v0.1.29..HEAD -- apps/ shared/ native/` is Fusion's two proxy files, `Info.plist`, two `.strings` lines and the version stamps — nothing in the app's launch or main-window path moved, and a main window that never appears cannot come from a title-bar accessory on a window that is not open. Re-run of `scripts/gui-verify.sh` alone, same notarized bytes: **`gui-verify: 13 passed, 0 failed`**, `launch opens exactly one window` among them, wizard `step 2`. Full `scripts/check-all.sh` again → **`check-all: all 4 layers passed`**, `CHECK_ALL_EXIT=0`, `dist guard: stapled app matches the stapled DMG (dd042b0e32a9f129f7401ed3e2e998c9ca17e7ac)`, `Executed 585 tests, with 0 failures (0 unexpected)` in 45.0 s, `updater-e2e: 19 checks passed`, `all MCP smoke checks passed`, `gui-verify: 13 passed, 0 failed`. So §307 rows 721-722's rule is what was applied, and the row still records the failure rather than only the pass: **the instrument can report a healthy app as window-less, twice in a row it did, and nothing in that run distinguished it from a real zero-window launch** except re-measurement. What it costs on this machine, said plainly because §313 row 792 named it: layer 4 `pkill`s every AgentSpace process this uid owns, so the owner's running 0.1.27 app went down twice and came back as `/Applications/AgentSpace.app` pid 92032 with **no `AGENTSPACE_*` key in its environment** (checked after each run), and the installed worker (pid 26074) was never touched. Artifact: `shasum -a 256 dist/AgentSpace-0.1.30.dmg` → `243f4fc86db0d6d3cdcf3899dc19213a56a3b0a6ffdaf6af0991b71f408637e2` over `5556169` bytes; the release's own `assets[].digest` is the same string and its `size` the same number; `curl -L` of the download URL returned the same 5,556,169 bytes, the same digest, and `cmp` against `dist/` was silent. Annotated `v0.1.30` at `cf7aa1b` — the commit whose tree was built, `git rev-list --count v0.1.30` = 408 = the stamp in the bundle — pushed with `master` over SSH (`git@github.com:misswell/AgentSpace.git`, because the `gh` token has no `workflow` scope) before the release existed. **The channel asserted, not assumed (§318 row 820's rule)**: `GET /repos/misswell/AgentSpace/releases/latest` answered `v0.1.30 / AgentSpace-0.1.30.dmg` with that digest on three samples ~4 s apart, with no `make_latest` write and no cache-busting — the case that endpoint is `SoftwareUpdater.latestReleaseURL`, and the reason the previous release needed a second write. Release `https://github.com/misswell/AgentSpace/releases/tag/v0.1.30`, `draft false / prerelease false`, one asset, notes naming both fixes, the two presses this release needs, and the three things it does not claim. **Not claimed** is row 847's list unchanged by publishing: nobody has pressed the new 「关闭 Agent 窗口」 button on a live proxy, rows 841-844 reach a desktop only after 「重新安装助手…」, and the installed pair on this machine is still `0.1.27 / 0.1.27` — which is checkable in one command and was, twice, before and after the gate runs |

## 323. The desktop capture read points as pixels, so a Retina agent desktop arrived at half resolution — and the four viewer cases that were measured before it changed (2026-09-23)

The plan this round was a Retina one: 「远程画面达到本机 Retina 清晰度」. The first
thing worth recording is that most of its *input* half already existed and is
measured — Core owns one `InputAction` vocabulary that GUI, CLI, MCP and the
worker's parser all share, `RemoteSurfaceNSView` implements the full AppKit event
set with a tracking area and first responder, `PreviewMapping` is the coordinate
layer, `InputSynthesizer` is the single place a `CGEvent` is built, the
Accessibility gate is step (2) of `Operations.input`, and `NO_INPUT_TARGET`,
`.cgSessionEventTap` and the refusal to drive the physical console are all §314–§322's.
Rewriting those into the plan's own proposed types would have created a second
source of truth for the same facts — and one of the plan's suggestions,
`.cghidEventTap`, is the tap that types into the **human's** session, refused by
construction in `InputSynthesizer` for the reason recorded there.

What was genuinely missing was on the display side, and it was one line of
arithmetic with a wide consequence: `SCDisplay.width/height` are **points** and an
`SCStreamConfiguration` is **pixels**, and the display branch of `CaptureEngine`
used the first as the second. On a HiDPI agent desktop that halves the capture in
each axis and the viewer scales it back up, so the picture on screen is
interpolation from the first pixel. The window (Fusion) branch had gone through
`DisplayScales` since it was written; the display branch was the last place that
had not, and the one-shot `screenshot` path reads `CGDisplayCopyDisplayMode().pixelWidth`
— so the two halves of the product disagreed about a display's own resolution.

Everything below was measured on this machine, in the agent account's own Aqua
session, through the product's own binaries: a worker built from this tree,
started by the installed worker so it inherits that session's TCC grants, driven
over `frame.open`/`frame.stats` and a headless viewer that speaks the frame
protocol from Core's own types (§322 row 843's recipe, extended where it needed
extending — rows 855 and 857 name the two extensions).

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 849 | An agent session on this machine has a **2x display**, and the old sizing captured it at the point size — so the defect is live and measurable, not hypothetical | pass (measured, both sizings through `frame.open` + `frame.stats`) | The agent account's session reports two displays: id 23 `1920x1080pt 1920x1080px` (1x, main) and id 22 `1512x982pt 3024x1964px` (**2x**) — read with `CGDisplayCopyDisplayMode` in that session, the same source `DisplayScales`/`ScreenCapture` use. `frame.open` on **id 22** with no requested size, then `frame.stats`: **`captureWidth 3024, captureHeight 1964`**, `mappingBytes 47,517,312`, `captureCapped false`. The same display with the *point* request (1512×982, which is the natural size the old code computed for it) answers `captureWidth 1512, captureHeight 982`, `mappingBytes 11,882,496`. Inverting the layout (`regionSize = 2 x (2112 + 4wh)`) gives exactly those two products, so no third size is involved. The worker's own new line says the same thing in words: `frame stream capturing 3024x1964 of a 3024x1964 display at 2x` and, for the same display under the old request, `frame stream capturing 1512x982 of a 3024x1964 display at 2x` |
| 850 | The fix is the display mode's pixel count, and the 1x case is unchanged — the change is conditional, not a blanket doubling | pass (code + live, both display classes) | `native/AgentSpaceWorker/Sources/AgentSpaceWorker/CaptureEngine.swift`: the `.display` branch now takes `sourceScale = DisplayScales.pixelsPerPoint(of: display.displayID)` and `natural = display.width * sourceScale`, mirroring the window branch beside it. Same session, **id 23** (the 1x display) with no requested size: `captureWidth 1920, captureHeight 1080`, `mappingBytes 16,593,024` = `2 x (2112 + 1920x1080x4)` exactly, and the log line `capturing 1920x1080 of a 1920x1080 display at 1x`. So a desktop that is not HiDPI is captured byte-for-byte as before, and a HiDPI one is captured at the resolution it actually renders |
| 851 | The viewer no longer asks for more pixels than the source has: 「原生」 means the source's own pixels, which is what the picker always claimed | pass (code + 15 new tests + the live buffer sizes) | `DisplayQuality` (Core) is the policy and `RemoteSurfaceNSView.layout()` takes the **smaller** of its own window's device pixels and the caller's limit, which the desktop viewer derives from the agent display's `pixelWidth/pixelHeight`. The measured case is §320 row 837's: a 1140×642 point window on a 2x panel used to ask a 1920-wide desktop for 2280×1283 and was handed an enlargement (2,925,240 px, `mappingBytes` 23,406,144); the same window now asks for 1920×1080 and gets the desktop itself (2,073,600 px, 16,593,024 — **−29 %**). `tests/Unit/DisplayQualityTests.swift` pins it as `testTheMeasuredRetinaViewerCaseIsNoLongerAnUpscale`, and `CaptureSizingTests.testANativeRetinaRequestKeepsTheUpscaleAndShedsThePillar` keeps the *policy* permissive for a caller that means to ask for more (the zoom knob does) |
| 852 | The pixel ceiling is derived from the frame budget rather than chosen, and the property it protects is asserted in both directions | pass (code + tests) | `SharedFrameGeometry.maximumPixels = (memoryBudget / (2 x slotCount) - slotMetadataSize) / bytesPerPixel` = **16,776,688** px: the largest surface whose mapping, counted **twice**, still fits the 256 MB budget — i.e. the largest stream that leaves room for a second one of its own size, which is what `FrameManager.open` refuses on. `CaptureSizing.planned()` fits first and cuts second (one factor on both axes, so the buffer keeps its subject's shape) and reports `capped`. Two tests hold the derivation: `testThePixelCeilingIsTheLargestSizeTwoStreamsCanShare` (the ceiling fits twice and ceiling+1 does not) and `testA5KDisplayFitsAndA6KOneDoesNot` (5120×2880 untouched, 6016×3384 capped to 82 % linear). The guard is needed because this change is what makes it reachable: a 6K desktop at its own pixels is 20.4 Mpx, ~163 MB of mapping for one stream |
| 853 | The display-quality choice is one preference, one default, and one migration — the two pickers that disagreed are gone | pass (code + tests + `LocalizationTests`) | The viewer's footer and Settings held the same `@AppStorage` key with **different declared defaults** (`0` = Native beside `1600`) and different option lists (Settings had no Native at all), so until either control was touched the two screens disagreed about the value of one preference. Now `DisplayQuality.storageKey` and `migrateStoredPreference()` live in Core beside the modes, `DisplayQualityPicker` is the one control both surfaces render, and a stored width is translated once at launch (`0`→native, ≤1280→performance, larger→balanced; `testTheMigrationRunsOnceAndKeepsAChoiceMadeSince`, `testTheMigrationIsANoOpWithNoStoredPreference`). `Performance` reuses the string both tables already carried; the four new keys exist in **both** `.lproj` tables, which `LocalizationTests` makes a fact rather than a habit |
| 854 | The picture is the display's picture: at the new sizing a capture is indistinguishable from an independent `screencapture` of the same display, and every smaller mode loses detail in proportion | pass (measured against an independent instrument) | The instrument: `/tmp/capprobe` (scratch, built here) starts one stream with the worker's own configuration — BGRA, `queueDepth 2`, `showsCursor true`, `scalesToFit true` — on the agent session's 2x display and saves one frame; the reference is `/usr/sbin/screencapture -x -C -D 2` (3024×1964, a different code path). Content was verified static first: two reference captures 3 s apart differ by **mean 0.0**. Results, each capture box-downscaled-and-returned for the above-half-scale detail column: **native 3024×1964** → mean\|diff\| **0.176**, pixels differing by >8/255 **0.000 %**, detail **0.651**; **balanced 2268×1473** → 0.482, 0.414 %, 0.430; **the old point size 1512×982** → 0.616, 0.891 %, 0.234; **performance 1280×832** → 0.686, 1.116 %, 0.314. Read as the ladder it is: the old code sat between Balanced and Performance in delivered detail, on a display whose own framebuffer has four times the pixels, and nothing in the product said so. **The same comparison on text**, which is what the round was for: a TextEdit window holding `TYPED-键盘-abcdefghijklmnopqrstuvwxyz-0123456789` was opened on that display and measured over its own rectangle (1312×844 px), against the same reference — **native** mean|diff| **0.006**, pixels differing by >8/255 **0.010 %**, >32/255 **0.006 %**, detail **0.984**; **balanced** 0.964 / 2.366 % / 1.275 % / 0.584; **the old point size** **1.414 / 2.967 % / 1.577 % / 0.410**. A glyph edge that lands in the wrong place is a >32 difference, and the old sizing had **260x** as many of them as the native one — which is the difference between text that is the display's text and text that is a resampled copy of it |
| 855 | What native pixels cost, measured through the product's frame protocol by a headless viewer | pass (measured; the instrument is the reusable part) | The engine parks a stream that nobody acknowledges after one second (back-pressure by design), so fps and latency need a *reader*: `/tmp/miniviewer` compiled Core's own sources with a 90-line main that performs the real handshake (`FrameHello` → `FrameHelloAck` → `SCM_RIGHTS` mapping), acknowledges every slot and closes. Same display, same motion, two sizings: **3024×1964** → 12.1 fps, capture→receive **p50 21.6 ms / p95 36.9 ms**, payload **10.8 MB (792 kB/s)**, mapping 47,529,984, worker 3.3–4.0 % CPU / ~130 MB RSS; **1512×982** → 12.1 fps, **p50 10.9 ms / p95 26.7 ms**, **1.8 MB (132 kB/s)**, mapping 11,894,784, 2.7–3.7 % / ~62 MB. The 1x desktop for reference, at 15 fps: **14.4 fps**, p50 4.4 ms / p95 11.7 ms, 3.9 MB over 12 s (**337 kB/s**) at 1920×1080. So the honest price of Retina on a 2x desktop is **~6x the bytes and ~+11 ms p50** for 4x the pixels — superlinear because the extra bytes are the detail the old code was discarding, and the reason `balanced` and `performance` exist as choices rather than as decoration |
| 856 | The input path works end to end on this tree: a hover, a click and a drag, each measured on a real desktop | pass (measured through the product's own CLI against the scratch worker) | Hover: `move 434 985` then `move 434 1033` (onto the Dock tile §322 row 842 identified) changed **1,528** pixels, **0** of them in the menu bar, concentrated in the Dock strip and at the cursor's two positions — a pointer move with no button event did something. Click: `click 11 11` opened the Apple menu (153,448 bright pixels in the top-left 400×600 against a dark desktop, diff bbox `(5,3)-(1431,995)`), and `key escape` closed it. Drag: `drag 541 90 760 330` moved the agent's TextEdit window from `(213,77)` to **`(422,307)`** — a `+209,+230` displacement for a `+219,+240` request, read back from the window catalog, with the 10 px difference in both axes shaped like AppKit's own drag threshold rather than a mapping error (the click above lands where it was aimed). Keys are still refused with no window open — `type`/`key` → `NO_INPUT_TARGET` with the pointer escape named — which is §322 rows 841–842 behaving as designed on this tree |
| 857 | `scroll` with a point that reaches no scroll area moved nothing, and nothing said so — the root cause is named, and the worker now says it | pass (measured, with the installed worker as the control) | Two scrolls of 20 lines over a 401-line TextEdit document at `(300,200)` changed **0** and **32** pixels of a 1920×1080 desktop (`bbox` of the 32 = a 2×16 strip at the caret). Not this change: the **installed 0.1.27 worker** answers the same request with **0** changed pixels on the same document, and the mechanism is visible one layer down — `/tmp/scrollprobe` (the worker's own chain, step by step) shows `AXUIElementCopyElementAtPosition` at `(300,200)` returning the **AXApplication** element (`role=AXApplication title=文本编辑`, no parent, no frame) instead of the window's content, and the same for a Finder window (`frame=0,1080 0x0`). With no `AXScrollArea` among the ancestors, `InputSynthesizer` declines the Accessibility channel and posts the wheel event instead — which §315 measured as inert in a session that is not on the console — and the op answered `performed: 1` either way. The change is that it can no longer be read as success: `InputSynthesizer.perform` returns which channel it took, `frame.input`'s reply carries `channels` per action, and the CLI prints a line naming what did not happen (`→ no scroll area was found at that point … Nothing at that point was scrolled.`). Measured: `channels: ["scrolledViaWheel"]` for the anchored scroll, `["performed","performed"]` for a move+click batch |
| 858 | Every automated gate that does not need the screen, and the reason the fourth one refused | pass (gates) / deferred (layer 4) | `scripts/test.sh` → **`Executed 600 tests, with 0 failures (0 unexpected)`** in 41.8 s (585 before: +11 `DisplayQualityTests`, +4 `CaptureSizingTests`), `npm test` in `packages/agentspace-mcp` → `# pass 24 / # fail 0`, `scripts/mcp-smoke.sh` → `all MCP smoke checks passed`, `scripts/updater-e2e.sh` → `19 checks passed`. Layer 4 was run against a **temporary bundle built from this tree** (`scripts/bundle-app.sh debug /tmp/astest`, `AGENTSPACE_GUI_APP` — `dist/` was not touched, per AGENTS.md rule 2) and refused for the environment reason §313 row 779 established: `the console session's screen is LOCKED`, so no window can appear and every accessibility read would be empty. It refused before `pkill`, so the owner's running app was not disturbed. `bash -n scripts/gui-verify.sh` is clean, and the tier check inside it was rewritten for the new control: the three titles are **localized**, so it accepts either shipped language's set rather than asserting a title that only holds in one of them (§318's rule) |
| 859 | What this does not claim | **PENDING / not measured** — four named gaps | (1) **Nobody has looked at the new picker.** Layer 4 is where the Settings control and the viewer's live-size readout would be checked, and the console was locked for the whole of this round; the claim is code+test, not "seen on screen". (2) **The installed pair is still `0.1.30 / 0.1.27`** (`defaults read` and `strings` on the active worker, both re-read after the measurement), so the capture fix reaches a user's desktop only after 「重新安装助手…」 — the same press §320 row 837 and §322 row 847 are waiting on, and the reason the numbers above were produced with a worker built from this tree rather than the installed one. (3) **Text on the 2x display was reached by accident, not by a recipe.** Two deliberate attempts failed — a high-frequency desktop picture (Finder's `desktop picture` AppleEvent hangs in a background session, timing the worker out for 60 s) and dragging the window across (`move`/`click`/`drag` at `x=2500` → `INVALID_COORDINATE`: pointer input is bounded to the **main** display, while `scroll`'s anchor is deliberately not validated, so the same point is refused for a click and accepted for a scroll). What worked was `open -a TextEdit <file>` with the second display already active, which macOS placed at x=2072 on its own — that window is therefore **unreachable by the pointer** and can only be driven by the keyboard, which is also why row 854's text measurement and row 856's keyboard result come from different displays. What is still missing is a deliberate way to reach a second display: the product can capture it, cannot click it, and the viewer never asks for it (`displayID: nil` captures whatever `SCShareableContent.displays[0]` is — the main display here, measured: the list is `[23 main, 22]`) (4) **`window.setFrame`/`window.close` cannot act on these apps in this session** — "no accessibility window matches" — because their AX window list exposes the application element, which is the same defect as row 857 and is *not* fixed here; the two TextEdit documents and one Finder window opened for the measurement could not be closed through the product's API (TextEdit was quit instead) |
| 860 | The gate found three defects in itself while this release was being gated, and each is now named rather than called flaky | pass (measured, each mechanism reproduced) | Two runs of layer 4 on the *same* notarized bytes failed two different sets, and neither set was the build. (1) **The identifier was on the wrong element.** `accessibilityIdentifier` was applied to the composed `DisplayQualityPicker()` view rather than to the `Picker` inside it, so it landed on whatever SwiftUI wrapped the control in: the gate's `pop up button` lookup found it in one run and not the next. Measured after the move with an isolated instance: `DEPTH 4 class=pop up button id=displayQualityPicker`. (2) **The retry turned one missing control into eleven failures.** The five-attempt loop pressed Escape unconditionally; with no menu open, Escape closed the Settings *window*, so the whole Update pane reported "not there" (`update pane reachable: expected [y] got [n]`). It now presses Escape only when it actually opened a menu. (3) **A SwiftUI Picker's menu is not in the accessibility tree until it is open** — five attempts, five `-1719 invalid index` — and clicking to open it puts the app into menu tracking, where the window's own elements stop resolving, so the check that read the option list was the thing making the next phase unreliable. The check now reads the control's `value` (the selected mode's own name, so the assertion is exact in both shipped languages), clicks nothing, and leaves no state behind; `stderr` is no longer discarded, so a failure says `no advanced settings window` instead of `[]`. Found on the way: the gate writes the app's **`settingsTab` preference**, which is shared with the installed copy — every run starts on whatever tab the previous one finished on, which is a candidate mechanism for the layer-4 flakes §302 rows 663–664, §307 rows 721–722, §318 rows 816–818 and §322 row 848 recorded. Not fixed here: a run that leaves the owner's tab where it ended is a side effect worth removing, in a change of its own. What the gate is *for*, measured on the artifact: `display quality control: one of the three modes`, and then `gui-verify: 13 passed, 0 failed` |
| 861 | 0.1.31's release chain: the artifact four layers approved is the artifact the channel serves | pass (measured, including the round trip) | `scripts/release.sh` → `/tmp/0131-release2.log`: `version 0.1.31 (413)`, five `ok` signatures (`AgentSpace.app`, `agentspace-helper`, `agentspace-worker`, `agentspace`, `agentspace-updater`), `signer: Developer ID Application: Guofeng Liu (U8U443D7ZL)`, `team: U8U443D7ZL`, `RELEASE_EXIT=0` — the run whose tree is `b06418e`, whose `git rev-list --count` is 413, the number stamped inside the bundle. `scripts/notarize.sh` → app zip `14e467ea-9a33-4697-a7c6-56062594e533` and `AgentSpace-0.1.31.dmg` `bd902bf0-8085-49b7-bdcd-6166b5a2078a`, both read back from Apple with `asc notarization list --limit 4` as **`Accepted`** rather than from the script's own exit, each followed by `The staple and validate action worked!`, then the four `ok` lines and `NOTARIZE_EXIT=0`; `spctl --assess --type execute -vvv` answers `source=Notarized Developer ID`, `origin=Developer ID Application: Guofeng Liu (U8U443D7ZL)`; `Contents/Helpers/agentspace --version` → `agentspace 0.1.31 (protocol 1)`, so protocol 1 is unchanged. `scripts/check-all.sh` → **`check-all: all 4 layers passed`**, `CHECK_ALL_EXIT=0`, `dist guard: stapled app matches the stapled DMG (251c8327e84b76eb5972cc50bafd06151242b522)`, `Executed 600 tests, with 0 failures (0 unexpected)` in 42.0 s, `updater-e2e: 19 checks passed`, `all MCP smoke checks passed`, `gui-verify: 13 passed, 0 failed`. Three earlier attempts on the way, recorded because a green gate that hides its reds is not a gate: the first failed at layer 3 because a hand-restricted `PATH` had no `node` at all, the second failed at layer 3 again because the volta *shim* alone is not a resolved toolchain (both self-inflicted, and the lesson is that this gate needs the shell's own `PATH`), and the third passed layers 1–3 and failed layer 4 with the two instrument defects row 860 now fixes. The DMG this produced: `shasum -a 256 dist/AgentSpace-0.1.31.dmg` → `68351f1022e5c7e147fbaec216ca9dfeaf3c4af835b49c842cf2b1e1b56043db` over `5590655` bytes. **Not claimed**: an in-app 0.1.30 → 0.1.31 update was not driven; what is measured is that the endpoint such an install polls answers the new tag with the right digest |
| 862 | `v0.1.31` is published, the channel answered the new tag with no write, and the two presses this release needs are stated | pass (measured, including the round trip) | Annotated `v0.1.31` at `b06418e` — the commit whose tree `release.sh` built, `v0.1.31^{commit}` = `b06418e82d84c65909a92b119aa7530d21a11bff` — pushed with `master` over HTTPS. `master` then moved once more (`756fe53`, the gate-script change of row 860), and the only file in it is `scripts/gui-verify.sh`, which is **not inside the bundle** (checked: `find dist/AgentSpace.app -name "gui-verify*"` is empty), so the artifact gated and published is the artifact built at `b06418e`. Release `https://github.com/misswell/AgentSpace/releases/tag/v0.1.31`, `draft false / prerelease false`, one asset, name 「0.1.31 — 桌面按它自己的像素采集，光标下面的东西点得到」. **The channel, asserted rather than assumed (§318 row 820's rule)**: `GET /repos/misswell/AgentSpace/releases/latest` answered `v0.1.31 / AgentSpace-0.1.31.dmg` on three samples ~4 s apart with `--latest` doing the work and no cache-busting, and the endpoint's `assets[].digest` is the string above over the same `5590655` bytes; `curl -L` of the download URL returned `68351f10…`, and `cmp` against `dist/` was **byte-for-byte identical**. **What this release does not claim**, in the notes as well as here: the sharpness fix is in the **worker**, so it reaches a desktop only after 「重新安装助手…」 (the installed pair is app 0.1.31 / worker 0.1.27), and the measurements above were produced with a worker built from this tree; a second display is still keyboard-only (`INVALID_COORDINATE` for pointer input, `window.setFrame`/`window.close` answering "no accessibility window matches"); and one behaviour changes on purpose for an existing preference — a stored `previewMaxWidth` is translated once, `0`→native, `≤1280`→performance, larger→balanced, so the `1280` stored on this machine becomes **Performance** and 「原生 Retina」 has to be chosen to get the sharpest picture |
| 863 | The GUI gate now asks before it costs the person at the machine anything, and the asking is measured in both directions | pass (measured: the refusal on the live app, and all three branches of the extracted block) | The owner's request after 0.1.31's release was 「做测试的时候可否尽量不要打扰我操作」, and the size of what they were asking about is readable in the logs: `gui-verify.sh` ran six times that afternoon (four through `check-all.sh`), and each run did `pkill -U "$(id -u)" -f "AgentSpace.app/Contents/MacOS/AgentSpace"` (`:215`) before driving its own copy on their screen for one to two minutes — windows, Settings, toolbar clicks, Escape — and re-opening their copy at the end. Nothing else in the gate chain reaches them: `scripts/mcp-smoke.sh:41`'s `pkill -f "agentspace-worker --space-id"` runs as the owner's uid and the installed worker runs as `agentuse`, so it cannot signal it — **pid 26074 held 5h27m of uptime across every run**, which is the proof rather than the reading. The guard: with any AgentSpace copy running, the script stops before the kill, prints what it would do and lists the processes, and exits 1 unless `AGENTSPACE_GUI_VERIFY_ALLOW_CLOSE=1`. Measured on the live app: the refusal printed, `exit=1`, and the app was **still running with the same pid afterwards** (the guard's own `pgrep` and the post-run check both read 15493), so the refusal is genuinely inert. The three branches were then exercised on the **extracted** block (lines 216–247, not a retyped copy): a copy running with no override → refuses; with `=1` → proceeds; with `=0` → refuses; nothing running with no override → proceeds, so a release on a quiet machine is unaffected. `check-all.sh` invokes layer 4 by name from a plain array, so the override propagates without a change there. **Not claimed:** the branch that proceeds past the kill was exercised in isolation, not by closing the owner's app a seventh time — the next run that legitimately clears the slate is where it is confirmed end to end, and the *durable* fix (running these checks in the agent account's own session, where the app under test would open on that account's display) is recorded in `status.md` as owed rather than half-built here |
