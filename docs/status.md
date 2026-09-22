# Project status — V3 handoff

Read this first when resuming AgentSpace. The binding product direction is
[`docs/v3-plan.md`](v3-plan.md); detailed historical evidence remains in
[`docs/validation.md`](validation.md).

Last updated: 2026-09-22 on `master`. Current public release: `0.1.28`
(`v0.1.28`, annotated at `b690162` — the commit whose tree the bundle was built
from; the GitHub Release asset reports
`sha256:4417e9395066d61315797866e5630221c8110dd594ca835c25171c788178fd23` over
`5548467` bytes, byte-for-byte the file `check-all.sh` gated and pulled back from
the download URL to prove it, and `releases/latest` — the product's own update
channel — answered the new tag on the first sample without a write (§319 rows
821–831). It ships one change,
and the change is in the CLI that travels inside the bundle. `agentspace scroll
<account> DX DY` named **no point**, so it took the legacy wheel post and moved
exactly as far as doing nothing — while Core, the worker's parser,
`docs/protocol.md`, the viewer and the Fusion router had all carried an anchor for
four releases; the CLI was the one producer hand-building its own dictionary. The
verb now reads `scroll <account> DX DY [X Y]` and encodes through Core's
`InputAction.wireValue`. Measured on one desktop, one box, one worker (pid 96035)
against a **0 px** idle floor: the installed `0.1.26` CLI's
`scroll 0 -5 450 300` answers `{"performed":1}` and moves **0 px**, this one moves
**106,510 px**; an anchor outside any scrollable area (`1500,900`) still moves 0,
which is what makes the number mean *this point scrolled*; and a half anchor
(`0 -5 450`) is refused where it used to answer success — the silent degradation
is how a dead verb stayed shipped for a whole release (`§319 rows 821–823`). The
same pass fixed two gate defects it tripped over: `swift build --product A
--product B` answers 0 having built **one** of them, and a notarization poll that
could not read a status waited forever on the empty string (`§319 rows 827–828`).
What `0.1.28` does **not** close, said plainly: `agentspace input --file` and
`agentspace_input` still accept a point-less scroll, because that is what the v1
wire says and tightening `InputAction.parse` would change a contract every
existing client walks (`§319 row 825`); and `@agentspace/mcp` is not on npm at all,
so the MCP half of this reaches only someone sitting in this checkout
(`§319 row 826`). The previous release, `0.1.27`,
shipped one small change with a loud symptom: updating the worker swapped the
privileged helper by unregistering it and registering again fifteen milliseconds
later, which launchd refuses for a couple of seconds while it finishes taking the
daemon down — so **the first press always failed with `HELPER_UNAVAILABLE` and the
second always worked**. `44dd9d3` had already measured that race (error 1 at
+13 ms, 0 at 2.7 s) and bought off the wait at one of the two swap sites, the
「重新安装助手…」 button; the worker-update site is now on the same
`AppModel.registerDaemon(attempts:)` path, with two source-invariant tests so a
third bare `.register()` cannot appear quietly (§317 rows 813–814). A human's
「取消」 (`-128`) is still never retried. The previous release, `0.1.26`,
shipped three things: the
viewer's hover, drag and scroll now share one Core gesture state machine, first
release to contain it (§314 rows 794–799); wheel scrolling in the worker drives
the Accessibility scroll bar, because a synthetic wheel event enters the
session's stream and is never dispatched to an app (§315 rows 800–804); and the
viewer's default capture width is the source's own pixel size instead of a 1600
resample of a 1920 desktop (§315 row 805). The scroll half of that is now
**measured working on the binaries a user actually gets** — after the owner
updated and pressed 「重新安装助手…」, a scroll naming a point moved a document
149,740 px against a 36–38 px idle floor (§317 row 811, retiring §316 row 808).
`0.1.26`'s remaining scroll gap — a call that names no point
(`§317 row 812`) — is what `0.1.28` above closes; `0.1.26` and `0.1.27` are still
current in every other respect.
The previous release, `0.1.25`, ships one change: the viewer was
destroying and rebuilding its hardware H.264 decoder on every keyframe, twice a
second per stream, and it now rebuilds only when the parameter sets differ
(§313 rows 788–790). The previous release, `0.1.24`, exists
because `0.1.23`'s live view was **black**: the flip §310 row 764 asked for composed its
matrix in the wrong order and drew the desktop *below* the drawable, so the
window showed nothing while every counter the frame engine publishes reported a
healthy stream (§311 rows 774–776). `0.1.23` had been published **with the
physical frame gates still open**, on the owner's instruction, and its notes said
so in their own section rather than implying a desktop that had been looked at.
The previous release, `0.1.22`, fixed the shared-memory name and left
the picture broken one step later: fixing the name only moved the error to
`shared frame notice does not match its mapping` (§309 row 749).
Two causes, both recorded in §309: a shared frame buffer has two sizes — the
logical layout both ends must agree on, and Darwin's page-rounded `st_size` the
kernel reports for the same object — and v0.1.22's viewer laid the region out
from the second one; separately, the worker could allocate a new buffer under a
live connection that never re-sends its descriptor, so the viewer kept reading
the old one. Now one `SharedFrameGeometry` computes every offset at both ends,
`mappedCapacity` is only a read bound, and one `frame.sock` connection carries one
immutable mapping — a resize ends the connection and the reconnect gets a new
descriptor. Neither cause is a Screen Recording, Accessibility, session, socket
permission or Metal problem, and the wire did not move (32-byte notice, 52-byte
header, `protocolVersion 1`).
**Both fixes are in the worker as well as the app**, and publishing never replaces
that worker by itself — the owner's 「重新安装助手…」 did at 18:30 on 2026-09-21,
which left the installed worker at `0.1.23` while `/Applications` held `0.1.24`.
That one-version gap cost nothing measured here: the two tags differ in the worker
by a version string and nothing else (§312 row 783), so §27's "same newest build"
pair was in place in substance. The pair is now matched for real: the owner updated
the App and pressed the button again at 15:20 on 2026-09-22, so `/Applications` is
`0.1.26 / build 383` and the active worker stamps `0.1.26` (§317 row 811).
`0.1.27` and `0.1.28` are published and **not** installed on this machine:
`/Applications/AgentSpace.app` still reports `0.1.26 / build 383` and its bundled
`Contents/Helpers/agentspace` stamps `0.1.26`, re-read here rather than recalled.
Neither release needs 「重新安装助手…」. `0.1.27`'s change is in the App, so
pressing the update is what makes the *next* helper swap a one-press one;
`0.1.28`'s is in the CLI, and that CLI ships **inside** the app bundle, so
「检查更新」 alone replaces the `scroll` verb that was answering 0 px. It also
needs nothing from the worker, and that is checkable rather than assumed: the
installed `0.1.26` worker's own parser already reads `x`/`y` off the wire
(`git show v0.1.26:shared/Core/Sources/AgentSpaceCore/InputActions.swift:175-178`),
which is *how* row 823 could hold the worker fixed at pid 96035 and move only the
CLI.
What that console lock cost was *screenshots*: on a locked console
`screencapture` refuses, System Events vends no windows, and
`scripts/check-all.sh` stops at its own fourth layer (rows 779, 783). The two
instruments that never needed it have now both run — `scripts/frame-benchmark.sh`
(§313 row 789) and the 60-minute `scripts/frame-soak.sh` (§313 row 791) — and
Gates B, F, G, H and I are the ones still open.

The layout fix then reached real pixels — a 0.1.23 app over the *old* 0.1.22
worker drew the AgentUse desktop with no mapping error, because root cause 1 lived
in Core and so in the app (§310 row 763). Having a picture to look at turned up
four more findings, all in §310: the Metal path had been drawing the desktop
**upside down** since the renderer was introduced, and the earlier rows that
recorded a desktop appearing were looking at it (row 764); a stream that switched
to H.264 stopped counting its own capture, so `captureFPS` read 0 on the path the
benchmark measures (row 765); a frame stream outlived its viewer and kept its
shared region mapped — `openStreams: 4` and 30 MB held for one window (row 766);
and the per-connection log line the gates read printed its numbers as `<private>`
(row 767). All three code fixes are in this tree with 545 unit/integration tests
green (row 770); `0.1.23` build 365 is notarized, stapled and installed in
`/Applications` (row 771). The physical gates are still pending, now for a second
reason — the owner's console is locked, so there is nothing to screenshot and the
accessibility tree vends no windows at all, which is why `scripts/check-all.sh`
stops at its own fourth layer (rows 769, 771).

That build then showed the owner a **black** window, and §311 is that story. The
vertical flip row 764 called for was right and its arithmetic was wrong:
`scale(1,-1).translatedBy(0,h)` prepends the translation, so it maps
`y → -(y+h)` and moves a 1280×720 frame to `y ∈ [-1440,-720]` — outside a drawable
that spans `[0,720]`, where `CIContext.render` draws nothing. The written matrix
and the intended one are compared by extent in a scratch program (row 774), so the
claim does not rest on the screenshot. What makes it a lesson rather than a typo is
that no instrument in the frame engine could have caught it: the worker published,
the client received and acknowledged, and `rendered` climbed — because `.uploaded`
means "the command buffer was committed", and on the H.264 path it is asserted
outright with the present result discarded (row 775). Gate A now passes on real
pixels: the fixed build over the same worker measures mean `0.1188` against the
installed `0.0355`, draws the menu bar at the top and the Dock at the bottom, and
changes when the agent's pointer moves (row 776). Resizing keeps real pixels at
every width (row 777) — but what that row read as row 766's leak surviving was a
close-then-reopen with a short overlap, not an orphan: its own stream IDs were both
fresh at every step, which is only possible if the previous pair was released, and
the release is the code path (`FrameServer.swift:106`). §312 row 782 retires that
conclusion and puts Gate E back to "not recorded", and row 781 retires the
`0.1.22`-worker labelling that made it sound unfixable.
The automated half of §26 is green for `0.1.24` (row 778) and `check-all` passes
three of four layers, the fourth having passed standalone on this same tree
twenty minutes before the console locked itself again (row 779). It is green for
`0.1.25` too (row 792), with that fourth layer **deferred rather than refused**:
`gui-verify.sh` opens by `pkill`ing every AgentSpace process this uid owns, which
at release time would have taken the owner's Desktop window — and the instance the
60-minute soak was measuring — down with it.

§313 is two findings from the same hour, and the difference between them is the
method. A report that the shipped viewer **froze** — its copy of the desktop stuck
at 08:28 while the header still read 就绪 — turned out to be a capture of a window
the WindowServer had stopped drawing: `-l` on an occluded window returns its last
cached image, the same window id hashed identically 15 seconds apart, the pixels at
that window's own bounds were the owner's browser, and the cached frame showed the
live-preview switch **off** next to a rendered desktop, which `DesktopViewerView`
cannot produce in a single render (row 787). No renderer code was changed on the
strength of it, and row 775's hole stays open rather than closed. The other finding
needed no screen at all: the log shows the viewer destroying and recreating its
hardware H.264 decoder **every 2.000 s per stream** — 750 such lines in 10 minutes —
because `decode` rebuilt the session for any packet carrying parameter sets, while
the worker attaches SPS/PPS to every keyframe by design with
`MaxKeyFrameInterval = fps * 2` (row 788). The fix rebuilds only when the sets
differ, and it was measured with the same instrument that found it: the two shipped
source files compiled into a headless tool that feeds the real encoder's packets to
the real decoder, where eight keyframes built eight hardware decoders before the
change and two after — the second one because the capture geometry moved (row 790). `scripts/frame-benchmark.sh` did run against the live
pair: 14.4 fps over 2 streams, capture→publish p50 13.8 ms / p95 27.9 ms, worker
2.4% of a core, 10 of 11 verdicts holding — the failure being
`app_and_worker_same_release`, which row 783 already shows is a label and not a
behaviour (row 789). The 60-minute soak then held the same two streams open in all
357 samples: 43,474 frames published at 12.09 fps, worker 2.1% of a core,
`appFDs 105 → 105`, app and worker RSS both *shrinking* by 3.6 MB and 5.8 MB, and
`mappingBytesTotal` flat at 9,668,992 bytes — the number row 766's leak would have
moved (row 791). Reading the log for that same hour puts the decoder defect on the
same scale: **2,011** hardware decompression sessions created and invalidated by the
running app in 60 minutes, ~39 a minute while the desktop changed and 1–8 once the
owner left it still. Which is also why row 791 calls that hour a baseline: it
measures the *unfixed* client. `0.1.25` is notarized, stapled, Gatekeeper-clean, its
dist app's CDHash identical to the DMG's inner copy, and layers 1–3 of `check-all`
pass on it — but it was never launched, and `gui-verify` was not run, because its
first act is to `pkill` every AgentSpace process this uid owns, which would have
killed both the owner's window and the soak's subject while `HIDIdleTime` read
0.044 s. Deferred, not passed (row 792). `0.1.25` was then published against
exactly that evidence, no more (row 793): the tag sits on the commit whose tree
the bundle was built from, and the release's stored `assets[].digest` — the value
the in-app updater compares a download against — equals the hash of the gated DMG.

## Product in one sentence

AgentSpace connects an AI agent to an existing standard macOS account and its
independent Aqua desktop. It never creates or deletes a macOS user.

The object chain is:

```text
Existing macOS account → attached AgentAccount → Aqua session → worker → desktop/runtime
```

AgentSpace is not a VM and never falls back to controlling the human user's
session.

## V3 implementation state

Phase 1 (attach existing account) is implemented in this tree:

- `AccountDiscovery` enumerates local passwd records and offers only standard
  users with uid >= 500, a `/Users/...` home, no admin-group membership, and
  excludes the current user and already attached usernames.
- `AccountAttachService` validates, prepares workspace/runtime, installs the
  root-owned worker, attempts to start it when an Aqua session exists, and
  saves the existing account as an `AgentAccount`. If macOS has not created the
  account's home directory yet, attach succeeds in `needsLogin` and the GUI's
  **Finish setup** action retries installation after the first GUI login.
- Attach rollback removes a created worktree, installed worker and root-owned
  runtime when a later step fails.
- Detach stops/removes the worker, removes its exact runtime through a typed
  helper operation, removes an AgentSpace-created worktree, and removes only
  the registry record. It never logs out, deletes, or edits the macOS user or
  its home.
- GUI account creation/deletion controls are now account selection,
  **Connect Account**, and **Disconnect Account**.
- The New Agent picker always exposes **Refresh accounts**, so an account added
  or removed in Users & Groups can be discovered without closing the wizard.
- The connected account intentionally receives only the background worker, not
  a second AgentSpace app. Its Accessibility and Screen Recording grants are
  given in that account's own System Settings after the worker is installed;
  the agent card now has buttons that open each privacy pane in that account's
  session, so the main account never opens the wrong System Settings window.
- Desktop Viewer has an explicit **Close** action (and ⌘W/ Escape cancellation)
  even when the worker is offline or a permission is missing.
- CLI primary verbs are `attach` and `detach`; legacy `create`/`delete`
  spellings remain aliases for compatibility but use V3 semantics.
- Legacy helper wire cases `createUser` and `deleteUser` still decode at
  protocol version 1, but validation and dispatch always refuse them. Their
  `sysadminctl`/directory-service mutation implementations are gone.

The runtime layout is now:

```text
/Library/Application Support/AgentSpace/
  Worker/versions/<version>/agentspace-worker   root:wheel 0755
  Worker/active/agentspace-worker               root:wheel 0755
  Runtime/<account-id>/                         0700 + inheritable ACL
  Spaces/index.json
  Logs/
  Worktrees/
```

Each account runtime grants full inherited access only to the controller user
and attached user. The worker verifies owner, mode and both ACL entries before
binding its socket. The V2 registry under `/Users/Shared/.AgentSpace` is read as
an upgrade source when the V3 registry does not yet exist; all later saves go to
the V3 root.

## Existing product capabilities retained

- Unix-socket JSON RPC with session-token authentication.
- Fail-closed session ownership checks; input is refused on the physical
  console and never redirected to the human session.
- ScreenCaptureKit desktop and window capture streamed over the binary frame
  engine (shared-memory damage plus adaptive H.264). The live view has no
  screenshot fallback: if the stream is gone the view says so instead of
  quietly showing an old picture. `screenshot` stays a separate one-shot
  capability for agents and for the manual snapshot button.
  Keyboard/mouse input, application control and guarded command execution.
- CLI and MCP account/status/desktop/app/exec surfaces. Old wire method names,
  `agentspace_*` MCP tools, registry keys and deep-link compatibility remain.
- English and Simplified Chinese localization with automated key parity.
- Signed, notarized and stapled release pipeline.
- Three reported permissions: Accessibility and Screen Recording gate the
  desktop, optional Full Disk Access gates this account's own protected folders.
  Each is detectable without prompting, has its own in-app authorization button,
  and is reported by GUI, `agentspace status` and `agentspace doctor`.

## Online update

Settings' last tab, *Update* (`SoftwareUpdateView`), over
`apps/AgentSpace/Services/SoftwareUpdate.swift` and two new SwiftPM products:
`AgentSpaceUpdaterSupport` (every decision, as testable functions) and
`agentspace-updater` (the only step that cannot run inside the app being
replaced). `docs/UPDATE_CHANNEL.md` states the whole contract; validation §302
records what was measured.

The shape a reviewer needs:

- Release metadata comes from GitHub only — the version, the archive URL, and
  GitHub's own `sha256:` digest for the asset.
- Nine checks run before anything is replaced, ending at the designated
  requirement (so a release cannot silently cost the user their TCC grants) and
  `spctl`. A failure at any of them leaves the running app untouched.
- Only `/Applications/AgentSpace.app` may self-replace. A copy running from
  `dist/` or a translocated path says so and stops.
- The updater cannot be handed a bundle that is not AgentSpace: after the swap
  it re-reads what landed and puts the backup back if it is not the app.
- An update changes the bundle, never the root helper or the installed worker.
  Those move only when the user presses 「重新安装助手…」.
- `scripts/updater-e2e.sh` gates the install step offline; a test instance
  launched with `AGENTSPACE_ROOT` set makes no network call at all.

## Still missing

V3 does not make the later roadmap appear by renaming Phase 1:

1. **Agent runtime manager / profiles** — compose startup apps, workspace and a
   command such as Claude Code into one Start action. The low-level launch and
   exec RPCs already exist.
2. **Binary frame-engine real-machine acceptance** — Desktop and Fusion now
   share one persistent, authenticated `frame.sock` client. Local display and
   window capture use ScreenCaptureKit; sparse damage travels through a
   two-slot anonymous shared-memory region with exact-sequence ACKs, while
   sustained high damage may switch to low-latency H.264. The hot path no
   longer polls JPEG/base64 over JSON or writes frames to disk. Resize and zoom
   reopen a debounced stream at the requested pixel size, and a Metal renderer
   keeps one texture with an in-memory BGRA fallback. §305's frame-engine round
   closed the failure and measurement halves of that sentence: a capture that
   stops by itself now ends the connection instead of freezing the last frame,
   an idle stream is distinguished from a lost one by a 2-second heartbeat with
   an 8-second stale deadline, the H.264 encoder is created only when a frame
   actually needs it, a viewer that stops reading is dropped after a one-second
   send deadline rather than blocking the worker, and `frame.stats` reports
   measured counts, rates and percentiles for each open stream.
   `scripts/frame-benchmark.sh` and `scripts/frame-soak.sh` turn that into
   numbers. What is still owed is the physical half — the measurement below, on
   a machine whose app *and* installed worker both speak for this build; code
   and unit evidence are recorded in §304 and §306.
   **That machine exists and then moved twice more**: §307 row 728 had this Mac on
   app 0.1.21 + worker 0.1.21 with `preview AgentUse --stats` answering real
   fields; §308 row 747 had app 0.1.22 over a 0.1.21 worker, which reproduces the
   shm-name failure on screen. The owner's 「重新安装助手…」 then put a **0.1.22
   worker** under the app, and the Desktop's line changed to
   `shared frame notice does not match its mapping` — §309 row 749, and §309's
   whole subject. So the benchmark's blocker is no longer "the worker cannot name
   its buffer"; it is "the two ends must read one buffer the same way", which is
   what 0.1.23 changes. §13's static numbers, §27's old-vs-new table and the
   soak's drift numbers come after an app *and* worker at 0.1.23, and §309 row 762
   is where they get recorded rather than promised.
   **A capture-buffer shape defect was found and fixed here (§320 rows 832–837).**
   The viewer asks for a box shaped like *its window*, ScreenCaptureKit scales the
   picture into that box without distorting it and pads the rest with transparent
   black, and the only size either end is told is the buffer's — so the picture
   arrived floating between 157-pixel pillars and every click the viewer resolved
   was off by up to **236 points of a 1920-wide desktop**, zero at the centre and
   worst at the sides. `CaptureSizing` (Core) now reconciles request with subject
   once, where both are known, and the fix is wire-free because `start()` already
   reports the resolved size. Measured live on the shipped worker before the change
   (`mappingBytes 5,564,544` = 1280×543 for a 1920×1080 display) and measured again
   with a scratch ScreenCaptureKit probe in the agent session, which returns 314
   fully-black columns for the box the shipped sizing asks for and **0** for the
   fitted one. Still owed on a real machine, for the same reason §315 row 804 and
   §316 row 808 are: this is the worker, and the installed worker is `0.1.26`, so
   the end-to-end click needs 「重新安装助手…」 before it can be called verified.
3. **Real-machine acceptance** — install the new worker into the already
   connected standard account,
   enter its Aqua session, grant Accessibility and Screen Recording, prove the
   worker online, and complete the Desktop and Fusion TextEdit gates while the
   main desktop is unaffected. Two Fusion checks are owed by validation §296:
   input against two overlapping windows of one app, and a text selection or
   slider driven through a proxy. Six more are owed by §298, all of them the
   physical half of a claim its code half already passed:
   - **A — Desktop isolation:** the agent's desktop opens and operates while the
     human's own windows never move.
   - **B — single-window Fusion:** one proxy shows exactly one agent window,
     never the whole display.
   - **C — two windows of one app:** two proxies drive their own windows, so
     input cannot land on a sibling.
   - **D — drag and scroll:** a TextEdit selection plus a trackpad scroll in the
     same run (rows 629–630).
   - **E — worker restart:** proxies rebuild, and a human-held button keeps
     automation at `INPUT_BUSY_BY_HUMAN` for the whole press (row 624).
   - **F — fast user switch:** the moment the agent's session is the console,
     capture and input fail closed instead of following the person.
4. **Wheel scrolling inside an agent session** — §314 row 798 found scroll dead;
   §315 found why, and the reason is not in this product's event code. A
   listen-only `CGEventTap` inside the agent session reads every posted scroll
   event back with its fields intact — `.line`, `.pixel`, `IsContinuous`, a
   `Began → Changed → Ended` phase chain — so the events *do* enter that
   session's stream, while the system cursor is verified at the same point by
   `CGWarpMouseCursorPosition` and eight shapes still move zero pixels against a
   `cmd+Down` control of 59,576. The window server accepts them and never
   dispatches them to an app. The channel that does work is Accessibility: the
   scroll area reports `AXSize` 656×390 over `AXContentSize` 656×5200, and
   writing its `AXVerticalScrollBar` value moved that document **35,908 pixels**
   where every event shape moved none. `InputSynthesizer`'s `.scroll` now drives
   the scroll bar first when the caller supplied a point, with the step derived
   from those two attributes (`ScrollMechanics`, 6 tests) rather than a guessed
   pixel count, and keeps the wheel post for a session that is the console.
   **The shipped path now works, measured through the product's own binaries**:
   after the owner updated the App and pressed 「重新安装助手…」, the active worker
   stamps `0.1.26`, and a scroll that names a point moved the document
   **149,740 px** where the idle floor is 36–38 px (`§317 row 811`, which retires
   row 808's PENDING). **One of the two things owed is now paid**: a scroll call
   that named no point used to be uncovered entirely, because `agentspace scroll
   <space> DX DY` put only `dx`/`dy` on the wire and so still took the legacy
   wheel post — measured on those same shipped binaries at **38 px**, i.e. the
   floor (`§317 row 812`). `0.1.28` gives the verb an anchor
   (`scroll <account> DX DY [X Y]`) and routes the CLI through Core's
   `InputAction.wireValue` instead of a hand-built dictionary; on the same
   desktop with the same worker (pid 96035) the installed CLI's
   `scroll 0 -5 450 300` moves **0 px** and this one moves **106,510 px** against
   a **0 px** idle floor, an anchor at `1500,900` — outside any scrollable area —
   still moves 0, and a half anchor is refused where it used to answer
   `performed: 1` (`§319 rows 821–823`). What is *still* owed here: a delta
   counted in *lines* against a fraction of a *document* is an approximation —
   the feel needs a human hand on a trackpad, not another frame diff — and
   `agentspace input --file` still accepts a point-less scroll because that is
   what the v1 wire says (`§319 row 825`). The same session's report that the
   reinstall needed two presses is `§317 row 813`: the worker-update swap site
   registered a daemon fifteen milliseconds after taking it away, which is the
   race `44dd9d3` measured and paid for at only one of its two call sites.
   `0.1.27` routes both through `AppModel.registerDaemon(attempts:)` and pins it
   with two source-invariant tests (`§317 row 814`); no third bare `.register()`
   can appear quietly. What is *not* claimed is a live one-press swap on this
   machine — the helper is already current there, so proving it means waiting for
   the next real swap rather than spending a second admin prompt on the owner's
   screen.
5. **Multi-account soak** — two attached accounts working concurrently while
   the human continues normal work.
6. **Fusion V2 surfaces** — transient windows, explicit clipboard bridging and
   restricted transfer-directory drag and drop remain intentionally deferred.

## V4 Fusion implementation state

The first Fusion vertical slice is now implemented in this tree:

- `preview.frame` re-checks the live session on every pull and tears capture
  down on console, indeterminate or no-WindowServer transitions.
- `RemoteWindow` uses `pid + windowID + generation`; `window.list` exposes only
  visible layer-0 regular-app windows discovered through public APIs.
- `window.stream.*` remains available for compatibility, while the GUI captures
  one desktop-independent `SCWindow` through the binary frame engine at the
  panel's pixel size. `window.input` accepts
  window-relative fractions and maps them against the worker's current global
  window frame, after raising *that* window so input cannot land on a sibling.
- **Open Apps** creates one native proxy `NSWindow` per remote window. Proxy
  position and size remain local; minimizing stops capture, restoring restarts
  it, and closing maps to a unique AX window or refuses an ambiguous match. A
  proxy whose stream stops answering — most often a restarted worker — rebuilds
  itself instead of freezing on the last frame.
- Pressing and travelling in a proxy is one `drag` action; pressing and releasing
  in place is a click. Direct proxy interaction owns a renewable five-second
  human input lease, but only deliberate interaction claims it — a cursor
  crossing the window does not pause the agent. Normal automation input returns
  `INPUT_BUSY_BY_HUMAN` during that interval. The lease is now taken when the
  button goes *down*, through the additive `window.human.claim`, and renewed
  while it is held; the passing cursor sends no request at all, and a hover that
  does arrive is forwarded only inside someone's live lease and without
  activating or raising anything (§298 rows 620–624).
- A gesture's button, click count and modifiers ride the same vocabulary
  `agentspace input` uses: the fraction→point mapping moved into Core as
  `RemoteWindowInput` and delegates to `InputAction.parse`, which also caught
  that a proxy drag was about to be rejected for naming its press `x` instead of
  `fromX` (§298 row 628). Trackpad deltas are accumulated into whole lines
  instead of rounding to zero, and the proxy's scroll now carries them at all.
- Pointer travel is state, not a gesture: `PointerTravelCoalescer` keeps one
  request in flight and only the newest position behind it, drained by the frame
  timer, so a wave across a proxy cannot queue a hundred stale positions ahead
  of the click that ends it.
- An abandoned stream stops itself. `PreviewController` arms a real idle ticker
  when the source starts and reaps the stream on its own queue — no second pull
  required, one stop per stream, no residue after a failed start (§298 rows
  618–619).
- The window-list poll is a link with states (`connected`, `reconnecting`,
  `suspended`, `console`, `permissionRequired`) and a 1→2→5 s ladder in
  `FusionLinkPolicy`. `SESSION_IS_CONSOLE` and `NO_WINDOW_SERVER` are reported
  as what they are and are never a reconnect storm; a refused poll suspends
  every live proxy instead of leaving each one pulling, and `FusionSession`
  stopped discarding its failures.
- A window that is not moving costs one short line: `window.stream.frame` takes
  an optional `seenSequence` and answers `unchanged` + `sequence` when the
  capture has not advanced, while the pull itself still renews the idle clock.
- Settings now separates Accounts, Permissions, Performance and Advanced.
- The fixed `FrameHeader`, `frame.open|close|configure|requestFull|stats`
  additions, authenticated binary socket, SCM_RIGHTS mapping handoff, anonymous
  two-slot shared memory, exact ACK back-pressure, dirty-region coalescing,
  adaptive H.264 path and reconnect generation checks are implemented and
  tested. Production peer authorization fails closed when the root-authored
  controller identity is absent. The physical cross-session and fast-user-
  switch acceptance remains pending until the new worker is installed (§304).

The code gates can verify protocol, lifecycle and mapping. The defining
TextEdit cross-session acceptance still requires the attached account's real
Aqua session and TCC grants, and must not be represented as passed until that
manual run is recorded in `docs/validation.md`.

## Measuring the frame engine

`scripts/frame-benchmark.sh` samples a live stream for a window (default 60 s):
CPU and resident size of both processes, descriptor counts, every `frame.stats`
field, and the byte totals of the directories a frame path could plausibly write
into. `scripts/frame-soak.sh` is the same sampler at hour scale, with drift
verdicts. Both write JSON under `artifacts/` and end in one verdict per property
— §13's quiet desktop, the lazy encoder, back-pressure, the shared-memory budget,
whether the CPU copy is the hotspot.

They need a real stream: no app running, no frame stream open, or a worker too
old to answer `frame.stats` each exits 3 with the reason, because "not measured"
must not be readable as "passed". `--mode static` is §13's claim as a gate, and
`--seconds`/`--minutes` are the short runs that check the arithmetic without
spending an hour.

## Required verification

Use the repository gates, not a remembered test count:

```bash
env PATH=/usr/bin:/bin:/usr/sbin:/sbin swift test
(cd packages/agentspace-mcp && npm test)
scripts/mcp-smoke.sh
scripts/updater-e2e.sh
scripts/check-all.sh
```

For official `dist/`, always run `scripts/release.sh` and then
`scripts/notarize.sh`; `check-all.sh` intentionally rejects an unstapled app.

`scripts/gui-verify.sh` refuses to run when the console is not presenting
windows — locked screen, fast-user-switched away, or session state it cannot
read — because all of its checks read an accessibility tree that a locked
session leaves empty. That refusal (`exit 1`, "the console session's screen is
LOCKED") is validation §297: it is an environment verdict, not a build verdict,
and it is a different result from failing every check.

The unlocked run is established: 8/8, with the wizard reaching `step 2`, on the
published 0.1.18 bundle (§301 row 654). Getting there exposed three defects
in the gate itself. It addressed the app by *process name*, so an installed copy
in `/Applications` let it score 0.1.12 while claiming to test the build under
test, and it resolved controls against `window 1`, whose order the window server
chooses (§299 rows 639-640). And its EXIT hand-back relaunched the owner's own
copy with `open`, which passes the caller's environment — so their window read
the gate's throwaway registry and reported their attached Agent as deleted
(§300 row 646, which overturns §48 row 150). Every `open` in the script now runs
with `AGENTSPACE_ROOT` and `AGENTSPACE_GUI_APP` removed, and the hand-back is
followed by a sweep that names any surviving copy still carrying them.

A fourth defect class showed up while 0.1.21 was being gated: two runs of
`scripts/gui-verify.sh` on the *same notarized bytes* failed two *different*
checks. Both were single looks taken right after an asynchronous re-layout (the
Settings window building its tabs, the wizard re-flowing its footer once an
account is chosen), and the same artifact answered correctly the next time it
was asked. The rule that came out of it: **a `gui-verify` failure that moves on
a re-run was the verifier, not the build** — so those lookups now poll for the
control and still assert the exact value (§307 rows 721-722).

One reading still disagrees: the gate has settled at two windows on some runs
while ten cold launches measured outside it gave one window every time (§299 row
642). §300 row 651 names the candidate mechanisms — a second copy of the shared
bundle id on the desktop, and `keystroke` being focus-targeted — without yet
reproducing them; the check prints its sample trace rather than a bare number.
The same class produced a second reading while §302 was checked: a *temporary*
bundle in `/tmp` that shares the installed copy's bundle id settled at **zero**
main windows on two runs, while `dist/AgentSpace.app` on the identical script
gave one. Only the Settings-window checks were scored there, so the update-pane
result stands and the four main-window checks in that run are unproven rather
than failed (§302 rows 663-664).

The gate now also asserts the two product behaviours §300 fixed: the empty
dashboard names the registry file it read when `AGENTSPACE_ROOT` is set, and the
New Agent wizard waits for Directory Service instead of claiming no standard
users exist. Both shipped in 0.1.18 (§301); they are not in 0.1.17 or earlier.

§302 adds five checks for the update pane: the tab is reachable, the check
control is present and enabled, and the control that could replace the running
app is **not on screen at all** until a release has been verified. They pass
against a bundle built from this tree and fail against 0.1.18's `dist/`, which
is the correct verdict for an artifact that has no such tab — so `check-all.sh`
now assumes `dist/` was built from the tree it is gating, which is what
`scripts/release.sh` produces.

A fifth defect class closed §300 row 651's open question. While 0.1.27 was being
gated, layer 4 failed four in-gate runs on the *same notarized bytes* that passed
13/13 standalone: twice `no name field` in the wizard, twice eight Settings
controls reporting empty. Both phases opened their window by *typing* a shortcut (`⌘N`,
`⌘,`), and a keystroke is delivered to whatever the console session last focused —
on a shared machine that is WeChat or Chrome, not the pid the script holds. The
Settings opener was worse than merely mis-targeted: it was a one-shot heredoc with
`>/dev/null 2>&1`, so the error that said the app never fronted was discarded and
nine absent controls got reported as nine empty attributes. Both now *ask* the menu
bar — walk the app's `menu bar items` and click the item whose
`AXMenuItemCmdChar` is `n` (or `,`) — which is localization-proof too, since this
machine's UI is Chinese and a menu title would not match. Each phase prints which
channel it used (`settings opener: clicked, windows=2`, `wizard: step 2`) instead
of a bare failure. The lesson generalizes past this script: when a layer-4 verdict
moves between runs, suspect a focus or timing assumption in the verifier before
suspecting the build, and never let a diagnostic channel discard its own error
(§318 rows 816–818, `df6b193` touches `scripts/gui-verify.sh` only).

## Compatibility rules

- Registry top-level key remains `"spaces"`; existing records decode without
  migration. New `homeDirectory` and `runtimeRoot` are optional.
- Protocol version remains 1 for compatible additions. Wire methods are not
  renamed.
- Pre-V2 CLI verbs and every `agentspace_*` MCP tool remain available.
- `agentspace://agent/<uuid>` is generated; the legacy `space` host resolves.
- English source text is the localization key and every key exists in both
  localization tables.

## Safety rules that must not regress

- No user creation or deletion. No `sysadminctl` mutation path.
- No fallback into the current user's desktop.
- No metric reads a macOS-protected folder: the disk walk skips
  `FilePrivacy.protectedSubpaths` unless Full Disk Access is granted, so a
  number never costs the user a privacy dialog in an unattended session.
- No generic shell or arbitrary-path privileged helper operation.
- Helper paths are derived from validated account IDs and fixed roots.
- Runtime access is verified before the worker binds.
- Work only in this checkout on `master`; do not create another worktree.

## Important paths

- Core: `shared/Core/Sources/AgentSpaceCore`
- GUI: `apps/AgentSpace`
- Worker: `native/AgentSpaceWorker`
- Privileged helper: `native/AgentSpacePrivilegedHelper`
- CLI: `native/AgentSpaceCLI`
- MCP: `packages/agentspace-mcp`
- Security model: `docs/security.md`
- Wire protocol: `docs/protocol.md`
- Update channel: `docs/UPDATE_CHANNEL.md`
- Validation evidence: `docs/validation.md`
