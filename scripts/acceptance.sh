#!/usr/bin/env bash
#
# The phase-0 acceptance gate — plan §44.
#
#   scripts/acceptance.sh [--iterations N] [--space NAME] [--mode MODE]
#
# Run this from your own logged-in desktop. Never over ssh, and never from the
# AgentSpace account: the whole point is that the session you are sitting at is
# the one that must not be disturbed.
#
# Exit codes:
#   0  the gate ran and every measured property was stable
#   1  the gate ran and something failed
#   3  the gate could not run (no background session yet) — not a pass
#   4  the gate ran but the console was busy on its own, so it proves nothing
#
set -uo pipefail

cd "$(dirname "$0")/.."

echo "== building =="
swift build --product agentspace-worker --product agentspace --product agentspace-session-test 2>&1 \
  | grep -Ev "^warning: 'agentspace'|^\[[0-9]" || true

for binary in .build/debug/agentspace-worker .build/debug/agentspace-session-test; do
  [[ -x "$binary" ]] || { echo "missing $binary" >&2; exit 1; }
done

# Report readiness first, so a failure below is easy to place.
echo
echo "== readiness =="
.build/debug/agentspace doctor 2>&1 | sed -n '1,40p' | sed 's/^/   /'

echo
echo "== acceptance =="
.build/debug/agentspace-session-test "$@"
status=$?

echo
case $status in
  0) echo "The phase-0 gate passed. Phase 1 and beyond may proceed." ;;
  1) echo "The phase-0 gate FAILED. Do not proceed past phase 0 until this is clean." >&2 ;;
  3) echo "The gate could not run: no background AgentSpace session exists yet."
     echo "Log into the Space's account once through fast user switching, then switch"
     echo "back and re-run. Until then only the fail-closed half is observable — and"
     echo "it is reported above." ;;
  4) echo "The gate ran but the desktop was changing on its own, so nothing is proven."
     echo "Re-run when the machine is idle." ;;
esac
exit $status
