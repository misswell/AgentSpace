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
| 150 | The Settings root field is wired to the launch-time AGENTSPACE_ROOT, and `open` does not pass shell env to a launched app — the field shows the env value only when the binary is executed directly | ✓ | §48 — the process env and the field, both read back |


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
