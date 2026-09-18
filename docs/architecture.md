# Architecture

AgentSpace runs AI agents in **separate macOS user sessions on the same Mac**.

```
Same Mac · same kernel · same /System · same hardware

├── Your session
│   ├── WindowServer
│   ├── your desktop, your keyboard and mouse, your focus
│   └── you keep working
│
├── AgentSpace A  (its own macOS user, its own Aqua session)
│   ├── its own WindowServer connection and framebuffer
│   ├── its own input event stream
│   └── agentspace-worker
│
└── AgentSpace B  (…)
```

Not a VM. No second macOS. No virtual display. No remote Mac. The mechanism is
macOS's own multi-user GUI support: a second account, logged in once through fast
user switching, keeps a live Aqua session in the background while you stay on
yours.

The value is not "create a user" and not "remote desktop". It is:

> **An agent can drive a real macOS GUI without ever disturbing the desktop a
> human is looking at.**

Everything below follows from that sentence.

---

## Three process boundaries

| Process | Runs as | May do | May **not** do |
|---|---|---|---|
| `AgentSpace.app` | your user | UI, Space management, status, screenshot preview, CLI/MCP request forwarding, log display | Create users, modify accounts, run a root shell |
| `AgentSpacePrivilegedHelper` | root, via `SMAppService` LaunchDaemon | A **closed set of typed operations**: create/delete the AgentSpace user, query uid, install/remove the worker LaunchAgent, prepare the runtime directory and its ACL, start/stop a named LaunchAgent, read session state | Anything generic. There is no `runShell(command)` and no `executeAnything(command)` — see below |
| `agentspace-worker` | the AgentSpace user | Screenshot, input, app lifecycle, exec, accessibility, serve the socket | Run as root, touch your session, reach the machine outside its workspace |

### Why the helper has no generic command

The helper is the only root component, so its XPC interface is a list of
*intents*, not a shell:

```swift
createUser(name:fullName:password:)   deleteUser(username:removeHome:)
installWorker(spaceID:username:)      removeWorker(spaceID:username:)
prepareRuntimeDirectory(spaceID:…)    startWorker(spaceID:) / stopWorker(spaceID:)
sessionInfo(spaceID:)
```

A generic escape hatch on a root daemon turns any code-execution bug anywhere in
the app into root. The typed list means the worst a compromised caller can do is
the worst thing on the list, and every argument is validated against an
allow-list pattern rather than interpolated into a command. Plan §6 and §56 both
call this out, and §56 requires a separate security review of the helper before
release.

---

## Data flow of one action

```
agentspace click dev 500 300
  │
  ├─ resolve Space "dev" → UUID, uid, socket path, token     (registry + runtime dir)
  │
  ├─ connect /Users/Shared/.AgentSpace/Runtime/<uuid>/worker.sock
  │
  ├─ {"protocol":1,"requestId":…,"token":…,"method":"input",
  │   "params":{"actions":[{"type":"click","x":500,"y":300}]}}
  │
  └─ worker
       ├─ protocol version gate        → PROTOCOL_MISMATCH
       ├─ token gate (constant time)   → UNAUTHORIZED
       ├─ session verdict              → SESSION_IS_CONSOLE / NO_WINDOW_SERVER
       ├─ AXIsProcessTrusted()         → ACCESSIBILITY_DENIED
       ├─ validate the whole batch     → INVALID_ACTION
       ├─ coordinates vs the display   → INVALID_COORDINATE
       ├─ a frontmost app must exist   → NO_INPUT_TARGET
       └─ CGEvent.post(tap: .cgSessionEventTap)
            │
            └─ enters THIS session's event stream only; the window server
               routes it to this session's key window. Your session never
               sees it.
```

The same shape serves the GUI and the MCP server. There is no second code path.

---

## Modules

```
shared/Core/Sources/AgentSpaceCore/       the contract everything shares
  Protocol.swift        framing, RPCRequest/Response, JSONValue, UnavailableStatus
  ErrorCodes.swift      the full code list, recoverability, remediation text
  SessionGuard.swift    the fail-closed console decision + PrivilegeGuard
  InputActions.swift    action model, validation, key tables
  Geometry.swift        point/pixel conversion, coordinate rules
  SpaceModel.swift      AgentSpace, SpaceState, Workspace, SharedFolder, ResourceUsage
  RuntimePaths.swift    the on-disk layout, ACL application
  Security.swift        session token, token storage, log redaction
  SpaceRegistry.swift   the Space index, resolution by name/UUID
  WorkerClient.swift    the socket client (used by CLI, tests, GUI, MCP)

native/AgentSpaceWorker/                  the daemon that lives in a session
  main.swift            arguments, readiness gates, bind, serve, shutdown
  WorkerContext.swift   identity and paths, resolved from the process itself
  Connection.swift      framing, OSLog categories, redaction
  Operations.swift      method dispatch — where the fail-closed order lives
  InputSynthesizer.swift  CGEvent posting, session tap only
  ScreenCapture.swift   preflight, screencapture, IHDR parsing, sips
  AppControl.swift      resolve, launch-and-wait-for-registration, quit, activate
  ShellExec.swift       posix_spawn, process group, timeout, stream capture
  AccessibilityBridge.swift  bounded AX tree walk and actions

native/AgentSpaceCLI/                     the CLI (and the MCP server's backend)
  main.swift            every command, --json everywhere, doctor
  Doctor.swift          readiness checks, each with a concrete fix

packages/agentspace-mcp/                  stdio MCP server (TypeScript)
apps/AgentSpace/                          SwiftUI app (phase 2+)
native/AgentSpacePrivilegedHelper/        the root helper (phase 3)
```

`AgentSpaceCore` is a library with no side effects and no globals, which is what
makes `SessionGuard` testable against synthetic dictionaries rather than only
against a machine that happens to have two sessions.

---

## The five invariants

Every design decision traces to one of these.

**1. Isolation.** Input is posted to `.cgSessionEventTap` only. The function that
posts takes no tap parameter, so the global HID tap is unreachable by
construction. Your mouse does not move, your keyboard is not taken, your focus
does not change, your desktop does not flicker.

**2. Fail closed.** If the session's console state cannot be *proven*, input is
refused. `indeterminate` and `isConsole` are the same refusal. There is no code
path that returns "probably fine".

**3. No fallback, ever.** If the background session is missing, offline,
unauthorised or unprovable, the operation fails with a typed reason. Nothing
retries on the console. This is why `UnavailableStatus` has no "proceed" variant
(plan §2), and why the CLI's failure path has no branch that runs a GUI command
locally.

**4. Low overhead.** Idle: main app under 100 MB and ~0% CPU; each worker under
50 MB and ~0% CPU. No continuous capture, no 100 ms polling (2–5 s, event-driven
where possible). `status` forks nothing unless you ask for `resources: "full"`.
The memory in a Space is Chrome and your IDE, not AgentSpace.

**5. Native.** Swift, SwiftUI, AppKit, CoreGraphics, ApplicationServices,
ServiceManagement, Security. No Electron, no WebView UI, no private SkyLight or
ScreenSharing frameworks, no `TCC.db` writes, no `DYLD` injection. The resource
question in (4) is the reason, and the plan's §43 is the reason for the rest.

---

## Lifecycle

### Creating a Space (plan §28)

```
Name → Workspace → Create
  → Privileged helper: create the standard (non-admin) user
  → generate a 32-byte password, store it in the Keychain
  → install the worker LaunchAgent into the agent user's ~/Library/LaunchAgents
  → prepare the runtime directory and its ACL
  → prompt: switch to AgentSpace – <name>, sign in once
  → in that session: grant Accessibility and Screen Recording
  → switch back
  → the app sees the worker come online and flips to Ready
```

The first login is manual on purpose. Doing it automatically means either a
stored auto-login credential or private APIs, and the plan (§10) explicitly
refuses to trade a large private-API surface for a one-time click.

### After a reboot

The AgentSpace user has no GUI session until someone logs in, so the Space reads
**Needs Login**. Nothing is started behind your back. One fast-user-switch login
brings it back. (Auto-login and remote session bootstrap are explicitly V1
non-goals — plan §39.)

### Stopping

| Action | Effect |
|---|---|
| **Stop Agent** | Stops the worker, keeps the GUI session |
| **Logout Desktop** | Ends the whole session, freeing more RAM |
| **Delete Space** | Stop worker → logout → remove LaunchAgent → remove runtime → delete the user → *then ask* about the home directory |

For a git-worktree workspace, deletion keeps the branch and removes the worktree.
Your original project is never touched.

---

## Deviation worth naming: the workspace

`exec`'s `cwd` and screenshot output paths are confined to the Space's declared
roots, and a path that escapes them — including through a symlink, which is
resolved before the prefix test — is refused `WORKSPACE_DENIED`.

But the agent's shell is **not** chrooted. macOS makes that expensive, and the
plan (§36) is explicit that the real boundary is the uid, the file permissions and
the session, not a sandbox AgentSpace pretends to be. Confinement is enforced on
the paths AgentSpace hands the worker, and by giving the agent account no access
to your home in the first place. When no roots are declared, `status` reports
`workspace.confined: false` rather than implying a confinement that is not in
effect. Phase 7 adds the editor that writes them.

---

## What this deliberately does not do (V1)

Cloud sync, accounts, an agent marketplace, model providers, an LLM chat UI, task
orchestration, Docker, a VM, Linux, Windows, a remote Mac, team collaboration,
screen-recording video, or complex workspace sync (plan §61).

V1 does one thing: **one Mac, several background macOS GUI sessions, an agent that
can drive them, and a human who is not interrupted.** The point is to make that
stable before making it broad.
