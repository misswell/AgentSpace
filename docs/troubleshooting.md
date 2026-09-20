# Troubleshooting

Start here:

```bash
agentspace doctor          # human-readable
agentspace doctor --json   # for a script or a bug report
```

Every check that is not `✓` prints what is wrong **and** what to do. This file
explains the ones people hit most. If `doctor` does not cover your case,
`docs/validation.md` §7 lists what is not yet built.

---

## `SESSION_IS_CONSOLE` — "input is refused"

**What it means.** The AgentSpace session is on your physical display right now.
Posting an event into it would type on your own screen, so AgentSpace refuses
instead. This is the product working, not a bug.

**Fix.** Switch back to your own account with fast user switching. The AgentSpace
session keeps running in the background; input works again the moment it is no
longer on the console. Nothing needs restarting.

**If it happens when you are *not* looking at the AgentSpace desktop:** the
session dictionary could not be read, and AgentSpace fails closed. Re-run
`agentspace doctor --json` and look at `sessionVerdict`:

| `sessionVerdict` | Meaning |
|---|---|
| `usable` | Background session; input permitted |
| `isConsole` | The session really is on the console |
| `indeterminate` | `CGSessionCopyCurrentDictionary()` did not answer — treated as console, deliberately |
| `noWindowServer` | No window server in this session |

---

## `WORKER_OFFLINE` — nothing is listening

The socket file may not exist, or may be stale from a crashed worker.

```bash
agentspace status <space>
ls -la /Library/Application Support/AgentSpace/Runtime/<space-uuid>/
```

**Most common cause: the AgentSpace user has never been logged in through the
GUI.** A macOS user only gets an Aqua session after a GUI login, and the worker's
LaunchAgent is scoped to that session (`LimitLoadToSessionType: Aqua`). This is
expected after a reboot — macOS does not restore the second session by itself.

**Fix.** Fast user switch into the AgentSpace user, let the worker start, then
switch back. `agentspace doctor` reports this as `Needs Login`.

If the socket exists but nothing answers, it is stale. The worker unlinks it on
the next start, so starting the worker is the fix. (A stale socket is not deleted
by hand here because the directory is ACL'd and deleting it as the wrong user
fails confusingly.)

---

## `ACCESSIBILITY_DENIED` / `SCREEN_RECORDING_DENIED`

The worker needs both grants **inside the AgentSpace session**, not in yours.

**Fix.** Fast user switch into the AgentSpace user, then:

- System Settings → Privacy & Security → **Accessibility** → enable
  `agentspace-worker`
- System Settings → Privacy & Security → **Screen & System Audio Recording** →
  enable `agentspace-worker`

Then `agentspace restart <space>`, because TCC grants are read at process start.

**Two things that confuse people here.**

1. **`agentspace doctor`'s TCC line is advisory.** It reports *your terminal's*
   grants, because TCC attributes a permission to the **responsible process**.
   The worker's own answer is what matters, and `doctor` gets that by asking the
   worker rather than by checking its own.
2. **Grants are keyed to the binary's path and signature.** Rebuilding at the same
   path with the same signing identity keeps them; changing either silently
   invalidates them. If input worked yesterday and not today after a rebuild,
   re-grant.

AgentSpace never writes `TCC.db`. If a guide tells you to, it is describing a
different tool with a different risk profile.

---

## Screenshots fail while Accessibility works

That is the split-permission case: `SCREEN_RECORDING_DENIED` and
`ACCESSIBILITY_DENIED` are separate toggles. AgentSpace checks
`CGPreflightScreenCaptureAccess()` **before** invoking `screencapture`, so a
missing grant is a clean typed error rather than a TCC dialog appearing in a
session nobody is watching.

---

## macOS says the worker cannot access other apps' data

This is **not** a broken installation and not one of the two grants that gate the
desktop. It is the file-privacy family: `Desktop`, `Documents`, `Downloads` and
per-app data under `Library` belong to the account, and macOS decides per access
who may read them.

**What AgentSpace does with it.** Nothing that requires a decision. The disk
measurement skips those roots until the grant exists and labels the number as
partial (`diskExcludesProtected`); `Full Disk Access` is probed by an open macOS
either allows or silently denies, never by a prompt, so a status poll cannot raise
a dialog nobody is watching.

**Fix, if the agent should work in those folders.** On the agent's card press
**Open Full Disk Access settings** (the same row exists in the authorization guide
and in the attached account's own AgentSpace window). The worker registers itself
as a row named `agentspace-worker` when you press it; enable that row, then
refresh the card. `agentspace doctor` reports the same state as a **warning**, not
a failure — a Space that can be seen and driven but not filed through is working.

**Do not** grant it to the AgentSpace app. The permission belongs to
`agentspace-worker`, the background process in the attached account.

---

## `INVALID_COORDINATE` — "off the main display"

The overwhelmingly likely cause: **a coordinate was taken from a screenshot in
pixels and used as a point.**

```
pointX = pixelX / scale
pointY = pixelY / scale
```

`agentspace screenshot` prints the scale on every human-readable run, and every
screenshot reply carries `scale`, `width`/`height` (points) and
`pixelWidth`/`pixelHeight` (pixels). On a 1920×1080 display at scale 2, a
screenshot is 3840×2160 and a click at the visual centre is `960, 540` — not
`1920, 1080`.

Do not derive the scale from `CGDisplayPixelsWide()`: on macOS 27 it returns
*points* for a scaled Retina display. `docs/validation.md` §2 has the measurement.

AgentSpace rejects an off-display coordinate rather than clamping it, because a
clamped click is a click in the wrong place and the agent would not know.

---

## `NO_INPUT_TARGET` — "no app is frontmost"

Keyboard and mouse events need somewhere to land. Posting into a session with
nothing frontmost is a silent no-op, and AgentSpace reports an error instead
because "nothing happened" is worse than "it failed" when a model is deciding
what to do next.

**Fix.** Launch or activate something in the Space first:

```bash
agentspace launch <space> Finder
agentspace apps <space>
```

A session that has just been logged into may briefly have only the desktop
showing; retrying after a second works.

---

## `APP_LAUNCH_TIMEOUT`

The app was launched but never registered a window. `launch` deliberately does not
trust `open`'s exit code — that only means LaunchServices accepted the request.

Common causes: the app is showing a first-run dialog or a modal in the AgentSpace
session, or it needs a permission it has not been given. Take a screenshot and
look.

Note that a **menu-bar app never owns an on-screen window**, so the window wait is
bounded to half the timeout rather than stalling every `LSUIElement` launch. If a
menu-bar app is the one timing out, the timeout is not the problem.

---

## `EXEC_DENIED`

The command matched AgentSpace's refusal list — `sudo`, `installer`,
`diskutil erase`, `launchctl bootstrap system`, `dscl create`, `sysadminctl`,
`rm -rf /`, `shutdown`, `reboot`, and similar. The error names the rule it hit.

This list is a guardrail, not a sandbox: the containment is that the executor is a
standard, non-admin user. Run the command yourself in your own terminal if you
really mean it.

---

## `WORKSPACE_DENIED`

The path is outside the Space's workspace and shared folders, or it is inside a
folder configured read-only.

Paths are canonicalised — `~` expanded, symlinks resolved — **before** the check,
so a symlink pointing out of the workspace is refused rather than followed. That
is intentional.

Before phase 7 the Space has no declared roots at all, and
`status.workspace.confined` is `false`: the worker reports the honest state rather
than implying a confinement that is not in effect.

---

## `UNAUTHORIZED`

The session token is missing or wrong.

```bash
ls -la /Library/Application Support/AgentSpace/Runtime/<space-uuid>/token
```

The CLI reads it automatically. If it is missing, the worker was started by hand
instead of by its LaunchAgent; restarting it writes a fresh one — but note that a
**fresh token invalidates anything holding the old one**, so restart the app too.

`testUnauthorizedSocketClientRejected` covers this path, including a forged token
that shares a long prefix with the real one.

---

## `PROTOCOL_MISMATCH`

The app, CLI and worker are different builds. Reinstall so all three come from the
same release. Each side refuses to guess at the other's field layout, which is the
point of the version gate.

---

## `COMMAND_TIMEOUT`

The process group was terminated after `timeoutMs` (default 120 s; max 1 h). You
get `timedOut: true` and `exitCode: null`, so a timeout is never mistakable for a
clean exit.

The child runs in its own process group and is signalled as a group — SIGTERM,
2 s grace, SIGKILL — so a shell that spawned children does not leave them behind.

---

## The worker will not start

Check its exit code:

| Code | Meaning |
|---|---|
| 64 | Bad arguments |
| 69 | `NO_WINDOW_SERVER` — no Aqua session (you ran it over ssh, or in a launchd context without `LimitLoadToSessionType: Aqua`) |
| 70 | Socket could not be created or bound |
| 77 | `WORKER_IS_ROOT` — it refuses to run as root, by design |
| 78 | Runtime directory unusable |

```bash
.build/debug/agentspace-worker --check      # machine-readable readiness, no socket
```

A path over 103 bytes is refused rather than truncated, because a truncated
`sockaddr_un.sun_path` produces a socket nobody can find. `--check` reports the
budget. The default layout uses 83 of 103 bytes.

---

## `agentspace doctor` says the helper is not installed

Connecting and disconnecting accounts needs the helper because the worker and
runtime live under root-owned Application Support. The helper never creates or
deletes a macOS user. Existing worker RPC remains unprivileged, and the CLI never
runs `sudo` or falls back to the current user's session.

---

## Input works but the wrong window receives it

`input` delivers to the **Space's frontmost application**, resolved from the
window server at the moment each action runs. If the wrong app has focus,
activate the right one first:

```bash
agentspace activate <space> "Google Chrome"
agentspace apps <space>            # shows which app is ←front
```

Alternatively, skip coordinates entirely:

```bash
agentspace ax <space> perform --title "Sign In" --click
```

which finds the control in the accessibility tree and clicks its frame centre.

---

## Drag does not work

Known and documented as **unverified**. `drag` follows how AppKit documents drag
tracking — press, pause, 24 interpolated points with deltas at ~one per frame,
pause, release — but end-to-end behaviour in a background session has not been
confirmed, because confirming it needs a second logged-in user.
`docs/validation.md` §7 lists it. Prefer `ax … --click` or keyboard navigation
where you can.

---

## Everything is slow / the app uses too much memory

It should not: idle targets are under 100 MB for the app and under 50 MB per
worker, with ~0% CPU. Check what the Space is actually costing:

```bash
agentspace status <space> --resources
```

The memory in a Space is Chrome and your IDE, not AgentSpace. If the *app* is
large, that is a bug worth reporting with `--json` output attached.

Do not poll `status` faster than every 2–5 seconds (plan §53); prefer event
notification where the GUI can.

---

## Reporting a bug

```bash
agentspace doctor --json > doctor.json
agentspace status <space> --json >> doctor.json
```

Diagnostics export strips passwords, tokens, Keychain material, typed input text
and full screenshots. Check the file before attaching it anyway — redaction is
best-effort, and a secret you pasted into a window title is still a secret.

---
## Connecting or disconnecting an account fails

### `HELPER_UNAVAILABLE` / `agentspace attach` exits 69

The root LaunchDaemon did not answer. AgentSpace cannot install its root-owned
worker or create the protected runtime without that fixed helper API, so it stops;
it never runs `sudo` and never falls back to the current user's session.

Fix: open AgentSpace, press **Install Helper**, approve macOS's administrator
prompt, then run `agentspace helper`.

### `HELPER_REJECTED`

The helper answered and refused. Common reasons:

- The selected username is the current user, an administrator, hidden/system
  account, missing, or has a nonstandard home.
- The account is already attached.
- The runtime root is neither the exact production Application Support path nor
  a supported explicit test root.
- The app/helper signature does not satisfy the fixed caller requirement.

Legacy `createUser` and `deleteUser` requests are also deliberately rejected:
V3 never changes macOS account lifecycle.

### Attach did not finish

Read the provisioning step list. AgentSpace rolls back any runtime, worktree and
worker it created after the failing step. It does not need to undo a macOS user
because it never created or changed one.

### Disconnect did not finish

A runtime-removal failure keeps the registry record so disconnect can be retried.
The existing macOS user and home were not touched. Fix the reported helper or
filesystem problem, then choose **Disconnect Account** again.
### The worktree was not removed

Deleting a Space removes its worktree but **keeps the branch**, and never touches
your repository. If git refused to remove the worktree, the deletion carries on and
says so rather than failing — a leftover directory is much better than an account
that cannot be removed.

Remove it yourself when convenient:

```bash
git -C ~/Code/MyApp worktree list
git -C ~/Code/MyApp worktree remove --force <path>
git -C ~/Code/MyApp worktree prune
```

Your branch is still there: `git -C ~/Code/MyApp branch --list 'agentspace/*'`.

## A Space shows "Needs Login" right after a reboot

That is correct behavior, not a fault (§39): no one has logged into the agent
account since the restart, so there is no session for a worker to run in. Fast
user switch into the Space's account once and back; the state becomes offline →
ready as the LaunchAgent brings the worker up.

If the state says **offline** instead, a session *does* exist and only the worker
died — check the agent account's LaunchAgent logs under the Space's runtime
directory. The two labels are derived from whether the account currently owns
any processes (`SystemSessions`); if a Space is stuck on Needs Login while a
session is genuinely live, that lookup has failed and `agentspace doctor` is the
next stop.

## A deep link does nothing, or reports SPACE_NOT_FOUND

`agentspace://space/<uuid>` links come from the CLI (`agentspace desktop`), from
scripts, or from notes you saved earlier. When nothing seems to happen:

1. **Is the app running?** The link launches the app if needed, but a fresh
   launch plus a slow first render can look like nothing happened — wait a
   beat before deciding it failed.
2. **Read the alert.** The app never swallows a link silently. A link to a
   Space that no longer exists raises `SPACE_NOT_FOUND`, naming the UUID —
   "probably deleted after the link was made". A malformed link raises
   `BAD_REQUEST` quoting the URL. The failure is in the app, on purpose: the
   process that posted the link may be long gone, so an error printed to its
   stdout would be invisible.
3. **Re-derive the link.** Old links die when the Space is deleted and
   recreated — the new Space gets a new UUID. Run `agentspace list --json` and
   use the current id; do not recycle old links.

If the viewer opens but shows `WORKER_OFFLINE`, the link worked and the *Space*
is what is not ready — that is the `WORKER_OFFLINE` section above, not a
deep-link problem.

## Building and distributing: the notarization failures

These are publisher-side failures — they affect the person running
`scripts/release.sh` / `scripts/notarize.sh`, not a user of a downloaded DMG.
All three were hit for real on the machine this project was built on; each fix
is the one that actually worked, not the one that sounded plausible.

### `No Keychain password item found for profile: …`

The notarytool keychain entry is **gone, not misnamed**. Keychain password items
for notarytool profiles are known to vanish without warning (observed twice on
this machine, months apart) while every other credential keeps working.

Fix — the profile owner runs, once, in their own terminal:

```bash
xcrun notarytool store-credentials octoshrink-notary \
  --apple-id <apple-id> --team-id <team-id>
```

macOS prompts for the app-specific password interactively. Never paste the
password into a chat or a script. Until this is restored, `scripts/notarize.sh`
falls back to the asc CLI if that is registered (next section).

### `UnauthenticatedRequest` from asc, with a key that used to work

The asc CLI answers every request with a 401 even though the key is fine. The
root cause that actually reproduced: the stored credential's **issuer ID is
empty or wrong**. The issuer is not the team ID (`U8U443D7ZL`-shaped) — it is
the UUID shown in App Store Connect → Users and Access → Integrations. The
issuer is also team-scoped, so any key of the same team uses the same UUID.

Fix — re-register with all three parts:

```bash
asc auth login --name agentspace-notary \
  --key-id <KEYID> --issuer-id <uuid-issuer> \
  --private-key ~/Downloads/AuthKey_<KEYID>.p8
asc notarization list --limit 1        # probe before trusting it
```

Private key files must not be group/world-readable or asc refuses them:
`chmod 600` first.

### A submission stays `In Progress` for hours

One submission of a given DMG was Accepted in 90 seconds; a second submission of
the same bytes sat In Progress for 3+ hours. Apple's queue is occasionally just
slow, and the submit `--wait` poll can time out locally (`HTTPClientError.
connectTimeout`) while the server-side submission continues fine.

What to do:

- Check the real state instead of resubmitting blindly:
  `asc notarization list` (or `xcrun notarytool history`).
- A local timeout does not mean the submission failed — poll `list` for the
  submission id before doing anything else.
- If you must resubmit, that is safe: notary allows duplicate submissions of
  the same file, and **any** Accepted submission's ticket staples onto those
  same bytes. Staple from an Accepted one and ignore the stragglers.
- If a submission ends `Invalid`, fetch the reason:
  `xcrun notarytool log <submission-id> --keychain-profile <profile>`.

### Gatekeeper refuses the downloaded app ("cannot be opened…")

Run the two checks the release chain runs, in order — they localize the break
immediately:

```bash
codesign --verify --strict dist/AgentSpace.app   # signature intact?
stapler validate dist/AgentSpace.app             # ticket present and valid?
spctl --assess --type execute dist/AgentSpace.app # what Gatekeeper itself runs
```

- Signature fails → the bundle was modified after signing; rebuild.
- Signature ok, staple invalid → notarized but not stapled (or stapled before
  the ticket existed): `scripts/notarize.sh`.
- All pass but Gatekeeper still refuses on *another Mac* → the DMG the user has
  is not this one, or the download lost quarantine attributes — verify the
  `stapler validate` of the exact DMG you shipped.
