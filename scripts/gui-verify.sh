#!/bin/bash
# gui-verify.sh — repeatable GUI smoke checks via the accessibility tree.
#
# The GUI verifications in docs/validation.md (§49, §53) were first done with
# one-off osascript calls. This script makes them mechanical: same checks,
# pass/fail counting, non-zero exit on any failure — so a Settings refactor
# can be regression-checked in one command instead of by memory.
#
# Requirements: Accessibility permission for the calling terminal (System
# Events drives the app), and the app built in dist/.
set -u
cd "$(dirname "$0")/.."

APP_BIN="dist/AgentSpace.app/Contents/MacOS/AgentSpace"
PASS=0; FAIL=0

note() { printf '  %s\n' "$*"; }
check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); note "ok   $1"
  else FAIL=$((FAIL+1)); note "FAIL $1: expected [$2] got [$3]"; fi
}

pkill -f "AgentSpace.app/Contents/MacOS/AgentSpace" 2>/dev/null; sleep 1
"$APP_BIN" >/dev/null 2>&1 &
APP_PID=$!
sleep 5
trap 'kill $APP_PID 2>/dev/null' EXIT

# --- Launch: exactly one window (§41's deep-link window bug) ----------------
# A binary that predates onOpenURL never consumes queued agentspace:// open
# events, so LaunchServices re-delivers them at every launch and each one
# spawns a WindowGroup window — three identical windows, and every sheet
# flag then presents in all of them at once. One launch, one window.
WINDOWS="$(osascript -e 'tell application "System Events" to tell process "AgentSpace" to return count of windows' 2>/dev/null)"
check "launch opens exactly one window" "1" "${WINDOWS:-?}"

# --- Settings: the polling floor lives in the control (§49) ----------------
osascript <<'EOF' >/tmp/gui-verify-slider.txt 2>/dev/null
tell application "System Events"
	tell process "AgentSpace"
		click menu item "Settings…" of menu 1 of menu bar item "AgentSpace" of menu bar 1
		delay 2
		-- the Settings window remembers its last tab; the slider is on General
		if name of window 1 is "Advanced" then
			click button "General" of toolbar 1 of window "Advanced"
			delay 1.5
		end if
		-- the slider's AX name carries its value ("Status refresh: 3s" by
		-- default) and it is not addressable by bare index, so use the
		-- default-named path that §49 verified
		set _s to slider "Status refresh: 3s" of group 1 of scroll area 1 of group 1 of window "General"
		return (value of attribute "AXMinValue" of _s) & "|" & (value of attribute "AXMaxValue" of _s)
	end tell
end tell
EOF
# AppleScript concatenates the list with "& |" & as list items; strip both
SLIDER="$(tr -d ' ,' </tmp/gui-verify-slider.txt 2>/dev/null)"
check "refresh slider min=2.0"  "2.0" "${SLIDER%%|*}"
check "refresh slider max=10.0" "10.0" "${SLIDER##*|}"

# --- Settings: Preview width tiers (§53) ------------------------------------
osascript <<'EOF' >/tmp/gui-verify-tiers.txt 2>/dev/null
tell application "System Events"
	tell process "AgentSpace"
		set _g to group 2 of scroll area 1 of group 1 of window 1
		set _p to pop up button 1 of _g
		click _p
		delay 0.8
		set _out to ""
		repeat with mi in menu items of menu 1 of _p
			set _out to _out & (title of mi) & "|"
		end repeat
		return _out
	end tell
end tell
EOF
# the popup needs a beat after click before its menu is enumerable; one
# retry covers the cold-start race observed between runs
TIERS="$(sed 's/|$//; s/ //g' /tmp/gui-verify-tiers.txt 2>/dev/null)"
if [ "$TIERS" != "960px|1280px|1600px|1920px" ]; then sleep 1.5; osascript -e 'key code 53' >/dev/null 2>&1; sleep 0.5
  osascript <<'EOF2' >/tmp/gui-verify-tiers.txt 2>/dev/null
tell application "System Events"
	tell process "AgentSpace"
		set _p to pop up button 1 of group 2 of scroll area 1 of group 1 of window "General"
		click _p
		delay 1.2
		set _out to ""
		repeat with mi in menu items of menu 1 of _p
			set _out to _out & (title of mi) & "|"
		end repeat
		return _out
	end tell
end tell
EOF2
  TIERS="$(sed 's/|$//; s/ //g' /tmp/gui-verify-tiers.txt 2>/dev/null)"
fi
check "preview tiers" "960px|1280px|1600px|1920px" "$TIERS"
osascript -e 'key code 53' >/dev/null 2>&1

# --- Deep link: dead Space raises SPACE_NOT_FOUND (§46) ---------------------
TMPROOT="$(mktemp -d /tmp/gui-verify.XXXXXX)"
mkdir -p "$TMPROOT/Spaces"
echo '{"spaces":[]}' > "$TMPROOT/Spaces/index.json"
kill $APP_PID 2>/dev/null; sleep 1
AGENTSPACE_ROOT="$TMPROOT" "$APP_BIN" >/dev/null 2>&1 &
APP_PID=$!
sleep 4
DEAD_ID="11111111-2222-4333-8444-555555555555"
open "agentspace://space/$DEAD_ID"
sleep 3
ALERT="$(osascript -e 'tell application "System Events" to tell process "AgentSpace" to return value of static text 1 of sheet 1 of window 1' 2>/dev/null | head -c 16)"
check "dead link alert" "SPACE_NOT_FOUND" "$ALERT"

# --- report ------------------------------------------------------------------
rm -rf "$TMPROOT" /tmp/gui-verify-slider.txt /tmp/gui-verify-tiers.txt
echo
echo "gui-verify: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
