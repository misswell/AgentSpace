#!/bin/bash
# check-all.sh — everything a release needs, in the order that fails fast.
#
# Aggregates the three independent verification layers into one command:
#   1. scripts/test.sh      — the Swift unit/safety suite (fastest, most signal)
#   2. scripts/mcp-smoke.sh — the MCP server speaks to a live worker
#   3. scripts/gui-verify.sh — the UI properties, through the accessibility tree
#
# Layers 2 and 3 need a live worker and an Accessibility-authorized terminal
# respectively; if their prerequisites are missing they fail with their own
# diagnostics, which is exactly what should stop a release.
#
# acceptance.sh (the phase-0 isolation gate) is deliberately not part of this
# aggregate: it opens TextEdit on the real desktop and runs for minutes —
# it is a decision to be made, not a checkbox (run it explicitly with
# --iterations 1000 before any actual release).
set -u
cd "$(dirname "$0")/.."

LAYERS=(scripts/test.sh scripts/mcp-smoke.sh scripts/gui-verify.sh)
FAILED=()

for layer in "${LAYERS[@]}"; do
  echo "==> $layer"
  if ! bash "$layer"; then
    FAILED+=("$layer")
    echo "    FAILED: $layer — stopping here"
    break
  fi
done

echo
if [ "${#FAILED[@]}" -eq 0 ]; then
  echo "check-all: all ${#LAYERS[@]} layers passed"
  exit 0
fi
echo "check-all: failed at ${FAILED[0]}"
exit 1
