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
/Library/Application Support/AgentSpace/Runtime/<space-uuid>/
    worker.sock    mode 0660, group staff
    token          mode 0600, 256 bits, CSPRNG
```

Three layers:

1. **A unix socket, not a localhost port.** It cannot be reached from off the
   machine, so there is no network attack surface at all.
2. **A directory ACL limited to the main user, the agent user and root.** Applied
   with `chmod +a`, with the two account names validated by the helper before use.
   The entries inherit to the token, socket and status files; the worker refuses
   to bind if the directory owner, mode or either principal's inherited ACL is
   missing. Only those principals can traverse into the directory.
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

### A metric never spends a privacy decision

The TCC rule above has a second consequence that is easy to miss: **nothing the
product measures may read a protected folder either.** The disk-usage figure
walks the agent's own home, and a home contains exactly the directories macOS
gates — `Desktop`, `Documents`, `Downloads`, and per-app data under `Library`.

Two families of gate fail differently, and both are unacceptable as a side effect
of a number:

- The folder gates **prompt** on first read. In an unattended background session
  that dialog has nobody to answer it — the same trap `screenshot` preflights for.
- Per-app data (`kTCCServiceSystemPolicyAppDataDetailed`, Photos, Messages) is
  consulted **per access**, so a walk of `~/Library` costs one tccd round trip per
  protected container and denies hard when prompting is disallowed.

So `DiskUsage.allocatedBytes(under:skip:)` is given the roots to skip, and the
worker passes `FilePrivacy.protectedSubpaths` unless the grant exists. The result
carries `skippedProtected`, which becomes `diskExcludesProtected` on the wire and
an explicit caption in the GUI: the number is a lower bound for part of the home,
never a quiet zero for the folders nobody looked in. Skip is **root-relative** —
an agent's own `~/project/Documents` is an ordinary directory and is still counted.

Full Disk Access is therefore a first-class, *optional* third grant: it is
detected silently (`FilePrivacy.granted` — the kernel denies the open, it does not
ask, so polling is safe), offered as an in-app button that opens
`Privacy_AllFiles`, and reported by `status`, `hello`, `agentspace status` and
`agentspace doctor` as `.warn` rather than `.fail`. Its row in System Settings
exists only after a gated read has been attempted, so the button performs that
attempt from the user's explicit click — never from a poll. A missing grant does
not move `state` to `needsPermission`: an agent that can see and drive its desktop
but keeps out of `~/Documents` is working, not stuck.

### Secrets

- The existing account's password never enters AgentSpace. It is typed only into
  the macOS login window.
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
| A metric raises the prompt nobody can answer | Disk walk skips macOS-protected roots unless Full Disk Access is granted; the grant is probed by a denied open, which never prompts | The disk figure is a labelled lower bound until the grant exists |
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

Eleven compatibility operations, enumerated in `HelperOperation`, each a value type with named,
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

### 2. No shell and no account mutation

Every privileged system utility is an argv array spawned with `posix_spawn`.
There is no `/bin/sh -c`, generic command, caller-supplied worker path, or
caller-supplied arbitrary filesystem path.

V3 additionally removes directory-service mutation from the helper. The
`createUser` and `deleteUser` enum values remain only so protocol-version-1
requests decode; validation and dispatch always return `HELPER_REJECTED`.
There is no `sysadminctl` command construction or user/home deletion
implementation behind them.

### 3. Existing-account targeting is verified twice

The app offers only discovered standard local users: uid >= 500, home under
`/Users`, not the current user, not a hidden account and not an administrator.
The helper does not trust that UI decision. Immediately before worker/runtime
operations it resolves the username again, verifies its uid and home, and checks
admin-group membership. Unknown state refuses.

The helper derives the LaunchAgent path from the verified account's directory
record and derives the runtime path from a UUID beneath the fixed validated
runtime root. Detach can remove only that exact runtime and the matching
LaunchAgent; there is no API that accepts a home-directory deletion target.
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

- It refuses every operation unless it is root and the caller still satisfies
  the signing requirement.
- Its mutation list is limited to installing/removing the bundled worker,
  preparing/removing an exact account runtime, and controlling/inspecting that
  account's worker session.
- Worker code is copied only from the signed helper bundle to a root-owned,
  versioned path.
- Runtime removal requires the same UUID, verified attached username, main user
  and validated root used for preparation.
- There is no `KeepAlive` loop for a crashing root daemon.

### 6. Runtime and worker integrity

The production root is exactly
`/Library/Application Support/AgentSpace`; only explicit test roots below
`/tmp` or the legacy shared location are accepted. Shared parents are
root-owned and traversable. Each runtime directory is 0700 and widened with
inheritable ACL entries for exactly the controller and attached users.

Before binding, the worker verifies the directory exists, is a directory, has
the expected owner and restrictive mode, and carries both named inherited ACL
entries. A socket ACL failure is fatal. Each worker release is archived as a
root-owned mode-0755 file beneath `Worker/versions/<version>`. LaunchAgents use
the atomically replaced root-owned `Worker/active/agentspace-worker` hard link,
which gives releases from 0.1.11 onward one stable execution path outside every
attached user's home. Moving to that path may create a new TCC entry once. Older
versioned-path entries are macOS-owned history and may remain visible until the
user removes or disables them in System Settings; AgentSpace never edits TCC.

### 7. What a reviewer should check first

1. `HelperValidation.validateAttachedUser` and the service's live uid/home/admin
   re-check.
2. `HelperOperation`: the list must remain typed and closed.
3. `HelperCommand`: worker paths and launchctl argv only; no account mutation.
4. `RuntimePermissionVerifier` and the inherited ACL applied by the helper.
5. `CodeSigningRequirement`, including the documented pid-reuse limitation.
6. The permanent refusal behavior for legacy `createUser`/`deleteUser`.
## Release checklist (plan §56) — reviewed, with the pins named

Every item is a control documented above and a property pinned by a named test,
so the review is re-runnable rather than a one-time opinion. Status as of the
validation doc's current section; the two items that need machine capabilities
this development environment lacks are marked honestly rather than checked.

| Item | Control | Pinned by | Status |
|---|---|---|---|
| Unix socket ACL | dir 0700 + inheritable ACL for exactly main user & agent user; socket 0660; worker verifies before bind | `testACLFailureIsReported`, `testRuntimePermissionVerifierAcceptsTheTwoPrincipalACL`, `testRuntimePermissionVerifierRefusesAMissingMainUserACL`, `testEverySpaceGetsItsOwnSocketTokenAndRuntimeDirectory` | verified in tests; the ACL *application* runs in the root helper — live run blocked |
| Token | 256-bit CSPRNG, `0600`, constant-time compare, required on every non-`hello` method | `testGeneratedTokenIs256BitsOfHex`, `testGeneratedTokensDiffer`, `testDifferentSpacesHaveDifferentTokens`, `testCorruptTokenFileReadsNil`, `testHelloIsTokenExemptButLeaksNothing` | verified |
| XPC authentication | helper verifies the caller's code-signing requirement | helper validation suite (closed interface, account shape, main-user checks) | verified at the validation layer; live XPC round-trip blocked (needs the root helper) |
| Code signing | Developer ID, hardened runtime, secure timestamp, notarized, stapled; `SMAppService` registration | `codesign --verify --strict` + `stapler validate` + `spctl --assess` on the app and DMG; the whole chain was executed live | **cleared end-to-end.** Developer ID (Guofeng Liu, U8U443D7ZL) + hardened runtime + timestamps; the DMG was submitted to Apple's notary service and **Accepted**, both app and DMG stapled, and `spctl` now accepts the app — a user can download, drag-install, and open with no right-click workaround. The credential that made it work is the machine's shared Apple-ID notarytool profile (`octoshrink-notary`, verified live in-session per this machine's global rule), not the ASC API key the asc CLI had stored |
| LaunchDaemon privileges | root, typed operations only, no shell | `testThereIsNoGenericEscapeHatchInTheProtocol`, the whole helper validation suite | verified at the validation layer; live run blocked |
| Symlink attack | `WorkspaceGuard` resolves symlinks before the prefix test; runtime dir not world-writable | `testSymlinksAreNotFollowedOutOfTheDirectory`, `testSymlinkEscapeIsRefused` | verified |
| Path traversal | `..` normalised before every check | `testPathInsideAllowedRootIsAccepted`, `testPathOutsideAllowedRootIsRefused`, `testNoRootsMeansEverythingIsRefused` | verified |
| Workspace escape | the allowed-root prefix test on resolved paths | `testWorkspaceCannotEscapeAllowedPath` | verified |
| Command injection | no shell string concatenation anywhere; `posix_spawn` with an argument vector | `testRefusesPrivilegeEscalation`, `testRefusesMachineLevelChanges`, `testPathQualifiedExecutableIsStillRefused`, `testWhitespaceIsNormalisedBeforeMatching`, `testCaseInsensitiveMatching` | verified |
| Log secret leakage | `Redaction` at the choke point; diagnostics export is whitelist + redactor | `testKeyedSecretValuesAreRedactedWhateverTheKeySpelling`, `testBareHexTokenInAStringIsRedacted`, `testRedactionIsIdempotent`, `testDiagnosticsExportNeverContainsTheWorkerToken` | verified |
| **Privileged helper, separately** | §42/§56 require a dedicated review | the "privileged helper — a separate review" section above, seven numbered properties | reviewed here; live verification blocked (root) |

A release can only be signed off when the remaining blocked rows clear: the
helper installed and exercised live (which also delivers the XPC round-trip and
ACL application), observed on a real machine. Notarization is no longer among
them — it cleared end-to-end on this machine. The rest of this matrix is green
and re-runnable.

## One worker per Space is enforced by the kernel (§97)

The socket is unlinked before bind, so a naive second worker would
silently steal the endpoint. It cannot: `bind()` first takes an
exclusive, non-blocking `flock` on `worker.lock` in the runtime
directory, and the kernel releases that lock when the process dies.
A second worker therefore fails fast with exit code 78
(`EX_CONFIG`) and the message "another worker is already serving
this Space", while the first worker — and its lock — are untouched.
The lock file has no security role; its only job is to make the
racy unlink-then-bind sequence safe to run twice.

---

## Distribution

Not the Mac App Store in phase one: a privileged helper, creating system users, a
LaunchDaemon, cross-user IPC, Accessibility and Screen Recording are all a poor fit
for the sandbox. Developer ID + notarization + DMG, then a Homebrew cask, with the
CLI shipped inside the app (plan §57).

---

## The deep link is an entrance, so it stays a narrow one (§31)

`agentspace://space/<uuid>` is a cross-process entrance into the app: any local
process can post the URL, not just the CLI. That is acceptable because of what
the link can and cannot do.

What it can do: select a Space and raise the detached Desktop Viewer window. The viewer
itself is the app's pull-model preview — it talks to the worker through the
same token-gated socket as everything else, shows the same permission and
offline states, and offers input only when the worker itself said input is
permitted.

What it cannot do, by construction: start a stream against a Space the app does
not have, bypass the token, deliver input, or carry any parameter beyond the
UUID. `AppDeepLink.spaceID` refuses everything that is not an exact
`agentspace://space/<uuid>` — other schemes, other hosts, malformed paths — and
a link naming a deleted Space surfaces `SPACE_NOT_FOUND` *inside the app*, the
only place a failure is visible when the poster may be long gone.

The reviewer's check: the deep-link handler ends in `selection = id` and a
`DesktopViewerWindowManager` lookup by that UUID, and nowhere else. If it ever
grows an action parameter, this section must grow a threat model first.

---

## Account credentials

AgentSpace never asks for, generates, stores, reveals, changes or transmits the
attached macOS account's login password. The user enters the account's existing
password only at the macOS login window. This removes account credentials from
the app/helper trust boundary entirely.

The runtime session token below is not a login password and cannot authenticate a
macOS login; it authorizes requests to one worker socket.
## The session token (§20) — what it is, and what it is not

Each Space's worker speaks only to clients that present the 256-bit
token minted at first start and stored in the Space's runtime
directory as `token` (mode 600). Two properties are deliberate:

**It survives a worker restart.** The token is the shared contract
between the app, the CLI and the MCP server on one side and the
worker on the other; minting a fresh one at every launch would break
crash recovery and the reconnect path. So a leaked token does not
age out on its own — it stays valid for as long as the Space's
runtime directory exists.

**The rotation point is the Space itself.** Deleting a Space removes
the runtime directory, which is the only supported way a token dies.
There is no `--rotate-token` flag today; if one is added, it must
re-mint the file and be reflected in every client that cached the
old value. Treat a token like a credential with no expiry: never
paste it into an export (§37's redaction turns any 64-hex-char match
into `<redacted-token>`), and prefer `agentspace` commands over
hand-rolled socket clients that would need the raw value.

---

## Attaching and detaching — fail closed on the management path

Attach accepts an already existing standard account; it does not alter directory
services or account credentials. The transaction creates only AgentSpace-owned
state. If writing the runtime record, applying the workspace, installing the
worker, or saving the registry fails, it rolls back the worktree, worker and
runtime it created.

Detach is intentionally narrower than macOS user management:

- stop the account worker;
- remove its AgentSpace LaunchAgent;
- remove an AgentSpace-created git worktree while keeping its branch;
- remove the exact UUID runtime through the helper;
- remove the registry record.

A runtime-removal failure keeps the registry record so the operation can be
retried. Detach never logs out the account, deletes it, changes its password, or
removes its home. Legacy helper requests that ask for either account creation or
account deletion are rejected before dispatch.

The remaining real-machine verification is positive-path acceptance with a
manually created second standard account and its Aqua/TCC session; no
directory-service mutation is part of that test.

---

## Release gate (§56) — status

Checked by `scripts/release.sh`, which runs the full sequence and prints what each
step verified. The rule for a release script: saying "done" without saying what was
checked is how an unsigned artifact ships.

| Item (§56) | Status | Where |
|---|---|---|
| Code Signing (app, helper, worker, CLI, strict) | ✓ script, verified here | all four verify; Developer ID Application cert, team `U8U443D7ZL` |
| XPC authentication | designed + unit-tested, needs live daemon | `docs/security.md` helper section; pid + code requirement, re-verified per call |
| LaunchDaemon privileges | designed; daemon start needs an admin password | typed RPC only, no shell; `HelperValidationTests` (37 adversarial) |
| Unix Socket ACL + Token | ✓ live-worker tests | `SafetyTests`: wrong token refused, socket mode 0700 |
| Workspace escape | ✓ unit tests | `testWorkspaceCannotEscapeAllowedPath`: traversal, absolute, symlink-out |
| Command injection | partial by design | `ExecGuard` is an evadable guardrail, documented as such; the real boundary is the Standard User uid |
| Symlink attack | partial | disk walk does not follow symlinks out; runtime dirs are 0700 |
| Log secret leakage | ✓ by construction | account passwords never enter the product; runtime tokens are redacted |
| Notarization | ✓ release pipeline | `scripts/notarize.sh` uses the verified `octoshrink-notary` profile with API-key fallback |

Official builds still run release, notarization, stapling and Gatekeeper checks
in that order; no credential is stored in the repository.

---

## The console refusal covers observation too

§12's fail-closed rule was originally applied to *injection* only, and the
screenshot handler carried a reasoned comment defending the difference: capturing
the console is "what the human sees anyway". The integration suite (§21 of
validation.md) demonstrated empirically why that reading is wrong: a
console-session worker returned a full 3840px PNG of the user's actual desktop.
The same worker's `ax.windows` / `ax.snapshot` would have handed over window
titles and the accessibility tree of whatever the user was doing — structured
text, no TCC prompt, no Screen Recording grant required.

The isolation promise (§60) is about content, not just control. The invariant is
now:

> **When the session is the console, the worker serves nothing about anyone's
> desktop.** `hello`, `status`, `exec` and `shutdown` answer; `screenshot`,
> `apps`, `launch`, `quit`, `forceQuit`, `activate` and every `ax.*` method
> refuse with `SESSION_IS_CONSOLE`.

`exec` stays available deliberately: it runs commands as the *agent user* and
reads no window server state — on a console session there is no agent desktop to
protect, but the account's own files are still its own.

The reversal is recorded here rather than quietly rewritten: the old comment's own
logic — "the human sees it anyway" — was precisely the leak.
