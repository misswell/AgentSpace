#!/usr/bin/env bash
#
# Run the whole suite.
#
# The safety tests spawn the real `agentspace-worker` binary over a real unix
# socket, and SwiftPM's test build does not build executable products as
# dependencies of the test targets. So the binaries are built first — otherwise
# every integration test skips, and a suite that skips is not a suite that passed.
#
#   scripts/test.sh
#
set -uo pipefail

cd "$(dirname "$0")/.."

echo "== building (binaries first, so the integration tests have something to spawn) =="
# No --product flags: repeated flags are last-one-wins on this toolchain (see
# bundle-app.sh and validation.md §20), so this was silently building only
# agentspace and skipping every safety test whenever .build did not already hold
# a worker from some other build. The explicit check below is the gate.
swift build 2>&1 | grep -Ev "^warning: 'agentspace'|^\[[0-9]" || true

WORKER=".build/debug/agentspace-worker"
if [[ ! -x "$WORKER" ]]; then
  echo "agentspace-worker was not built; the safety tests would all skip." >&2
  exit 1
fi
export AGENTSPACE_WORKER_BINARY="$(pwd)/$WORKER"

# Leftover workers from an interrupted run would hold sockets in /tmp roots.
pkill -f "agentspace-worker --space-id" 2>/dev/null || true

echo
echo "== swift test =="
# The whole run goes to a file and only its tail to the screen, because a red
# suite whose failing case was scrolled away is a gate that cannot be debugged:
# `tail -60` alone threw away the name of the one case that failed out of 583.
FULL_LOG="${TMPDIR:-/tmp}/agentspace-test-full.log"
swift test 2>&1 | grep -Ev "^warning: 'agentspace'|^\[[0-9]" | tee "$FULL_LOG" | tail -60
STATUS=${PIPESTATUS[0]}

echo
if [[ $STATUS -eq 0 ]]; then
  echo "PASS — see docs/validation.md §4 for the recorded results."
else
  echo "FAIL (exit $STATUS)" >&2
  # Named first, before the noise: these are the only lines that say what happened.
  echo "       failing cases (full run: $FULL_LOG)" >&2
  grep -E "^Test Case .* failed|error: |Fatal error|crashed" "$FULL_LOG" | head -40 >&2
fi
exit $STATUS
