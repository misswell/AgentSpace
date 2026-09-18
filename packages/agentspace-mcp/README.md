# @agentspace/mcp

A [Model Context Protocol](https://modelcontextprotocol.io) server that lets an
agent drive a **background macOS desktop** through
[AgentSpace](https://github.com/agentspace) — without touching the human's own
screen.

AgentSpace runs agents inside isolated macOS user sessions ("Spaces"), each with
its own Aqua/WindowServer session. It is **not** a VM. This server is a thin
bridge: every action is delegated to the local `agentspace` Swift CLI, which is
the same core API the AgentSpace GUI uses.

> **The one rule:** this server never runs a GUI command itself and never falls
> back to your console session. If AgentSpace reports that the Space's session
> is unavailable, the error is relayed — code, message and `fix` — and nothing
> else is tried.

---

## Install

Requires **Node >= 18** and a working `agentspace` binary.

```bash
# from this directory
npm install
npm run build
```

Run it over stdio:

```bash
node dist/index.js
# or, once published:
npx @agentspace/mcp
```

### Client configuration

```jsonc
{
  "mcpServers": {
    "agentspace": {
      "command": "npx",
      "args": ["-y", "@agentspace/mcp"],
      "env": {
        // optional — see "Binary discovery" below
        "AGENTSPACE_BIN": "/Applications/AgentSpace.app/Contents/MacOS/agentspace"
      }
    }
  }
}
```

Pointing at a locally built copy instead:

```jsonc
{
  "mcpServers": {
    "agentspace": {
      "command": "node",
      "args": ["/absolute/path/to/packages/agentspace-mcp/dist/index.js"]
    }
  }
}
```

---

## Binary discovery

The server looks for the `agentspace` CLI **in this order**:

1. the `AGENTSPACE_BIN` environment variable,
2. `/Applications/AgentSpace.app/Contents/MacOS/agentspace`,
3. each directory on `PATH`.

If `AGENTSPACE_BIN` is set but does not point at an executable file, the server
does **not** silently fall through to the next candidate. An explicit override
that does not work is a configuration mistake, and quietly running some other
binary would hide it — so the tool call fails with a message naming every
location that was tried.

Discovery happens **per tool call**, not at startup. If no binary is found, the
server still starts and every tool call returns a clear error explaining how to
install AgentSpace or point at the binary. The server never crashes at startup
because the CLI is missing.

### Environment variables

| Variable | Meaning |
| --- | --- |
| `AGENTSPACE_BIN` | Absolute path to the `agentspace` CLI. Highest-priority discovery source. |
| `AGENTSPACE_ROOT` | Passed through to the CLI unchanged. Use it for alternate installations and testing. |
| `AGENTSPACE_MCP_TIMEOUT_MS` | Per-call timeout in milliseconds. Default `120000` (120s). Non-positive or unparsable values fall back to the default; a call is always bounded. |

---

## Tools

All 14 tools are prefixed `agentspace_`. Coordinates are always **display
points**, never screenshot pixels — see "Points vs pixels" below.

### Read-only

| Tool | What it does |
| --- | --- |
| `agentspace_list` | List every Space: id, name, macOS user, state, workspace, worker reachability. Start here to discover Space names. |
| `agentspace_status` | One Space's health: worker liveness, session verdict, Accessibility + Screen Recording grants, display geometry, resource use. |
| `agentspace_screenshot` | Capture the Space's desktop. Returns an **image** plus path, width, height, pixelWidth, pixelHeight and scale. |
| `agentspace_apps` | List apps running inside the Space (pid, name, policy, frontmost). |
| `agentspace_ax_snapshot` | Accessibility element tree of the Space (or one pid) with roles, titles and identifiers. |

### Input (these change the Space's desktop)

| Tool | What it does |
| --- | --- |
| `agentspace_input` | Perform a **batch** of actions in one call: `move`, `click`, `doubleClick`, `rightClick`, `drag`, `scroll`, `type`, `key`, `sleep`. Preferred — the whole batch is validated before anything runs. |
| `agentspace_click` | Click at a point (`double`, `right` optional). |
| `agentspace_type` | Type literal text into the focused control. Does not press Return. |
| `agentspace_key` | Press a key combo, e.g. `cmd+l`, `escape`. |
| `agentspace_scroll` | Scroll the focused view by an integer delta (`dy` negative scrolls down). |
| `agentspace_drag` | Press, move, release between two points. |
| `agentspace_launch` | Launch an app inside the Space. |
| `agentspace_quit` | Quit an app inside the Space (graceful, or `force`). |
| `agentspace_exec` | Run a shell command **as the Space's user, inside the Space**. Returns stdout, stderr, exitCode and duration. |

### The `agentspace_input` batch

```json
[
  {"type": "move", "x": 500, "y": 300},
  {"type": "click", "x": 500, "y": 300, "button": "left", "count": 1, "modifiers": ["cmd"]},
  {"type": "drag", "fromX": 1, "fromY": 1, "toX": 50, "toY": 50, "button": "left"},
  {"type": "scroll", "dx": 0, "dy": -500},
  {"type": "type", "text": "hello"},
  {"type": "key", "key": "cmd+l"},
  {"type": "key", "keys": ["cmd", "enter"]},
  {"type": "sleep", "ms": 250}
]
```

Every coordinate here is in **points**.

---

## Recommended agent loop

```
status  →  screenshot  →  reason  →  input  →  screenshot  →  verify
```

1. **`agentspace_status`** — confirm the worker is running, the session is
   usable, and the TCC grants are present. Fail here before doing anything.
2. **`agentspace_screenshot`** — look before you act. Read the reported `scale`.
3. **Reason** about the image.
4. **`agentspace_input`** — send one batch (or a single-purpose tool for a
   one-off). Prefer batching: fewer round trips, and a rejected batch performs
   nothing.
5. **`agentspace_screenshot`** — verify what actually happened, and correct if
   it did not.

This loop is also embedded in the server's MCP `instructions`, so clients that
surface instructions will show it to the model automatically.

### Points vs pixels

Input coordinates are **display points**, not screenshot pixels:

```
points = pixels / scale
pixels = points * scale
```

A feature at pixel `(px, py)` in a screenshot with `scale = 2` is at point
`(px / 2, py / 2)`. Passing pixel coordinates is the most common mistake and it
silently clicks the wrong thing, so `agentspace_screenshot` always reports
`scale`, `width`/`height` (the PNG actually written) and
`pixelWidth`/`pixelHeight` (the full framebuffer before any downscale).

### If the agent desktop is on the physical console

Synthetic input is **refused** with code `SESSION_IS_CONSOLE` when the Space's
desktop is currently on the physical console (for example someone
fast-user-switched into it). The refusal is deliberate: the events would
otherwise land on the human's own screen. Switch back to your own account and
input resumes. Relay the error's `fix`; do not retry in a loop.

---

## GUI-only operations (intentional omission)

There is **deliberately no tool** for:

- **creating or deleting a Space** — that makes or removes a macOS user, and
- **granting Accessibility or Screen Recording (TCC)** — that is a
  privacy-permission change in the agent user's session.

Both go through AgentSpace's privileged helper and the **AgentSpace GUI**. A
human must do them. If a task seems to need one of these, stop and ask the human
— that is a design decision, not a missing feature. Do not work around it by
shelling out to `sudo`, `dscl` or `tccutil`.

---

## Error handling

Every CLI call is checked in one place:

- **Failure envelope** (`{"ok": false, "error": {...}, "fix": "..."}`) → the MCP
  tool result is `isError: true` and the text contains the error **code**, the
  **message** and the **fix**. Codes are the AgentSpace ones — `SESSION_IS_CONSOLE`,
  `SESSION_NOT_READY`, `WORKER_OFFLINE`, `ACCESSIBILITY_DENIED`,
  `SCREEN_RECORDING_DENIED`, `INVALID_COORDINATE`, `NO_INPUT_TARGET`,
  `APP_NOT_FOUND`, `APP_LAUNCH_TIMEOUT`, `EXEC_DENIED`, `COMMAND_TIMEOUT`, and so on.
- **Non-zero exit without a failure envelope** → reported as an error, with the
  full parsed result attached. (`agentspace exec` exits with the *inner*
  command's status after a successful RPC, so that case is called out
  explicitly.)
- **stdout that is not JSON** → an error containing the exit code plus the
  stdout and stderr tails. That is a bug report, not a silent failure.
- **Timeout** → an error naming the limit and the `AGENTSPACE_MCP_TIMEOUT_MS`
  override.

The CLI is always run with `spawn(bin, args)` — no shell, arguments passed as an
array — so no argument value can be reinterpreted as shell syntax. Free-text
arguments that begin with `-` are protected with the CLI's `--` end-of-flags
separator.

---

## Development

```bash
npm install
npm run build          # tsc -> dist/
node --test test/      # unit tests for the pure arg builders
npm start              # run the stdio server
```

`test/args.test.mjs` imports the compiled `dist/args.js`, so **build before
testing**. It covers the argv mapping (for example `agentspace_click` →
`["click", space, "10", "20", "--json"]`, `--double` handling, `exec --cwd`) and
the rejection of missing or malformed required arguments.

> **Note on `node --test test/`:** Node 18 and 20 expand a bare directory
> argument; Node 21+ does not, and would try to run `test/` itself as a module.
> `test/package.json` sets `main` to the real test file so the documented
> `node --test test/` command works on every supported Node, including 24. This
> is a runner compatibility shim, not a published package.

### Layout

| File | Purpose |
| --- | --- |
| `src/index.ts` | MCP server, tool registrations, and the single CLI-invocation path. |
| `src/args.ts` | Pure argv builders — no I/O, fully unit tested. |
| `src/binary.ts` | Lazy `agentspace` binary discovery. |
| `src/cli.ts` | `spawn` wrapper with timeout and buffered capture. |
| `src/envelope.ts` | JSON parsing, failure-envelope recognition, error formatting. |
| `test/args.test.mjs` | `node --test` tests for the arg builders. |
