#!/usr/bin/env bash
#
# Wrap the SwiftPM GUI binary, the CLI and the worker into a real .app bundle.
#
# SwiftPM has no bundle product, and a bare executable is not a good macOS
# citizen: it has no Dock name, no menu-bar identity, and — the part that matters
# — no stable identity for TCC. A permission granted to a loose binary is
# attributed to whatever launched it (your terminal), which is exactly wrong for
# a worker that must hold its own Accessibility and Screen Recording grants.
#
#   scripts/bundle-app.sh [debug|release] [output-dir]
#
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIGURATION="${1:-debug}"
OUT_DIR="${2:-dist}"

APP="$OUT_DIR/AgentSpace.app"
BIN_DIR=".build/$CONFIGURATION"

echo "== building ($CONFIGURATION) =="
swift build -c "$CONFIGURATION" \
  --product AgentSpaceApp --product agentspace --product agentspace-worker

for binary in AgentSpaceApp agentspace agentspace-worker; do
  [[ -x "$BIN_DIR/$binary" ]] || { echo "missing $BIN_DIR/$binary" >&2; exit 1; }
done

echo "== assembling $APP =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" \
         "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"

# Layout, and why it is not the obvious one.
#
# `AgentSpace` and `agentspace` differ only in case, and the default macOS
# filesystem is case-INSENSITIVE. Putting them in the same directory means the
# second `cp` silently overwrites the first: the bundle looks complete, the GUI
# binary is gone, and nothing reports an error. (Found by doing it.)
#
# So the CLI lives in Contents/Helpers, which is also the conventional place for
# nested executable code that is not the main binary — it keeps `--deep`
# verification and the notarization scan happy, and it avoids the collision
# entirely rather than relying on the filesystem being case-sensitive.
cp "$BIN_DIR/AgentSpaceApp"     "$APP/Contents/MacOS/AgentSpace"
cp "$BIN_DIR/agentspace-worker" "$APP/Contents/MacOS/agentspace-worker"
cp "$BIN_DIR/agentspace"        "$APP/Contents/Helpers/agentspace"
cp apps/AgentSpace/Resources/Info.plist "$APP/Contents/Info.plist"

# Assert the layout rather than trusting it. A case collision is invisible in a
# directory listing, so the only reliable check is comparing content.
if [ "$(shasum -a 256 < "$APP/Contents/MacOS/AgentSpace" | cut -d' ' -f1)" = \
   "$(shasum -a 256 < "$APP/Contents/Helpers/agentspace" | cut -d' ' -f1)" ]; then
  echo "the GUI binary and the CLI are the same file — the app bundle is broken" >&2
  exit 1
fi

# The worker's LaunchAgent plist and its template are phase 3 work; the directory
# exists now so the layout matches docs/architecture.md and the helper has
# somewhere to install into.

# Sign inside-out. An unstable signature invalidates both TCC grants on every
# rebuild, which is the single most confusing failure mode in this project: input
# simply stops working, with ACCESSIBILITY_DENIED as the only clue.
IDENTITY="${AGENTSPACE_CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
    IDENTITY="$(security find-identity -v -p codesigning \
      | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')"
  else
    IDENTITY="-"
    echo "   no Developer ID; ad-hoc signing (TCC grants will NOT survive a rebuild)"
  fi
fi

sign() {
  local path="$1" identifier="$2"
  codesign --force --options runtime --timestamp=none \
    --identifier "$identifier" --sign "$IDENTITY" "$path" 2>&1 | sed 's/^/   /' \
    || codesign --force --identifier "$identifier" --sign - "$path" 2>&1 | sed 's/^/   /'
}

sign "$APP/Contents/MacOS/agentspace-worker" "com.agentspace.AgentSpace.Worker"
sign "$APP/Contents/Helpers/agentspace"      "com.agentspace.AgentSpace.CLI"
sign "$APP"                                  "com.agentspace.AgentSpace"

echo "== verifying =="
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/   /' || true
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Signature" | sed 's/^/   /' || true

echo
echo "== bundled =="
printf '   %s\n' "$APP"
find "$APP" -type f | sed "s|^|   |"
echo
echo "   open $APP"
echo
echo "Note: the bundled CLI is at"
echo "   $APP/Contents/Helpers/agentspace"
echo "and that path is what an MCP client should be given as AGENTSPACE_BIN — a"
echo "different copy of the binary would be a different TCC identity."
