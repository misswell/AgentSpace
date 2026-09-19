# AgentSpace V2 — the agent-account product plan

> 原文（中文产品方案 V2）由产品提供；本文件是它在仓库中的规范化版本，
> 每一节标注了当前状态。状态含义：
> **done** — 本轮（v2-agent-account）已落地；**next** — 下一轮；
> **kept** — 既有设计，保持不变；**never** — 永久不做。

**Landed on `master`** (merge commit `6732a62`); this file and
`docs/status.md` are the record. Sections marked *next* are the remaining
work.

V2 redefines the product: **AgentSpace is a macOS-native multi-user agent
desktop manager**. Not a VM, not a remote machine — one Mac, several AI-agent
users, each with its own hidden desktop.

Object chain (was `Space → Worker`):

```
Agent Account → macOS User → Desktop Session → Agent Runtime
```

User story: give every AI agent its own macOS account and desktop. The agent
browses, codes, tests and operates GUI apps while the human keeps working.

## Status by section

| § | Section | Status |
|---|---|---|
| 1 | Product definition: "Give every AI agent its own macOS account and desktop" | done (README, GUI copy) |
| 2 | Core concept: manage several macOS agent users; the human's account is unaffected | done (README + GUI copy) |
| 3 | Primary object `Space` → **Agent Account** (`AgentAccount` record; `displayName`/`macOSUsername`/`status` aliases; registry JSON keys unchanged) | done |
| 4 | User mental model: account cards with macOS user + desktop status | done (`AgentCardGrid`) |
| 5 | Create wizard: name → purpose → what-will-be-created → provisioning → first login | done (`NewAgentWizard`, 3 steps + provisioning + `LoginInstructions`); first login kept as-is (a GUI session must be initialized by macOS) |
| 6 | Architecture split: main app / agent user / agent runtime | kept (already the shipped architecture) |
| 7 | Desktop Viewer productized as "Open Desktop" | done (title "«name» Desktop", toolbar "Open Desktop") |
| 8 | Viewer tech: screenshot+input RPC now, SCK stream at 15 FPS later | kept — SCK streaming already shipped (§52); FPS tuning is next |
| 9 | Control model: main app sends tasks/status only; worker drives the session | kept (fail-closed input path unchanged) |
| 10 | Runtime Manager: launch Terminal/Chrome/VS Code/Claude in the agent session | next (SpaceService.launch/activate/quit wrappers landed as groundwork) |
| 11 | Agent Profile: workspace, startup apps, command, MCP | next (purpose stored on the record now) |
| 12 | Workspace belongs to the account; git worktree recommended | kept (existing `Workspace` model, `agentspace/` branches) |
| 13 | Multiple agents side by side | kept (already supported; isolation validated) |
| 14 | Finder-style home instead of a dashboard | done (`AgentCardGrid`) |
| 15 | Menu bar: agents + statuses + Open/Settings/Quit | done (`MenuBarExtra`) |
| 16 | CLI: `create account`, `list`, `open`, `start/stop`, `exec` | done (new verbs; old verbs remain as aliases) |
| 17 | MCP: `agent_list/status/open_desktop/screenshot/click/type/launch/exec` | done (old `agentspace_*` tools remain as aliases) |
| 18 | Safety model: never touch the human's desktop; check session UID + console state | kept (SessionGuard/ExecGuard fail-closed, unchanged and re-validated) |
| 19 | Delete flow: stop runtime → logout → remove worker → delete user → (optional) home | kept (existing rollback-ordered `SpaceProvisioner.delete`) |
| 20 | Status model incl. `sleeping` | done (display names: Sleeping = session alive, worker stopped; registry rawValues unchanged) |
| 21 | Phases 1–5 | 1–2 were already shipped and validated; this round completes the product layer; 3–4 next; 5 kept |
| 22 | Never: VM, images, snapshots, CPU/RAM allocation, virtual disks | never |
| 23 | Final README description | done |
| 24 | End state: create a Coding Agent; Claude Code/Chrome/VS Code all run there | next (needs §10/§11) |

## Compatibility rules (binding on every V2 change)

1. Registry JSON (`<root>/Spaces/index.json`): old records decode unchanged;
   `purpose` is written only when set.
2. Worker wire protocol: no method renamed, protocolVersion unchanged.
3. CLI: every pre-V2 verb keeps working (`desktop`, bare `create NAME`, …);
   V2 verbs (`open`, `accounts`, `create account`) are the primary spelling.
4. MCP: every `agentspace_*` tool stays registered; `agent_*` names are
   additive and share the same bridge.
5. Deep links: `agentspace://agent/<uuid>` is generated; the legacy
   `agentspace://space/<uuid>` still resolves.

## Implementation map (this round)

- `shared/Core/Sources/AgentSpaceCore/SpaceModel.swift` — `AgentAccount`,
  `AgentPurpose`, status display names.
- `shared/Core/Sources/AgentSpaceCore/AppDeepLink.swift` — dual-host links.
- `apps/AgentSpace/Views/NewAgentWizard.swift` — the three-step wizard +
  `HelperCard` (moved out of DoctorView.swift).
- `apps/AgentSpace/Views/Components.swift` — `AgentCardGrid`, V2 empty state.
- `apps/AgentSpace/App/AgentSpaceApp.swift` — `MenuBarExtra`, "New Agent…".
- `apps/AgentSpace/Services/SpaceService.swift` — launch/activate/quit
  wrappers (runtime-manager groundwork).
- `native/AgentSpaceCLI/Sources/AgentSpaceCLI/main.swift` — verb aliases,
  usage rewrite, account vocabulary.
- `packages/agentspace-mcp/src/{index,args}.ts` — `agent_*` tools,
  `buildOpenDesktopArgs`, instructions.
