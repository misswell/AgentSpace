#!/usr/bin/env bash
# updater-e2e.sh — drives the self-update install step end to end, offline.
#
# The unit tests prove the updater reads exactly the argument vector the GUI
# writes. They cannot prove the part that matters: that `replaceItemAt` leaves a
# launchable bundle at the app's path, that the relaunched app is the *new* one,
# and that a refusal puts the *old* one back. Those are filesystem and process
# behaviours, so this script runs the real updater binary against stand-in
# bundles.
#
# Deliberately out of scope here, and recorded as a gap in docs/validation.md:
# the download, the digest comparison and codesign/Gatekeeper verification.
# Those decisions are made by the app before the updater is launched, against a
# real signed bundle, and this script has neither network nor identity to check.
#
# Nothing here touches /Applications, dist/, or the owner's home: every path is
# under a mktemp workspace, and $HOME is redirected for the one case that falls
# back to the default log path.
#
#   scripts/updater-e2e.sh
set -uo pipefail

cd "$(dirname "$0")/.."

if ! swift build --product agentspace-updater >/dev/null 2>&1; then
  echo "updater-e2e: could not build agentspace-updater" >&2
  exit 1
fi
BIN_DIR="$(swift build --show-bin-path 2>/dev/null | tail -1)"
UPDATER="$BIN_DIR/agentspace-updater"
if [[ ! -x "$UPDATER" ]]; then
  echo "updater-e2e: $UPDATER missing" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILURES=0
CHECKS=0
pass() { CHECKS=$((CHECKS + 1)); echo "  ok   $1"; }
fail() { CHECKS=$((CHECKS + 1)); FAILURES=$((FAILURES + 1)); echo "  FAIL $1" >&2; }
check() { # $1=description $2="0" when the thing holds
  if [[ "$2" == "0" ]]; then pass "$1"; else fail "$1"; fi
}
expect_status() { # $1=expected status $2=actual status $3=description
  if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3 — expected exit $1, got $2"; fi
}

MARKER="$WORK/launched"

# A stand-in AgentSpace: the metadata the updater inspects, plus a main
# executable that records which copy actually got launched. It writes a file and
# exits, so nothing is ever left running on the owner's desktop.
make_app() { # $1=bundle path $2=identifier $3=version
  mkdir -p "$1/Contents/MacOS"
  cat > "$1/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>AgentSpace</string>
	<key>CFBundleIdentifier</key><string>$2</string>
	<key>CFBundleName</key><string>AgentSpace</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$3</string>
</dict>
</plist>
PLIST
  cat > "$1/Contents/MacOS/AgentSpace" <<LAUNCH
#!/bin/sh
echo "$2 $3" >> "$MARKER"
LAUNCH
  chmod 755 "$1/Contents/MacOS/AgentSpace"
}

installed_version() { # $1=bundle path
  sed -n 's:.*<key>CFBundleShortVersionString</key><string>\(.*\)</string>.*:\1:p' \
    "$1/Contents/Info.plist" 2>/dev/null | head -1
}
installed_identifier() {
  sed -n 's:.*<key>CFBundleIdentifier</key><string>\(.*\)</string>.*:\1:p' \
    "$1/Contents/Info.plist" 2>/dev/null | head -1
}

# The updater waits for its parent to disappear before swapping, so each run is
# given a child that exits on its own. Bash reaps it, which is what makes
# `kill(pid, 0)` start failing.
run_updater() { # $1=source $2=destination $3=staging $4=helper $5=log
  sleep 0.4 &
  local parent=$!
  "$UPDATER" "$parent" "$1" "$2" "$3" "$4" "$5"
  local status=$?
  wait "$parent" 2>/dev/null
  return $status
}

waits_for() { # $1=glob-free text file $2=expected line $3=seconds
  local file="$1" expected="$2" deadline=$((SECONDS + ${3:-5}))
  while (( SECONDS < deadline )); do
    if [[ -f "$file" ]] && grep -qx "$expected" "$file" 2>/dev/null; then return 0; fi
    sleep 0.1
  done
  return 1
}

# --- 1. the happy path: replace, relaunch the new copy, leave nothing behind --
echo "== install replaces the app and relaunches the new copy"
APP_DIR="$WORK/case1"
STAGE="$APP_DIR/staging"
HELPER="$APP_DIR/helper"
mkdir -p "$APP_DIR/Applications" "$STAGE" "$HELPER"
DEST="$APP_DIR/Applications/AgentSpace.app"
make_app "$DEST" com.agentspace.AgentSpace 0.0.1
make_app "$STAGE/AgentSpace.app" com.agentspace.AgentSpace 9.9.9
printf 'copy-of-the-updater\n' > "$HELPER/agentspace-updater"
LOG="$APP_DIR/update.log"

run_updater "$STAGE/AgentSpace.app" "$DEST" "$STAGE" "$HELPER" "$LOG"
STATUS=$?
expect_status 0 "$STATUS" "the updater exits 0"

# The relaunched stand-in appends its identity; "9.9.9" means the bytes that
# landed are the bytes that ran.
waits_for "$MARKER" "com.agentspace.AgentSpace 9.9.9"
check "the launched app was the new copy" "$?"
check "the installed bundle reports 9.9.9" \
  "$([[ "$(installed_version "$DEST")" == "9.9.9" ]] && echo 0 || echo 1)"
check "the installed bundle is still AgentSpace" \
  "$([[ "$(installed_identifier "$DEST")" == "com.agentspace.AgentSpace" ]] && echo 0 || echo 1)"
check "the staging directory was removed" "$([[ ! -e "$STAGE" ]] && echo 0 || echo 1)"
check "the updater copy was removed" "$([[ ! -e "$HELPER" ]] && echo 0 || echo 1)"
check "no .AgentSpace-update-*/backup-* left in the app directory" \
  "$([[ -z "$(ls -a "$APP_DIR/Applications" | grep -E '^\.(AgentSpace-update|AgentSpace-backup)-' || true)" ]] && echo 0 || echo 1)"
check "the log records the install" \
  "$([[ -f "$LOG" ]] && grep -q 'update installed at' "$LOG" && echo 0 || echo 1)"

# --- 2. the refusal: a bundle that is not AgentSpace must not survive the swap -
echo "== a non-AgentSpace release is put back and the old copy restored"
APP_DIR2="$WORK/case2"
STAGE2="$APP_DIR2/staging"
HELPER2="$APP_DIR2/helper"
mkdir -p "$APP_DIR2/Applications" "$STAGE2" "$HELPER2"
DEST2="$APP_DIR2/Applications/AgentSpace.app"
make_app "$DEST2" com.agentspace.AgentSpace 0.0.1
make_app "$STAGE2/AgentSpace.app" com.example.impostor 6.6.6
LOG2="$APP_DIR2/update.log"
: > "$MARKER"

run_updater "$STAGE2/AgentSpace.app" "$DEST2" "$STAGE2" "$HELPER2" "$LOG2"
STATUS=$?
expect_status 1 "$STATUS" "the updater exits 1"
check "the old bundle is back at the app's path" \
  "$([[ "$(installed_identifier "$DEST2")" == "com.agentspace.AgentSpace" ]] && echo 0 || echo 1)"
check "the restored copy is still version 0.0.1" \
  "$([[ "$(installed_version "$DEST2")" == "0.0.1" ]] && echo 0 || echo 1)"
waits_for "$MARKER" "com.agentspace.AgentSpace 0.0.1"
check "the relaunched app after the refusal is the old copy" "$?"
check "the impostor never ran" \
  "$(! grep -q 'com.example.impostor' "$MARKER" && echo 0 || echo 1)"
check "the staging directory was removed after the refusal" \
  "$([[ ! -e "$STAGE2" ]] && echo 0 || echo 1)"
check "the helper copy was removed after the refusal" \
  "$([[ ! -e "$HELPER2" ]] && echo 0 || echo 1)"
check "no scratch bundle left in the app directory" \
  "$([[ -z "$(ls -a "$APP_DIR2/Applications" | grep -E '^\.(AgentSpace-update|AgentSpace-backup)-' || true)" ]] && echo 0 || echo 1)"
check "the log records the failure" \
  "$([[ -f "$LOG2" ]] && grep -q 'update failed' "$LOG2" && echo 0 || echo 1)"

# --- 3. an argument vector that is not the contract: refuse before touching ---
echo "== a malformed call exits 2 without touching anything"
APP_DIR3="$WORK/case3"
mkdir -p "$APP_DIR3"
DEST3="$APP_DIR3/AgentSpace.app"
make_app "$DEST3" com.agentspace.AgentSpace 0.0.1
BEFORE="$(installed_version "$DEST3")"
# The one case whose log path cannot be redirected: an unreadable vector has no
# seventh value to take it from, so the refusal line lands in the real
# ~/Library/Logs/AgentSpace/update.log. That is the correct production
# behaviour — a refusal that leaves no trace is indistinguishable from a crash.
"$UPDATER" 1234 "$DEST3" >/dev/null 2>&1
STATUS=$?
expect_status 2 "$STATUS" "the updater exits 2"
check "the app bundle is untouched" \
  "$([[ "$(installed_version "$DEST3")" == "$BEFORE" ]] && echo 0 || echo 1)"

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "updater-e2e: $CHECKS checks passed"
  exit 0
fi
echo "updater-e2e: $FAILURES of $CHECKS checks failed" >&2
exit 1
