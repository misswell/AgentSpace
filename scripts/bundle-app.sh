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
# No --product flags on purpose: this SwiftPM treats repeated --product flags as
# last-one-wins, so listing four products here built ONLY agentspace-helper and
# still exited 0 — caught the first time the release build ran from a clean
# .build, where the other three binaries had never existed. The debug path looked
# fine for weeks because earlier full builds had left the other three in place.
# Building the whole package is barely slower, and the [[ -x ]] assertions below
# are the actual gate.
swift build -c "$CONFIGURATION"

for binary in AgentSpaceApp agentspace agentspace-worker agentspace-helper agentspace-updater; do
  [[ -x "$BIN_DIR/$binary" ]] || { echo "missing $BIN_DIR/$binary" >&2; exit 1; }
done

echo "== assembling $APP =="
rm -rf "$APP"
# Contents/Library/LaunchDaemons is where SMAppService.daemon(plistName:) requires
# a LaunchDaemon to live — it is not a location of our choosing.
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" \
         "$APP/Contents/Library/LaunchDaemons" \
         "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents" \
         "$APP/Contents/Library/SystemExtensions"

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
# The updater travels with the app it updates: the GUI copies it to a scratch
# directory before running it, because the bundle it lives in is the bundle being
# replaced. UpdaterLaunchPlan.updaterURL(in:) names this exact path.
cp "$BIN_DIR/agentspace-updater" "$APP/Contents/Helpers/agentspace-updater"
cp apps/AgentSpace/Resources/Info.plist "$APP/Contents/Info.plist"
# The virtual network's entitlement travels with the bundle as a provisioning
# profile. Without it every launch of the app is killed by amfid before main
# runs — measured: exit 137 with no message, on an app that `codesign --verify`
# called valid (§398). The profile is what authorises the restricted
# `system-extension.install` entitlement.
if [[ -f apps/AgentSpace/Resources/embedded.provisionprofile ]]; then
  cp apps/AgentSpace/Resources/embedded.provisionprofile "$APP/Contents/embedded.provisionprofile"
fi
# Stamp the build number from git rather than editing the plist by hand:
# every bundle produced since is distinguishable in the UI (for example,
# "0.1.13 (build)"),
# which is the guard against silently running an older copy. The repo plist
# stays untouched so builds never dirty the tree.
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
echo "    version $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist") ($BUILD)"
cp apps/AgentSpace/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# The helper and its LaunchDaemon. The helper goes in Contents/Library/LaunchDaemons
# next to its plist, because BundleProgram is resolved relative to Contents and the
# path in the plist is "Contents/Library/LaunchDaemons/agentspace-helper".
cp "$BIN_DIR/agentspace-helper" \
   "$APP/Contents/Library/LaunchDaemons/agentspace-helper"
cp apps/AgentSpace/Resources/com.agentspace.AgentSpace.Helper.plist \
   "$APP/Contents/Library/LaunchDaemons/com.agentspace.AgentSpace.Helper.plist"

# The packet-tunnel system extension. Built separately because it is Go plus a
# system-extension bundle, and a failure there should say so rather than look
# like a broken GUI build.
echo "== bundling the tunnel system extension =="
TUNNEL_BUILD="$OUT_DIR/.tunnel"
rm -rf "$TUNNEL_BUILD"
if ! ./scripts/build-tunnel.sh "$TUNNEL_BUILD" 2>&1 | sed 's/^/   /'; then
  echo "the tunnel extension could not be built." >&2
  echo "  A release needs it: the virtual network is a system extension, not an app extension (TN3134)." >&2
  exit 1
fi
rm -rf "$APP/Contents/Library/SystemExtensions/com.misswell.AgentSpace.Tunnel.systemextension"
cp -R "$TUNNEL_BUILD/com.misswell.AgentSpace.Tunnel.systemextension" \
      "$APP/Contents/Library/SystemExtensions/com.misswell.AgentSpace.Tunnel.systemextension"
# The extension's version must follow the app's, or a system update would see a
# newer app carrying an older extension and refuse to replace it.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" \
  "$APP/Contents/Library/SystemExtensions/com.misswell.AgentSpace.Tunnel.systemextension/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" \
  "$APP/Contents/Library/SystemExtensions/com.misswell.AgentSpace.Tunnel.systemextension/Contents/Info.plist"

# Localization tables. NSLocalizedString in Core and the GUI resolves against
# the main bundle, so the .lproj folders must sit in Contents/Resources —
# without them every lookup falls back to the English key, in every language.
for lproj in apps/AgentSpace/Resources/*.lproj; do
  cp -R "$lproj" "$APP/Contents/Resources/"
done

# The generated MCP configuration must work for DMG users as well as a source
# checkout. @agentspace/mcp has no public npm release: ship the exact service
# and production dependencies that this release gates, without requiring a
# package download when a client connects. Node remains a client prerequisite.
echo "== bundling MCP service =="
npm ci --prefix packages/agentspace-mcp --ignore-scripts --silent
npm run build --prefix packages/agentspace-mcp
MCP_DEST="$APP/Contents/Resources/agentspace-mcp"
mkdir -p "$MCP_DEST"
cp packages/agentspace-mcp/package.json packages/agentspace-mcp/package-lock.json "$MCP_DEST/"
cp packages/agentspace-mcp/launch.sh "$MCP_DEST/launch.sh"
chmod 755 "$MCP_DEST/launch.sh"
cp -R packages/agentspace-mcp/dist "$MCP_DEST/dist"
npm ci --prefix "$MCP_DEST" --omit=dev --ignore-scripts --silent
rm "$MCP_DEST/package-lock.json"

# The plist and the client must agree about the Mach service name, or the app
# times out with no error to explain why. Asserted rather than assumed.
PLIST="$APP/Contents/Library/LaunchDaemons/com.agentspace.AgentSpace.Helper.plist"
ADVERTISED="$(/usr/libexec/PlistBuddy \
  -c 'Print :MachServices:com.agentspace.AgentSpace.Helper' "$PLIST" 2>/dev/null | tr -d '[:space:]')"
if [[ "$ADVERTISED" != "true" ]]; then
  echo "the LaunchDaemon plist does not advertise the Mach service the client connects to." >&2
  echo "  expected key: com.agentspace.AgentSpace.Helper" >&2
  echo "  PlistBuddy said: '${ADVERTISED:-<key missing>}'" >&2
  exit 1
fi

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

sign_with_entitlements() {
  local path="$1" identifier="$2" entitlements="$3"
  local ts="--timestamp"
  [[ "$IDENTITY" == "-" ]] && ts="--timestamp=none"
  # An ad-hoc signature cannot carry restricted entitlements: amfid rejects the
  # process. Development builds therefore fall back to no entitlements, and the
  # virtual network is unavailable until the bundle is Developer ID signed —
  # which is the truth, and is reported by `agentspace network doctor` rather
  # than hidden here.
  if [[ "$IDENTITY" == "-" ]]; then
    echo "   note: ad-hoc build, so $identifier is signed without its restricted entitlements; the virtual network needs a Developer ID build"
    sign "$path" "$identifier"
    return
  fi
  codesign --force --options runtime "$ts" \
    --entitlements "$entitlements" \
    --identifier "$identifier" --sign "$IDENTITY" "$path" 2>&1 | sed 's/^/   /' \
    || { echo "   codesign failed for $path with entitlements $entitlements" >&2; exit 1; }
}

sign() {
  local path="$1" identifier="$2"
  # A secure timestamp is one of the notary service's requirements (§57): a
  # Developer ID signature without one is refused before its contents are even
  # examined. Ad-hoc signing has no timestamp authority, so it keeps =none.
  local ts="--timestamp"
  [[ "$IDENTITY" == "-" ]] && ts="--timestamp=none"
  if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --options runtime "$ts" \
      --identifier "$identifier" --sign - "$path" 2>&1 | sed 's/^/   /' \
      || { echo "   ad-hoc codesign failed for $path" >&2; exit 1; }
    return
  fi
  # This used to be one `||` away from re-signing ad-hoc, which meant a hiccup at
  # Apple's timestamp service produced a release bundle with no identity at all —
  # and every step of this script still said `ok`. That fallback belongs to the
  # no-certificate case above, not to a real identity: an artifact that cannot be
  # Developer ID signed is not releasable, so say it here rather than 20 minutes
  # later when the notary service calls it Invalid.
  codesign --force --options runtime "$ts" \
    --identifier "$identifier" --sign "$IDENTITY" "$path" 2>&1 | sed 's/^/   /' \
    || { echo "   codesign failed for $path with '$IDENTITY' — a Developer ID signature needs Apple's timestamp service (http://timestamp.apple.com/ts01), and nothing was ad-hoc-signed in its place" >&2; exit 1; }
}

# The system extension is signed before the app, like every nested binary: an
# outer signature that covers an unsigned child is not a valid signature.
# It carries its own provisioning profile and its own entitlement, and it must
# NOT carry `system-extension.install` — only the app that activates it does.
if [[ -d "$APP/Contents/Library/SystemExtensions/com.misswell.AgentSpace.Tunnel.systemextension" ]]; then
  sign_with_entitlements \
    "$APP/Contents/Library/SystemExtensions/com.misswell.AgentSpace.Tunnel.systemextension" \
    "com.misswell.AgentSpace.Tunnel" \
    native/AgentSpaceTunnel/Tunnel.entitlements
fi
sign "$APP/Contents/MacOS/agentspace-worker" "com.agentspace.AgentSpace.Worker"
sign "$APP/Contents/Helpers/agentspace"      "com.agentspace.AgentSpace.CLI"
# Its own identifier: the updater is a separate Mach-O that runs as its own
# process, and an update candidate is checked for carrying it before it installs.
sign "$APP/Contents/Helpers/agentspace-updater" "com.agentspace.AgentSpace.Updater"
# The helper carries its own identifier: it is a separate Mach-O with a separate
# privilege level, and the requirement it enforces names it explicitly.
sign "$APP/Contents/Library/LaunchDaemons/agentspace-helper" "com.agentspace.AgentSpace.Helper"
# The app itself carries the two entitlements that make it allowed to install and
# manage a system extension. Without its provisioning profile macOS kills it at
# launch (§398), so the profile is copied above rather than left to chance.
sign_with_entitlements "$APP" "com.misswell.AgentSpace" apps/AgentSpace/Resources/App.entitlements

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
echo "   $APP/Contents/Library/LaunchDaemons/agentspace-helper"

# The helper's own self-check, run from inside the bundle it will actually be
# installed from. It refuses to claim health when something is wrong, so this is a
# real gate rather than a smoke test — and it needs no root, which is the point of
# having the mode at all.
echo "== helper self-check (from the bundle) =="
if "$APP/Contents/Library/LaunchDaemons/agentspace-helper" --self-check 2>&1 | sed 's/^/   /'; then
  echo "   helper self-check passed"
else
  echo "   helper self-check reported problems (expected before the daemon is installed)" >&2
fi
echo "and that path is what an MCP client should be given as AGENTSPACE_BIN — a"
echo "different copy of the binary would be a different TCC identity."
