#!/bin/bash
# check-all.sh — everything a release needs, in the order that fails fast.
#
# Aggregates the four independent verification layers into one command:
#   1. scripts/test.sh          — the Swift unit/safety suite (fastest, most signal)
#   2. scripts/updater-e2e.sh   — the self-update install step, offline and hermetic
#   3. scripts/mcp-smoke.sh     — the MCP server speaks to a live worker
#   4. scripts/gui-verify.sh    — the UI properties, through the accessibility tree
#
# Layers 3 and 4 need a live worker and an Accessibility-authorized terminal
# respectively; if their prerequisites are missing they fail with their own
# diagnostics, which is exactly what should stop a release.
#
# Layer 4 falls back rather than stopping when the console gate refuses to touch
# a machine somebody is using: `scripts/session-gui-verify.sh` runs the same 13
# checks inside an agent account's own session (see `run_layer` below). That
# fallback needs an attached account with a live worker; without one it reports
# its own refusal, which stops the release just as the console gate would have.
#
# acceptance.sh (the phase-0 isolation gate) is deliberately not part of this
# aggregate: it opens TextEdit on the real desktop and runs for minutes —
# it is a decision to be made, not a checkbox (run it explicitly with
# --iterations 1000 before any actual release).
set -u
cd "$(dirname "$0")/.."
VERSION="$(sed -n 's/.*cliVersion = "\(.*\)".*/\1/p' native/AgentSpaceCLI/Sources/AgentSpaceCLI/main.swift | head -1)"
DMG="dist/AgentSpace-${VERSION}.dmg"

# --- dist integrity guard (the §59 poisoning) --------------------------------
# dist/ is the distribution directory; §59 recorded an unnotarized rebuild
# silently replacing stapled bytes there. If distribution artifacts exist,
# they must still be the stapled pair: app stapled, DMG stapled, and the
# app's CDHash identical to the DMG's inner app. A rebuild that bypasses
# release.sh/notarize.sh fails here instead of shipping.
if [ -d dist/AgentSpace.app ]; then
  if ! xcrun stapler validate dist/AgentSpace.app >/dev/null 2>&1; then
    echo "check-all: dist/AgentSpace.app is NOT stapled — dist was rebuilt outside" >&2
    echo "  the notarize flow. Restore from the stapled DMG or re-run notarize.sh." >&2
    exit 1
  fi
  if [ -f "$DMG" ]; then
    MNT="$(mktemp -d)"
    if hdiutil attach "$DMG" -mountpoint "$MNT" -quiet -nobrowse 2>/dev/null; then
      INNER="$(codesign -dvvv "$MNT/AgentSpace.app" 2>&1 | grep -m1 'CDHash=' | awk -F'=' '{print $2}')"
      OUTER="$(codesign -dvvv dist/AgentSpace.app 2>&1 | grep -m1 'CDHash=' | awk -F'=' '{print $2}')"
      hdiutil detach "$MNT" -quiet
      if [ -n "$INNER" ] && [ "$INNER" != "$OUTER" ]; then
        echo "check-all: dist app CDHash ($OUTER) differs from the DMG's ($INNER)" >&2
        echo "  — the DMG no longer contains the dist app's bytes. Rebuild the DMG" >&2
        echo "  from the stapled app and re-notarize." >&2
        exit 1
      fi
      echo "==> dist guard: stapled app matches the stapled DMG ($INNER)"
    else
      echo "check-all: could not mount $DMG to compare" >&2
      exit 1
    fi
  fi
fi

LAYERS=(scripts/test.sh scripts/updater-e2e.sh scripts/mcp-smoke.sh scripts/gui-verify.sh)
FAILED=()

# Layer 4 has a twin. `scripts/gui-verify.sh` clears the slate — it closes every
# AgentSpace copy this uid owns and drives a window of its own on the human's
# screen — and it refuses (exit 3) rather than do that to somebody who is
# working: a running copy, a locked screen, a session that is not on the
# console. Exit 3 means *nothing was verified*, so giving up there would stop a
# release for a reason that is not the build.
#
# `scripts/session-gui-verify.sh` answers the same 13 checks from inside an
# agent account's own session, where the human's screen, focus and windows are
# not in play at all. So the layer falls back to it — never silently: which
# instrument produced the verdict is printed either way, because "layer 4 passed"
# on its own would not say whether a person's desktop was used to get that
# answer.
run_layer() {
  local script="$1" code
  bash "$script"
  code=$?
  if [ "$script" = "scripts/gui-verify.sh" ] && [ "$code" -eq 3 ]; then
    echo "    gui-verify verified nothing (exit 3, above) — running its session-side twin"
    bash scripts/session-gui-verify.sh
    code=$?
    if [ "$code" -eq 3 ]; then
      echo "    the session-side twin refused too (exit 3) — layer 4 verified nothing at all"
    elif [ "$code" -ne 0 ]; then
      echo "    the session-side twin ran and failed — the report above names the checks"
    fi
    return "$code"
  fi
  return "$code"
}

for layer in "${LAYERS[@]}"; do
  echo "==> $layer"
  if ! run_layer "$layer"; then
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
