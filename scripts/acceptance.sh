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

# Distribution readiness (§57): if a built app exists, check what a downloading
# user will actually experience. Not built yet → skip; built but not stapled →
# say so honestly rather than implying the DMG is distributable.
if [[ -d dist/AgentSpace.app ]]; then
  echo
  echo "== distribution (dist/) =="
  if stapler validate dist/AgentSpace.app > /dev/null 2>&1; then
    echo "   ok  app notarized and stapled"
    if ls dist/AgentSpace-*.dmg > /dev/null 2>&1; then
      dmg="$(ls dist/AgentSpace-*.dmg | head -1)"
      if stapler validate "$dmg" > /dev/null 2>&1; then
        echo "   ok  $dmg notarized and stapled"
      else
        echo "   WARN  $dmg is not stapled — run scripts/notarize.sh before distributing" >&2
      fi
    fi
    spctl --assess --type execute dist/AgentSpace.app > /dev/null 2>&1 \
      && echo "   ok  Gatekeeper accepts the app" \
      || echo "   WARN  Gatekeeper refuses the app" >&2
  else
    echo "   note  dist/AgentSpace.app is not stapled (development build)"
  fi
fi

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
