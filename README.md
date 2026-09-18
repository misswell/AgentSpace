# AgentSpace

**Give AI agents their own macOS desktop.**

AgentSpace runs GUI agents inside separate macOS user sessions, so agents can
click, type, launch apps and test software without taking over your keyboard,
mouse or screen.

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

A Space is created once, logged into once by hand, and then lives in the
background. Agents drive it over a unix socket; you never see it unless you open
**View Desktop**.

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

Phase 0/1 of the plan. The core works and is tested; the GUI and the privileged
helper are not built yet. `docs/validation.md` records exactly what is verified
and what is not, with the measurements.

**Working today**

- `agentspace-worker` — the per-Space daemon: unix socket RPC, fail-closed console
  guard, session-tap input, screenshot, app lifecycle, `exec`, accessibility tree
- `agentspace` — the CLI, with `--json` on everything, plus `agentspace doctor`
- `AgentSpaceCore` — the shared protocol, models and safety logic
- 151 tests, 0 failures; the safety suite runs against a live worker over a live
  socket

**Not built yet**

- The SwiftUI app (phase 2) and the privileged helper (phase 3), so Spaces cannot
  be created from the GUI yet
- The MCP server (phase 6)

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

## Build

Requires Apple Silicon and macOS 26+. Xcode command line tools and Swift 6.

```bash
swift build                 # agentspace-worker and agentspace
swift test                  # 151 tests; the worker integration tests need the
                            # binary built first
scripts/demo.sh             # end-to-end run against a throwaway root
```

Binaries land in `.build/debug/`. The worker's own readiness check, which needs no
socket and no second user:

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

## Requirements

Apple Silicon, macOS 26+. Intel Macs are out of scope for v1; the plan supports
expanding the range only after macOS 15/26/27 have been validated.

## Licence

MIT. See [`LICENSE`](LICENSE) and [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)
— this project learned from [`viraatdas/offstage`](https://github.com/viraatdas/offstage)
(MIT), and the divergences are listed in `docs/validation.md` §8.
