// Tests for the failure-envelope seam — plan §50.
//
// The property under test: when a Space is unavailable, the MCP server relays
// AgentSpace's *typed* envelope — code, message, fix — and never substitutes a
// local execution path. There is deliberately no fallback anywhere in the MCP
// server; the closest thing to one would be treating a failure as "run it
// myself", and these tests pin the seam that makes that impossible: a CLI
// failure is parsed into a structured CliFailure whose formatted text states,
// to the agent, that no fallback exists.
//
// The first test uses the *real* `agentspace` binary when it has been built
// (AGENTSPACE_CLI_BIN, or the usual build-directory locations). Without it the
// test skips loudly rather than passing vacuously — the same convention the
// Swift integration suite uses.

import test from "node:test";
import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { runAgentspace, resolveTimeoutMs } from "../dist/cli.js";
import {
  parseJson,
  readFailureEnvelope,
  isFailureEnvelope,
  formatFailure,
} from "../dist/envelope.js";

const here = path.dirname(fileURLToPath(import.meta.url));

/** Locate the Swift CLI the way the repo's other suites do. */
function locateCli() {
  if (process.env.AGENTSPACE_CLI_BIN && existsSync(process.env.AGENTSPACE_CLI_BIN)) {
    return process.env.AGENTSPACE_CLI_BIN;
  }
  let dir = here;
  for (let i = 0; i < 6; i++) {
    const candidate = path.join(dir, ".build", "debug", "agentspace");
    if (existsSync(candidate)) return candidate;
    dir = path.dirname(dir);
  }
  return null;
}

test("a missing Space surfaces as a typed envelope with a fix, not prose", async () => {
  const bin = locateCli();
  if (!bin) {
    return test.skip("agentspace CLI not built; run `swift build` first");
  }
  const result = await runAgentspace(
    bin,
    ["status", "Definitely Missing", "--json"],
    { timeoutMs: resolveTimeoutMs({}) },
    );
  // §31: not-found is its own exit code, distinguishable from a generic failure.
  assert.equal(result.exitCode, 66, `expected 66, got ${result.exitCode}: ${result.stderr}`);

  const parsed = parseJson(result.stdout);
  assert.ok(parsed, "the failure must be JSON, not prose");
  assert.equal(isFailureEnvelope(parsed), true, "an error response must be a failure envelope");

  const failure = readFailureEnvelope(parsed);
  assert.ok(failure, "the envelope must parse into a CliFailure");
  assert.match(failure.code, /^[A-Z_]+$/, "the code must be one of the §21 typed codes");
  assert.ok(failure.message.length > 0, "the message must explain itself");
  assert.ok(failure.fix, "the CLI must include a concrete fix for this code");

  const formatted = formatFailure(failure, "agentspace_status");
  assert.ok(formatted.includes(failure.code), "the formatted text carries the code");
  assert.ok(formatted.includes("no local fallback"), "the agent must be told there is no fallback to its own console session");
});

test("a success envelope is never misread as a failure", () => {
  const success = { ok: true, result: { worker: true } };
  assert.equal(isFailureEnvelope(success), false);
  assert.equal(readFailureEnvelope(success), undefined);
});

test("unparsable CLI output degrades to a bounded diagnostic, not a crash", () => {
  const garbage = "\u0000 not json at all \u0000".repeat(500);
  const parsed = parseJson(garbage);
  assert.equal(parsed, undefined);
});

test("an absent binary surfaces as an error result, never a fallback execution", async () => {
  const result = await runAgentspace(
    "/nonexistent/agentspace-binary-for-test",
    ["status", "--json"],
    { timeoutMs: resolveTimeoutMs({}) },
    );
  assert.notEqual(result.spawnError, undefined, "spawn failure must be reported");
  assert.equal(result.exitCode, null);
  // And the envelope layer must refuse to read success out of that.
  const parsed = parseJson(result.stdout);
  assert.equal(isFailureEnvelope(parsed ?? {}), false);
});
