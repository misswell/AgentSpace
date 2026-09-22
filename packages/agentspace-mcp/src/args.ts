/**
 * Pure argument builders for the `agentspace` CLI.
 *
 * These functions do no I/O and never spawn anything, so they can be unit
 * tested with plain `node --test` (see `test/args.test.mjs`). Keeping the
 * mapping "MCP tool input -> argv array" here, rather than inline in the tool
 * handlers, is what makes that test possible.
 *
 * Rules every builder follows:
 *   - It returns a `string[]` suitable for `spawn(bin, args)` — never a shell
 *     string. Nothing in this module concatenates a command line.
 *   - `--json` is always passed, because the MCP server only ever speaks the
 *     CLI's JSON envelope.
 *   - Missing or malformed required arguments throw {@link ArgError} instead of
 *     producing an argv that the CLI would reject with a confusing usage error.
 */

/** Thrown when a tool argument cannot be turned into a valid CLI argument. */
export class ArgError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ArgError";
  }
}

export interface ClickOptions {
  /** `--double`: the CLI emits a `doubleClick` action. */
  double?: boolean | undefined;
  /** `--right`: the CLI emits a `rightClick` action (with `button: right`). */
  right?: boolean | undefined;
}

export interface ScreenshotOptions {
  /** Downscale the PNG so its width is at most this many pixels. */
  maxWidth?: number | undefined;
  /** 0-based display index to capture. */
  display?: number | undefined;
  /** Explicit output path for the PNG. */
  out?: string | undefined;
}

export interface ExecOptions {
  /** Working directory for the command inside the Space. */
  cwd?: string | undefined;
  /** Per-command timeout in milliseconds. */
  timeoutMs?: number | undefined;
  /** Extra environment variables for the command. */
  env?: Record<string, string> | undefined;
}

export interface QuitOptions {
  /** `--force`: use the force-quit method instead of a graceful quit. */
  force?: boolean | undefined;
}

export interface AxSnapshotOptions {
  /** Restrict the snapshot to one process id. */
  pid?: number | undefined;
  /** Maximum tree depth to walk. */
  maxDepth?: number | undefined;
  /** Maximum number of nodes to return. */
  maxNodes?: number | undefined;
  /** `--all`: include non-"interesting" nodes (the CLI defaults to interesting-only). */
  all?: boolean | undefined;
}

// MARK: - validation helpers

/** Reject anything that is not a non-empty string; return it otherwise. */
function requireText(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new ArgError(`${field} must be a non-empty string`);
  }
  return value;
}

/** Reject a missing/blank Space reference. */
function requireSpace(value: unknown): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new ArgError("space must be a non-empty Space name or UUID");
  }
  return value.trim();
}

/** Accept any finite number (coordinates in display points may be fractional). */
function requireNumber(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new ArgError(`${field} must be a finite number`);
  }
  return value;
}

/** Accept only integers (the CLI parses scroll/timers/indices with `Int`). */
function requireInteger(value: unknown, field: string): number {
  const n = requireNumber(value, field);
  if (!Number.isInteger(n)) {
    throw new ArgError(`${field} must be an integer`);
  }
  return n;
}

/**
 * Append a free-text argument (`type` text, `exec` command, an app name, a key
 * combo) so the CLI cannot mistake it for a flag.
 *
 * For ordinary text the result is the documented order:
 *   `[<command>, <space>, <text>, ...flags, "--json"]`
 *
 * If the text begins with `-` it would be parsed as a flag by the CLI, so we
 * emit the CLI's end-of-flags separator instead. `--json` has to come *before*
 * the `--` separator, otherwise the separator would swallow it too:
 *   `[<command>, <space>, "--json", ...flags, "--", <text>]`
 */
function withFreeText(head: string[], text: string, flags: string[]): string[] {
  if (text.startsWith("-")) {
    return [...head, "--json", ...flags, "--", text];
  }
  return [...head, text, ...flags, "--json"];
}

// MARK: - builders

/** `agentspace list [--json]` */
export function buildListArgs(): string[] {
  return ["list", "--json"];
}

/**
 * `agentspace open <account> [--json]` — plan(v2) §16/§17. The CLI verb is
 * `open`; the pre-V2 spelling `desktop` is the same code path.
 */
export function buildOpenDesktopArgs(space: string): string[] {
  return ["open", requireSpace(space), "--json"];
}

/**
 * `agentspace status [space] [--json]`
 *
 * The Space is optional: the CLI falls back to the first registered Space.
 */
export function buildStatusArgs(space?: string): string[] {
  if (space === undefined || space === "") {
    return ["status", "--json"];
  }
  return ["status", requireSpace(space), "--json"];
}

/**
 * `agentspace screenshot <space> --inline [--max-width N] [--display N] [--out PATH] [--json]`
 *
 * `--inline` is always requested: it is what makes the CLI embed the PNG as
 * `pngBase64` in the JSON result, which the MCP server turns into an MCP image
 * content block.
 */
export function buildScreenshotArgs(space: string, options: ScreenshotOptions = {}): string[] {
  const args = ["screenshot", requireSpace(space), "--inline"];
  if (options.maxWidth !== undefined) {
    args.push("--max-width", String(requireInteger(options.maxWidth, "maxWidth")));
  }
  if (options.display !== undefined) {
    args.push("--display", String(requireInteger(options.display, "display")));
  }
  if (options.out !== undefined) {
    args.push("--out", requireText(options.out, "out"));
  }
  args.push("--json");
  return args;
}

/**
 * `agentspace input <space> --file - [--json]`
 *
 * The batch of actions is written to the child's stdin by the caller (see
 * `serializeActions`), hence `--file -`.
 */
export function buildInputArgs(space: string): string[] {
  return ["input", requireSpace(space), "--file", "-", "--json"];
}

/**
 * Serialize an action batch for `agentspace input`'s stdin.
 *
 * The actions themselves are validated by the worker (it rejects the whole
 * batch with `INVALID_ACTION` before performing anything), so this only checks
 * the outer shape to avoid sending obviously wrong payloads.
 */
export function serializeActions(actions: readonly unknown[]): string {
  if (!Array.isArray(actions) || actions.length === 0) {
    throw new ArgError("actions must be a non-empty array of input actions");
  }
  return JSON.stringify(actions);
}

/** `agentspace click <space> X Y [--double] [--right] [--json]` */
export function buildClickArgs(
  space: string,
  x: number,
  y: number,
  options: ClickOptions = {},
): string[] {
  const args = [
    "click",
    requireSpace(space),
    String(requireNumber(x, "x")),
    String(requireNumber(y, "y")),
  ];
  if (options.double) {
    args.push("--double");
  }
  if (options.right) {
    args.push("--right");
  }
  args.push("--json");
  return args;
}

/** `agentspace type <space> TEXT [--json]` */
export function buildTypeArgs(space: string, text: string): string[] {
  return withFreeText(["type", requireSpace(space)], requireText(text, "text"), []);
}

/** `agentspace key <space> COMBO [--json]` */
export function buildKeyArgs(space: string, combo: string): string[] {
  return withFreeText(["key", requireSpace(space)], requireText(combo, "combo"), []);
}

/**
 * `agentspace scroll <space> DX DY [X Y]` — deltas are integers, the anchor is a
 * display point. The anchor is not decoration: without a point the worker can
 * only post a wheel event, and in a background Aqua session that event enters the
 * session's stream and is never dispatched to an app, so the view does not move.
 */
export function buildScrollArgs(
  space: string,
  dx: number,
  dy: number,
  x?: number,
  y?: number,
): string[] {
  const args = [
    "scroll",
    requireSpace(space),
    String(requireInteger(dx, "dx")),
    String(requireInteger(dy, "dy")),
  ];
  const hasX = x !== undefined && x !== null;
  const hasY = y !== undefined && y !== null;
  if (hasX || hasY) {
    if (!hasX || !hasY) {
      throw new ArgError("scroll anchor needs both x and y");
    }
    args.push(String(requireNumber(x, "x")), String(requireNumber(y, "y")));
  }
  args.push("--json");
  return args;
}

/** `agentspace drag <space> X1 Y1 X2 Y2 [--json]` — coordinates are points. */
export function buildDragArgs(
  space: string,
  x1: number,
  y1: number,
  x2: number,
  y2: number,
): string[] {
  return [
    "drag",
    requireSpace(space),
    String(requireNumber(x1, "x1")),
    String(requireNumber(y1, "y1")),
    String(requireNumber(x2, "x2")),
    String(requireNumber(y2, "y2")),
    "--json",
  ];
}

/** `agentspace launch <space> APP [--json]` */
export function buildLaunchArgs(space: string, app: string): string[] {
  return withFreeText(["launch", requireSpace(space)], requireText(app, "app"), []);
}

/** `agentspace quit <space> APP [--force] [--json]` */
export function buildQuitArgs(space: string, app: string, options: QuitOptions = {}): string[] {
  const flags: string[] = [];
  if (options.force) {
    flags.push("--force");
  }
  return withFreeText(["quit", requireSpace(space)], requireText(app, "app"), flags);
}

/** `agentspace apps <space> [--json]` */
export function buildAppsArgs(space: string): string[] {
  return ["apps", requireSpace(space), "--json"];
}

/**
 * `agentspace exec <space> COMMAND [--cwd DIR] [--timeout MS] [--env K=V]... [--json]`
 *
 * The command is passed as a single argv element; the CLI joins the remaining
 * positionals back together. Nothing here is interpreted by a shell.
 */
export function buildExecArgs(space: string, command: string, options: ExecOptions = {}): string[] {
  const flags: string[] = [];
  if (options.cwd !== undefined) {
    flags.push("--cwd", requireText(options.cwd, "cwd"));
  }
  if (options.timeoutMs !== undefined) {
    flags.push("--timeout", String(requireInteger(options.timeoutMs, "timeoutMs")));
  }
  if (options.env !== undefined) {
    for (const [key, value] of Object.entries(options.env)) {
      if (key.length === 0 || key.includes("=")) {
        throw new ArgError(`env keys must be non-empty and must not contain "=" (got ${JSON.stringify(key)})`);
      }
      flags.push("--env", `${key}=${value}`);
    }
  }
  return withFreeText(["exec", requireSpace(space)], requireText(command, "command"), flags);
}

/**
 * `agentspace ax <space> snapshot [--pid N] [--max-depth N] [--max-nodes N] [--all] [--json]`
 */
export function buildAxSnapshotArgs(space: string, options: AxSnapshotOptions = {}): string[] {
  const args = ["ax", requireSpace(space), "snapshot"];
  if (options.pid !== undefined) {
    args.push("--pid", String(requireInteger(options.pid, "pid")));
  }
  if (options.maxDepth !== undefined) {
    args.push("--max-depth", String(requireInteger(options.maxDepth, "maxDepth")));
  }
  if (options.maxNodes !== undefined) {
    args.push("--max-nodes", String(requireInteger(options.maxNodes, "maxNodes")));
  }
  if (options.all) {
    args.push("--all");
  }
  args.push("--json");
  return args;
}
