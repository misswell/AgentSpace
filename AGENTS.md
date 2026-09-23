# AGENTS.md — rules for AI agents working on this repository

**Read [`docs/status.md`](docs/status.md) first.** It is the handoff map: what
the product is, what is done, what is next, and where the evidence lives. This
file is the short version of the rules that are expensive to get wrong.

(Not to be confused with the §35 safety rules for agents running *inside* a
Space — those are `agentspace integrate rules` and are a different audience.)

## The product, in one breath

AgentSpace connects every AI agent to an existing standard macOS account and
desktop — a real user with its own Aqua session, driven over a unix socket. It
never creates or deletes macOS users. Not a VM,
never a fallback to the human's own session. Modules: `apps/AgentSpace` (GUI),
`native/AgentSpaceWorker` (per-account daemon), `native/AgentSpaceCLI`,
`native/AgentSpacePrivilegedHelper` (root, closed op list),
`shared/Core/Sources/AgentSpaceCore` (protocol + models + safety),
`packages/agentspace-mcp`.

## Non-negotiables

1. **One branch, one folder.** Work in the `~/Code/solo/AgentSpace` checkout on
   `master`. Do **not** create worktrees or a second checkout — a previous
   round did exactly that and the owner found two project folders confusing.
   If you must isolate a risky change, use a short-lived branch in this same
   folder, merge it, and delete it.
2. **dist discipline.** `scripts/check-all.sh` refuses to pass unless
   `dist/AgentSpace.app` is notarized and stapled. So the order is always
   `scripts/release.sh` → `scripts/notarize.sh` (profile `octoshrink-notary`,
   with the `asc` API-key fallback). Never "just rebuild" `dist/`; build test
   bundles to a temp directory instead.
3. **Never add a fallback that drives the human's session.** Input is refused
   when the agent desktop is on the physical console (`SESSION_IS_CONSOLE`) —
   that refusal is the product. New privileged operations go through the
   helper's closed list of typed operations (`HelperProtocol.swift`), never
   through a shell, and never through `sudo` in the CLI.
   **Never add macOS account lifecycle back:** attach/detach may change only
   AgentSpace-owned worker, runtime, workspace and registry state.
4. **Compatibility rules** (current direction in [`docs/v3-plan.md`](docs/v3-plan.md)):
   registry JSON keys and the `"spaces"` top-level key never change; old
   records must decode unchanged (`purpose` is written only when set); wire
   methods are never renamed and `protocolVersion` stays 1 for compatible
   additions; pre-V2 CLI verbs keep working (`desktop`, bare `create NAME`);
   every `agentspace_*` MCP tool stays registered (`agent_*` names are
   additive aliases over the same builders); `agentspace://agent/<uuid>` is
   generated while the legacy `space` host still resolves.
5. **Localization.** English source text *is* the key. Core uses
   `NSLocalizedString("…", comment: "")`; GUI uses SwiftUI `Text("…")`. Every
   key must exist in **both** `apps/AgentSpace/Resources/{en,zh-Hans}.lproj/Localizable.strings`;
   `tests/Unit/LocalizationTests.swift` fails the build otherwise.
   `scripts/bundle-app.sh` copies the `.lproj` folders into the bundle.
6. **Online update.** The channel and its limits are
   [`docs/UPDATE_CHANNEL.md`](docs/UPDATE_CHANNEL.md). An in-app update replaces
   **only** `/Applications/AgentSpace.app`: never make an update touch the root
   helper or the installed worker (those move only when the user presses
   「重新安装助手…」), never relax the verification chain to make an update
   succeed, and remember that releases before 0.1.19 ship no updater — the first
   one after this feature must be installed from the DMG by hand, and a release
   note that does not say so is a broken promise (§302 row 662). Publishing is not
   done until `GET /repos/misswell/AgentSpace/releases/latest` answers the new tag:
   that endpoint *is* `SoftwareUpdater.latestReleaseURL`, and it kept serving the
   previous release for six minutes after a draft was flipped to
   `draft: false` — only a write to the release itself (`make_latest=true`) moved
   it (§318 row 820).

## Vocabulary (old → new; both spellings work in code and interface)

| Old | New |
|---|---|
| Space | agent account (`AgentAccount`) |
| Create/delete account | Connect/disconnect existing account |
| "Create Agent Space" wizard | "New Agent" wizard |
| View Desktop | Open Desktop |
| `agentspace desktop <space>` | `agentspace open <account>` |
| `agentspace list` | `agentspace accounts` |
| Offline (worker stopped, session alive) | Sleeping |

## Workflow

- Tests: `scripts/test.sh` (or `swift test`), `npm test` in
  `packages/agentspace-mcp`, `scripts/mcp-smoke.sh`, then
  `scripts/check-all.sh` as the gate. **PATH caveat**: `WorkspacePreparerTests`
  assumes `/usr/bin/git`; run with
  `env PATH=/usr/bin:/bin:/usr/sbin:/sbin swift test` or make it PATH-agnostic.
- **Layer 4 has two instruments, and neither may disturb a person.**
  `scripts/gui-verify.sh` verifies the UI on the console: it closes every
  AgentSpace copy this uid owns and drives a window on the human's screen, so it
  asks first and exits **3** ("nothing was verified") when it will not — hence
  exit 3 ≠ failure. `scripts/session-gui-verify.sh` runs the same 13 checks
  inside an agent account's own session via `agentspace exec`
  (`tests/SessionUI`, product `agentspace-gui-check`), where nothing appears on
  the owner's screen and their processes cannot even be signalled.
  `check-all.sh` falls back to it on a 3 and always prints which instrument
  answered. Reach for the session gate when anyone is at the Mac (§324).
- Never hardcode test counts in README or docs — they drift; point at
  `docs/validation.md`.
- Record behaviour claims in [`docs/validation.md`](docs/validation.md): a new
  numbered section with a claim table (`# | Claim | Verdict | Evidence`),
  continuing the global claim index. Cite plan sections as `plan §N`
  (the original plan) or `plan(v2) §N` (`docs/v2-plan.md`).
- Commit style: no prefixes. `validation §N: <finding>`, `<scope>: <behaviour>`,
  or `<Feature>: <what and why> (plan §N)`.
- macOS facts already paid for (do not relearn): `kCGSSessionManagerNameKey` is
  inert — `SessionGetInfo` is the working session probe. Runtime parents must be
  traversable before a named ACL on a child can help; the V3 parent is 0755 and
  each account runtime is 0700 plus its two-user inherited ACL. A synthetic
  scroll event posted to `.cgSessionEventTap` in a background Aqua session *does*
  enter that session's stream (a listen-only tap reads it back) and is *never*
  dispatched to an app — eight shapes, zero pixels, where the `AXVerticalScrollBar`
  value of the same scroll area moved 35,908 px (§315). Moves, clicks, drags and
  keys are dispatched normally, so scroll is its own channel problem.
  `CGEventTypes.h` field numbers, because guessing them invalidates a test:
  88 `IsContinuous`, 93 `FixedPtDeltaAxis1`, 96 `PointDeltaAxis1`,
  **99 `ScrollPhase`**, 123 `MomentumPhase`; phases `Began=1 Changed=2 Ended=4
  Cancelled=8 MayBegin=128` — 4 is `Stationary`, 8 is `Cancelled`, and there is
  no `kCGScrollWheelEventIsPixel`. A `CGEvent.tapCreate` callback runs on the run
  loop: `Thread.sleep` between posts starves it and reports "nothing arrived".
  Two shell/toolchain traps, both paid for twice: `swift build --product A
  --product B` exits **0** having built only one of them (§319 row 827), and a
  backtick inside the double-quoted `osascript -e "…"` string is a command
  substitution, so a comment that types \`like this\` *runs* — and its output is
  spliced into the script being executed (§319 row 830).
