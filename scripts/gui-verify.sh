#!/bin/bash
# gui-verify.sh — repeatable GUI smoke checks via the accessibility tree.
#
# The GUI verifications in docs/validation.md (§49, §53) were first done with
# one-off osascript calls. This script makes them mechanical: same checks,
# pass/fail counting, non-zero exit on any failure — so a Settings refactor
# can be regression-checked in one command instead of by memory.
#
# LANGUAGE RULE (§273): the app follows the system language and a test must
# not change that. Every control is found by its AXIdentifier, by a
# language-stable attribute (the ⌘, menu char, the toolbar index), or by a
# string that is deliberately never translated (an error code, "960 px").
# An earlier version forced `-AppleLanguages (en)` on the instance it
# launched; the owner then found themselves clicking through a create flow in
# an English window on a Chinese system. That forcing is banned here.
#
# Requirements: Accessibility permission for the calling terminal (System
# Events drives the app), and an app bundle. `AGENTSPACE_GUI_APP` can point at
# a temporary verification bundle; the default remains the release bundle in
# dist/.
set -u
cd "$(dirname "$0")/.."

APP_BUNDLE="${AGENTSPACE_GUI_APP:-dist/AgentSpace.app}"
case "$APP_BUNDLE" in
  /*) ;;
  *) APP_BUNDLE="$PWD/$APP_BUNDLE" ;;
esac
APP_BIN="$APP_BUNDLE/Contents/MacOS/AgentSpace"
PASS=0; FAIL=0

note() { printf '  %s\n' "$*"; }
check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); note "ok   $1"
  else FAIL=$((FAIL+1)); note "FAIL $1: expected [$2] got [$3]"; fi
}

# The recursive finder, shared by every check. `entire contents` returns
# nothing on SwiftUI windows, so descend explicitly through UI elements and
# match on AXIdentifier — the one attribute no localization touches.
cat > /tmp/gui-verify-lib.applescript <<'APPLESCRIPT'
on findById(theWindow, wantedId, theClass, theDepth)
	if theDepth > 8 then return missing value
	tell application "System Events"
		try
			repeat with _e in (UI elements of theWindow)
				try
					if class of _e is theClass then
						if ((value of attribute "AXIdentifier" of _e) as text) is wantedId then return _e
					end if
				end try
			end repeat
		end try
		repeat with _e in (UI elements of theWindow)
			set _found to my findById(_e, wantedId, theClass, theDepth + 1)
			if _found is not missing value then return _found
		end repeat
	end tell
	return missing value
end findById
APPLESCRIPT

# The test replaces the running app; if it was open before, hand it back at
# the end — as a normal launch, in the user's own system language.
#
# Both the lookup and the kill are scoped to this uid on purpose. AgentSpace is
# also running inside every attached agent account, and an unscoped pattern
# counts that instance as "the app was open here": the hand-back then launches
# the build under test onto the human's own desktop and leaves it there after
# the run, and the kill reaches for a process this user cannot signal anyway.
WAS_RUNNING_APP=""
while IFS= read -r running; do
	case "$running" in
		*/AgentSpace.app/Contents/MacOS/AgentSpace)
			WAS_RUNNING_APP="${running%/Contents/MacOS/AgentSpace}"
			break ;;
	esac
done < <(ps -U "$(id -u)" -o comm=)
pkill -U "$(id -u)" -f "AgentSpace.app/Contents/MacOS/AgentSpace" 2>/dev/null; sleep 1
"$APP_BIN" >/dev/null 2>&1 &
APP_PID=$!
sleep 5
trap '{ kill $APP_PID 2>/dev/null; [ -n "$WAS_RUNNING_APP" ] && open "$WAS_RUNNING_APP"; } 2>/dev/null' EXIT

# --- Launch: exactly one window (§41's deep-link window bug) ----------------
# A binary that predates onOpenURL never consumes queued agentspace:// open
# events, so LaunchServices re-delivers them at every launch and each one
# spawns a WindowGroup window — three identical windows, and every sheet
# flag then presents in all of them at once. One launch, one window.
WINDOWS=""
for attempt in 1 2 3 4 5; do
  WINDOWS="$(osascript -e 'tell application "System Events" to tell process "AgentSpace" to return count of windows' 2>/dev/null)"
  [ "${WINDOWS:-?}" = "1" ] && break
  sleep 1
done
check "launch opens exactly one window" "1" "${WINDOWS:-?}"

# --- Version stamp: the sidebar shows what the bundle actually carries -------
# The build number is stamped at bundle time (scripts/bundle-app.sh); if the
# UI ever drifts from the plist, "am I on the new build?" becomes unanswerable
# again, which is the failure this pins. The label around the number is
# localized, so the check compares the current marketing-version part, not the whole line.
SHORT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
BUILDN="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_BUNDLE/Contents/Info.plist")"
# The sidebar footer is not in the AX tree the instant the window is; retries
# cover the cold-start race, same as the tier check below.
BUILD_TEXT=""
for attempt in 1 2 3 4 5; do
  BUILD_TEXT="$(osascript -e "$(cat /tmp/gui-verify-lib.applescript)
tell application \"System Events\"
	tell process \"AgentSpace\"
		set frontmost to true
		set _t to \"\"
		repeat with _w in windows
			set _e to my findById(_w, \"appBuildVersion\", static text, 0)
			if _e is not missing value then set _t to (value of _e) as text
		end repeat
		return _t
	end tell
end tell" 2>/dev/null)"
  case "$BUILD_TEXT" in *"$SHORT ($BUILDN)"*) break;; esac
  sleep 2
done
case "$BUILD_TEXT" in
  *"$SHORT ($BUILDN)"*) check "sidebar build stamp matches the bundle" "found" "found";;
  *) check "sidebar build stamp matches the bundle" "$SHORT ($BUILDN) in [$BUILD_TEXT]" "missing";;
esac

# --- Settings: open it the way every language names it: ⌘, ------------------
osascript >/dev/null 2>&1 <<'EOF'
tell application "System Events"
	tell process "AgentSpace"
		set frontmost to true
		repeat with _mi in menu items of menu 1 of menu bar item "AgentSpace" of menu bar 1
			try
				if value of attribute "AXMenuItemCmdChar" of _mi is "," then
					click _mi
					exit repeat
				end if
			end try
		end repeat
	end tell
end tell
EOF
sleep 2
# The window remembers its last tab; the first toolbar button is General in
# any language, and clicking it again when already there is a no-op.
osascript -e 'tell application "System Events" to tell process "AgentSpace" to click button 1 of toolbar 1 of window 1' >/dev/null 2>&1
sleep 1

# --- Settings: the polling floor lives in the control (§49) -----------------
SLIDER="$(osascript -e "$(cat /tmp/gui-verify-lib.applescript)
tell application \"System Events\"
	tell process \"AgentSpace\"
		set _s to my findById(window 1, \"statusRefreshSlider\", slider, 0)
		if _s is missing value then return \"\"
		return (value of attribute \"AXMinValue\" of _s) & \"|\" & (value of attribute \"AXMaxValue\" of _s)
	end tell
end tell" 2>/dev/null)"
SLIDER="$(echo "$SLIDER" | tr -d ' ,')"
check "refresh slider min=2.0"  "2.0" "${SLIDER%%|*}"
check "refresh slider max=10.0" "10.0" "${SLIDER##*|}"

# --- Settings: Preview width tiers (§53) -------------------------------------
# The tier labels ("960 px" …) are deliberately untranslated, so the titles
# compare equal in both languages.
TIERS=""
for attempt in 1 2; do
  TIERS="$(osascript -e "$(cat /tmp/gui-verify-lib.applescript)
tell application \"System Events\"
	tell process \"AgentSpace\"
		set _p to my findById(window 1, \"previewWidthPicker\", pop up button, 0)
		if _p is missing value then return \"\"
		click _p
		delay 1
		set _out to \"\"
		repeat with _mi in (menu items of menu 1 of _p)
			set _out to _out & ((title of _mi) as text) & \"|\"
		end repeat
		return _out
	end tell
end tell" 2>/dev/null)"
  TIERS="$(echo "$TIERS" | sed 's/|$//; s/ //g')"
  [ "$TIERS" = "960px|1280px|1600px|1920px" ] && break
  osascript -e 'key code 53' >/dev/null 2>&1; sleep 1
done
check "preview tiers" "960px|1280px|1600px|1920px" "$TIERS"
osascript -e 'key code 53' >/dev/null 2>&1
# close the Settings window so the deep-link phase below sees one window again
osascript -e 'tell application "System Events" to tell process "AgentSpace" to keystroke "w" using command down' >/dev/null 2>&1
sleep 1

# --- The wizard: account selection and helper readiness ----------------------
# The first step has two valid outcomes: an existing account can be selected
# and Continue reaches the review card, or the machine has no attachable account
# and the card offers the exact next actions. A click on a disabled SwiftUI
# button is a no-op, so merely returning "step 2" after `click` is not evidence
# that the wizard advanced (that was the bug this check used to miss).
# The finder library has to be handed to *this* script too. An earlier version
# ran it as a bare heredoc, so `my findById` was an unknown handler, the error
# went to /dev/null, and the phase below reported a healthy wizard that had
# never opened.
WIZARD="$(osascript -e "$(cat /tmp/gui-verify-lib.applescript)
tell application \"System Events\"
	tell process \"AgentSpace\"
		set frontmost to true
		keystroke \"n\" using command down
		delay 2
		set _f to my findById(window 1, \"agentNameField\", text field, 0)
		if _f is missing value then return \"no name field\"
		set value of _f to \"gui verify\"
		set _p to my findById(window 1, \"macOSUserPicker\", radio group, 0)
		if _p is not missing value then
			-- The first radio item is the unselected placeholder; choose the
			-- first real account so this check exercises the enabled path too.
			tell _p to click radio button 2
			delay 1
		end if
		delay 1
		set _c to my findById(window 1, \"wizardContinue\", button, 0)
		if _c is missing value then return \"no continue button\"
		if (enabled of _c) as boolean then
			click _c
			delay 2
			set _review to my findById(window 1, \"createAgentButton\", button, 0)
			if _review is missing value then return \"continue did not reach review\"
			return \"step 2\"
		end if
		set _open to my findById(window 1, \"openUsersGroupsButton\", button, 0)
		set _refresh to my findById(window 1, \"refreshAccountsButton\", button, 0)
		if _open is not missing value and _refresh is not missing value then return \"empty account state\"
		return \"account selection required\"
	end tell
end tell" 2>&1)"
CARDS="$(osascript -e "$(cat /tmp/gui-verify-lib.applescript)
on textsOf(theWindow, theDepth, theAcc)
	if theDepth > 9 then return theAcc
	tell application \"System Events\"
		try
			if class of theWindow is static text then set end of theAcc to (value of theWindow) as text
		end try
		try
			repeat with _e in (UI elements of theWindow)
				set theAcc to my textsOf(_e, theDepth + 1, theAcc)
			end repeat
		end try
	end tell
	return theAcc
end textsOf

tell application \"System Events\"
	tell process \"AgentSpace\"
		set _acc to {}
		repeat with _w in windows
			set _acc to my textsOf(_w, 0, _acc)
		end repeat
		set _t to \"\"
		repeat with _x in _acc
			set _t to _t & (_x as text) & linefeed
		end repeat
		return _t
	end tell
end tell" 2>&1)"
case "$CARDS" in
  *HELPER_OUTDATED*) OUTDATED=1;;
  *) OUTDATED=0;;
esac
CREATE_ENABLED="$(osascript -e "$(cat /tmp/gui-verify-lib.applescript)
tell application \"System Events\"
	tell process \"AgentSpace\"
		set _b to my findById(window 1, \"createAgentButton\", button, 0)
		if _b is missing value then return \"missing\"
		return (enabled of _b) as text
	end tell
end tell" 2>&1 | tr -d ' ,')"
if [ "$WIZARD" = "empty account state" ]; then
  check "wizard explains how to add an account" "empty account state" "$WIZARD"
elif [ "$WIZARD" = "step 2" ]; then
  check "wizard reaches the helper card" "step 2" "$WIZARD"
elif [ "$CREATE_ENABLED" = "missing" ]; then
  # No review button and no account guidance is a real diagnostic failure.
  check "wizard reaches a real next state" "step 2" "$WIZARD"
elif [ "$OUTDATED" = "1" ]; then
  check "Create is refused while the helper is stale" "false" "$CREATE_ENABLED"
else
  check "Create is armed for a current helper" "true" "$CREATE_ENABLED"
fi
note "wizard: $WIZARD"
# Close the wizard rather than create anything: this test reads, it does not
# change the machine.
osascript -e 'tell application "System Events" to tell process "AgentSpace" to key code 53' >/dev/null 2>&1
sleep 1

# --- Deep link: dead Space raises SPACE_NOT_FOUND (§46) ---------------------
TMPROOT="$(mktemp -d /tmp/gui-verify.XXXXXX)"
mkdir -p "$TMPROOT/Spaces"
echo '{"spaces":[]}' > "$TMPROOT/Spaces/index.json"
kill $APP_PID 2>/dev/null; sleep 1
AGENTSPACE_ROOT="$TMPROOT" "$APP_BIN" >/dev/null 2>&1 &
APP_PID=$!
sleep 4
DEAD_ID="11111111-2222-4333-8444-555555555555"
# Always target the bundle under test.  A bare scheme open can route to an
# older copy in /Applications, making this assertion inspect the wrong app.
open -a "$APP_BUNDLE" "agentspace://space/$DEAD_ID"
sleep 3
# the alert's first static text is the error code, which is never localized
ALERT="$(osascript -e 'tell application "System Events" to tell process "AgentSpace" to return value of static text 1 of sheet 1 of window 1' 2>/dev/null | head -c 16)"
check "dead link alert" "SPACE_NOT_FOUND" "$ALERT"

# --- report ------------------------------------------------------------------
rm -rf "$TMPROOT" /tmp/gui-verify-lib.applescript
echo
echo "gui-verify: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
