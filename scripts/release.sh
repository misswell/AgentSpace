#!/usr/bin/env bash
#
# Build a releasable AgentSpace: signed app bundle + DMG (plan §57).
#
# Verifiable without any Apple Developer account:
#   scripts/release.sh
#
# With notarization (needs `xcrun notarytool store-credentials` to have been run
# once, under the profile name in $NOTARY_PROFILE):
#   NOTARY_PROFILE=agentspace scripts/release.sh --notarize
#
# Every step prints what it checked, because a release script that says "done"
# without saying what it verified is how an unsigned artifact ships.
#
set -euo pipefail

cd "$(dirname "$0")/.."

NOTARIZE=false
if [[ "${1:-}" == "--notarize" ]]; then
  NOTARIZE=true
fi

VERSION="$(sed -n 's/.*cliVersion = "\(.*\)".*/\1/p' native/AgentSpaceCLI/Sources/AgentSpaceCLI/main.swift | head -1)"
[[ -n "$VERSION" ]] || { echo "could not read the CLI version" >&2; exit 1; }

echo "== 1. release build =="
./scripts/bundle-app.sh release dist
APP="dist/AgentSpace.app"
DMG="dist/AgentSpace-$VERSION.dmg"

echo
echo "== 2. signatures =="
# Strict: every nested binary must verify, not just the outer envelope. The helper
# and the worker are the two whose signature is a *security* boundary — the helper
# checks the caller's team identifier, so a re-signed app silently breaks every
# Space creation.
for target in "$APP" "$APP/Contents/Library/LaunchDaemons/agentspace-helper" "$APP/Contents/MacOS/agentspace-worker" "$APP/Contents/Helpers/agentspace"; do
  codesign --verify --strict --verbose=0 "$target" \
    || { echo "signature invalid: $target" >&2; exit 1; }
  echo "  ok  $(basename "$target")"
done

IDENTITY="$(codesign -dv --verbose=2 "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
TEAM="$(codesign -dv --verbose=2 "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
echo "  signer: ${IDENTITY:-<ad-hoc or unsigned>}"
echo "  team:   ${TEAM:-none}"

# A Developer ID application certificate is what a DMG user's Gatekeeper expects.
# Ad-hoc signing (the default without a certificate) is correct for development
# and is reported here rather than treated as an error — the honest release gate
# is spctl below, which will simply refuse an ad-hoc bundle.
if [[ "$IDENTITY" != *"Developer ID Application"* ]]; then
  echo "  note: not Developer ID signed. For distribution:"
  echo "        scripts/release.sh with AGENTSPACE_SIGNING_IDENTITY set (see step 1 of docs/security.md §release)."
fi

echo
echo "== 3. Gatekeeper assessment =="
# `spctl` is the consumer's actual experience: this is what macOS runs on first
# launch. Its failure on an ad-hoc or self-signed build is expected and is why the
# message names the fix rather than implying the bundle is broken.
if spctl --assess --type execute "$APP" 2>/dev/null; then
  echo "  ok  Gatekeeper accepts $APP"
else
  echo "  refused by Gatekeeper (expected without Developer ID + notarization)."
  echo "      A user installing this DMG must right-click → Open, or run:"
  echo "      xattr -dr com.apple.quarantine '$APP'"
fi

echo
echo "== 4. DMG =="
rm -f "$DMG"
hdiutil create -quiet -volname "AgentSpace $VERSION" -srcfolder "$APP" -ov -format UDZO "$DMG"
hdiutil verify -quiet "$DMG" && echo "  ok  checksum verified: $DMG"

# Attach and prove what a user would actually get, then detach. A DMG whose
# contents are wrong has failed even if its checksum is perfect.
#
# A deterministic mountpoint rather than parsing `hdiutil attach` output: with
# -quiet it prints nothing, so the parsed volume path was empty and the check
# failed against /Volumes/ itself. The mountpoint also makes the cleanup exact.
MOUNTED="$(mktemp -d /tmp/agentspace-dmg.XXXXXX)"
if ! diskutil image attach --readOnly --mountOptions nobrowse --mountPoint "$MOUNTED" "$DMG" >/dev/null 2>&1; then
  echo "could not mount $DMG" >&2
  rmdir "$MOUNTED" 2>/dev/null || true
  exit 1
fi
if [[ ! -d "$MOUNTED/AgentSpace.app" ]]; then
  echo "DMG does not contain AgentSpace.app" >&2
  hdiutil detach "$MOUNTED" -quiet || true
  rmdir "$MOUNTED" 2>/dev/null || true
  exit 1
fi
echo "  ok  contains AgentSpace.app"
codesign --verify --strict "$MOUNTED/AgentSpace.app" \
  && echo "  ok  the copy inside the DMG still verifies"
hdiutil detach "$MOUNTED" -quiet || true
rmdir "$MOUNTED" 2>/dev/null || true

echo
echo "== 5. notarization =="
if [[ "$NOTARIZE" == true ]]; then
  PROFILE="${NOTARY_PROFILE:-}"
  if [[ -z "$PROFILE" ]]; then
    echo "  NOTARY_PROFILE is not set. Store credentials once with:" >&2
    echo "    xcrun notarytool store-credentials AGENTSPACE_NOTARY \\" >&2
    echo "      --apple-id <email> --team-id U8U443D7ZL --password <app-specific-password>" >&2
    echo "  then run: NOTARY_PROFILE=AGENTSPACE_NOTARY scripts/release.sh --notarize" >&2
    exit 1
  fi
  echo "  submitting $DMG (this can take minutes)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler staple "$DMG"
  spctl --assess --type execute "$APP" && echo "  ok  Gatekeeper now accepts the notarized app"
else
  # A failure here would be misleading: nothing was attempted. Stated plainly.
  echo "  skipped — distribution builds need Developer ID + notarization (§57)."
  echo "  Notarized releases also require the helper review in docs/security.md to be signed off."
fi

echo
echo "Release artifact: $DMG"
echo "  version $VERSION, protocol $(./.build/release/agentspace --version | sed -n 's/.*protocol \([0-9]*\).*/\1/p')"
