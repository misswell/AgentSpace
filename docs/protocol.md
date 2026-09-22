# Protocol

`protocolVersion = 1`

AgentSpace has one wire contract. The GUI, the CLI and the MCP server all speak
it, so there is one core API rather than three implementations that drift
(plan §49).

Transport is a **unix domain socket**, never a localhost HTTP port: a unix socket
cannot be reached from off the machine, and its directory ACL is a second lock
behind the session token.

```
/Library/Application Support/AgentSpace/
  Runtime/
    <space-uuid>/
      worker.sock        the socket
      worker.pid         pid of the listening worker
      token              the 256-bit session secret, mode 0600
      status.json        last known status, written by the worker
      worker.lock        flock'd by bind() so a second worker fails fast
      worker.out.log     the worker's stdout, via the LaunchAgent
      worker.err.log     the worker's stderr, via the LaunchAgent
      space.json         written by the privileged helper (roots, main user)
      screenshots/       where captures land by default
  Spaces/index.json      the Space registry
  Logs/
```

`/Users/Shared` rather than `/tmp` because it survives a reboot — which is
exactly when a stale socket would otherwise be mistaken for a live one.

---

## Framing

One JSON object per line, UTF-8, `\n` terminated. **One request per connection:**
the client sends one line, the worker answers with exactly one line, then closes.

| Limit | Value |
|---|---|
| Max request | 1 MiB (`BAD_REQUEST` beyond, thrown *while* reading so the memory is never spent) |
| Max response | 64 MiB (screenshots are base64 here) |

## Request

```json
{
  "protocol": 1,
  "requestId": "8B1B0C0A-...",
  "token": "9f2c…64 hex chars…",
  "method": "screenshot",
  "params": { "maxWidth": 1280 }
}
```

`token` is required for every method except `hello`. `hello` answers without one
because it is how a client discovers that a token is required; it returns only
non-sensitive liveness facts.

## Response

Exactly one of `result` / `error` is present.

```json
{ "id": "8B1B0C0A-...", "ok": true, "result": { "performed": 3 } }
```

```json
{
  "id": "8B1B0C0A-...",
  "ok": false,
  "error": {
    "code": "SESSION_IS_CONSOLE",
    "message": "refusing to inject input: the 'Frontend' session is currently on the console, so events would land on the user's own screen.",
    "recoverable": true
  }
}
```

`recoverable` is derived from the code, not chosen per call site, so a hard
failure cannot be accidentally advertised as retryable.

---

## Methods

### `hello` — token exempt

```json
{
  "protocol": 1,
  "worker": { "version": "0.1.0", "pid": 55007 },
  "space": { "id": "…", "name": "Frontend" },
  "user": { "uid": 502, "name": "_agentspace_a37f91", "home": "/Users/_agentspace_a37f91" },
  "session": { "verdict": "usable", "onConsole": false, "permitsInput": true, "windowServer": true },
  "display": { "width": 1920, "height": 1080, "pixelWidth": 3840, "pixelHeight": 2160, "scale": 2 },
  "permissions": { "screenRecording": true, "accessibility": true, "fileAccess": false },
  "requiresToken": true
}
```

`session.verdict` is one of `usable`, `isConsole`, `noWindowServer`,
`indeterminate`. Only `usable` sets `permitsInput: true`.

`permissions.fileAccess` is Full Disk Access — the grant that decides whether
this account's worker may read the folders macOS protects. It is **optional**:
`screenRecording` and `accessibility` gate whether the desktop can be operated at
all, and only those two move `state` to `needsPermission`. A worker from before
this field existed simply omits it, which a client must read as "never probed",
not as "denied".

### `status`

Params: `{ "resources": "full" | "disk" | "summary" }`. `full` adds a `resources`
block (one `ps` fork); `disk` adds the same block plus the home-directory walk;
`summary` — the default — forks nothing, because the UI polls this every few
seconds and §53 wants that to be nearly free.

```json
{
  "space": "Frontend", "spaceId": "…", "uid": 502, "user": "_agentspace_a37f91",
  "state": "ready", "stateLabel": "Ready", "acceptsInput": true,
  "worker": true, "workerPid": 55007, "workerUptimeSeconds": 412,
  "screenRecording": true, "accessibility": true, "fileAccess": false,
  "session": { "verdict": "usable", "onConsole": false },
  "display": { "width": 1920, "height": 1080, "pixelWidth": 3840, "pixelHeight": 2160, "scale": 2 },
  "workspace": { "confined": true, "allowedRoots": ["…"], "writableRoots": ["…"] },
  "resources": { "cpuPercent": 8.4, "memoryBytes": 1460000000, "processCount": 47 }
}
```

Only `"resources": "disk"` runs the walk, and the block then also carries:

```json
"diskBytes": 4823482368, "diskTruncated": true, "diskExcludesProtected": true
```

`diskBytes` is `null` when the walk did not run (never a `0`, which a client
would read as a measured empty home), `diskTruncated` means the file budget was
hit, and `diskExcludesProtected` means the walk stopped at the macOS folder gates
because this process has no Full Disk Access — so the figure is a lower bound for
part of the home, not the home. `diskTruncated` and `diskExcludesProtected` are
omitted rather than sent as `false`. See
[`security.md`](security.md) for why a metric is not allowed to enter
`Documents`.

### `screenshot`

Params: `maxWidth` (positive int), `display` (1-based; 1 is the main display),
`path` (confined to the workspace when one is declared), `inline` (bool).

```json
{
  "path": "/Library/Application Support/AgentSpace/Runtime/…/screenshots/shot-1789712260381.png",
  "width": 640, "height": 360,
  "pixelWidth": 3840, "pixelHeight": 2160,
  "scale": 2
}
```

`width`/`height` describe the file that was written (after any downscale) and are
read back out of the PNG's IHDR rather than remembered from the request.
`pixelWidth`/`pixelHeight` describe the full framebuffer.

With `inline: true` the result additionally carries `pngBase64`.

**Checked before anything else:** `CGPreflightScreenCaptureAccess()`. Without the
grant the call fails `SCREEN_RECORDING_DENIED` *without invoking
`screencapture`*, because running it unpermitted can raise a TCC prompt in a
session nobody is looking at.

**Coordinates.** `scale` is the display's backing scale. Input coordinates are
**points**:

```
pointX = pixelX / scale
pointY = pixelY / scale
```

Measured on macOS 27.0, `CGDisplayPixelsWide()` returns the *point* width on a
scaled Retina display, so the scale comes from
`CGDisplayCopyDisplayMode().pixelWidth / .width` instead. See
`docs/validation.md` §2.

### `input`

```json
{ "actions": [ … ] }
```

| type | fields |
|---|---|
| `move` | `x`, `y` |
| `click` | `x`, `y`, `button` (`left`\|`right`\|`middle`), `count` (1–5), `modifiers` |
| `doubleClick` | as `click`, with `count` forced to 2 |
| `rightClick` | as `click`, with `button` forced to `right` |
| `drag` | `fromX`, `fromY`, `toX`, `toY`, `button`, `modifiers` |
| `scroll` | `dx`, `dy`, and the point `x`, `y` to scroll at — without the point nothing moves in a background session (§315) |
| `type` | `text` |
| `key` | `key` (`"cmd+l"`) **or** `keys` (`["cmd","l"]`) |
| `sleep` | `ms` (0–30000; alias `wait`) |

### Binary Frame Engine — `frame.*` + `frame.sock`

Current Desktop and Fusion clients call additive protocol-v1 methods
`frame.open`, `frame.close`, `frame.configure`, `frame.requestFull` and
`frame.stats`. `frame.open` names a `display` or `(pid, windowId, generation)`
window target plus FPS and target pixel dimensions; it returns a stream UUID
and the per-account `Runtime/<id>/frame.sock` path.

The frame socket is one persistent Unix connection. Its first line is a
`FrameHello` containing protocol version, account UUID, stream UUID, token,
client pid and capabilities. The worker checks all of those plus `getpeereid()`
against the configured controller UID before returning its instance UUID,
session generation and modes. A wrong token, UID, account, stream or protocol
closes the connection without a frame.

For the normal `sharedBGRA` mode the worker creates a random POSIX shared-memory
object at mode 0600, maps and immediately unlinks it, then passes the only
controller descriptor with `SCM_RIGHTS`. The socket carries fixed 52-byte
`FrameHeader`s and small `SharedFrameNotice`s; pixels never enter JSON or the
socket. Two slots are owned by socket ACKs. If both are busy, the worker keeps
only the newest CVPixelBuffer and unions damage; it never overwrites a reader
or queues historical frames. A delta names `baseSequence`; mismatch requests a
full frame. New connection, resolution, worker instance or session generation
also requires a full baseline and a new mapping.

ScreenCaptureKit supplies BGRA CVPixelBuffers and dirty rectangles to the same
CaptureEngine for displays and windows. Static frames publish no pixel payload.
Sustained high damage switches to low-latency VideoToolbox H.264 (no frame
reordering); the app decodes to a Metal-compatible CVPixelBuffer. Returning to
delta always begins with a full BGRA baseline. Desktop and Fusion both render
through one persistent Metal texture and never create an NSImage per frame.

Every captured/published frame re-checks the live session verdict. Console,
indeterminate or missing-WindowServer state stops capture and refuses output;
there is no fallback to the controller's desktop or to a disk screenshot loop.

### Legacy live preview — `preview.start`, `preview.frame`, `preview.stop`

Compatibility surface for clients predating the Frame Engine. It remains a pull
model that fits the one-request-per-connection protocol. The current GUI does
not call it. `preview.start { maxFPS }` → `{ streaming, fps }`;
`preview.frame` → `{ inline }` (base64 JPEG of the newest frame — frames captured
faster than the client pulls are dropped, newest wins); `preview.stop` closes it.

- `preview.start` is refused like every observation method: `SESSION_IS_CONSOLE`
  on a console-session worker, `SCREEN_RECORDING_DENIED` without the grant.
- A stream nobody pulls stops itself after ~10 s (`PREVIEW_NOT_RUNNING` on the
  next pull) — a viewer that crashes must not leave the worker capturing forever.
- `preview.frame` without a stream is `PREVIEW_NOT_RUNNING`, never a silent
  success.
- Every `preview.frame` pull re-evaluates the live session verdict. A Fast User
  Switch to the agent account, an indeterminate verdict, or loss of its
  WindowServer stops the `SCStream`, discards the last frame, and refuses the
  pull. Start-time safety is not treated as a lifetime grant.

### Fusion windows — `window.*`

`window.list` returns the visible layer-0 standard application windows in the
worker's Aqua session. Each record carries `id`, `pid`, app metadata, title,
frame, visibility and `generation`. The identity for every later call is the
triple `{ windowId, pid, generation }`. The catalog advances the generation
when it observes a `(pid, windowId)` disappear and later reappear, so a stale
identity cannot authorize that observable reuse. Public CGWindow metadata
cannot prove replacement that begins and ends entirely between two catalog
snapshots; destructive AX actions therefore also require a unique live
pid/title/frame match and refuse ambiguity.

The legacy `window.stream.start`, `.frame` and `.stop` use that identity. Capture uses
`SCContentFilter(desktopIndependentWindow:)`, so the returned JPEG is the
selected application window rather than the whole agent display. Like Desktop
preview, every frame pull is fail-closed and the controller retains only the
latest frame.

`.frame` also answers with `sequence`, the number of frames that stream has
captured. A client that already drew frame *N* may send `seenSequence: N`; if
nothing newer has been captured the answer is `{ "unchanged": true, "sequence":
N }` with no `inline`, so a window that is not moving stops costing a JPEG
encode, a base64 round trip and an image decode. The pull itself still happens,
because the pull is what keeps the stream's idle watchdog from reaping it. A
client that sends no `seenSequence`, and a worker too old to answer one, both
keep receiving every frame as before.

`window.input` takes the identity plus one action. Pointer actions use
`xFraction` / `yFraction` in 0...1; the worker re-reads the current global
window frame immediately before posting the event, so a moved remote window
does not make a cached coordinate dangerous. Past the geometry the action is the
**same** object `input` accepts — `button`, `count`, `modifiers`, `dx`, `dy` —
because the worker resolves the fractions and hands the result to the same
parser, rather than maintaining a second dialect. `type` and `key` reuse the
normal input action shapes. Returns `{ "performed": N }`.

Direct Fusion interaction holds a five-second human input lease; ordinary
`input` calls during that lease fail `INPUT_BUSY_BY_HUMAN`. The lease is claimed
by a deliberate gesture, and `window.human.claim` lets a proxy claim it when the
button goes *down* instead of when the finished gesture is posted. It takes the
identity and nothing else, performs no input, activates nothing, and answers
`{ "claimed": true, "remainingSeconds": S }`.

A `move` with no button held — pointer travel across the proxy — is the one
action that never claims the lease. It is forwarded only while a lease someone
else already took is still live, and then without activating or raising anything;
otherwise the answer is `{ "performed": 0, "skipped": "hover" }`. Crossing a
proxy with the mouse must not change which application the agent is working in.

`window.activate` activates the owning pid. `window.close` maps the CG window to
exactly one AX window by pid, title and frame (±5 points) and refuses ambiguous
matches instead of guessing. `window.minimize` is registered for compatible
clients; the V4 app minimizes its local proxy and stops capture without changing
the remote window.

**Console refusal covers observation too.** The same `SESSION_IS_CONSOLE`
verdict gates every method that observes or manipulates the GUI session —
`screenshot`, `apps`, `launch`, `quit`, `forceQuit`, `activate` and all `ax.*`.
A console-session worker serves only `hello`, `status`, `exec` and `shutdown`:
on the console, the framebuffer and window list belong to the user, and §54
forbids a screenshot of the user's desktop.

**The order of checks is the safety contract:**

1. **Session verdict.** `isConsole` → `SESSION_IS_CONSOLE`.
   `indeterminate` → also `SESSION_IS_CONSOLE` (fail closed). `noWindowServer` →
   `NO_WINDOW_SERVER`.
2. **Accessibility.** Absent → `ACCESSIBILITY_DENIED`.
3. **Whole batch validated.** One bad action performs *nothing*; the error names
   the offending index.
4. **Coordinates** checked against the real display → `INVALID_COORDINATE`.
5. **A frontmost app must exist** → `NO_INPUT_TARGET`. Posting into a session
   with nothing frontmost is a silent no-op, and a silent no-op is worse than an
   error because the caller believes it worked.
6. **Perform.** Nothing above this line has a side effect.

Every event is posted with `CGEvent.post(tap: .cgSessionEventTap)`. The function
that posts takes no tap parameter, so `.cghidEventTap` — the global entry point
that the window server routes to whichever session is *on the console* — is
unreachable from the code by construction.

Limits: 512 actions per call, 10000 characters per `type`, 30000 ms per `sleep`,
120000 ms of sleep per batch.

### `apps`

Every app in the session, `regular` **and** `accessory`, each with its `policy`.
Omitting accessory apps makes every launch of a menu-bar app look like a failure.

```json
{ "count": 62, "apps": [ { "pid": 5852, "name": "Zed", "bundleId": "dev.zed.Zed", "path": "/Applications/Zed.app", "policy": "regular", "active": true } ] }
```

### `launch` / `activate` / `quit` / `forceQuit`

Params: `{ "app": "Google Chrome" }` — a name, a bundle id, or an absolute path
to a `.app`. `launch` also takes `timeoutSeconds` (default 30).

`launch` does **not** trust `open`'s exit code: it waits until the app has a pid
and, for a regular app, until it owns an on-screen window. A menu-bar app never
owns one, so the window wait is bounded to half the timeout rather than stalling
every `LSUIElement` launch.

### `exec`

Params: `command`, `cwd`, `env` (object of strings), `timeoutMs` (1–3600000),
`stdin`.

```json
{ "exitCode": 0, "signal": null, "timedOut": false,
  "stdout": "…", "stderr": "", "duration": 25, "truncated": false }
```

- Runs as the **Space's own user**, via `/bin/sh -c`. There is no `sudo` path and
  no helper round-trip.
- `HOME`, `USER`, `LOGNAME`, `TMPDIR` are forced to the agent user's own, never
  the caller's. `DISPLAY` is removed.
- The child gets its own process group (`POSIX_SPAWN_SETSID`), and
  `POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF` are set because connections are
  served on libdispatch threads that run with signals blocked, and that mask
  survives `exec`.
- On timeout: SIGTERM to the group, 2 s grace, SIGKILL. `timedOut: true` forces
  `exitCode: null` so a timeout is never mistakable for a clean exit.
- A non-zero exit is a **normal result**, not an RPC error.
- Output is capped at 4 MiB per stream; the tail is kept and `truncated` is set.
- `cwd` is confined to the Space's declared roots when it has any
  (`WORKSPACE_DENIED` otherwise).
- Commands on the refusal list fail `EXEC_DENIED`. That list is a guardrail
  against mistakes and prompt injection, **not a sandbox** — the containment is
  the uid. See `docs/security.md`.

### `ax.snapshot` / `ax.frontmost` / `ax.windows` / `ax.perform`

`ax.snapshot`: params `pid` (defaults to frontmost), `maxDepth` (12),
`maxNodes` (2000), `interestingOnly` (true). Returns a bounded breadth-first walk
with role, title, description, value, identifier, enabled, focused, frame
(including `centerX`/`centerY` for clicking) and the supported actions.

`ax.perform`: params `pid`, `action` (`"AXPress"`, or `click: true` to find the
element and click its frame centre through the session event tap), plus the
predicate `role`, `titleContains`, `identifier`.

Bounded on both depth and node count: a browser accessibility tree is tens of
thousands of nodes and walking one unbounded would wedge the worker.

### `systemSettings.open`

Params: `{ "pane": "accessibility" | "screenRecording" | "fullDiskAccess" }`.
Opens that privacy pane **in the attached account's own Aqua session** — the
worker is the only process that can do it, and a controller that opened the URL
through its own `NSWorkspace` would show the human's settings instead, which is
the confusion the whole feature exists to remove.

`SystemSettingsPane` (in Core) is the closed allow-list of `x-apple.systempreferences:`
anchors; no other destination is reachable through this method. Each pane is
paired with the silent pre-check that makes the worker appear as a row the user
can switch on: `AXIsProcessTrustedWithOptions(prompt:)`,
`CGRequestScreenCaptureAccess()`, and for Full Disk Access one deliberately-gated
read (`FilePrivacy.registerForFullDiskAccess`). macOS never prompts for that last
grant — a gated open is simply denied — so without the attempt there is no row
to approve.

### `shutdown`

Params: `reason`. Replies, then exits 0 after 0.2 s so the reply is delivered.

---

## Error codes

Every code, and what a caller should do. `recoverable` is derived from the code.

| Code | Recoverable | Meaning |
|---|---|---|
| `SESSION_NOT_READY` | yes | No usable background session |
| `SESSION_IS_CONSOLE` | yes | The session is the physical console, **or its state could not be determined** |
| `NO_WINDOW_SERVER` | yes | No window server in this session |
| `WORKER_OFFLINE` | yes | Nothing listening on the socket |
| `HELPER_UNAVAILABLE` | yes | The privileged helper is not installed or did not answer; install it from the app |
| `HELPER_REJECTED` | yes | The helper answered and refused — bad argument, a non-AgentSpace account, or a caller whose code signature failed the check |
| `WORKER_IS_ROOT` | **no** | The worker refused to run as root |
| `ACCESSIBILITY_DENIED` | **no** | TCC Accessibility missing; an agent cannot fix this by retrying |
| `SCREEN_RECORDING_DENIED` | **no** | TCC Screen Recording missing |
| `INVALID_COORDINATE` | **no** | Off-display, negative, or non-finite |
| `INVALID_ACTION` | **no** | Malformed action batch; nothing was performed |
| `NO_INPUT_TARGET` | yes | No frontmost app to deliver to |
| `INPUT_BUSY_BY_HUMAN` | yes | A person interacted with a Fusion proxy in the last five seconds |
| `APP_NOT_FOUND` | yes | No such app in this session |
| `APP_LAUNCH_TIMEOUT` | yes | Launched, never registered |
| `WORKSPACE_INVALID` | **no** | The workspace reference does not resolve to a prepared workspace |
| `PREVIEW_NOT_RUNNING` | yes | `preview.stop` (or a frame request) with no live preview stream |
| `APP_NOT_RUNNING` | yes | Not running, so cannot be quit or activated |
| `WORKSPACE_DENIED` | **no** | Path outside the Space's roots, or a read-only root |
| `COMMAND_TIMEOUT` | yes | The process group was terminated |
| `EXEC_DENIED` | **no** | On the refusal list |
| `UNAUTHORIZED` | **no** | Missing or wrong session token |
| `BAD_REQUEST` | **no** | Malformed request |
| `METHOD_NOT_FOUND` | **no** | Unknown method |
| `PROTOCOL_MISMATCH` | **no** | GUI, CLI and worker are different builds |
| `INTERNAL_ERROR` | **no** | A bug; export diagnostics |

## The `unavailable` envelope

Client entry points (the CLI's `--json` failures, and the MCP server's errors)
surface a failure as plan §2 requires:

```json
{ "status": "unavailable", "reason": "SESSION_IS_CONSOLE",
  "ok": false,
  "error": { "code": "SESSION_IS_CONSOLE", "message": "…", "recoverable": true },
  "fix": "…" }
```

There is deliberately **no variant of this value that means "carry on in the
user's session"**. That is the whole point of the type: the failure case is
first-class and typed, so no caller can catch it and be tempted to fall back.

## Server/client behaviour worth knowing

- **Signal mask.** The worker serves connections on libdispatch threads with most
  signals blocked, and that mask survives `exec`. `exec` therefore spawns with an
  explicit empty mask and default dispositions; without it a timed-out child
  would ignore SIGTERM until the SIGKILL.
- **Client disconnect.** A failed write (EPIPE; `SIGPIPE` is ignored
  process-wide) or EOF marks the peer gone and stops further writes. Clients must
  keep the socket open until they have read the full response line.
- **Stale sockets.** The worker unlinks the socket before binding. A socket file
  whose worker has died is removed on the next start rather than causing
  `EADDRINUSE` forever.
- **`sun_path` is 103 bytes.** The default layout uses 83. An over-long root is
  detected and refused rather than silently truncated into a socket nobody can
  find; `agentspace doctor` reports the budget.

## Hand-testing with `nc`

```bash
sock=/Library/Application Support/AgentSpace/Runtime/<uuid>/worker.sock

printf '{"protocol":1,"requestId":"1","method":"hello"}\n' | nc -U "$sock"

token=$(cat /Library/Application Support/AgentSpace/Runtime/<uuid>/token)
printf '{"protocol":1,"requestId":"2","token":"%s","method":"status","params":{}}\n' "$token" | nc -U "$sock"

printf '{"protocol":1,"requestId":"3","token":"%s","method":"screenshot","params":{"maxWidth":640}}\n' "$token" | nc -U "$sock"
```

Use plain `nc -U`, not `nc -N -U`: `-N` half-closes after stdin EOF and the worker
reads that as a client disconnect.
