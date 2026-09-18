/**
 * Running the `agentspace` CLI.
 *
 * The CLI is invoked with `spawn(bin, args)` — no shell, ever — so argument
 * values can never be interpreted as shell syntax (command injection is not
 * possible by construction). stdin/stdout/stderr are captured, and a timeout is
 * enforced so a wedged worker cannot hang an MCP tool call forever.
 */

import { spawn } from "node:child_process";

/** Default per-call timeout: 120 seconds. */
export const DEFAULT_TIMEOUT_MS = 120_000;

/**
 * Cap on captured output. A Retina screenshot comes back as base64 inside the
 * JSON, so this is generous — it exists to bound memory against a runaway
 * process, not to limit normal use.
 */
export const MAX_CAPTURE_BYTES = 128 * 1024 * 1024;

export interface CliRunResult {
  /** Process exit code, or `null` if it was killed or never started. */
  exitCode: number | null;
  /** Signal name if the process was signalled, else `null`. */
  signal: NodeJS.Signals | null;
  stdout: string;
  stderr: string;
  /** True when the harness killed the process after `timeoutMs`. */
  timedOut: boolean;
  /** Set when the process could not be started at all (e.g. ENOENT/EACCES). */
  spawnError?: string;
  /** True when captured output exceeded {@link MAX_CAPTURE_BYTES}. */
  truncated: boolean;
}

export interface RunOptions {
  timeoutMs: number;
  /** Text to write to the child's stdin (used by `agentspace input`). */
  stdin?: string | undefined;
}

/**
 * Resolve the timeout from `AGENTSPACE_MCP_TIMEOUT_MS`, falling back to
 * {@link DEFAULT_TIMEOUT_MS}. A non-positive or unparsable value is ignored
 * rather than treated as "no timeout" — an MCP tool call must always be bounded.
 */
export function resolveTimeoutMs(env: NodeJS.ProcessEnv = process.env): number {
  const raw = env.AGENTSPACE_MCP_TIMEOUT_MS?.trim();
  if (raw === undefined || raw === "") {
    return DEFAULT_TIMEOUT_MS;
  }
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return DEFAULT_TIMEOUT_MS;
  }
  return Math.floor(parsed);
}

/**
 * Run the CLI once and collect its result.
 *
 * Never rejects: every failure mode (missing binary, non-zero exit, timeout,
 * oversized output) is represented in the resolved value so the caller can turn
 * it into a precise MCP error.
 *
 * `process.env` is inherited as-is, which is also how `AGENTSPACE_ROOT` reaches
 * the CLI for alternate installations.
 */
export function runAgentspace(
  binPath: string,
  args: readonly string[],
  options: RunOptions,
): Promise<CliRunResult> {
  return new Promise((resolve) => {
    let child;
    try {
      child = spawn(binPath, [...args], {
        // No `shell: true` — this is the guarantee that no argument can be
        // reinterpreted as shell syntax.
        shell: false,
        stdio: ["pipe", "pipe", "pipe"],
        env: { ...process.env },
      });
    } catch (error) {
      resolve({
        exitCode: null,
        signal: null,
        stdout: "",
        stderr: "",
        timedOut: false,
        spawnError: error instanceof Error ? error.message : String(error),
        truncated: false,
      });
      return;
    }

    const stdoutChunks: Buffer[] = [];
    const stderrChunks: Buffer[] = [];
    let stdoutBytes = 0;
    let stderrBytes = 0;
    let truncated = false;
    let timedOut = false;
    let settled = false;

    const finish = (result: Omit<CliRunResult, "truncated">): void => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      resolve({ ...result, truncated });
    };

    const timer = setTimeout(() => {
      timedOut = true;
      // SIGKILL: the CLI forwards work to a worker over a socket, so a gentle
      // signal could leave the child waiting. We want the tool call back.
      child.kill("SIGKILL");
    }, options.timeoutMs);
    // Do not keep the MCP server's event loop alive just for this timer.
    if (typeof timer.unref === "function") {
      timer.unref();
    }

    child.stdout.on("data", (chunk: Buffer) => {
      if (stdoutBytes >= MAX_CAPTURE_BYTES) {
        truncated = true;
        return;
      }
      stdoutBytes += chunk.length;
      stdoutChunks.push(chunk);
    });

    child.stderr.on("data", (chunk: Buffer) => {
      if (stderrBytes >= MAX_CAPTURE_BYTES) {
        truncated = true;
        return;
      }
      stderrBytes += chunk.length;
      stderrChunks.push(chunk);
    });

    child.on("error", (error: Error) => {
      finish({
        exitCode: null,
        signal: null,
        stdout: "",
        stderr: "",
        timedOut: false,
        spawnError: error.message,
      });
    });

    child.on("close", (code, signal) => {
      finish({
        exitCode: code,
        signal: signal ?? null,
        stdout: Buffer.concat(stdoutChunks).toString("utf8"),
        stderr: Buffer.concat(stderrChunks).toString("utf8"),
        timedOut,
      });
    });

    // Always close stdin. `agentspace input --file -` reads it to EOF, and any
    // other command that happened to read stdin would otherwise block.
    if (child.stdin !== null) {
      child.stdin.on("error", () => {
        // A child that exits before reading stdin makes writes fail with
        // EPIPE; that is not interesting on its own — the close handler above
        // reports the real outcome.
      });
      if (options.stdin !== undefined) {
        child.stdin.end(options.stdin, "utf8");
      } else {
        child.stdin.end();
      }
    }
  });
}
