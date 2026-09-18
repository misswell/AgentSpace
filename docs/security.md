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

## The privileged helper — a separate review

Plan §56 asks for the helper to get its own security review, on the grounds that
it is the only root component and therefore the only place where a bug is not
contained by the per-Space user. This is that review. It is written to be read
adversarially: each section is "what can be made to happen", not "what the code
does".

### The threat model, stated once

The adversary is **the agent**. That is unusual, and it is the point of the
product: AgentSpace deliberately gives a model-driven process the ability to
click, type and run commands on a computer. So the helper must assume the caller
is running someone else's instructions, that those instructions may include
"become an administrator" or "read the other Space's data", and that the caller
may have already compromised the app process itself. Anything the helper exposes
is reachable by that adversary.

The adversary is *not* assumed to be root. If an attacker already has root, the
helper is irrelevant — they can `dscl` directly. The helper exists to make sure
that **not** having root is enough to stay safe, and that the path from "can drive
a desktop" to "can create and delete accounts" does not exist.

### 1. The interface is a closed list, and that is the primary control

Nine operations, enumerated in `HelperOperation`, each a value type with named,
typed fields. There is no `runShell`, no `writeFile`, no `chmod`, no
`executeAtPath`.

This is the control the others support rather than duplicate. A generic escape
hatch would make every other measure irrelevant: if the helper can be made to run
an arbitrary command as root, then validating the username perfectly is beside the
point. `testThereIsNoGenericEscapeHatchInTheProtocol` fails the day somebody adds
an operation whose name has a `run`, `exec`, `write` or `path` component, and
`testNoRequestFieldCanCarryAnArbitraryCommand` fails the day the wire format gains
a field, so both changes require deliberately editing a test that says "confirm
this cannot carry a command".

### 2. No shell, anywhere

Every privileged command is an `argv` array spawned with `posix_spawn`
(`CommandRunner.run`). There is no `/bin/sh -c` in the helper, and
`testNoCommandEverInvokesAShell` asserts it.

The consequence is worth stating plainly, because it is the reason the display
name does not need to be sanitised for shell purposes: **there is no quoting
layer**. A display name containing `; rm -rf /` is one `argv` element that
`sysadminctl` receives as a literal display name. The attack that this
traditionally enables does not have a representation in this design.

### 3. Accounts are `_agentspace_` plus six hex characters, and only those are reachable

`HelperValidation.isAgentSpaceAccount` is a single rule with three parts: a fixed
prefix, a fixed length, and a closed character set. One rule, obviously complete,
rather than five that each handle a case somebody thought of. It simultaneously
excludes:

| Attack | Why it fails |
|---|---|
| Delete the user's own account | `guofeng` has no `_agentspace_` prefix |
| Delete `root`, `_mbsetupuser` | same, plus an explicit protected list |
| Traverse with `..` | `.` is not in the alphabet |
| Inject a second argument | space is not in the alphabet |
| Be read as a flag by `dscl` | `-` is not in the alphabet |
| Shell metacharacters | none are in the alphabet |
| Non-ASCII lookalikes | all are outside the alphabet |

`isAgentSpaceAccount` is checked *again* inside `HelperService.deleteUser`,
against the account as it exists on the machine, and the home path is built from
the validated name rather than taken from the request — so there is no path field
to aim at `/Users/guofeng`, and `removeHome` can only ever remove the Space's own
home.

`testASpaceCanNeverBeGrantedAccessToAnotherSpace` covers the subtler version of
the same problem: granting an AgentSpace account access to a sibling's runtime
directory would hand over a socket carrying a live session token, so the main user
must be a human account.

### 4. Caller verification, and one honest limitation

The helper checks the connecting process's code signature against
`anchor apple generic and certificate leaf[subject.OU] = "U8U443D7ZL" and
(identifier "com.agentspace.AgentSpace" or "com.agentspace.AgentSpace.Helper")`,
and rejects the connection otherwise. It also re-verifies the pid immediately
before every privileged operation, so occupying the check once is not enough.

**The limitation.** The correct identity for an XPC peer is its audit token, which
the kernel supplies and the peer cannot forge. The supported API for using one is
`xpc_peer_requirement_create_team_identity` — added in **macOS 26.0**, and
documented in the SDK as "the peer has the specified identity and is signed with
the same team identifier as the current process", which is exactly this check. It
takes an `xpc_object_t`, so using it means abandoning `NSXPCConnection` for raw
XPC.

`NSXPCConnection` exposes only `processIdentifier` — verified directly against
`Foundation/NSXPCConnection.h`, which declares `processIdentifier` and nothing
else. So on the supported API surface the check is pid-based, and that leaves a
**pid-reuse window**: if the real app exits at exactly the right moment, an
attacker's process could be assigned the same pid and satisfy the check.

Three things reduce it, and none eliminates it:

1. The signature is validated, so the attacker must present code signed with our
   Team ID — an ad-hoc binary with a copied identifier does not pass.
2. The process is re-identified and its cdhash compared, so an attacker must be
   the same *code* twice, not merely occupy the pid once.
3. The check runs again immediately before each privileged operation.

This is recorded rather than papered over because it is a real residual risk and
the fix is known: move the helper to raw XPC and use `xpc_peer_requirement`. That
is the recommended change for the next iteration — it is the one place where the
supported API is weaker than the platform allows. The plan's §3 also asks to avoid
macOS 26-only APIs while targeting 26+, so the right shape is
`if #available(macOS 26.0, *)` with the pid check as the documented fallback.

### 5. The helper refuses to be useful by accident

- It exits **77** if `geteuid() != 0`, matching the worker's wrong-privilege code.
  A helper that cannot be privileged does not half-perform an operation.
- `handle` re-checks root before dispatching.
- `createUser` cleans up a half-created account if `sysadminctl` fails, so the
  next attempt does not hit a confusing "already exists".
- `deleteUser` **verifies** the account is gone rather than assuming, because the
  app removes the Space from its registry immediately afterwards and an orphan
  account would be unreachable.
- `UserID` below 500 is refused on delete: a `_agentspace_`-named account can
  never legitimately be a system account.
- There is no `KeepAlive` in the LaunchDaemon plist, deliberately: restarting a
  crashing root daemon in a loop would hide from review the bug that made it
  crash. `testTheLaunchDaemonPlistIsValidAndMatchesTheMachServiceName` asserts it
  is absent.

### 6. Things that are *not* in the helper, and cannot be

- **No `-admin`.** `HelperCommand.createUser` never passes it, there is no
  parameter that could, and `testCreateUserIsNeverAnAdministrator` asserts the
  generated command lacks `-admin`, `-adminUser` and `-secureToken`. Plan §8: a
  Space is a standard user.
- **No worker path from the caller.** The helper installs its own bundled
  `agentspace-worker`, never a path the app supplies. A caller-controlled path
  here would be arbitrary code execution as a launchd job.
- **No `TCC.db` writes anywhere in the project.**
- **No arbitrary-file operations.** Even `prepareRuntimeDirectory` accepts only a
  space ID, an account, a main user and a runtime root, and the runtime root must
  be under `/Users/Shared` or `/tmp` — so the chmod/chown it performs cannot be
  aimed at a system directory.

### 7. What a reviewer should check first

In order of how much damage a mistake would do:

1. `HelperValidation.isAgentSpaceAccount` — the whole of §3 rests on it, and it is
   one small function.
2. `HelperCommand` — every command the helper can run, in one file, as arrays.
3. `HelperValidation.validate` — the per-operation rules, especially that
   `deleteUser` requires `isAgentSpaceAccount`.
4. `CodeSigningRequirement` — and the limitation in §4 above.
5. The absence of `-c` in any `posix_spawn` call.

`agentspace-helper --self-check` reports what a *particular installed* helper will
enforce, which is what a reviewer should run on the machine rather than reading
the source and assuming.

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
