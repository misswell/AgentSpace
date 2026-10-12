import type { McpServer, ToolCallback } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { CallToolResult, ToolAnnotations } from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";
import {
  buildActivateArgs, buildAppsAvailableArgs, buildAxArgs, buildClipboardArgs,
  buildMoveArgs, buildOpenResourceArgs, buildWindowArgs,
} from "./args.js";

export function registerToolPair<S extends z.ZodRawShape>(server: McpServer, suffix: string,
  config: { title: string; description: string; inputSchema: S; annotations?: ToolAnnotations },
  callback: ToolCallback<S>): void {
  for (const prefix of ["agent_", "agentspace_"]) server.registerTool(prefix + suffix, config, callback);
}

type Bridge = (args: string[], options: { context: string; stdin?: string | undefined }) => Promise<CallToolResult>;
const space = z.string().trim().min(1).describe("Connected agent account name or UUID. Use agent_list first.");
const pid = z.number().int().positive().max(2_147_483_647).optional().describe("Process in the agent session; defaults to its frontmost app.");
const selector = {
  pid,
  role: z.string().min(1).optional().describe("Exact AX role, for example AXButton or AXTextField."),
  title: z.string().min(1).optional().describe("Case-insensitive substring of the control's title, description or value."),
  identifier: z.string().min(1).optional().describe("Exact AX identifier from ax_snapshot."),
};
const text = z.string().refine(value => Buffer.byteLength(value, "utf8") <= 1_048_576, "text exceeds 1 MiB");
const readonly: ToolAnnotations = { readOnlyHint: true, destructiveHint: false };

export function registerSessionTools(server: McpServer, bridge: Bridge): void {
  registerToolPair(server, "capabilities", {
    title: "Agent desktop capability guide", inputSchema: {}, annotations: readonly,
    description: "Discover the available system-operation tools, workflows, required permissions and human-only boundaries. This describes the API; use status for the live account's readiness.",
  }, async () => ({ content: [{ type: "text", text: JSON.stringify({
    scope: "Existing standard macOS account's own background Aqua session. Call agent_list then agent_status before acting.",
    workflows: {
      apps: "apps_available → launch/activate → apps; app can be a bundle ID, name, path or running PID.",
      controls: "ax_snapshot → ax_perform (AXPress/AXShowMenu/etc from actions), or ax_set_value on a unique writable control. Use screenshot and point input for custom controls.",
      windows: "windows → window_action with windowId=id, pid and generation from that same listing. Minimized windows may disappear from this listing: ax_windows/ax_snapshot with the app PID → ax_perform AXRaise on a specific window → windows for its fresh identity. Refresh if stale.",
      browserAndDocuments: "open_resource for http/https, absolute local files/directories or file URLs; control the resulting app through AX and input.",
      clipboard: "clipboard_read / clipboard_write operate only on this account's text clipboard; use key cmd+v to paste.",
      filesAndAutomation: "exec runs file, search, network, scripting and developer tools as the agent user. cwd follows declared workspace roots; status.workspace.confined reports whether roots are declared. Inspect stdout/stderr/exitCode; OS permissions still apply.",
      systemSettings: "launch System Settings, inspect AX then act; open_resource also accepts x-apple.systempreferences URLs. Opening a pane does not grant permission.",
    },
    permissions: { inputAndAX: "Accessibility", screenshots: "Screen Recording", protectedFiles: "Full Disk Access when needed; optional" },
    boundaries: ["No fallback to the human's physical console", "No root/admin execution, account lifecycle or TCC bypass", "Login, unlock, password prompts and privacy grants require a human in macOS", "An app must expose AX or accept input; unsupported controls return errors"],
    workerUpgrade: "resource.open, clipboard.read/write and ax.setValue require Worker 0.1.82+. METHOD_NOT_FOUND means update/reinstall the Worker through AgentSpace.",
    naming: "agent_* and agentspace_* have identical schemas and behavior; agent_open_desktop opens the viewer on the human's screen only when requested.",
  }, null, 2) }] }));

  registerToolPair(server, "apps_available", {
    title: "Find installed applications", inputSchema: { space, query: z.string().optional(), limit: z.number().int().min(1).max(1000).optional(), all: z.boolean().optional() }, annotations: readonly,
    description: "Find launchable apps with bundle IDs, paths and running PIDs. query filters names/IDs/paths; all includes background agents. No icon payloads. Use before launch.",
  }, async ({ space, ...options }) => bridge(buildAppsAvailableArgs(space, options), { context: "find installed applications" }));

  registerToolPair(server, "activate", {
    title: "Activate an agent application", inputSchema: { space, app: z.string().min(1) },
    description: "Bring a running app to the front in the agent session. Accepts PID, bundle ID, name or app path; use window_action to target a particular window.",
  }, async ({ space, app }) => bridge(buildActivateArgs(space, app), { context: "activate application" }));

  registerToolPair(server, "move", {
    title: "Move the agent pointer", inputSchema: { space, x: z.number().finite(), y: z.number().finite() },
    description: "Move/hover without clicking. Coordinates are desktop points, not scaled screenshot pixels. Use input for a batch.",
  }, async ({ space, x, y }) => bridge(buildMoveArgs(space, x, y), { context: "move pointer" }));

  for (const command of ["frontmost", "windows"] as const) {
    registerToolPair(server, `ax_${command}`, {
      title: `Read AX ${command}`, inputSchema: { space, pid }, annotations: readonly,
      description: command === "frontmost" ? "Read the frontmost app and focused control in the agent session." : "Read an app's AX windows; pid defaults to the frontmost app. For actionable window identities use windows.",
    }, async ({ space, pid }) => bridge(buildAxArgs(space, command, { pid }), { context: `read AX ${command}` }));
  }
  registerToolPair(server, "ax_element_at", {
    title: "Inspect a control at a point", inputSchema: { space, x: z.number().finite(), y: z.number().finite() }, annotations: readonly,
    description: "Identify the AX control, application and PID under a desktop point before acting. Coordinates are display points.",
  }, async ({ space, x, y }) => bridge(buildAxArgs(space, "element-at", { x, y }), { context: "inspect AX control" }));

  registerToolPair(server, "ax_perform", {
    title: "Perform a control action", inputSchema: { space, ...selector, action: z.string().min(1).optional(), click: z.boolean().optional() },
    description: "Target a control by role/title/identifier from ax_snapshot. Supply action from its actions (AXPress, AXShowMenu, etc), or click=true for a coordinate click. Selectors combine; use a specific identifier/title because this operation targets the first match.",
  }, async ({ space, ...options }) => bridge(buildAxArgs(space, "perform", options), { context: "perform AX action" }));

  registerToolPair(server, "ax_set_value", {
    title: "Write a control value", inputSchema: { space, ...selector, value: z.union([text, z.number().finite(), z.boolean()]) },
    description: "Write AXValue on exactly one matching writable text field, slider or other control. Use valueSettable from ax_snapshot. Empty text clears a field. Ambiguous selectors and read-only controls fail; use keyboard/input when unsupported. Requires Worker 0.1.82+.",
  }, async ({ space, value, ...options }) => bridge(buildAxArgs(space, "set-value", options), { context: "write AX value", stdin: JSON.stringify(value) }));

  registerToolPair(server, "windows", {
    title: "List agent windows", inputSchema: { space }, annotations: readonly,
    description: "List windows discoverable by the agent session's window server, frames in points and identities (id, pid, generation). Minimized windows may disappear: inspect ax_windows and perform AXRaise to restore, then refresh this listing. Pass all three identity fields to window_action.",
  }, async ({ space }) => bridge(buildWindowArgs(space, "list"), { context: "list windows" }));

  registerToolPair(server, "window_action", {
    title: "Manage an agent window", inputSchema: { space,
      action: z.enum(["activate", "close", "minimize", "set-frame"]),
      windowId: z.number().int().min(0).max(4_294_967_295), pid: z.number().int().positive().max(2_147_483_647), generation: z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER),
      frame: z.object({ x: z.number().finite(), y: z.number().finite(), width: z.number().gt(40).finite(), height: z.number().gt(40).finite() }).optional(),
    }, annotations: { destructiveHint: true },
    description: "Activate, close, minimize, move or resize a window. Identity must come from windows (windowId=id); stale identities fail. After minimize, restore via ax_perform AXRaise on a specific AX window, then list windows for a fresh identity before activating. set-frame requires the entire frame in display points. Closing may affect unsaved work.",
  }, async ({ space, action, frame, ...target }) => bridge(buildWindowArgs(space, action, target, frame), { context: `window ${action}` }));

  registerToolPair(server, "open_resource", {
    title: "Open a resource in the agent desktop", inputSchema: { space, resource: z.string().min(1) }, annotations: { openWorldHint: true },
    description: "Open a webpage, local document/directory or System Settings URL using the default app inside the agent session. Accepts http/https, file, x-apple.systempreferences or an absolute path. Opening settings does not grant permissions. Requires Worker 0.1.82+.",
  }, async ({ space, resource }) => bridge(buildOpenResourceArgs(space, resource), { context: "open resource" }));

  registerToolPair(server, "clipboard_read", {
    title: "Read the agent clipboard", inputSchema: { space }, annotations: readonly,
    description: "Read this agent account's text clipboard (up to 1 MiB). text=null when it contains no text. Never reads the human's console clipboard. Requires Worker 0.1.82+.",
  }, async ({ space }) => bridge(buildClipboardArgs(space, "read"), { context: "read agent clipboard" }));

  registerToolPair(server, "clipboard_write", {
    title: "Write the agent clipboard", inputSchema: { space, text }, annotations: { destructiveHint: true },
    description: "Replace this agent account's clipboard with UTF-8 text, up to 1 MiB. Empty text clears it; use key cmd+v to paste. Existing clipboard formats are replaced. Requires Worker 0.1.82+.",
  }, async ({ space, text }) => bridge(buildClipboardArgs(space, "write"), { context: "write agent clipboard", stdin: text }));
}
