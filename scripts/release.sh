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
# Guard against silently discarding notarization work: if the dist artifacts on
# disk are stapled, a plain rebuild replaces them with unsigned-for-notary
# output and the next download fails Gatekeeper. Say so, loudly.
for prev in dist/AgentSpace.app dist/AgentSpace-*.dmg; do
  if [[ -e "$prev" ]] && stapler validate "$prev" > /dev/null 2>&1; then
    echo "  note: $prev is notarized and stapled; this rebuild replaces it —"
    echo "        run scripts/notarize.sh again afterwards."
  fi
done
./scripts/bundle-app.sh release dist
APP="dist/AgentSpace.app"
DMG="dist/AgentSpace-$VERSION.dmg"

echo
echo "== 1b. the handles layer 4 presses are readable in these bytes =="
# Layer 4 finds buttons by accessibility identifier, so a shipped bundle that
# lost one means a person driving the UI by name — or this repo's own gate —
# has nothing to press. This reads the bundle that is about to be signed, which
# is the only build anybody installs.
#
# What the check can see: Swift stores an ASCII string literal of 15 bytes or
# fewer *inside the String's own words* (a small string), so an optimized build
# materializes it as mov/movk halfword immediates and never as a contiguous
# `__cstring` entry — measured as matched pairs, a tree against the binary built
# from that tree: 0.1.84's sources leave 8 of 62 identifiers absent from their
# shipped binary, all <=15 bytes with the present ones starting at 17, and this
# tree leaves 3 of 63 absent, all <=15 bytes with the present ones starting at
# exactly 16 (validation section 386). Absence of bytes therefore proves
# nothing about a short name, so every handle below is named at 16 characters or
# longer and ReleaseIdentifierGateTests keeps it that way. Matching is on a whole
# pooled string rather than a substring, because a short name that is also a
# prefix of another literal would otherwise be satisfied by that other view.
LAYER4_HANDLES=(
  agentSignInDoorCard
  agentViewerSignInDoor
  openAgentPermissionGuide
  openAgentSystemSignIn
  permissionGuideSignIn
  agentClipboardBridgeValue
  agentConnectionsValue
  appBuildVersionStamp
  automaticUpdateCheckToggle
  createAgentButton
  displayQualityPicker
  mainToolbarSettings
  newAgentContinue
  newAgentNameField
  newAgentUserPicker
  openUsersGroupsButton
  refreshAccountsButton
  registryRootOverrideNotice
  softwareUpdatePane
  statusRefreshSlider
  updateCheckButton
  updateInstallButton
)
GUI_BIN="$APP/Contents/MacOS/AgentSpace"
# Written to a file, not piped: this script runs under `pipefail`, and `grep -q`
# exits the moment it matches, so `printf '%s\n' "$GUI_STRINGS" | grep -qx` made
# *printf* die of SIGPIPE and the pipeline reported failure for handles that were
# present — 16 of 21 on the 0.1.85 runner, which then correctly refused to
# publish a build whose only defect was this check (§386 row 1256).
GUI_STRINGS_FILE="$(mktemp /tmp/agentspace-strings.XXXXXX)"
trap 'rm -f "$GUI_STRINGS_FILE"' EXIT
strings -a "$GUI_BIN" > "$GUI_STRINGS_FILE"
missing_handles=0
for handle in "${LAYER4_HANDLES[@]}"; do
  if grep -qx "$handle" "$GUI_STRINGS_FILE"; then
    echo "  ok  $handle"
  else
    echo "  MISSING  $handle is not a whole string in $GUI_BIN: layer 4 cannot press it in a shipped build" >&2
    missing_handles=1
  fi
done
[[ $missing_handles -eq 0 ]] || exit 1

echo
echo "== 2. signatures =="
# Strict: every nested binary must verify, not just the outer envelope. The helper
# and the worker are the two whose signature is a *security* boundary — the helper
# checks the caller's team identifier, so a re-signed app silently breaks every
# Space creation.
for target in "$APP" "$APP/Contents/Library/LaunchDaemons/agentspace-helper" "$APP/Contents/MacOS/agentspace-worker" "$APP/Contents/Helpers/agentspace" "$APP/Contents/Helpers/agentspace-updater"; do
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
