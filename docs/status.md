# Project status — the handoff document

**Read this first if you are picking AgentSpace up.** It is the map: what the
product is, what is done, what is left, and the conventions a change must not
break. The exhaustive evidence lives in `docs/validation.md` (266 numbered
sections, each with claims and the tests that pin them); the product plan for
the account vocabulary lives in `docs/v2-plan.md`. This file is the summary
those two assume you already found.

Last updated: 2026-09-19, at `master` = the merge of `v2-agent-account`
(commit `6732a62`), pushed to `origin`.

---

## 1. What AgentSpace is

**Give every AI agent its own macOS account and desktop.**

Not a VM, not a remote machine, not a second macOS install. It is macOS's own
multi-user GUI support — the mechanism Fast User Switching is built on. Each
agent account is a real macOS user with its own Aqua session, its own
WindowServer connection, its own files, keychain and browser data. You keep
working in your own account; your pointer, keyboard and focus are never taken.

Object chain: **Agent Account → macOS User → Desktop Session → Agent Runtime**
(the last stage — the runtime manager — is the next round of work).

Three processes, one wire protocol:

```
AgentSpace.app (GUI, runs as you)
      │ unix socket RPC, token-authenticated
agentspace-worker (runs inside the agent's own Aqua session)
      │
agentspace-helper (root LaunchDaemon; a closed list of typed operations)
```

The CLI (`agentspace`) and the MCP server (`@agentspace/mcp`, which bridges to
the CLI) are the third and fourth surfaces; all four speak the same protocol
(`docs/protocol.md`), which is the one-implementation rule (plan §49).

## 2. Repository state

- **One branch: `master`.** Nothing else, local or remote. In particular the
  temporary `v2-agent-account` branch was merged (commit `6732a62`) and
  deleted, and the worktree directory `../AgentSpace-v2` it lived in was
  removed. **Do not recreate a second checkout**: work in
  `~/Code/solo/AgentSpace`.
- **Working tree clean**, pushed to `origin/master`.
- **Tests: 373 Swift + 23 MCP, all green** (counts drift; `scripts/test.sh`
  and `npm test` are the truth). One caveat in §5.
- **`dist/`** holds the release artifact (`AgentSpace.app` + `AgentSpace-0.1.0.dmg`),
  Developer ID signed (`U8U443D7ZL`). `dist/` is gitignored and *guarded*:
  `scripts/check-all.sh` refuses to pass unless the app is **notarized and
  stapled**, and the DMG contains exactly those bytes. Rebuild → notarize,
  never rebuild alone (see §5).

## 3. What is done (and where the evidence is)

| Area | State | Evidence |
|---|---|---|
| Create flow end-to-end: helper makes the macOS user, runtime dir, LaunchAgent | ✅ works | validation §265 ("the first real create"); fixed the macOS 27 `createhomedir` removal — the helper now skips the missing tool (`HelperService.createUser`) |
| Orphan-account recovery: interrupted creates leave `_agentspace_…` accounts the UI could not see | ✅ Doctor lists them and the app removes them with a button (`Delete Orphaned Accounts…`) — the user never meets `sysadminctl` | validation §265; `runDoctor`/`deleteOrphanedAccounts` in `AppModel`, helper ops in `HelperService` |
| First login flow (the one manual step: fetch password → Fast User Switching → grant Accessibility + Screen Recording → switch back) | ✅ app walks through it | `LoginInstructions`/`LoginPasswordView`; validation §28-era sections |
| Desktop Viewer: ScreenCaptureKit stream at 5 FPS, 1 FPS screenshot fallback, click-to-input with correct point/pixel mapping | ✅ | validation §52; `DesktopViewerView`, `PreviewController`, `ScreenCaptureKitSource` |
| Fail-closed safety: input refused when the agent desktop is on the physical console; exec guard; no fallback to the human's session ever | ✅ | `SessionGuard`/`ExecGuard`; validation §12/§48; safety suite over a live socket |
| V2 account vocabulary: `AgentAccount` record, purpose-driven 3-step wizard, Finder-style account cards, menu bar, "Open Desktop" | ✅ merged | `docs/v2-plan.md` §1–§9, §14–§16; validation §266 |
| CLI: `accounts`/`open`/`create account` (new) beside `list`/`desktop`/`create` (kept) | ✅ | validation §266; CLI smoke |
| MCP: `agent_list/status/open_desktop/screenshot/click/type/launch/exec` beside the 14 `agentspace_*` tools | ✅ | `packages/agentspace-mcp`; `scripts/mcp-smoke.sh` |
| Localization: English + Simplified Chinese, English source text as the key | ✅ 364 keys per table | `tests/Unit/LocalizationTests.swift` enforces parity and coverage |
| Release pipeline: bundle → sign → DMG → notarize → staple | ✅ working | `scripts/release.sh`, `scripts/notarize.sh`; validation §57 |

## 4. What is next

### 4a. For the human (only a person can do these)

1. **Remove the leftover orphan account** `_agentspace_a5b707` (from a create
   that failed before the `createhomedir` fix). Open the app → ⌘⇧D (Doctor) →
   the red "Orphaned accounts" row → **Delete Orphaned Accounts…**.
2. **Create the first usable agent** and complete its one manual first login
   (password → Fast User Switching → grant the two permissions → switch back).
   The wizard and the Space page walk through it.
3. **Notarization credential**: `scripts/notarize.sh` defaults to the keychain
   profile `octoshrink-notary` (verified live on 2026-09-19), falling back to
   the `asc` API key. If both are gone, store credentials as its instructions
   say; **the dist guard fails without a stapled app**, so a release cannot
   skip this step.

### 4b. For the next agent (development)

In priority order:

1. **Runtime Manager** (`docs/v2-plan.md` §10/§11) — the biggest missing
   product piece. Launch Terminal/Chrome/VS Code inside the agent session and
   run the agent's own command (e.g. `claude`) there; per-purpose startup
   templates read from the `purpose` field already stored on the record.
   Groundwork that exists: `SpaceService.launch/activate/quit` wrappers and the
   `Method.launch/activate/quit/exec` wire methods.
2. **Preview tuning** (`v2-plan` §8): raise the live stream toward the 15 FPS
   target where the machine allows; keep the 1 FPS fallback.
3. **The three external gates** recorded in validation §263/§265 — the
   root-only helper chain test with approval prompts disabled, the second-GUI-
   session acceptance run for §44/§48's positive isolation half, and the public
   release URL the Homebrew cask waits on. These need decisions/access outside
   the repo; do not invent filler to close them.
4. **Multi-agent soak** (`v2-plan` §13/§21 Phase 5): two agents working (code +
   test) while the human works, with the isolation invariants held.

## 5. Conventions and gotchas a new agent must know

**Localization.** English source text *is* the key. GUI literals use SwiftUI
`Text("…")`; Core uses `NSLocalizedString("…", comment: "")`. Both
`apps/AgentSpace/Resources/{en,zh-Hans}.lproj/Localizable.strings` must carry
every key — `LocalizationTests` fails the build otherwise. `scripts/bundle-app.sh`
copies the `.lproj` folders into `Contents/Resources`; without them every lookup
silently falls back to English.

**Compatibility rules (binding, from `v2-plan.md`).**
1. Registry JSON (`<root>/Spaces/index.json`) — stored field names and the
   `"spaces"` key never change; old records must decode unchanged; `purpose` is
   written only when set.
2. Wire protocol — no method renames; `protocolVersion` stays 1 for compatible
   additions.
3. CLI — pre-V2 verbs keep working (`desktop`, bare `create NAME`); the V2
   spellings are primary in help text.
4. MCP — every `agentspace_*` tool stays registered; `agent_*` names are
   additive and share the same builders.
5. Deep links — `agentspace://agent/<uuid>` is generated; the legacy
   `agentspace://space/<uuid>` still resolves.

**Test PATH caveat.** `WorkspacePreparerTests` asserts the git path is
`/usr/bin/git`. With Homebrew's git earlier on `PATH` that test fails — an
environment artifact, not a regression. Run the suite with a system PATH
(`env PATH=/usr/bin:/bin:/usr/sbin:/sbin swift test`) or fix the test to be
PATH-agnostic.

**dist discipline.** `check-all.sh` runs first a dist guard: if
`dist/AgentSpace.app` exists it must `stapler validate`, and the DMG must
contain exactly that app. So: `scripts/release.sh` → `scripts/notarize.sh`, in
that order, and never "just rebuild" dist. If you must rebuild for testing,
build to a temp directory instead.

**macOS 27 specifics already learned (do not relearn).**
- `/usr/bin/createhomedir` was removed by Apple; the helper skips it and macOS
  creates the home at first GUI login (validation §265).
- `kCGSSessionManagerNameKey` is inert; `SessionGetInfo` is the working
  session probe (`SystemSessions`, THIRD_PARTY_NOTICES records this).
- A create that fails after `sysadminctl -addUser` can leave an orphan; the
  helper now verifies its own cleanup, and Doctor surfaces anything it missed.

**Vocabulary map** (old → new; both spellings work in code and interface):

| Old | New |
|---|---|
| Space | agent account (`AgentAccount`) |
| "Create Agent Space" wizard | "New Agent" wizard |
| View Desktop | Open Desktop |
| `agentspace desktop <space>` | `agentspace open <account>` |
| `agentspace list` | `agentspace accounts` |
| Offline (worker stopped, session alive) | Sleeping |

## 6. Where to look

| Question | File |
|---|---|
| What is verified, with measurements? | `docs/validation.md` |
| What is the V2 product plan, section by section, and its status? | `docs/v2-plan.md` |
| How do the processes talk? | `docs/protocol.md` |
| What is the threat model, and what is *not* a control? | `docs/security.md` |
| An error code decoded | `docs/troubleshooting.md` |
| Module map and invariants | `docs/architecture.md` |
| Build/test/package scripts | `scripts/{build,test,bundle-app,release,notarize,check-all,mcp-smoke}.sh` |
