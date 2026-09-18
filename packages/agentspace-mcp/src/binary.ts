/**
 * Locating the `agentspace` CLI binary.
 *
 * Discovery order (first match wins):
 *   1. the `AGENTSPACE_BIN` environment variable,
 *   2. `/Applications/AgentSpace.app/Contents/MacOS/agentspace`,
 *   3. each directory on `PATH`.
 *
 * Discovery is deliberately *lazy*: it happens per tool call, not at server
 * startup. A missing binary must produce a clear, actionable MCP tool error —
 * never a crash before the server can answer at all.
 *
 * If `AGENTSPACE_BIN` is set but does not point at an executable file we do
 * **not** silently fall through to the next candidate. An explicit override
 * that does not work is a configuration mistake, and quietly running some
 * other binary would hide it.
 */

import { accessSync, constants, statSync } from "node:fs";
import { delimiter, join } from "node:path";

/** The binary shipped inside the app bundle. */
export const BUNDLED_BINARY = "/Applications/AgentSpace.app/Contents/MacOS/agentspace";

/** Name of the executable looked for on `PATH`. */
export const BINARY_NAME = "agentspace";

export type DiscoverySource = "AGENTSPACE_BIN" | "app-bundle" | "PATH";

export type BinaryDiscovery =
  | { ok: true; path: string; source: DiscoverySource }
  | { ok: false; message: string };

/** True when `path` exists, is a regular file, and is executable. */
function isExecutableFile(path: string): boolean {
  try {
    if (!statSync(path).isFile()) {
      return false;
    }
    accessSync(path, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

/** Directories on `PATH`, in order, ignoring empty entries (`::`). */
function pathDirectories(env: NodeJS.ProcessEnv): string[] {
  const raw = env.PATH;
  if (raw === undefined || raw === "") {
    return [];
  }
  return raw.split(delimiter).filter((dir) => dir.length > 0);
}

/**
 * Build the message shown when no usable binary could be found.
 *
 * It names every location that was tried so the caller can fix the problem
 * without reading this source.
 */
function notFoundMessage(env: NodeJS.ProcessEnv, override: string | undefined): string {
  const overrideLine =
    override === undefined
      ? "1. AGENTSPACE_BIN is not set."
      : `1. AGENTSPACE_BIN is set to ${JSON.stringify(override)}, but that is not an executable file.`;
  const pathDirs = pathDirectories(env);
  const pathLine =
    pathDirs.length === 0
      ? "3. PATH is empty, so it was not searched."
      : `3. Searched PATH (${pathDirs.join(", ")}).`;

  return [
    "Could not find the `agentspace` CLI binary.",
    "",
    "Looked, in order:",
    overrideLine,
    `2. ${BUNDLED_BINARY} — not an executable file.`,
    pathLine,
    "",
    "To fix this, either:",
    "  - install AgentSpace so the binary exists at " + BUNDLED_BINARY + ", or",
    "  - put an `agentspace` executable on PATH, or",
    "  - set AGENTSPACE_BIN=/full/path/to/agentspace (and, for an alternate",
    "    installation, AGENTSPACE_ROOT=/path/to/agentspace-root).",
    "",
    "The MCP server does not ship or download the CLI, and it will never",
    "substitute a different way of driving the desktop.",
  ].join("\n");
}

/**
 * Find the `agentspace` binary using the documented order.
 *
 * @param env environment to read (defaults to `process.env`); injectable so the
 *            discovery logic is observable without touching the real machine.
 */
export function discoverBinary(env: NodeJS.ProcessEnv = process.env): BinaryDiscovery {
  const override = env.AGENTSPACE_BIN?.trim();

  if (override !== undefined && override.length > 0) {
    // An explicit override is authoritative: either it works or the caller is
    // told exactly why it does not. No silent fallback.
    if (isExecutableFile(override)) {
      return { ok: true, path: override, source: "AGENTSPACE_BIN" };
    }
    return { ok: false, message: notFoundMessage(env, override) };
  }

  if (isExecutableFile(BUNDLED_BINARY)) {
    return { ok: true, path: BUNDLED_BINARY, source: "app-bundle" };
  }

  for (const dir of pathDirectories(env)) {
    const candidate = join(dir, BINARY_NAME);
    if (isExecutableFile(candidate)) {
      return { ok: true, path: candidate, source: "PATH" };
    }
  }

  return { ok: false, message: notFoundMessage(env, undefined) };
}
