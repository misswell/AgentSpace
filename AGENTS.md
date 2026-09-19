# AGENTS.md — rules for AI agents working on this repository

**Read [`docs/status.md`](docs/status.md) first.** It is the handoff map: what
the product is, what is done, what is next, and where the evidence lives. This
file is the short version of the rules that are expensive to get wrong.

(Not to be confused with the §35 safety rules for agents running *inside* a
Space — those are `agentspace integrate rules` and are a different audience.)

## The product, in one breath

AgentSpace gives every AI agent its own macOS account and desktop — a real
macOS user with its own Aqua session, driven over a unix socket. Not a VM,
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
4. **Compatibility rules** (full list in [`docs/v2-plan.md`](docs/v2-plan.md)):
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

## Vocabulary (old → new; both spellings work in code and interface)

| Old | New |
|---|---|
| Space | agent account (`AgentAccount`) |
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
- Never hardcode test counts in README or docs — they drift; point at
  `docs/validation.md`.
- Record behaviour claims in [`docs/validation.md`](docs/validation.md): a new
  numbered section with a claim table (`# | Claim | Verdict | Evidence`),
  continuing the global claim index. Cite plan sections as `plan §N`
  (the original plan) or `plan(v2) §N` (`docs/v2-plan.md`).
- Commit style: no prefixes. `validation §N: <finding>`, `<scope>: <behaviour>`,
  or `<Feature>: <what and why> (plan §N)`.
- macOS facts already paid for (do not relearn): `/usr/bin/createhomedir` was
  removed by Apple — the helper skips it and macOS creates the home at first
  GUI login; `kCGSSessionManagerNameKey` is inert — `SessionGetInfo` is the
  working probe; an interrupted create can leave an orphan `_agentspace_…`
  account — the helper verifies its own cleanup and Doctor surfaces what it
  missed.
