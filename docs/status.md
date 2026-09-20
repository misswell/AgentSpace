# Project status — V3 handoff

Read this first when resuming AgentSpace. The binding product direction is
[`docs/v3-plan.md`](v3-plan.md); detailed historical evidence remains in
[`docs/validation.md`](validation.md).

Last updated: 2026-09-20 on `master`.

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
- ScreenCaptureKit desktop stream with screenshot fallback, keyboard/mouse
  input, application control and guarded command execution.
- CLI and MCP account/status/desktop/app/exec surfaces. Old wire method names,
  `agentspace_*` MCP tools, registry keys and deep-link compatibility remain.
- English and Simplified Chinese localization with automated key parity.
- Signed, notarized and stapled release pipeline.
- Three reported permissions: Accessibility and Screen Recording gate the
  desktop, optional Full Disk Access gates this account's own protected folders.
  Each is detectable without prompting, has its own in-app authorization button,
  and is reported by GUI, `agentspace status` and `agentspace doctor`.

## Still missing

V3 does not make the later roadmap appear by renaming Phase 1:

1. **Agent runtime manager / profiles** — compose startup apps, workspace and a
   command such as Claude Code into one Start action. The low-level launch and
   exec RPCs already exist.
2. **Binary capture migration / Desktop performance pass** — Core framing and
   back-pressure exist, but Desktop and Fusion still pull base64 JPEG over the
   JSON socket. Move both to a binary frame socket, then tune toward 15 FPS.
3. **Real-machine acceptance** — connect a manually created standard account,
   enter its Aqua session, grant Accessibility and Screen Recording, prove the
   worker online, and complete the Desktop and Fusion TextEdit gates while the
   main desktop is unaffected. Two Fusion checks are owed by validation §296:
   input against two overlapping windows of one app, and a text selection or
   slider driven through a proxy.
4. **Multi-account soak** — two attached accounts working concurrently while
   the human continues normal work.
5. **Fusion V2 surfaces** — transient windows, explicit clipboard bridging and
   restricted transfer-directory drag and drop remain intentionally deferred.

## V4 Fusion implementation state

The first Fusion vertical slice is now implemented in this tree:

- `preview.frame` re-checks the live session on every pull and tears capture
  down on console, indeterminate or no-WindowServer transitions.
- `RemoteWindow` uses `pid + windowID + generation`; `window.list` exposes only
  visible layer-0 regular-app windows discovered through public APIs.
- `window.stream.*` captures one desktop-independent `SCWindow` at the panel's
  pixel size, retaining only the newest JPEG. `window.input` accepts
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
  `INPUT_BUSY_BY_HUMAN` during that interval.
- Settings now separates Accounts, Permissions, Performance and Advanced.
- The fixed binary `FrameHeader` and one-slot back-pressure primitive are in
  Core and tested. The current first-slice app still pulls JPEG through the
  compatible JSON RPC; the separate binary socket migration remains P8/P9.

The code gates can verify protocol, lifecycle and mapping. The defining
TextEdit cross-session acceptance still requires the attached account's real
Aqua session and TCC grants, and must not be represented as passed until that
manual run is recorded in `docs/validation.md`.

## Required verification

Use the repository gates, not a remembered test count:

```bash
env PATH=/usr/bin:/bin:/usr/sbin:/sbin swift test
(cd packages/agentspace-mcp && npm test)
scripts/mcp-smoke.sh
scripts/check-all.sh
```

For official `dist/`, always run `scripts/release.sh` and then
`scripts/notarize.sh`; `check-all.sh` intentionally rejects an unstapled app.

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
- Validation evidence: `docs/validation.md`
