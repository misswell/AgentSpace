import test from "node:test";
import assert from "node:assert/strict";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { BUNDLED_BINARY, discoverBinary } from "../dist/binary.js";

test("binary discovery targets the bundled CLI and never falls through an invalid override", () => {
  assert.equal(
    BUNDLED_BINARY,
    "/Applications/AgentSpace.app/Contents/Helpers/agentspace",
    "the default must identify the CLI helper, not the case-colliding GUI executable",
  );

  const tempRoot = mkdtempSync(path.join(tmpdir(), "agentspace-mcp-binary-"));
  const fallback = path.join(tempRoot, "agentspace");
  const invalidOverride = path.join(tempRoot, "missing-override");
  writeFileSync(fallback, "#!/bin/sh\nexit 0\n");
  chmodSync(fallback, 0o755);

  try {
    const result = discoverBinary({
      AGENTSPACE_BIN: invalidOverride,
      PATH: tempRoot,
    });
    assert.equal(result.ok, false);
    assert.match(result.message, /AGENTSPACE_BIN is set/);
    assert.doesNotMatch(result.message, /selected|using .*agentspace/i);
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
});
