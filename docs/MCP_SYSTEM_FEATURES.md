# MCP system feature coverage

AgentSpace exposes the connected standard account's background macOS desktop.
The aim is broad daily system use through native desktop input, Accessibility
and execution as that account. An API entry is not proof that every app or
protected macOS operation supports automation; live evidence is in validation §383.

Every suffix below works with both `agent_` and `agentspace_`. Begin with
`list`, `status` and `capabilities`. Console desktop access is refused; use
status and the returned recovery path when a desktop operation is unavailable.
The controller never operates its own desktop.

| System task | Available route | Practical limits |
| --- | --- | --- |
| Discover and run applications | `apps_available`, `apps`, `launch`, `activate`, `quit` | Apps launch inside the agent session; running PIDs must belong to that session. |
| Menus, buttons, tabs and dialogs | `ax_snapshot`, `ax_frontmost`, `ax_element_at`, `ax_perform` | Read supported AX actions first. Specific selectors avoid the first-match ambiguity of `ax_perform`. Custom controls may need input. |
| Edit fields and adjust sliders | `ax_set_value`, or `type`/`key`/`input` | Value writes require exactly one writable matching control. Secure/password prompts remain human-mediated. |
| Window management | `windows`, `ax_windows`, `window_action`, `ax_perform` | Activate, close, minimize or set geometry. Minimized windows may disappear from `windows`: use the app PID and a specific AX window selector with `AXRaise` to restore, then obtain a fresh id/pid/generation. Closing can affect unsaved documents; some apps lack AX geometry support. |
| Mouse and keyboard | `move`, `click`, `drag`, `key`, `scroll`, `input` | Display points. Scroll must include its point inside a scroll area. Batches validate before executing, but are not transactions that can roll back earlier actions. |
| Screenshots and multiple displays | `screenshot` | Screen Recording grant required. Display indices start at 1. Use the printed image-to-point factors, including downscaling and origin. |
| Browser, documents and Finder folders | `open_resource` then AX/input | http/https, local file/path and System Settings URLs. Browser internals, app-specific data APIs and custom schemes are not dedicated MCP APIs. |
| Clipboard copy/paste | `clipboard_read`, `clipboard_write`, `key` (`cmd+c`, `cmd+v`) | Plain UTF-8 text up to 1 MiB. Writes replace other formats. Rich image/file clipboard APIs are not included. |
| Files, search, archives, networking and developer tools | `exec` with installed tools/scripts | Runs as the account, with OS file permissions and the existing exec guards. It is not a general root/admin service. Declared workspace roots govern cwd; the shell's existing confinement limits remain. |
| Per-account System Settings | `launch` System Settings / `open_resource` settings URL, then AX/input | Settings available to the standard user can be operated. A privacy pane opening is not a privacy grant. Network, Bluetooth, audio and display controls depend on macOS/app permissions and AX support. |
| View the agent desktop personally | `open_desktop` | Human-facing operation: it opens a viewer on the person's screen when requested. Automation should use the background tools. |
| Login, unlocking, administrator approval, TCC grants | Human authenticates in macOS; AgentSpace shows recovery entries | No password API, root shell, permission bypass or account lifecycle API is exposed. Machine restart/shutdown and protected service changes retain the exec guard refusals. |

## Suggested workflow

1. Confirm session readiness and required grants with `status`.
2. Discover the app or window. Inspect AX and prefer supported named actions.
3. If the control is custom, take a screenshot, convert its image pixels using
   the printed factors and send point input. Verify the resulting state.
4. Use `exec` for account-level files and scripts; inspect exit status and output.
5. On errors, follow the supplied fix. An older Worker rejecting an additive
   method needs a Worker update, not a fallback on the console.

## Delivery and remaining gaps

Update AgentSpace to 0.1.82, use its existing helper/Worker reinstall action as
needed for the Worker change, then rerun the client integration action and
restart the MCP client. The app now carries the server and production dependencies;
Node.js 18+ remains required (22 recommended). A source checkout can use
`packages/agentspace-mcp/launch.sh` after building the package.

Remaining dedicated APIs include rich clipboard formats, app-specific browser
DOM/data integration, notifications/media devices and scheduled automation.
Many of those tasks already have an AX/input/exec route, but that route needs
per-task verification. System authentication and authorization are intentional
human boundaries, not features to bypass to claim full coverage.
