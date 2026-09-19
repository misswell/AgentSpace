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
