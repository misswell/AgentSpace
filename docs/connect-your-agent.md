# Connect your agent to AgentSpace

AgentSpace gives your AI agent its own macOS account and desktop. This guide
is for the person who wants their agent — Codex, Claude Code, ZCode, Kimi
Code, Xiaomi MiMo, OpenCode, or any MCP client — to actually **work on that
desktop**: launch apps, type, click, scroll, take screenshots, run tests in
Terminal. Everything happens inside the agent's own session; your screen,
keyboard and focus are never touched.

## Before you start

- AgentSpace **0.1.59 or newer** installed (`AgentSpace.app` → 检查更新).
- At least one agent account connected and its session running — the app's
  account page shows the status cards, or run `agentspace accounts`.

## One command per client

Run this in Terminal (see the next section if `agentspace` is not found):

```bash
agentspace integrate <target> --install
```

| Target | Client | Writes |
|---|---|---|
| `claude` | Claude Code | `~/.claude.json` |
| `codex` | Codex | `~/.codex/config.toml` |
| `opencode` | OpenCode | `~/.config/opencode/opencode.json` |
| `zcode` | ZCode | `~/.zcode/cli/config.json` |
| `kimi` | Kimi Code | `~/.kimi-code/mcp.json` |
| `mimo` | Xiaomi MiMo | `~/.config/mimocode/mimocode.jsonc` |

Every target also accepts plain `agentspace integrate <target>` (prints the
config for you to paste yourself) and `--json` (machine-readable, for
scripting or any other MCP client).

**What the command does — and does not do.** It writes exactly one
`agentspace` entry into that file and nothing else; everything already in the
file is preserved (including MiMo's `$schema` or ZCode's `plugins`). If the
file existed, its previous contents are saved next to it as
`<file>.agentspace.bak` first. If the file already contains a different
`agentspace` entry, the command refuses rather than overwriting your setup.
The entry pins the MCP server to *this* install's CLI via `AGENTSPACE_BIN` —
that binding is what carries the macOS permissions; do not repoint it at
another copy.

Prefer clicking to typing? The app does the same thing: account page →
**Install MCP Into…** → pick the client, confirm, done.

## If the terminal says `command not found`

The CLI ships inside the app bundle and is not on your `PATH`. Either add a
once-and-forget alias:

```bash
echo 'alias agentspace=/Applications/AgentSpace.app/Contents/Helpers/agentspace' >> ~/.zshrc && source ~/.zshrc
```

or link it where your shell already looks:

```bash
sudo ln -sf /Applications/AgentSpace.app/Contents/Helpers/agentspace /usr/local/bin/agentspace
```

## Restart the client, then check

Restart Codex (or whichever client you configured) and ask it something like
「调用 agentspace_status」/ "call agentspace_status". If it answers, the bridge
is live: the agent now has the `agentspace_*` tools — `exec`, `launch`,
`screenshot`, `click`, `type`, `key`, `scroll`, `drag`, `ax_snapshot`,
`apps`, and friends.

## Tell it to work — and give it the rules

From here you just ask in natural language, for example:

> 在 agent 桌面里打开 Terminal，运行 swift test，失败就用 agentspace_screenshot 截图给我。
>
> Open Terminal on the agent desktop, run the test suite, and screenshot any failure.

Two habits worth keeping. First, put AgentSpace's four safety rules where the
agent reads its instructions — one command prints them, `--install` appends
them between clearly-marked sections it owns (idempotent, backed up):

```bash
agentspace integrate rules                 # print, to paste into AGENTS.md / CLAUDE.md
agentspace integrate rules --install       # write into ~/CLAUDE.md
agentspace integrate rules --config ~/.codex/AGENTS.md --install
```

The rules — written in Chinese, ready to paste — tell the agent to **prefer**
AgentSpace and say so out loud when it cannot:

```text
- 优先使用 AgentSpace：任何需要图形界面、会打开可见 macOS 窗口的操作，尽量用 AgentSpace 提供的 `agentspace_*` 工具（或 `agentspace` 命令行）在 Agent 桌面上执行。
- AgentSpace 可用时，不要在用户当前会话中直接启动 GUI 应用。
- 如果 AgentSpace 报告后台会话不可用，把问题报告给用户，不要无声地改用其他方式。
- AgentSpace 不可用或确实无法完成时，才回退到用户当前会话执行，并明确告知用户。
```

Second, remember the agent desktop is a real, separate macOS session: if a
tool reports that the session is unavailable, wake the account in the AgentSpace
app (the session may have been logged out) and try again — that refusal is the
safety design working, not a bug.

## Troubleshooting

- **`command not found`** — see the alias above.
- **The client starts but no `agentspace_*` tools appear** — make sure you
  restarted the client after the install, and that `npx` works in a terminal
  (`node` ≥ 18). The MCP server runs via `npx -y @agentspace/mcp`.
- **Tools error with a session-unavailable code** — wake the account in the
  app. If it persists, `agentspace doctor` diagnoses the machine, and
  `agentspace diagnostics` exports a redacted bundle.
- **You configured a client by hand and it half-works** — remove your
  `agentspace` entry and re-run `agentspace integrate <target> --install`, or
  compare against what the plain (no `--install`) command prints; the shapes
  differ per client and a near-miss is silently ignored by some of them
  (ZCode's schema is strict).
