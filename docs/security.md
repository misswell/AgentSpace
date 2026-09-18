# Security

Read `architecture.md` first for the process boundaries. This file is the threat
model, the controls, and — stated plainly — what is **not** a control.

## What AgentSpace is defending against

1. **Interrupting the human.** The agent must not move their mouse, take their
   keyboard, steal focus, or put a window on their screen. This is the
   product-level security property; if AgentSpace gets this wrong there is no
   product.
2. **An agent — or a prompt injection — doing machine-level damage.** It should
   not be able to install a daemon, create an account, modify the system, or read
   the user's private files.
3. **One Space compromising another.** A Space runs untrusted code by design. A
   browser exploit or a prompt-injected shell inside Space A must not become
   control of Space B.
4. **Anything else on the machine talking to a Space's worker**, including other
   local users.

## The controls

### The real boundary: a standard user with its own uid

This is the primary control and everything else is supplementary.

Each Space is a **standard, non-admin** macOS user with its own uid, its own home
directory and no `sudo`. That single fact removes: modifying the system,
installing system daemons, changing other accounts, reading the main user's
private files, and most of what a compromised agent would want. Plan §8.

The worker runs as that user. It never elevates. The helper never runs agent
commands. There is no path from "agent executed something" to root.

### `fail closed`, everywhere

If the session's console state cannot be proven, input is refused.

```swift
public static func verdict(using source: SessionInfoSource) -> SessionVerdict {
    if let graphic = source.hasGraphicAccess(), graphic == false { return .noWindowServer }
    switch onConsole(dictionary: source.currentSessionDictionary()) {
    case .some(true):  return .isConsole
    case .some(false): return .usable
    case .none:        return .indeterminate   // ← read as "refuse"
    }
}
```

`indeterminate` refuses exactly like `isConsole`. There is no branch that returns
`usable` on a missing answer. `testOnlyExplicitFalsePermitsInput` asserts the
property over every malformed dictionary shape.

The verdict is recomputed **per input request**, never cached: a session can
become the console at any instant, and that is precisely what fast user switching
does. A cached "not on console" is the stale answer that would type on someone's
real screen.

### The session event tap, and why the wrong tap is unreachable

Three ways exist to inject a `CGEvent`:

| Tap | What happens |
|---|---|
| `.cghidEventTap` | The window server routes it to whichever session is **on the console** — the human's screen. Never correct from a background session. |
| `postToPid` | Bypasses the window server; delivers into the void (measured: zero deliveries). |
| `.cgSessionEventTap` | The per-session entry point. From a process inside session N, the event enters session N's stream and reaches session N's key window. |

Only the third is used, and `InputSynthesizer.post` takes **no tap parameter**, so
the first is unreachable from the code rather than merely unused. That matters:
"we remember not to use it" is not a control, and a future edit cannot introduce
one by accident.

The one case where the session tap *would* reach the human's screen is if the
worker's session were the console. That is refused outright before any event is
constructed.

### The unix socket, the token, and the ACL

```
/Users/Shared/.AgentSpace/Runtime/<space-uuid>/
    worker.sock    mode 0660, group staff
    token          mode 0600, 256 bits, CSPRNG
```

Three layers:

1. **A unix socket, not a localhost port.** It cannot be reached from off the
   machine, so there is no network attack surface at all.
2. **A directory ACL limited to the main user, the agent user and root.** Applied
   with `chmod +a`, with the two account names validated by the helper before use.
   Only those principals can traverse into the directory.
3. **A 256-bit session token**, required on every method except `hello`, compared
   with `timingsafe_bcmp`.

Why a token when the directory is already restricted? Because **the agent session
can read the socket directory by design.** Without a token, anything that gets
code execution inside an AgentSpace could connect to a *sibling* Space's worker
and drive it. The token means compromising one Space does not become compromising
all of them. `testDifferentSpacesHaveDifferentTokens` asserts it: two workers, and
neither token opens the other.

A byte-by-byte comparison would leak the token's prefix through timing to anyone
who can open the socket repeatedly — the exact adversary the token exists for —
so the comparison is constant time.

### No generic root shell

The helper's XPC surface is a closed list of typed operations. There is no
`exec(command)`. See `architecture.md`.

### Refusing the spectacular commands

`exec` refuses a listed set of commands — `sudo`, `installer`, `diskutil erase`,
`launchctl bootstrap system`, `dscl create`, `sysadminctl`, `rm -rf /`,
`shutdown`, `reboot`, `csrutil`, `nvram`, `kextload`, `tccutil`,
`security authorizationdb`, and others.

**This is not a sandbox and the code says so.** Matching is on the raw command
string, so `s''udo whoami` evades it — and there is a test
(`testQuotingEvadesTheListByDesign`) that documents that, so nobody later mistakes
the list for containment. It stops the ordinary case and the obvious
prompt-injection payload. The containment is the uid.

### Workspace confinement, with symlinks resolved first

`WorkspaceGuard.resolve` canonicalises a path — expanding `~`, making it
absolute, and resolving symlinks on the longest existing prefix — **before** the
prefix test. A symlink whose string starts with an allowed root but whose target
is `/Users/you/.ssh` is therefore refused. Path comparison is on component
boundaries, so `/tmp/ws-evil` is not inside `/tmp/ws`.

Default access for a shared folder is **read-only**; write requires an explicit
`readWrite`. Not shared by default: `~`, `~/Library`, Desktop, Documents,
Downloads, `.ssh`, Keychain.

### Never touching `TCC.db`

AgentSpace does not write the TCC database, pre-seed grants, or reset them. Some
tools do and it works, but the plan (§19) is explicit that a long-lived product
should not depend on it. Grants are given by the human, in the AgentSpace
session, through System Settings — and `agentspace doctor` says exactly which
toggle is missing.

A related consequence: `screenshot` calls `CGPreflightScreenCaptureAccess()`
first and refuses **without invoking `screencapture`** when the grant is absent,
because invoking it unpermitted can raise a TCC prompt in a session nobody is
looking at — a dialog that can never be answered, appearing forever.

### Secrets

- The account password is 32 random bytes, stored in the **Keychain**, viewable
  on demand for the first login. Never in `config.json`, `UserDefaults` or a log.
- The session token lives in its `0600` file, never in the registry.
- `Redaction` scrubs both key-named secrets and any bare 64-hex-character string
  that appears inside a message, because the likeliest leak is a token
  interpolated into text rather than sitting under a key someone remembered to
  list. Every worker log line passes through it in one place, so a new log
  statement cannot forget.
- Diagnostics export strips passwords, tokens, Keychain material, typed input
  text and full screenshots (plan §37).

`testRegistryPersistsWorkspaceWithoutSecrets` asserts the registry file contains
none of `password`, `passwd`, `token`, `secret`, `keychain`.

### Never running as root

`PrivilegeGuard` refuses at startup with exit code 77 and `WORKER_IS_ROOT`. A root
worker would hand an injected agent the whole machine; the check is deliberately
not recoverable, so nothing retries it.

---

## Threat model

| Threat | Control | Residual risk |
|---|---|---|
| Agent input lands on the human's screen | Per-request fail-closed console check; session tap only, no tap parameter in the poster | None known while the check holds |
| Console state unreadable → guess | `indeterminate` refuses | None — refusal is the failure mode |
| Prompt injection runs `sudo rm -rf /` | Standard user; `exec` refusal list | Evadable by quoting, but the uid still applies |
| Agent reads the human's private files | Separate uid; agent home; explicit shared folders defaulting to read-only | A folder the human shares is readable |
| Agent escapes its workspace via a symlink | `WorkspaceGuard` resolves before the prefix test | The agent's shell is not chrooted; only AgentSpace-supplied paths are confined |
| Local user drives a Space's worker | 0700 directory + ACL + 256-bit token + constant-time compare | A same-uid compromise inside that Space |
| Compromise of Space A drives Space B | Per-Space token | None known |
| Malicious peer floods the socket | 1 MiB request cap enforced while reading; 512-action batches; 4 MiB output caps | A same-principal DoS is out of scope |
| Log leak of a token or password | `Redaction` at the single logging choke point | A future call site that bypasses `Log` |
| Helper abused for root | Closed typed XPC surface; code-signature requirement checked | Needs the phase-3 security review (§56) |
| TCC prompt loops forever | Preflight first, never invoke unpermitted | None |
| `APP_LAUNCH` returns a unusable pid | Wait for real registration | — |

## Not controls

Stated so nobody over-trusts them:

- The `exec` refusal list is a guardrail, not containment.
- The workspace confinement applies to paths AgentSpace passes in, not to an
  arbitrary shell the agent starts.
- The agent session is not sandboxed beyond the uid. It can open a network
  connection, read anything the agent user can read, and consume CPU and memory.
  `status.resources` exists so you can see that.
- `AXUIElement` access can read window titles and control elements. That is the
  point, and it is scoped to the agent session.

## Release checklist (plan §56)

Before a release, review each of these against the built artifacts:

- [ ] Unix socket ACL — directory 0700 + ACL for exactly the main user and agent
      user; socket 0660
- [ ] Token — 256 bits from the CSPRNG, `0600`, constant-time compare, required
      on every non-`hello` method
- [ ] XPC authentication — helper verifies the caller's code-signing requirement;
      no other process can call it
- [ ] Code signing — Developer ID, notarized; `SMAppService` registration
- [ ] LaunchDaemon privileges — the helper runs as root and does only the typed
      operations
- [ ] Symlink attack — `WorkspaceGuard` resolves before the prefix test; the
      runtime directory is not world-writable
- [ ] Path traversal — `..` normalised before every check
- [ ] Workspace escape — covered by `testWorkspaceCannotEscapeAllowedPath`
- [ ] Command injection — no shell string concatenation anywhere; `posix_spawn`
      with an argument vector, `chmod` with fixed arguments
- [ ] Log secret leakage — `Redaction` at the choke point; export strips typed
      text and screenshots
- [ ] **Privileged helper security review, separately** — the plan calls for this
      explicitly and it is phase 3 work

## Distribution

Not the Mac App Store in phase one: a privileged helper, creating system users, a
LaunchDaemon, cross-user IPC, Accessibility and Screen Recording are all a poor fit
for the sandbox. Developer ID + notarization + DMG, then a Homebrew cask, with the
CLI shipped inside the app (plan §57).
