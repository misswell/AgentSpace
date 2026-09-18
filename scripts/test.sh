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
swift build --product agentspace-worker --product agentspace 2>&1 \
  | grep -Ev "^warning: 'agentspace'|^\[[0-9]" || true

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
swift test 2>&1 | grep -Ev "^warning: 'agentspace'|^\[[0-9]" | tail -60
STATUS=${PIPESTATUS[0]}

echo
if [[ $STATUS -eq 0 ]]; then
  echo "PASS — see docs/validation.md §4 for the recorded results."
else
  echo "FAIL (exit $STATUS)" >&2
fi
exit $STATUS
