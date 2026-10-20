# Connect your agent to AgentSpace

AgentSpace gives your AI agent its own macOS account and desktop. This guide
is for the person who wants their agent — Claude Code, Codex, Cursor, VS Code,
Zed, or any other MCP client — to actually **work on that desktop**: launch
apps, type, click, scroll, take screenshots, run tests in Terminal. Everything
happens inside the agent's own session; your screen, keyboard and focus are
never touched.

## Before you start

- AgentSpace **0.1.86 or newer** installed (`AgentSpace.app` → 检查更新).
- Node.js **18 or newer** (22 recommended) for the MCP client.
- At least one agent account connected and its session running — the app's
  account page shows the status cards, or run `agentspace accounts`.

## One command per client

Run this in Terminal (see the next section if `agentspace` is not found):

```bash
agentspace integrate <target> --install
```

`agentspace integrate` with no target lists every supported client, its
display name and the file it writes. The 24 built-in targets:

| Target | Client | Writes |
|---|---|---|
| `claude` | Claude Code | `~/.claude.json` |
| `codex` | Codex | `~/.codex/config.toml` |
| `cursor` | Cursor | `~/.cursor/mcp.json` |
| `windsurf` | Windsurf | `~/.codeium/windsurf/mcp_config.json` |
| `vscode` | VS Code (1.99+) | `~/Library/Application Support/Code/User/mcp.json` |
| `zed` | Zed | `~/.config/zed/settings.json` |
| `kiro` | Kiro | `~/.kiro/settings/mcp.json` |
| `gemini` | Gemini CLI | `~/.gemini/settings.json` |
| `qwen` | Qwen Code | `~/.qwen/settings.json` |
| `qoder` | Qoder CLI | `~/.qoder/settings.json` |
| `amazonq` | Amazon Q Developer | `~/.aws/amazonq/mcp.json` |
| `copilot` | GitHub Copilot CLI | `~/.copilot/mcp-config.json` |
| `cline` | Cline (VS Code extension) | `~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json` |
| `opencode` | OpenCode | `~/.config/opencode/opencode.json` |
| `zcode` | ZCode | `~/.zcode/cli/config.json` |
| `kimi` | Kimi Code | `~/.kimi-code/mcp.json` |
| `mimo` | Xiaomi MiMo | `~/.config/mimocode/mimocode.jsonc` |
| `crush` | Crush | `~/.config/crush/crush.json` |
| `amp` | Amp | `~/.config/amp/settings.json` |
| `factory` | Factory Droid | `~/.factory/mcp.json` |
| `minimax` | MiniMax Code | `~/.minimax/mcp.json` |
| `antigravity` | Google Antigravity | `~/.gemini/config/mcp_config.json` |
| `claude-desktop` | Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| `lmstudio` | LM Studio | `~/.lmstudio/mcp.json` |

Each target gets the **shape that client actually reads**, not one universal
JSON blob: VS Code wants `servers`, Zed wants `context_servers`, Amp wants
`amp.mcpServers`, OpenCode/Crush want `mcp`, ZCode wants nested `mcp.servers`,
Codex wants TOML. Most others take a plain `mcpServers` entry. The app's
**Install MCP Into…** menu groups the same 24 by 命令行 Agent / 编辑器 / 桌面应用 /
编辑器扩展.

For any MCP client not on that list, `agentspace integrate generic` prints a
generic `mcpServers` entry to paste into whatever file that client reads — or
point `--install` at the file directly:

```bash
agentspace integrate generic --install --config ~/path/to/your-client.json
```

Every target also accepts plain `agentspace integrate <target>` (prints the
config for you to paste yourself) and `--json` (machine-readable, for
scripting or any other MCP client).

**What the command does — and does not do.** It writes exactly one
`agentspace` entry into that file and nothing else; everything already in the
file is preserved (including MiMo's `$schema` or ZCode's `plugins`). If the
file existed, its previous contents are saved next to it as
`<file>.agentspace.bak` first. A custom Codex TOML entry is refused rather than
overwritten; a precisely matching old generated `npx` entry can migrate to the
bundled service. JSON clients retain their one-key merge behavior. A settings
file that uses `//` comments (VS Code, Zed, MiMo) is left untouched and the
command says so: rewriting it would delete your comments, so edit that one by
hand with the printed config.
From 0.1.82 the configuration starts the server shipped with this App, without
fetching `@agentspace/mcp` from npm. Rerun integration after updating from an
older version and restart the client to reload its tools. The entry pins the
MCP server to *this* install's CLI via `AGENTSPACE_BIN` —
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
`apps`, and friends. Every tool also has an identical `agent_*` name.
Ask for `agent_capabilities` to see application/window management, AX actions,
value writes, resource opening and clipboard workflows. See
[system feature coverage](MCP_SYSTEM_FEATURES.md) for the full map.

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
  restarted the client after the install, and that Node.js ≥ 18 is available.
  The bundled launcher checks PATH, Homebrew and Volta, or uses the absolute
  `AGENTSPACE_MCP_NODE` path. `@agentspace/mcp` has no public npm release;
  replace an old npx entry by rerunning integration with the updated App.
- **The AI says there is no AgentSpace while the account page says 就绪** —
  the two answer different questions: the page describes the desktop, the
  client's config decides whether it has any `agentspace_*` tools. An entry
  written before 0.1.82 still runs `npx -y @agentspace/mcp`, which cannot
  start. Since 0.1.83 `agentspace doctor` prints an **Agent connections**
  check naming each client and, for one that is broken, the exact repair
  command; the account page shows the same as **Agent 连接**. Repair with
  `agentspace integrate <target> --install` and restart that client.
- **Tools error with a session-unavailable code** — wake the account in the
  app. If it persists, `agentspace doctor` diagnoses the machine, and
  `agentspace diagnostics` exports a redacted bundle.
- **You configured a client by hand and it half-works** — remove your
  `agentspace` entry and re-run `agentspace integrate <target> --install`, or
  compare against what the plain (no `--install`) command prints; the shapes
  differ per client and a near-miss is silently ignored by some of them
  (ZCode's schema is strict).
