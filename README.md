# AgentSpace

**Give every AI agent its own macOS account and desktop.**

AgentSpace manages agent accounts: each one is a real macOS user with its own
desktop session, so agents can browse, code, test and operate GUI apps without
taking over your keyboard, mouse or screen. The current product plan is
[`docs/v3-plan.md`](docs/v3-plan.md).

**No VM. No second macOS installation. No remote Mac.**

```
Your desktop                    Agent desktop
────────────                    ─────────────
VS Code            ·            Chrome
Terminal           ·            Simulator
Safari             ·            Xcode
                   ·
You keep working   ·            The agent keeps working
```

Your pointer does not move. Your keyboard is not taken. Your focus does not
change. Your desktop does not flicker.

---

## How

Same Mac, same kernel, same `/System`, same hardware — macOS's own multi-user GUI
support, which is what fast user switching is built on.

```
┌─ your session ────────────┐   ┌─ AgentSpace A ────────────┐
│ WindowServer              │   │ its own macOS user        │
│ your desktop, input, focus│   │ its own Aqua session      │
│ you, working              │   │ its own framebuffer       │
└───────────────────────────┘   │ its own input stream      │
                                │ agentspace-worker         │
                                └───────────────────────────┘
```

An existing standard account is connected once, logged into by its owner, and
then lives in the background. Agents drive it over a unix socket; you never see
it unless you open **Open Desktop**.

## Why not the obvious alternatives

| | Costs |
|---|---|
| A VM | A second macOS, tens of GB, and it is not your real machine |
| Xvfb-style virtual display | Does not exist on macOS, and a fake display cannot test real GPU/Metal apps |
| Private `SkyLight` / `ScreenSharing` frameworks | Break on every OS update; not something a product can rest on |
| Running the agent on your desktop | The thing this project exists to avoid |

AgentSpace uses an API Apple ships and supports: a second user, a second Aqua
session.

---

## Status

**Handing this project to someone (or something) new? Read
[`docs/status.md`](docs/status.md) first** — it is the map: state, next work,
and the conventions a change must not break. `docs/validation.md` records
exactly what is verified and what is not, with the measurements.

**Honest state: the foundation is done and tested; the product's headline
promise is not delivered yet.** Agent accounts with their own desktops work
end to end. What does not exist is the runtime manager — nothing yet starts an
agent's own tooling (Terminal, Chrome, VS Code, `claude`) inside its session
from one action, so driving an agent today means CLI calls or clicking in its
desktop by hand. See [`docs/status.md`](docs/status.md) §0 for the full gap
list before promising anything.

**Working today**

- `AgentSpace.app` — the SwiftUI app: agent-account home with status cards, a
  three-step New Agent wizard, the Desktop Viewer with click-to-input, the menu
  bar, and diagnostics. English and Simplified Chinese.
- Connecting an existing standard macOS account: discovery, validation,
  root-owned runtime/worker installation, LaunchAgent start and rollback.
- Disconnecting removes only AgentSpace-owned state; the macOS user and its
  home are always retained.
- `agentspace-worker` — the per-account daemon: unix socket RPC, fail-closed console
  guard, session-tap input, screenshot, app lifecycle, `exec`, accessibility tree
- `agentspace` — the CLI, with `--json` on everything, plus `agentspace doctor`
- `@agentspace/mcp` — the MCP server: 22 tools over stdio (`agent_*` and the
  original `agentspace_*` names), bridged to the same CLI
- `AgentSpaceCore` — the shared protocol, models and safety logic
- `agentspace-helper` — the root LaunchDaemon: a closed list of typed
  operations, no shell, and a code-signing check on its caller.
- Git-worktree workspaces: the agent gets its own checkout on an `agentspace/…`
  branch, so it can never edit the tree you have open.
- The full Swift and MCP suites pass with zero failures; the safety suite runs
  against a live worker over a live socket, and the workspace tests use real
  git. The exact test count, per suite, lives in `docs/validation.md` — a number
  hardcoded here would drift the moment a test is added.

**Not built yet — and the first one is the product's point**

- **The runtime manager** (plan(v2) §10/§11): launching the agent's own tools
  (Terminal, Chrome, VS Code) inside its session and running its command
  there, with per-account profiles. Building blocks (`launch`/`exec` over the
  wire, `purpose` on the record) exist; nothing composes them. Until this
  lands, "give every agent its own Mac desktop" is a foundation, not a
  finished product.
- Agent profiles and the end-to-end story of plan(v2) §24.
- Multi-agent concurrency soak (§13).
- Preview tuning beyond the current 5 FPS stream (target 15).

**Verified on this machine** — macOS 27.0, Apple Silicon:

```
$ agentspace click Demo 100 100
agentspace: SESSION_IS_CONSOLE: refusing to inject input: the 'Demo' session is
currently on the console, so events would land on the user's own screen.
  → The AgentSpace desktop is on your physical display right now. Switch back to
    your own account; input resumes automatically and is refused until then.
```

That refusal is the product. There is no code path that falls back to your
session.

---

## Install

If you have the DMG (`dist/AgentSpace-0.1.9.dmg`, produced by
`scripts/release.sh` and notarized by `scripts/notarize.sh` — run both, in that
order; `check-all.sh`'s dist guard fails on an unstapled app):

1. Open the DMG and drag **AgentSpace** into Applications.
2. Open the app. It is Developer ID signed, notarized, and stapled, so
   Gatekeeper opens it directly — no right-click, no "allow anyway".
3. Press **Install Helper** and confirm with your administrator password.
   The helper (a root LaunchDaemon) installs the root-owned worker and prepares
   private runtimes; it never creates or deletes macOS users, and nothing in
   AgentSpace runs `sudo`.

From source instead: see **Build** below.

---

## Build

Requires Apple Silicon and macOS 26+. Xcode command line tools and Swift 6.

```bash
scripts/build.sh            # both binaries, sanity-checked, signed
scripts/test.sh             # the whole suite; builds the worker first, because
                            # the safety suite spawns it and a skipped suite is
                            # not a passing suite
scripts/bundle-app.sh       # a signed dist/AgentSpace.app
scripts/demo.sh             # end-to-end CLI run against a throwaway root
scripts/mcp-smoke.sh        # real MCP JSON-RPC against a live worker
scripts/acceptance.sh       # the phase-0 isolation gate (plan §44)
scripts/gui-verify.sh       # the UI properties, re-read through the
                            # accessibility tree (slider bounds, preview
                            # tiers, the dead-link alert)
```

One command runs everything a release needs, in the order that fails fast:

```bash
scripts/check-all.sh        # test suite → MCP smoke → GUI verification
```

The privileged helper reports its own state, and needs no root to do it:

```bash
dist/AgentSpace.app/Contents/Library/LaunchDaemons/agentspace-helper --self-check
dist/AgentSpace.app/Contents/Helpers/agentspace helper
```

The acceptance gate is the one that decides whether the product works:

```bash
scripts/acceptance.sh --iterations 1000
```

It opens TextEdit on your desktop, drives 1000 mixed click/type/scroll actions on
the agent's desktop through the worker, then checks that your content, focus and
pointer are untouched. Run it from your own desktop, never over ssh. Exit code 3
means the gate could not run — no background session yet — and that is
deliberately not the same as passing. Exit code 66 means there is no Space at
all yet (create one first); the fail-closed half needs a Space's worker, even
before its first login.

The worker's own readiness check, which needs no socket and no second user:

```bash
.build/debug/agentspace-worker --check
```

## Try it without creating a user

`scripts/demo.sh` starts a real worker against a throwaway root and drives every
CLI surface. On a normal single-user machine the worker lands in your own session,
which is the console — so the observable result is that every input call is
correctly refused, and everything else works.

```bash
agentspace status Demo
agentspace exec Demo "sw_vers -productVersion"
agentspace screenshot Demo --max-width 640
agentspace doctor
```

## Usage

```bash
agentspace list                       # Spaces and their state
agentspace status dev                 # session, permissions, resources
agentspace doctor                     # is this machine ready?

agentspace screenshot dev             # capture the agent's desktop
agentspace apps dev                   # what is running in there

agentspace click dev 500 300          # coordinates are POINTS
agentspace type dev "hello"
agentspace key dev cmd+l
agentspace exec dev "npm test"

agentspace launch dev "Google Chrome"
agentspace quit dev Chrome
```

`--json` on every command, for agents, scripts and CI:

```bash
agentspace status dev --json
```

```json
{
  "status": "running", "space": "dev", "uid": 503, "worker": true,
  "screenRecording": true, "accessibility": true
}
```

### `agentspace open <account>` (alias: `desktop`)

Opens that account's desktop in the AgentSpace app — the same §52 stream
the app shows, raised through the `agentspace://agent/<uuid>` deep link (the
pre-rename `space` host still resolves). The
worker does not need to be online; the viewer reports the offline state
honestly rather than pretending.

## Give it to an agent (MCP)

```bash
cd packages/agentspace-mcp && npm install && npm run build
```

Point your MCP client at `node packages/agentspace-mcp/dist/index.js`, or set
`AGENTSPACE_BIN` if the CLI is not in one of the standard locations. 22 tools.
The current names: `agent_list`, `agent_status`, `agent_open_desktop`,
`agent_screenshot`, `agent_click`, `agent_type`, `agent_launch`, `agent_exec`.
The original 14 `agentspace_*` tools remain registered with identical
behaviour, so existing client configurations keep working.

**There is deliberately no tool that creates or deletes a Space, and none that
grants a permission.** Those change the machine and require a human in the GUI.
A tool that existed would eventually be called.

The server never runs a GUI command itself. When a Space is unavailable it relays
the refusal — `SESSION_IS_CONSOLE`, with the fix — rather than retrying anywhere
else. `scripts/mcp-smoke.sh` proves it by speaking real MCP JSON-RPC over stdio
and asserting that no reply ever mentions falling back to your own session.

## Screenshots and coordinates

One trap worth knowing before you write any automation:

```
Input coordinates are POINTS. Screenshots are PIXELS.

  pointX = pixelX / scale
  pointY = pixelY / scale
```

On a 1920×1080 display at scale 2, a screenshot is 3840×2160 — so the visual
centre is `960, 540`, not `1920, 1080`. Every screenshot reply carries `scale`,
`width`/`height` in points and `pixelWidth`/`pixelHeight` in pixels, and the CLI
prints the scale on every run.

Do not derive the scale from `CGDisplayPixelsWide()`. On macOS 27 it returns
*points* for a scaled Retina display, so that derivation gives `1` and every
coordinate ends up off by a factor of two. This was measured, not assumed —
`docs/validation.md` §2.

## Design rules

1. **Never fall back to your desktop.** No background session, no worker, no
   grant, no window server, or a state that cannot be determined — all fail with a
   typed reason. None of them quietly run in your session.
2. **Fail closed.** If the session's console state cannot be *proven*, input is
   refused.
3. **`cgSessionEventTap` only.** The global HID tap reaches whichever session is on
   the console. The function that posts events takes no tap parameter, so it is
   unreachable by construction.
4. **Low overhead.** Idle: under 100 MB for the app, under 50 MB per worker, ~0%
   CPU. No continuous capture, no 100 ms polling.
5. **Native.** Swift, SwiftUI, AppKit, CoreGraphics, ApplicationServices,
   ServiceManagement, Security. No Electron, no private frameworks, no `TCC.db`
   writes.

## Documentation

| | |
|---|---|
| [`docs/status.md`](docs/status.md) | **The handoff map** — state, next work, conventions |
| [`docs/v2-plan.md`](docs/v2-plan.md) | The agent-account product plan, section by section |
| [`docs/architecture.md`](docs/architecture.md) | Process boundaries, invariants, lifecycle |
| [`docs/protocol.md`](docs/protocol.md) | The wire contract, method by method |
| [`docs/security.md`](docs/security.md) | Threat model and controls — and what is *not* a control |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | Every error code, and what to do |
| [`docs/validation.md`](docs/validation.md) | What is verified, what is not, with measurements |

## Layout

```
apps/AgentSpace/                    SwiftUI app            (phase 2)
native/AgentSpaceWorker/            the per-session daemon
native/AgentSpaceCLI/               the agentspace CLI
native/AgentSpacePrivilegedHelper/  root helper            (phase 3)
shared/Core/                        protocol, models, safety logic
packages/agentspace-mcp/            MCP server             (phase 6)
tests/Unit tests/Safety tests/Integration tests/probes
docs/ scripts/
```

### Connecting an agent account

First create a standard secondary user in System Settings → Users & Groups.
Then use **New Agent…** in the app to select and connect that existing account.
The helper installs only AgentSpace's root-owned worker and private runtime; it
never creates or deletes macOS users.

```bash
agentspace attach AgentDev
agentspace attach AgentDev --repo ~/Code/Api --branch agentspace/api
agentspace detach AgentDev                  # always keeps the user and home
```

The CLI never runs `sudo`. If the helper is not installed it exits **69** and says
so — it does not fall back to your own account.

Sign in to the connected account through Fast User Switching with its existing
password and grant Accessibility and Screen Recording to the worker. AgentSpace
does not know or store that password.

## Requirements

Apple Silicon, macOS 26+. Intel Macs are out of scope for v1; the plan supports
expanding the range only after macOS 15/26/27 have been validated.

## Licence

MIT. See [`LICENSE`](LICENSE) and [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)
— this project learned from [`viraatdas/offstage`](https://github.com/viraatdas/offstage)
(MIT), and the divergences are listed in `docs/validation.md` §8.
