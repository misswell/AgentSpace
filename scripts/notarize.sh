#!/usr/bin/env bash
#
# Submit the release artifacts for Apple notarization and staple the tickets
# (plan §57). Run `scripts/release.sh` first — this assumes dist/AgentSpace.app
# and dist/AgentSpace-*.dmg exist and carry Developer ID signatures with
# hardened runtime and secure timestamps (release.sh verifies all of that).
#
#   scripts/notarize.sh                    # uses $NOTARY_PROFILE (default:
#                                          # octoshrink-notary, this machine's
#                                          # shared Apple-ID profile)
#   NOTARY_PROFILE=other scripts/notarize.sh
#
# Credentials: an Apple-ID notarytool keychain profile or an App Store Connect
# API key registered with `asc auth login`. Per this machine's global rule
# (~/.codex/AGENTS.md): a profile *name* proves nothing — the profile is
# verified live (history) before any submission, and if it fails the exact
# missing credential is reported rather than guessed at.
#
# Order matters: staple the APP first, then rebuild the DMG from the stapled
# app, submit that, staple the DMG — so the copy a user drags out of the DMG
# carries its own ticket too.
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP="dist/AgentSpace.app"
DMG="$(ls dist/AgentSpace-*.dmg | head -1)"
VERSION="$(sed -n 's/.*cliVersion = "\(.*\)".*/\1/p' native/AgentSpaceCLI/Sources/AgentSpaceCLI/main.swift | head -1)"
PROFILE="${NOTARY_PROFILE:-octoshrink-notary}"

echo "== 0. verify the credential live (a name proves nothing) =="
if xcrun notarytool history --keychain-profile "$PROFILE" > /dev/null 2>&1; then
  echo "  ok  notarytool profile '$PROFILE' is live"
  MODE="notarytool"
elif asc notarization list --limit 1 > /dev/null 2>&1; then
  # The keychain entry is known to vanish without warning (it did once on
  # 2026-09-10 and again on 2026-09-18); the asc CLI with a fully registered
  # App Store Connect API key (key id + issuer + .p8) is the verified fallback.
  echo "  ok  asc credentials are live (keychain profile absent)"
  MODE="asc"
else
  echo "no working notarization credential." >&2
  echo "  restore the shared profile with:" >&2
  echo "    xcrun notarytool store-credentials $PROFILE --apple-id <apple-id> --team-id U8U443D7ZL" >&2
  echo "  or register the asc API key (key id + issuer id + .p8 path):" >&2
  echo "    asc auth login --name agentspace-notary --key-id <id> --issuer-id <uuid> --private-key <p8>" >&2
  exit 1
fi

echo "== 1. staple the app, rebuild the DMG from it =="
xcrun stapler staple "$APP"
rm -f "$DMG"
hdiutil create -quiet -volname "AgentSpace $VERSION" -srcfolder "$APP" -ov -format UDZO "$DMG"

echo "== 2. submit the DMG and wait =="
if [[ "$MODE" == "notarytool" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
else
  asc notarization submit --file "$DMG" --wait
fi

echo "== 3. staple the DMG =="
xcrun stapler staple "$DMG"

echo "== 4. verify what a user will actually get =="
codesign --verify --strict "$APP" && echo "  ok  app still verifies"
stapler validate "$APP" > /dev/null && echo "  ok  app staple valid"
stapler validate "$DMG" > /dev/null && echo "  ok  dmg staple valid"
spctl --assess --type execute "$APP" \
  && echo "  ok  Gatekeeper accepts the app" \
  || { echo "  Gatekeeper refused — fetch the log with:" >&2
       echo "    xcrun notarytool log --keychain-profile $PROFILE <submission-id>" >&2
       exit 1; }

echo "Done: $APP and $DMG are notarized, stapled, and Gatekeeper-clean."
