/**
 * Reading the CLI's JSON output, in particular its failure envelope.
 *
 * With `--json`, AgentSpace prints on failure:
 *
 *   {
 *     "status": "unavailable",
 *     "reason": "SESSION_IS_CONSOLE",
 *     "ok": false,
 *     "error": { "code": "SESSION_IS_CONSOLE", "message": "...", "recoverable": true },
 *     "fix": "..."
 *   }
 *
 * The whole point of this module is that the MCP server relays that envelope
 * verbatim-ish — code, message and fix — instead of collapsing it into "the
 * command failed". An agent that cannot see `SESSION_IS_CONSOLE` and its `fix`
 * will retry forever or, worse, try to work around it.
 */

/** The fields the MCP server needs out of a failed CLI run. */
export interface CliFailure {
  code: string;
  message: string;
  fix?: string;
  recoverable?: boolean;
  reason?: string;
  /** The parsed JSON envelope, for passthrough to the caller. */
  raw: unknown;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Parse CLI stdout as JSON. Returns `undefined` when it is not valid JSON. */
export function parseJson(stdout: string): unknown {
  const trimmed = stdout.trim();
  if (trimmed.length === 0) {
    return undefined;
  }
  try {
    return JSON.parse(trimmed);
  } catch {
    return undefined;
  }
}

/**
 * Recognise a failure envelope.
 *
 * `ok: false` is the authoritative signal. The `error.code` check exists for
 * robustness across CLI builds, but only when `ok` is not explicitly `true`, so
 * a successful result that happens to carry an `error` key is not misread.
 */
export function readFailureEnvelope(value: unknown): CliFailure | undefined {
  if (!isRecord(value)) {
    return undefined;
  }
  const errorField = isRecord(value["error"]) ? value["error"] : undefined;
  const okFalse = value["ok"] === false;
  const statusUnavailable = value["status"] === "unavailable";
  const hasCode = typeof errorField?.["code"] === "string" && value["ok"] !== true;
  if (!okFalse && !statusUnavailable && !hasCode) {
    return undefined;
  }

  const code =
    typeof errorField?.["code"] === "string"
      ? errorField["code"]
      : typeof value["reason"] === "string"
        ? value["reason"]
        : "UNKNOWN";
  const message =
    typeof errorField?.["message"] === "string"
      ? errorField["message"]
      : typeof value["message"] === "string"
        ? value["message"]
        : "(the CLI did not include a message)";

  // `fix` lives at the top level of the envelope; accept it nested too.
  const fix =
    typeof value["fix"] === "string"
      ? value["fix"]
      : typeof errorField?.["fix"] === "string"
        ? errorField["fix"]
        : undefined;
  const recoverable =
    typeof errorField?.["recoverable"] === "boolean" ? errorField["recoverable"] : undefined;
  const reason = typeof value["reason"] === "string" ? value["reason"] : undefined;

  const failure: CliFailure = { code, message, raw: value };
  if (fix !== undefined) {
    failure.fix = fix;
  }
  if (recoverable !== undefined) {
    failure.recoverable = recoverable;
  }
  if (reason !== undefined) {
    failure.reason = reason;
  }
  return failure;
}

/** True when `value` looks like the envelope AgentSpace prints on failure. */
export function isFailureEnvelope(value: unknown): boolean {
  return readFailureEnvelope(value) !== undefined;
}

/**
 * Render a failure envelope for an MCP tool error.
 *
 * The text always carries `code`, `message` and `fix`, because those are the
 * three things the caller needs to decide what to do next.
 */
export function formatFailure(failure: CliFailure, context: string): string {
  const lines = [
    `AgentSpace refused the request (${failure.code}) while running: ${context}`,
    "",
    `code: ${failure.code}`,
    `message: ${failure.message}`,
  ];
  if (failure.fix !== undefined) {
    lines.push(`fix: ${failure.fix}`);
  } else {
    lines.push("fix: (the CLI did not include a fix for this code)");
  }
  if (failure.recoverable !== undefined) {
    lines.push(`recoverable: ${failure.recoverable ? "yes" : "no"}`);
  }
  if (failure.reason !== undefined && failure.reason !== failure.code) {
    lines.push(`reason: ${failure.reason}`);
  }
  lines.push(
    "",
    "This is AgentSpace reporting that the Space's background session or the",
    "request itself is unavailable. The MCP server does not retry against",
    "anything else and has no local fallback to your own console session.",
  );
  return lines.join("\n");
}

/** Keep a bounded tail of raw output for bug reports. */
export function tail(text: string, maxChars = 4000): string {
  const trimmed = text.trim();
  if (trimmed.length <= maxChars) {
    return trimmed;
  }
  return `…[${trimmed.length - maxChars} earlier characters omitted]…\n${trimmed.slice(-maxChars)}`;
}

/**
 * Report a run whose stdout was not JSON at all.
 *
 * That is a bug (or a binary that is not `agentspace`), so the message carries
 * everything needed to file one: exit code, stdout tail, stderr tail.
 */
export function formatUnparsableOutput(params: {
  context: string;
  exitCode: number | null;
  signal: NodeJS.Signals | null;
  stdout: string;
  stderr: string;
  truncated: boolean;
}): string {
  const exit =
    params.exitCode !== null
      ? String(params.exitCode)
      : params.signal !== null
        ? `killed by ${params.signal}`
        : "unknown";
  const lines = [
    `The agentspace CLI produced output that is not valid JSON while running: ${params.context}`,
    "",
    `exit code: ${exit}`,
    "This is a bug report, not a silent failure: the CLI is documented to print",
    "JSON on stdout for every command when --json is passed.",
  ];
  if (params.truncated) {
    lines.push("(output was truncated by the MCP server's capture limit)");
  }
  lines.push(
    "",
    "--- stdout (tail) ---",
    tail(params.stdout) || "(empty)",
    "",
    "--- stderr (tail) ---",
    tail(params.stderr) || "(empty)",
  );
  return lines.join("\n");
}
