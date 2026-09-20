#!/usr/bin/env node
/**
 * @agentspace/mcp — an MCP server that bridges to the `agentspace` CLI.
 *
 * AgentSpace runs AI agents inside isolated macOS user sessions ("Spaces") so
 * an agent can click, type, launch apps and screenshot a *background* desktop
 * without disturbing the human's own desktop. It is not a VM.
 *
 * THE ONE RULE THIS FILE MUST NEVER BREAK
 * ---------------------------------------
 * The MCP server never drives the GUI itself and never falls back to the user's
 * console session. Every action is delegated to the `agentspace` CLI, which is
 * the single core API shared with the GUI. If the CLI reports that the Space's
 * session is unavailable (for example `SESSION_IS_CONSOLE`), that error is
 * relayed to the caller with its code, its message and its `fix`. There is no
 * code path here that "just runs it locally because the background session was
 * unavailable".
 *
 * A second, deliberate omission: creating or deleting Spaces, and the TCC
 * grants they need (Accessibility, Screen Recording), are NOT exposed as tools.
 * A human has to do those in the AgentSpace GUI. If a caller asks for them, the
 * correct answer is that no such tool exists — that is intentional, not a gap.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";

import {
  ArgError,
  buildAppsArgs,
  buildAxSnapshotArgs,
  buildClickArgs,
  buildDragArgs,
  buildExecArgs,
  buildInputArgs,
  buildKeyArgs,
  buildLaunchArgs,
  buildListArgs,
  buildOpenDesktopArgs,
  buildQuitArgs,
  buildScreenshotArgs,
  buildScrollArgs,
  buildStatusArgs,
  buildTypeArgs,
  serializeActions,
} from "./args.js";
import { discoverBinary } from "./binary.js";
import { resolveTimeoutMs, runAgentspace } from "./cli.js";
import {
  formatFailure,
  formatUnparsableOutput,
  parseJson,
  readFailureEnvelope,
  tail,
} from "./envelope.js";

// MARK: - MCP content helpers

/** The MCP tool result type, straight from the SDK so shapes stay in sync. */
type ToolResult = CallToolResult;

function textResult(text: string): ToolResult {
  return { content: [{ type: "text", text }] };
}

function errorResult(text: string): ToolResult {
  return { content: [{ type: "text", text }], isError: true };
}

function prettyJson(value: unknown): string {
  const rendered = JSON.stringify(value, null, 2);
  return rendered === undefined ? String(value) : rendered;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asString(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function asNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

// MARK: - Running the CLI and turning its answer into a tool result

type InvokeOutcome =
  | { kind: "ok"; value: unknown }
  | { kind: "error"; result: ToolResult };

interface InvokeOptions {
  /** Human-readable description of the call, used in error text. */
  context: string;
  /** Text written to the child's stdin (`agentspace input --file -`). */
  stdin?: string | undefined;
}

/**
 * Ask the CLI once and classify the answer. This is the *only* place that
 * talks to AgentSpace, which is what keeps the "no local fallback" rule true by
 * construction rather than by discipline.
 */
async function invoke(argsArray: string[], options: InvokeOptions): Promise<InvokeOutcome> {
  const discovery = discoverBinary();
  if (!discovery.ok) {
    // Not found is a per-call error, not a startup crash: the server stays up
    // so the client receives a useful explanation instead of a dead process.
    return { kind: "error", result: errorResult(discovery.message) };
  }

  const timeoutMs = resolveTimeoutMs();
  const runOptions: { timeoutMs: number; stdin?: string | undefined } = { timeoutMs };
  if (options.stdin !== undefined) {
    runOptions.stdin = options.stdin;
  }

  const result = await runAgentspace(discovery.path, argsArray, runOptions);

  if (result.spawnError !== undefined) {
    return {
      kind: "error",
      result: errorResult(
        [
          `Could not start the agentspace CLI at ${discovery.path}: ${result.spawnError}`,
          "",
          "The binary was found but could not be executed. A wrong architecture,",
          "a quarantine flag, or a broken symlink are the usual causes. Fix the",
          "binary, or point AGENTSPACE_BIN at a working one.",
        ].join("\n"),
      ),
    };
  }

  if (result.timedOut) {
    const stderrTail = tail(result.stderr);
    return {
      kind: "error",
      result: errorResult(
        [
          `The agentspace CLI timed out after ${timeoutMs} ms while running: ${options.context}`,
          "",
          `The timeout is configurable with AGENTSPACE_MCP_TIMEOUT_MS (currently ${timeoutMs} ms).`,
          "Raising it will not help if the Space's worker is offline — check `agentspace_list`.",
          stderrTail.length > 0 ? `\n--- stderr (tail) ---\n${stderrTail}` : "",
        ]
          .join("\n")
          .trimEnd(),
      ),
    };
  }

  const parsed = parseJson(result.stdout);
  if (parsed === undefined) {
    // The CLI contract says stdout is always JSON with --json. Anything else is
    // a bug, so report it as one rather than swallowing it.
    return {
      kind: "error",
      result: errorResult(
        formatUnparsableOutput({
          context: options.context,
          exitCode: result.exitCode,
          signal: result.signal,
          stdout: result.stdout,
          stderr: result.stderr,
          truncated: result.truncated,
        }),
      ),
    };
  }

  const failure = readFailureEnvelope(parsed);
  if (failure !== undefined) {
    // The important branch: relay code + message + fix, and do not retry.
    return { kind: "error", result: errorResult(formatFailure(failure, options.context)) };
  }

  if (result.exitCode !== 0) {
    // Non-zero without a failure envelope. `agentspace exec` is the documented
    // case: a successful RPC whose inner command exited non-zero. Report it as
    // an error (never swallow it) but hand back the full result either way.
    return {
      kind: "error",
      result: {
        content: [
          {
            type: "text",
            text: `agentspace exited with code ${result.exitCode} while running: ${options.context}\n\nFull result follows. For \`agentspace exec\` this is the exit status of the command inside the Space, not a failure of AgentSpace itself.`,
          },
          { type: "text", text: prettyJson(parsed) },
        ],
        isError: true,
      },
    };
  }

  return { kind: "ok", value: parsed };
}

/** Run the CLI and render a successful JSON result as text. */
async function callCli(argsArray: string[], options: InvokeOptions): Promise<ToolResult> {
  const outcome = await invoke(argsArray, options);
  if (outcome.kind === "error") {
    return outcome.result;
  }
  return textResult(prettyJson(outcome.value));
}

/**
 * Turn a screenshot result into text plus an MCP image block.
 *
 * The text names every geometry field the CLI reports and, crucially, reminds
 * the caller that input coordinates are points, not screenshot pixels.
 */
function screenshotResult(value: unknown): ToolResult {
  const record = isRecord(value) ? value : {};
  const path = asString(record["path"]);
  const width = asNumber(record["width"]);
  const height = asNumber(record["height"]);
  const pixelWidth = asNumber(record["pixelWidth"]);
  const pixelHeight = asNumber(record["pixelHeight"]);
  const scale = asNumber(record["scale"]);
  const base64 = asString(record["pngBase64"]);

  const scaleForMath = scale !== undefined && scale > 0 ? scale : 1;
  const lines = [
    "Screenshot of the AgentSpace desktop.",
    "",
    `path: ${path ?? "(not reported)"}`,
    `width: ${width ?? "?"}  height: ${height ?? "?"}   (PNG pixels actually written)`,
    `pixelWidth: ${pixelWidth ?? "?"}  pixelHeight: ${pixelHeight ?? "?"}   (full framebuffer before any downscale)`,
    `scale: ${scale ?? "?"}`,
    "",
    "IMPORTANT — input coordinates are display POINTS, not screenshot pixels:",
    `  points = pixels / scale    (pixels = points * scale)`,
    `  with scale ${scaleForMath}, a feature at pixel (px, py) is at point (px / ${scaleForMath}, py / ${scaleForMath})`,
    "Pass points to agentspace_click / agentspace_input. If the image was",
    "downscaled with maxWidth, use the reported width/height for the image and",
    "the pixelWidth/pixelHeight (and scale) only for the point conversion.",
  ];

  const content: ToolResult["content"] = [{ type: "text", text: lines.join("\n") }];

  if (base64 !== undefined && base64.length > 0) {
    content.push({ type: "image", data: base64, mimeType: "image/png" });
  } else {
    content.push({
      type: "text",
      text: "Note: the CLI did not return `pngBase64`, so no image block is attached. The PNG is still on disk at the path above.",
    });
  }

  return { content };
}

// MARK: - Server

const INSTRUCTIONS = `AgentSpace gives every AI agent its own macOS account and desktop. Each agent account is a real macOS user with its own background desktop session, so an agent can click, type, launch apps and take screenshots without disturbing the human's own screen. This server is a thin bridge to the local \`agentspace\` CLI; it never drives the GUI itself and never falls back to your console session.

Tool names: the agent_* names (agent_list, agent_status, agent_open_desktop, agent_screenshot, agent_click, agent_type, agent_launch, agent_exec) are the current spelling. The older agentspace_* tools (agentspace_list, agentspace_status, agentspace_screenshot, agentspace_apps, agentspace_ax_snapshot, agentspace_input, agentspace_click, agentspace_type, agentspace_key, agentspace_scroll, agentspace_drag, agentspace_launch, agentspace_quit, agentspace_exec) remain available with identical behaviour — existing configurations keep working. Prefer the agent_* names in new work.

Recommended loop:
1. agent_status — confirm the account exists, its worker is running, and its session permits input. Check accessibility/screenRecording here first.
2. agent_screenshot — look before you act. Read the reported scale.
3. Reason about the image.
4. agentspace_input — send one batch of actions (preferred: fewer round trips, and the batch is validated before anything is performed). The single-purpose tools (agent_click, agent_type, agentspace_key, agentspace_scroll, agentspace_drag) each send a one-action batch.
5. agent_screenshot — verify what actually happened, and correct if it did not.

Coordinates are display POINTS: points = screenshot pixels / scale. Passing pixel coordinates is the most common mistake and it silently clicks the wrong thing.

WARNING: synthetic input is refused with code SESSION_IS_CONSOLE when the agent desktop is currently on the physical console (for example someone fast-user-switched into it). The refusal is deliberate: the events would otherwise land on the human's own screen. Switch back to your own account and input resumes. Relay the error's fix rather than retrying in a loop.

No tool creates or deletes agent accounts, and no tool grants Accessibility or Screen Recording. Those are macOS-user- and TCC-level actions that a human must do in the AgentSpace GUI. If a task seems to need them, stop and ask the human.`;

const server = new McpServer(
  {
    name: "agentspace",
    version: "0.1.7",
  },
  {
    capabilities: { tools: {} },
    // Where the SDK expects it: the second (options) argument.
    instructions: INSTRUCTIONS,
  },
);

const spaceSchema = z
  .string()
  .min(1)
  .describe(
    'Space name or UUID, e.g. "research" or "7E1B4C2A-...". Use agentspace_list to see the available Spaces.',
  );

const modifierSchema = z
  .string()
  .describe(
    'Modifier name: "cmd", "ctrl", "alt", "shift" or "fn". Common aliases ("command", "control", "option", "meta", "super") are accepted.',
  );

// The batch action schema mirrors the CLI's `input --file -` payload. The Space
// worker validates the whole batch before performing any of it, so this schema
// stays permissive about names/aliases and strict only about shape.
const clickFields = {
  x: z.number().describe("X in display points (not screenshot pixels)."),
  y: z.number().describe("Y in display points (not screenshot pixels)."),
};

const inputActionSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("move"),
    ...clickFields,
  }),
  z.object({
    type: z.literal("click"),
    ...clickFields,
    button: z.enum(["left", "right", "middle"]).optional().describe("Mouse button; default left."),
    count: z.number().int().min(1).max(5).optional().describe("Click count; 2 or more is a double-click."),
    modifiers: z.array(modifierSchema).optional().describe("Modifiers held during the click."),
  }),
  z.object({
    type: z.literal("doubleClick"),
    ...clickFields,
    button: z.enum(["left", "right", "middle"]).optional(),
    modifiers: z.array(modifierSchema).optional(),
  }),
  z.object({
    type: z.literal("rightClick"),
    ...clickFields,
    modifiers: z.array(modifierSchema).optional(),
  }),
  z.object({
    type: z.literal("drag"),
    fromX: z.number().describe("Start X in display points."),
    fromY: z.number().describe("Start Y in display points."),
    toX: z.number().describe("End X in display points."),
    toY: z.number().describe("End Y in display points."),
    button: z.enum(["left", "right", "middle"]).optional(),
    modifiers: z.array(modifierSchema).optional(),
  }),
  z.object({
    type: z.literal("scroll"),
    dx: z.number().int().optional().describe("Horizontal scroll delta; default 0."),
    dy: z.number().int().optional().describe("Vertical scroll delta; negative scrolls down."),
    x: z.number().optional().describe("Optional anchor X in display points."),
    y: z.number().optional().describe("Optional anchor Y in display points."),
  }),
  z.object({
    type: z.literal("type"),
    text: z.string().describe("Literal text to type into the focused control."),
  }),
  z.object({
    type: z.literal("key"),
    key: z.string().optional().describe('Key combo as one string, e.g. "cmd+l". Use this or `keys`.'),
    keys: z
      .array(z.string())
      .optional()
      .describe('Key combo as an array, e.g. ["cmd","enter"]. Exactly one non-modifier key.'),
  }),
  z.object({
    type: z.literal("sleep"),
    ms: z.number().int().min(0).max(30_000).describe("Let the target settle, in milliseconds."),
  }),
  z.object({
    type: z.literal("wait"),
    ms: z.number().int().min(0).max(30_000).describe("Alias of sleep."),
  }),
]);

// MARK: read-only tools

server.registerTool(
  "agentspace_list",
  {
    title: "List AgentSpaces",
    description:
      "Deprecated alias of agent_list. List every AgentSpace on this machine with its id, name, macOS user, state, workspace and whether its worker is currently reachable. Start here to discover valid Space names. Read-only.",
    inputSchema: {},
    annotations: { readOnlyHint: true },
  },
  async () => callCli(buildListArgs(), { context: "agentspace list" }),
);

server.registerTool(
  "agentspace_status",
  {
    title: "Status of a Space",
    description:
      "Report one Space's health: worker liveness, session verdict (usable / on-console / no window server), Accessibility and Screen Recording grants, display geometry in points and pixels, and resource use. Call this before acting. Read-only.",
    inputSchema: {
      space: spaceSchema
        .optional()
        .describe("Space name or UUID. Omit to use the first registered Space."),
    },
    annotations: { readOnlyHint: true },
  },
  async ({ space }) =>
    callCli(buildStatusArgs(space), {
      context: `agentspace status ${space ?? "(default space)"}`,
    }),
);

server.registerTool(
  "agentspace_screenshot",
  {
    title: "Screenshot a Space",
    description:
      "Capture the Space's background desktop and return it as an image, plus path, width, height, pixelWidth, pixelHeight and scale. Input coordinates are POINTS = pixels / scale. Read-only.",
    inputSchema: {
      space: spaceSchema,
      maxWidth: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Downscale the returned PNG to at most this many pixels wide."),
      display: z.number().int().min(0).optional().describe("0-based display index to capture."),
      out: z.string().optional().describe("Explicit path for the PNG inside the Space's workspace."),
    },
    annotations: { readOnlyHint: true },
  },
  async ({ space, maxWidth, display, out }) => {
    const options: { maxWidth?: number | undefined; display?: number | undefined; out?: string | undefined } = {};
    if (maxWidth !== undefined) options.maxWidth = maxWidth;
    if (display !== undefined) options.display = display;
    if (out !== undefined) options.out = out;
    const outcome = await invoke(buildScreenshotArgs(space, options), {
      context: `agentspace screenshot ${space}`,
    });
    if (outcome.kind === "error") {
      return outcome.result;
    }
    return screenshotResult(outcome.value);
  },
);

server.registerTool(
  "agentspace_apps",
  {
    title: "List running apps in a Space",
    description:
      "List the applications running inside a Space, with pid, name, window policy and which one is frontmost. Use it to find a target for agentspace_launch or to check what is on screen. Read-only.",
    inputSchema: { space: spaceSchema },
    annotations: { readOnlyHint: true },
  },
  async ({ space }) =>
    callCli(buildAppsArgs(space), { context: `agentspace apps ${space}` }),
);

server.registerTool(
  "agentspace_ax_snapshot",
  {
    title: "Accessibility snapshot of a Space",
    description:
      "Return the Accessibility element tree of a Space (optionally for one pid), with roles, titles and identifiers. Use it to target controls precisely instead of guessing coordinates. Read-only.",
    inputSchema: {
      space: spaceSchema,
      pid: z.number().int().optional().describe("Restrict the snapshot to this process id."),
      maxDepth: z.number().int().positive().optional().describe("Maximum tree depth to walk."),
      maxNodes: z.number().int().positive().optional().describe("Maximum number of nodes to return."),
      all: z
        .boolean()
        .optional()
        .describe("Include non-interactive elements. By default only interesting nodes are returned."),
    },
    annotations: { readOnlyHint: true },
  },
  async ({ space, pid, maxDepth, maxNodes, all }) => {
    const options: {
      pid?: number | undefined;
      maxDepth?: number | undefined;
      maxNodes?: number | undefined;
      all?: boolean | undefined;
    } = {};
    if (pid !== undefined) options.pid = pid;
    if (maxDepth !== undefined) options.maxDepth = maxDepth;
    if (maxNodes !== undefined) options.maxNodes = maxNodes;
    if (all !== undefined) options.all = all;
    return callCli(buildAxSnapshotArgs(space, options), {
      context: `agentspace ax ${space} snapshot`,
    });
  },
);

// MARK: input tools (these change the Space's desktop)

server.registerTool(
  "agentspace_input",
  {
    title: "Send a batch of input actions to a Space",
    description:
      "Perform several input actions in one call: move, click, doubleClick, rightClick, drag, scroll, type, key, sleep. Coordinates are display POINTS. The whole batch is validated before anything runs, so a rejected batch performs nothing. Prefer this over many single-action calls.",
    inputSchema: {
      space: spaceSchema,
      actions: z
        .array(inputActionSchema)
        .min(1)
        .max(512)
        .describe("Ordered list of actions to perform."),
    },
  },
  async ({ space, actions }) => {
    let payload: string;
    try {
      payload = serializeActions(actions);
    } catch (error) {
      if (error instanceof ArgError) {
        return errorResult(error.message);
      }
      throw error;
    }
    return callCli(buildInputArgs(space), {
      context: `agentspace input ${space}`,
      stdin: payload,
    });
  },
);

server.registerTool(
  "agentspace_click",
  {
    title: "Click in a Space",
    description:
      "Move the pointer to a point and click. Coordinates are display POINTS (pixels / scale), not screenshot pixels. Refused if the Space's desktop is on the physical console.",
    inputSchema: {
      space: spaceSchema,
      x: z.number().describe("X in display points."),
      y: z.number().describe("Y in display points."),
      double: z.boolean().optional().describe("Double-click instead of a single click."),
      right: z.boolean().optional().describe("Right-click instead of a left click."),
    },
  },
  async ({ space, x, y, double, right }) => {
    const options: { double?: boolean | undefined; right?: boolean | undefined } = {};
    if (double !== undefined) options.double = double;
    if (right !== undefined) options.right = right;
    return callCli(buildClickArgs(space, x, y, options), {
      context: `agentspace click ${space} ${x} ${y}`,
    });
  },
);

server.registerTool(
  "agentspace_type",
  {
    title: "Type text in a Space",
    description:
      "Type literal text into whatever control is focused in the Space. Does not press Return — use agentspace_key with \"enter\" (or \"cmd+enter\") for that. Refused if the Space's desktop is on the physical console.",
    inputSchema: {
      space: spaceSchema,
      text: z.string().min(1).describe("Text to type. Sent as a single literal string."),
    },
  },
  async ({ space, text }) =>
    callCli(buildTypeArgs(space, text), { context: `agentspace type ${space}` }),
);

server.registerTool(
  "agentspace_key",
  {
    title: "Press a key combo in a Space",
    description:
      'Press a key combination, e.g. "cmd+l", "cmd+shift+4", "enter" or "escape". Modifiers and key are joined with "+". Refused if the Space\'s desktop is on the physical console.',
    inputSchema: {
      space: spaceSchema,
      combo: z.string().min(1).describe('Key combo, e.g. "cmd+l" or "escape".'),
    },
  },
  async ({ space, combo }) =>
    callCli(buildKeyArgs(space, combo), { context: `agentspace key ${space} ${combo}` }),
);

server.registerTool(
  "agentspace_scroll",
  {
    title: "Scroll in a Space",
    description:
      "Scroll the focused view by a pixel delta. dx/dy are integer deltas; negative dy scrolls down. Refused if the Space's desktop is on the physical console.",
    inputSchema: {
      space: spaceSchema,
      dx: z.number().int().describe("Horizontal scroll delta."),
      dy: z.number().int().describe("Vertical scroll delta; negative scrolls down."),
    },
  },
  async ({ space, dx, dy }) =>
    callCli(buildScrollArgs(space, dx, dy), { context: `agentspace scroll ${space} ${dx} ${dy}` }),
);

server.registerTool(
  "agentspace_drag",
  {
    title: "Drag in a Space",
    description:
      "Press at one point, move to another and release. All four coordinates are display POINTS. Refused if the Space's desktop is on the physical console.",
    inputSchema: {
      space: spaceSchema,
      x1: z.number().describe("Start X in display points."),
      y1: z.number().describe("Start Y in display points."),
      x2: z.number().describe("End X in display points."),
      y2: z.number().describe("End Y in display points."),
    },
  },
  async ({ space, x1, y1, x2, y2 }) =>
    callCli(buildDragArgs(space, x1, y1, x2, y2), {
      context: `agentspace drag ${space} ${x1} ${y1} ${x2} ${y2}`,
    }),
);

server.registerTool(
  "agentspace_launch",
  {
    title: "Launch an app in a Space",
    description:
      "Launch an application inside the Space (or bring it up if already running). Pass a name the Space knows (see agentspace_apps) or an absolute path to a .app bundle. Does not affect the human's desktop.",
    inputSchema: {
      space: spaceSchema,
      app: z.string().min(1).describe('App name, e.g. "Safari", or an absolute path to a .app bundle.'),
    },
  },
  async ({ space, app }) =>
    callCli(buildLaunchArgs(space, app), { context: `agentspace launch ${space} ${app}` }),
);

server.registerTool(
  "agentspace_quit",
  {
    title: "Quit an app in a Space",
    description:
      "Quit an application running inside the Space. Graceful by default; set force for a force-quit. Use agentspace_apps first to see what is running.",
    inputSchema: {
      space: spaceSchema,
      app: z.string().min(1).describe("App name as reported by agentspace_apps."),
      force: z.boolean().optional().describe("Force-quit instead of asking the app to quit."),
    },
    annotations: { destructiveHint: true },
  },
  async ({ space, app, force }) => {
    const options: { force?: boolean | undefined } = {};
    if (force !== undefined) options.force = force;
    return callCli(buildQuitArgs(space, app, options), {
      context: `agentspace quit ${space} ${app}`,
    });
  },
);

server.registerTool(
  "agentspace_exec",
  {
    title: "Run a shell command inside a Space",
    description:
      "Run a shell command as the Space's macOS user, inside that user's session. stdout, stderr, exitCode and duration come back as JSON. The command runs in the Space, not on the human's desktop. Some commands are refused by AgentSpace's guard list; the error says which.",
    inputSchema: {
      space: spaceSchema,
      command: z.string().min(1).describe("Shell command to run in the Space."),
      cwd: z.string().optional().describe("Working directory inside the Space (must be in its workspace)."),
      timeoutMs: z.number().int().positive().optional().describe("Per-command timeout in milliseconds."),
      env: z
        .record(z.string())
        .optional()
        .describe("Extra environment variables for the command, e.g. {\"FOO\":\"bar\"}."),
    },
  },
  async ({ space, command, cwd, timeoutMs, env }) => {
    const options: {
      cwd?: string | undefined;
      timeoutMs?: number | undefined;
      env?: Record<string, string> | undefined;
    } = {};
    if (cwd !== undefined) options.cwd = cwd;
    if (timeoutMs !== undefined) options.timeoutMs = timeoutMs;
    if (env !== undefined) options.env = env;
    return callCli(buildExecArgs(space, command, options), {
      context: `agentspace exec ${space} ${command}`,
    });
  },
);

// MARK: V2 tool names (plan(v2) §17)
//
// The agent_* spellings of the core surface. They call the SAME arg builders
// and the SAME CLI bridge as the agentspace_* tools above — one
// implementation, two names — so the two families cannot drift. The
// agentspace_* names stay registered unchanged for existing client configs.

server.registerTool(
  "agent_list",
  {
    title: "List agent accounts",
    description:
      "List every agent account on this machine with its id, name, macOS user, state, workspace and whether its worker is currently reachable. Start here to discover valid account names. Read-only.",
    inputSchema: {},
    annotations: { readOnlyHint: true },
  },
  async () => callCli(buildListArgs(), { context: "agentspace list" }),
);

server.registerTool(
  "agent_status",
  {
    title: "Status of an agent account",
    description:
      "Report one agent account's health: worker liveness, session verdict (usable / on-console / no window server), Accessibility and Screen Recording grants, display geometry in points and pixels, and resource use. Call this before acting. Read-only.",
    inputSchema: {
      space: spaceSchema
        .optional()
        .describe("Account name or UUID. Omit to use the first registered account."),
    },
    annotations: { readOnlyHint: true },
  },
  async ({ space }) =>
    callCli(buildStatusArgs(space), {
      context: `agentspace status ${space ?? "(default account)"}`,
    }),
);

server.registerTool(
  "agent_open_desktop",
  {
    title: "Open an agent's desktop",
    description:
      "Open the agent's live desktop in the AgentSpace app on the human's screen (a deep link into the Desktop Viewer). The agent session itself is untouched. Use when a human should look at or interact with the agent's desktop directly.",
    inputSchema: {
      space: spaceSchema.describe("Account name or UUID, e.g. \"dev\"."),
    },
  },
  async ({ space }) => callCli(buildOpenDesktopArgs(space), {
    context: `agentspace open ${space}`,
  }),
);

server.registerTool(
  "agent_screenshot",
  {
    title: "Screenshot an agent's desktop",
    description:
      "Capture the agent's background desktop and return it as an image, plus path, width, height, pixelWidth, pixelHeight and scale. Input coordinates are POINTS = pixels / scale. Read-only.",
    inputSchema: {
      space: spaceSchema,
      maxWidth: z
        .number()
        .int()
        .positive()
        .optional()
        .describe("Downscale the returned PNG to at most this many pixels wide."),
      display: z.number().int().min(0).optional().describe("0-based display index to capture."),
      out: z.string().optional().describe("Explicit path for the PNG inside the account's workspace."),
    },
    annotations: { readOnlyHint: true },
  },
  async ({ space, maxWidth, display, out }) => {
    const options: { maxWidth?: number | undefined; display?: number | undefined; out?: string | undefined } = {};
    if (maxWidth !== undefined) options.maxWidth = maxWidth;
    if (display !== undefined) options.display = display;
    if (out !== undefined) options.out = out;
    const outcome = await invoke(buildScreenshotArgs(space, options), {
      context: `agentspace screenshot ${space}`,
    });
    if (outcome.kind === "error") {
      return outcome.result;
    }
    return screenshotResult(outcome.value);
  },
);

server.registerTool(
  "agent_click",
  {
    title: "Click in an agent's desktop",
    description:
      "Move the pointer to a point and click. Coordinates are display POINTS (pixels / scale), not screenshot pixels. Refused if the agent's desktop is on the physical console.",
    inputSchema: {
      space: spaceSchema,
      x: z.number().describe("X in display points."),
      y: z.number().describe("Y in display points."),
      double: z.boolean().optional().describe("Double-click instead of a single click."),
      right: z.boolean().optional().describe("Right-click instead of a left click."),
    },
  },
  async ({ space, x, y, double, right }) => {
    const options: { double?: boolean | undefined; right?: boolean | undefined } = {};
    if (double !== undefined) options.double = double;
    if (right !== undefined) options.right = right;
    return callCli(buildClickArgs(space, x, y, options), {
      context: `agentspace click ${space} ${x} ${y}`,
    });
  },
);

server.registerTool(
  "agent_type",
  {
    title: "Type text in an agent's desktop",
    description:
      "Type literal text into whatever control is focused in the agent session. Does not press Return — use agentspace_key with \"enter\" (or \"cmd+enter\") for that. Refused if the agent's desktop is on the physical console.",
    inputSchema: {
      space: spaceSchema,
      text: z.string().min(1).describe("Text to type. Sent as a single literal string."),
    },
  },
  async ({ space, text }) =>
    callCli(buildTypeArgs(space, text), { context: `agentspace type ${space}` }),
);

server.registerTool(
  "agent_launch",
  {
    title: "Launch an app in an agent session",
    description:
      "Launch an application inside the agent's desktop session (or bring it up if already running). Pass a name the session knows (see agentspace_apps) or an absolute path to a .app bundle. Does not affect the human's desktop.",
    inputSchema: {
      space: spaceSchema,
      app: z.string().min(1).describe('App name, e.g. "Safari", or an absolute path to a .app bundle.'),
    },
  },
  async ({ space, app }) =>
    callCli(buildLaunchArgs(space, app), { context: `agentspace launch ${space} ${app}` }),
);

server.registerTool(
  "agent_exec",
  {
    title: "Run a shell command inside an agent session",
    description:
      "Run a shell command as the agent account's macOS user, inside that user's session. stdout, stderr, exitCode and duration come back as JSON. The command runs in the agent session, not on the human's desktop. Some commands are refused by AgentSpace's guard list; the error says which.",
    inputSchema: {
      space: spaceSchema,
      command: z.string().min(1).describe("Shell command to run in the agent session."),
      cwd: z.string().optional().describe("Working directory inside the account's workspace (must be within it)."),
      timeoutMs: z.number().int().positive().optional().describe("Per-command timeout in milliseconds."),
      env: z
        .record(z.string())
        .optional()
        .describe("Extra environment variables for the command, e.g. {\"FOO\":\"bar\"}."),
    },
  },
  async ({ space, command, cwd, timeoutMs, env }) => {
    const options: {
      cwd?: string | undefined;
      timeoutMs?: number | undefined;
      env?: Record<string, string> | undefined;
    } = {};
    if (cwd !== undefined) options.cwd = cwd;
    if (timeoutMs !== undefined) options.timeoutMs = timeoutMs;
    if (env !== undefined) options.env = env;
    return callCli(buildExecArgs(space, command, options), {
      context: `agentspace exec ${space} ${command}`,
    });
  },
);

// NOTE (intentional omission): there is deliberately no tool for creating or
// deleting a Space, and none for granting Accessibility or Screen Recording.
// Those require making or removing a macOS user and changing TCC, which
// agentspace does only through the privileged helper and the AgentSpace GUI. If
// a caller needs one, a human must do it in the GUI. Do not add such a tool
// here, and do not work around it by shelling out to `sudo` or `dscl`.

// MARK: - Start

async function main(): Promise<void> {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  // stderr only: stdout is the MCP protocol channel and must stay clean.
  console.error("agentspace-mcp: ready (bridging to the agentspace CLI over stdio)");
}

main().catch((error: unknown) => {
  console.error("agentspace-mcp: fatal error:", error);
  process.exit(1);
});
