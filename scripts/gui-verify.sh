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

# Run the management UI against an isolated empty registry. The verification
# must not inherit a real attached account's runtime (which intentionally shows
# the account-owner permission hand-off instead of the management dashboard),
# and it must never inspect or mutate the user's actual registry.
GUI_ROOT="$(mktemp -d /tmp/gui-verify-root.XXXXXX)"
mkdir -p "$GUI_ROOT/Spaces"
printf '%s\n' '{"spaces":[]}' > "$GUI_ROOT/Spaces/index.json"
export AGENTSPACE_ROOT="$GUI_ROOT"

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

on windowWithId(theProcess, wantedId, theClass)
	tell application "System Events"
		repeat with _w in (windows of theProcess)
			if my findById(_w, wantedId, theClass, 0) is not missing value then return _w
		end repeat
	end tell
	return missing value
end windowWithId

on findAny(theWindow, wantedId, theDepth)
	-- Identifier-only lookup, for controls whose AppKit class is SwiftUI's choice
	-- rather than ours: a Toggle reports as a checkbox, a Form as a group, and
	-- neither is spelled in the source.
	if theDepth > 8 then return missing value
	tell application "System Events"
		try
			repeat with _e in (UI elements of theWindow)
				try
					if ((value of attribute "AXIdentifier" of _e) as text) is wantedId then return _e
				end try
			end repeat
		end try
		repeat with _e in (UI elements of theWindow)
			set _found to my findAny(_e, wantedId, theDepth + 1)
			if _found is not missing value then return _found
		end repeat
	end tell
	return missing value
end findAny

on advancedSettingsWindow(theProcess)
	-- Which window is Settings cannot be answered by `window 1`: the dashboard
	-- and the Settings window are both on screen and the order the accessibility
	-- API reports them in is the window server's, not the app's. A run that read
	-- `window 1` sometimes looked at the dashboard and reported the Advanced
	-- controls as missing — six passed, one inexplicably empty. So the tab is
	-- chosen by walking every window for a toolbar whose fourth button reveals
	-- the slider this tab owns. Fourth because the settings tabs are declared in
	-- a fixed order, which holds in every language.
	tell application "System Events"
		repeat with _w in (windows of theProcess)
			try
				if (count of (buttons of toolbar 1 of _w)) > 3 then
					click button 4 of toolbar 1 of _w
					delay 1
					if my findById(_w, "statusRefreshSlider", slider, 0) is not missing value then return _w
				end if
			end try
		end repeat
	end tell
	return missing value
end advancedSettingsWindow

on updateSettingsWindow(theProcess)
	-- The LAST toolbar button, not "button 5": the tab order is a contract this
	-- script already depends on (button 4 is Advanced), and Update is declared
	-- after it. Reading the count rather than hard-coding an index keeps this
	-- check pointing at a real tab if a sixth one ever appears.
	tell application "System Events"
		repeat with _w in (windows of theProcess)
			try
				set _n to count of (buttons of toolbar 1 of _w)
				if _n > 0 then
					click button _n of toolbar 1 of _w
					delay 1
					if my findAny(_w, "updateCheckButton", 0) is not missing value then return _w
				end if
			end try
		end repeat
	end tell
	return missing value
end updateSettingsWindow
APPLESCRIPT

# Every check below reads the accessibility tree of a window the app puts on
# screen, and a locked console session orders no window on screen for anything:
# not for the app under test, and not for TextEdit either. Without this guard the
# run reports seven failures — indistinguishable from seven product regressions —
# when the machine is simply not presenting windows. It refuses instead, and it
# refuses before touching the running app, because there is nothing to verify and
# no reason to disturb the user's session for it. It never tries to unlock.
#
# Same probe the worker's own console guard uses, and the same documented trap:
# the dictionary carries `kCGSSessionOnConsoleKey` (two S's), not the
# documented-flavoured single-S spelling. Undetermined is refused: a session
# state nobody can read is exactly when a green check would mean nothing.
#
# The values are read as booleans-or-numbers rather than as Swift `Bool`,
# because CoreGraphics hands back CFBoolean for one key and CFNumber for the
# other. A flag that cannot be read is treated as "not presenting".
SESSION_STATE="$(xcrun swift - 2>/dev/null <<'SWIFT'
import CoreGraphics
import Foundation
func flag(_ value: Any?) -> Bool? {
    if let b = value as? Bool { return b }
    if let n = value as? NSNumber { return n.intValue != 0 }
    if let i = value as? Int { return i != 0 }
    return nil
}
guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else {
    print("unknown"); exit(0)
}
let console = flag(d["kCGSSessionOnConsoleKey"]) ?? flag(d["kCGSessionOnConsoleKey"])
let locked = flag(d["CGSSessionScreenIsLocked"]) ?? false
if console != true { print("off-console") } else if locked { print("locked") } else { print("presenting") }
SWIFT
)"
case "${SESSION_STATE:-unknown}" in
  presenting) ;;
  locked)
    rm -rf "$GUI_ROOT"
    echo "gui-verify: refusing to run — the console session's screen is LOCKED, so no" >&2
    echo "  app can put a window on screen and every accessibility read would come back" >&2
    echo "  empty. That is the machine, not the build. Unlock the screen and re-run." >&2
    exit 1 ;;
  off-console)
    rm -rf "$GUI_ROOT"
    echo "gui-verify: refusing to run — this session is not on the console, so its" >&2
    echo "  windows are not being presented and nothing here could be observed." >&2
    exit 1 ;;
  *)
    rm -rf "$GUI_ROOT"
    echo "gui-verify: refusing to run — the session's console state could not be read," >&2
    echo "  and a verification that cannot say what it observed says nothing." >&2
    exit 1 ;;
esac
note "session presenting windows ($SESSION_STATE)"

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
pkill -U "$(id -u)" -f "AgentSpace.app/Contents/MacOS/AgentSpace" 2>/dev/null
# Wait for the slate to actually be clear. The human's own copy in
# /Applications has the same process name as the build under test, and a
# name-based accessibility query binds to whichever System Events resolves
# first — so a run that starts while the old copy is still dying reads the
# *old* app's windows and reports the build under test as broken. It also
# refuses rather than escalating: killing a process this script does not own
# twice in a row means something is holding it, and that is worth seeing.
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -U "$(id -u)" -f "AgentSpace.app/Contents/MacOS/AgentSpace" >/dev/null 2>&1 || break
  sleep 1
done
if pgrep -U "$(id -u)" -f "AgentSpace.app/Contents/MacOS/AgentSpace" >/dev/null 2>&1; then
  echo "gui-verify: refusing to run — an AgentSpace instance this uid still will not" >&2
  echo "  exit after 10s:" >&2
  pgrep -U "$(id -u)" -lf "AgentSpace.app/Contents/MacOS/AgentSpace" | sed 's/^/    /' >&2
  rm -rf "$GUI_ROOT"
  exit 1
fi
# `-NSQuitAlwaysKeepsWindows NO` is an argv-domain override: it writes nothing
# and changes nothing the user sees. It removes one known source of extra
# windows — AppKit restoring what a previous verification run left in the shared
# `com.agentspace.*` defaults (the installed copy shares that domain, and its
# window autosave names run up to AppWindow-4). It is not claimed to explain the
# whole of this check's history: with the flag in place a run still settled at
# two windows once (§299 row 643). The §41 defect the check exists for is queued
# deep-link re-delivery, and those windows still arrive with restoration off.
"$APP_BIN" -NSQuitAlwaysKeepsWindows NO >/dev/null 2>&1 &
APP_PID=$!
# Every query below addresses the app by pid for the same reason.
PT="first application process whose unix id is $APP_PID"
sleep 5
# `open` hands its own environment to the application it launches — measured,
# not assumed: the copy this script returned to the owner carried
# `AGENTSPACE_ROOT=/tmp/gui-verify-root.a6EBZu` in its process environment, so
# their real window read the throwaway registry and reported their attached
# Agent as missing (§300). Every `open` below therefore runs with the test
# variables removed, and the hand-back is checked afterwards.
cleanup() {
  kill $APP_PID 2>/dev/null
  rm -rf "$GUI_ROOT"
  [ -n "$WAS_RUNNING_APP" ] && env -u AGENTSPACE_ROOT -u AGENTSPACE_GUI_APP open "$WAS_RUNNING_APP"
  sleep 2
  for survivor in $(pgrep -U "$(id -u)" -f "AgentSpace.app/Contents/MacOS/AgentSpace"); do
    if ps eww -p "$survivor" 2>/dev/null | tr ' ' '\n' | grep -q '^AGENTSPACE_ROOT='; then
      echo "gui-verify: WARNING pid $survivor still carries AGENTSPACE_ROOT — quit it and reopen AgentSpace" >&2
    fi
  done
}
trap cleanup EXIT

# --- Launch: exactly one window (§41's deep-link window bug) ----------------
# A binary that predates onOpenURL never consumes queued agentspace:// open
# events, so LaunchServices re-delivers them at every launch and each one
# spawns a WindowGroup window — three identical windows, and every sheet
# flag then presents in all of them at once. One launch, one window.
WINDOWS=""
PREV_WINDOWS=""
SAMPLES=""
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  WINDOWS="$(osascript -e "tell application \"System Events\" to tell ($PT) to return count of windows" 2>/dev/null)"
  SAMPLES="$SAMPLES${SAMPLES:+,}${WINDOWS:-?}"
  # Two equal readings in a row, not the first reading. Single samples have been
  # observed to disagree with themselves a second apart on this machine — one
  # failing run reported a settled `2,2` and then an empty window list from the
  # diagnostic immediately after it — so one reading is not yet evidence about
  # the build. A count that *stays* at 2 is exactly what this check exists to
  # catch, and requiring agreement still catches it.
  #
  # A count that stays at 0 is not the same fact: 0 is what a window that has
  # not been ordered on screen yet reads as, and agreement does not make a
  # launch any further along. A run on 0.1.19 settled on `0,0` at five and six
  # seconds and reported four failures, while the same bundle polled from the
  # moment of its exec showed its window 0.4s in, three times out of three. So
  # 0 spends the whole retry budget before it is believed; a window that really
  # never arrives still fails, fifteen seconds later.
  [ "$WINDOWS" = "$PREV_WINDOWS" ] && [ "$WINDOWS" != "0" ] && break
  PREV_WINDOWS="$WINDOWS"
  sleep 1
done
if [ "${WINDOWS:-?}" != "1" ]; then
  # A bare `expected 1 got 2` has three possible causes and they need different
  # fixes: a queued deep link re-delivered at launch (§41), AppKit restoring a
  # window another run left behind, or a genuinely second window from this
  # build. Naming the windows here is what tells them apart later, so the
  # failure carries them instead of just the count.
  osascript -e "tell application \"System Events\" to tell ($PT)
set _o to \"\"
repeat with _w in windows
	set _o to _o & (count of (UI elements of _w) as text) & \" elements; \"
end repeat
return _o" 2>/dev/null > /tmp/gui-verify-windows.txt
  note "  windows seen: $(cat /tmp/gui-verify-windows.txt 2>/dev/null)"
  OTHERS="$(pgrep -U "$(id -u)" -lf "AgentSpace.app/Contents/MacOS" | grep -v "^$APP_PID " || true)"
  note "  window count samples: $SAMPLES"
  note "  bundle under test: $APP_BUNDLE (pid $APP_PID)"
  note "  other AgentSpace processes: ${OTHERS:-none}"
fi
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
	tell ($PT)
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

# --- The empty state names the registry it actually read (§300) --------------
# This run's whole premise is a throwaway AGENTSPACE_ROOT, and an owner looking
# at that window concluded their Agent had been deleted. The panel has to say
# which file it read before it offers any theory about why it is empty.
NOTICE=""
for attempt in 1 2 3; do
  NOTICE="$(osascript -e "$(cat /tmp/gui-verify-lib.applescript)
tell application \"System Events\"
	tell ($PT)
		set _out to \"\"
		repeat with _w in windows
			set _e to my findById(_w, \"registryRootOverrideNotice\", static text, 0)
			if _e is not missing value then set _out to (value of _e) as text
		end repeat
		return _out
	end tell
end tell" 2>/dev/null | tr -d '\n')"
  case "$NOTICE" in *"$GUI_ROOT"*) break;; esac
  sleep 1
done
case "$NOTICE" in
  *"$GUI_ROOT"*) check "empty state names the registry it read" "found" "found";;
  *) check "empty state names the registry it read" "[$NOTICE] to contain $GUI_ROOT" "missing";;
esac

# --- Settings: open it the way every language names it: ⌘, ------------------
# Asked of the target process's own menu bar, and retried. The heredoc this
# replaces ran once and threw both its error and its outcome away, so a run
# whose menu bar was not ready yet reported Settings as *empty* five checks
# later — nine controls missing at once, with nothing to say whether the tab
# never opened or the click never landed.
SETTINGS_OPEN=""
for attempt in 1 2 3 4 5; do
  SETTINGS_OPEN="$(osascript -e "$(cat /tmp/gui-verify-lib.applescript)
tell application \"System Events\"
	set _p to ($PT)
	set frontmost of _p to true
	set _mm to menu 1 of menu bar item \"AgentSpace\" of menu bar 1 of _p
	set _hit to \"no comma item (\" & (count of menu items of _mm) & \" items)\"
	repeat with _mi in menu items of _mm
		try
			if value of attribute \"AXMenuItemCmdChar\" of _mi is \",\" then
				click _mi
				set _hit to \"clicked\"
				exit repeat
			end if
		end try
	end repeat
	return _hit
end tell" 2>&1 | tr -d '\n')"
  sleep 2
  [ "$SETTINGS_OPEN" = "clicked" ] && break
  sleep 1
done
# Whether the click landed and whether anything is on screen are two different
# facts, and only the second one explains the checks below.
SETTINGS_WINDOWS="$(osascript -e "tell application \"System Events\" to return (count of windows of ($PT)) as text" 2>&1 | tr -d '\n')"
note "settings opener: $SETTINGS_OPEN, windows=$SETTINGS_WINDOWS"

# --- Settings: the polling floor lives in the control (§49) -----------------
# Poll for the control, then assert its values. A single read two seconds after
# ⌘, reported both Advanced controls as missing on a build that answered them
# correctly one run later (§307) — the same disagreement between two runs of
# this script that §299 and §302 recorded for window counts. Retrying the
# *lookup* keeps the assertion exact: a slider that really never arrives still
# fails, five seconds later.
SLIDER=""
for attempt in 1 2 3 4 5; do
  SLIDER="$(osascript -e "$(cat /tmp/gui-verify-lib.applescript)
tell application \"System Events\"
	set _p to ($PT)
	set _w to my advancedSettingsWindow(_p)
	if _w is missing value then return \"\"
	set _s to my findById(_w, \"statusRefreshSlider\", slider, 0)
	if _s is missing value then return \"\"
	return (value of attribute \"AXMinValue\" of _s) & \"|\" & (value of attribute \"AXMaxValue\" of _s)
end tell" 2>/dev/null)"
  SLIDER="$(echo "$SLIDER" | tr -d ' ,')"
  [ -n "$SLIDER" ] && [ "$SLIDER" != "|" ] && break
  sleep 1
done
check "refresh slider min=2.0"  "2.0" "${SLIDER%%|*}"
check "refresh slider max=10.0" "10.0" "${SLIDER##*|}"

# --- Settings: the display-quality tiers (§53, §323) --------------------------
# This control used to be a width list whose labels were deliberately
# untranslated. It is now the mode picker the viewer's footer carries as well —
# one key, one default, one option list — and its three names *are* localized,
# so the assertion is exact against each shipped language instead of against
# titles that only hold in one of them. §318's rule: never assert a localized
# title in whatever language the machine happens to run.
QUALITY=""
for attempt in 1 2 3 4 5; do
  QUALITY="$(osascript -e "$(cat /tmp/gui-verify-lib.applescript)
tell application \"System Events\"
	set _p to ($PT)
	set _w to my advancedSettingsWindow(_p)
	if _w is missing value then return \"\"
	set _pp to my findById(_w, \"displayQualityPicker\", pop up button, 0)
	if _pp is missing value then return \"\"
	click _pp
	delay 1
	set _out to \"\"
	repeat with _mi in (menu items of menu 1 of _pp)
		set _out to _out & ((title of _mi) as text) & \"|\"
	end repeat
	return _out
end tell" 2>/dev/null)"
  QUALITY="$(echo "$QUALITY" | sed 's/|$//; s/ //g')"
  case "$QUALITY" in
    "NativeRetina|Balanced|Performance"|"原生Retina|均衡|性能") break ;;
  esac
  osascript -e 'key code 53' >/dev/null 2>&1; sleep 1
done
case "$QUALITY" in
  "NativeRetina|Balanced|Performance") QUALITY_VERDICT="NativeRetina|Balanced|Performance" ;;
  "原生Retina|均衡|性能")                QUALITY_VERDICT="NativeRetina|Balanced|Performance" ;;
  *)                                     QUALITY_VERDICT="$QUALITY" ;;
esac
check "display quality tiers" "NativeRetina|Balanced|Performance" "$QUALITY_VERDICT"
osascript -e 'key code 53' >/dev/null 2>&1

# --- Settings: the Update pane exists and starts in a safe state -------------
# The claim worth gating is not "the tab is there" but "the destructive control
# is not on screen yet". `updateInstallButton` lives only in the `.available`
# state, which requires a download that matched GitHub's digest and passed
# signature, team, identity and Gatekeeper — so before any of that the pane
# offers a check and a preference, and nothing that could replace the app.
# AGENTSPACE_ROOT is set for this run, which suppresses the automatic check, so
# this is genuinely the untouched state rather than a result.
UPDATE_PANE="$(osascript -e "$(cat /tmp/gui-verify-lib.applescript)
tell application \"System Events\"
	set _p to ($PT)
	set _w to my updateSettingsWindow(_p)
	if _w is missing value then return \"n|n|?|n|n\"
	set _out to \"\"
	repeat with _id in {\"softwareUpdatePane\", \"updateCheckButton\", \"automaticUpdateCheckToggle\"}
		if my findAny(_w, (_id as text), 0) is missing value then
			set _out to _out & \"n|\"
		else
			set _out to _out & \"y|\"
		end if
	end repeat
	set _c to my findAny(_w, \"updateCheckButton\", 0)
	if _c is missing value then
		set _out to _out & \"?|\"
	else if (enabled of _c) as boolean then
		set _out to _out & \"enabled|\"
	else
		set _out to _out & \"disabled|\"
	end if
	if my findAny(_w, \"updateInstallButton\", 0) is missing value then
		set _out to _out & \"absent\"
	else
		set _out to _out & \"present\"
	end if
	return _out
end tell" 2>/dev/null)"
check "update pane reachable"       "y" "$(echo "$UPDATE_PANE" | cut -d'|' -f1)"
check "update check control"        "y" "$(echo "$UPDATE_PANE" | cut -d'|' -f2)"
check "update preference control"   "y" "$(echo "$UPDATE_PANE" | cut -d'|' -f3)"
check "checking is possible"        "enabled" "$(echo "$UPDATE_PANE" | cut -d'|' -f4)"
check "install control before a release is verified" "absent" "$(echo "$UPDATE_PANE" | cut -d'|' -f5)"
# close the Settings window so the deep-link phase below sees one window again
osascript -e "tell application \"System Events\" to tell ($PT) to keystroke \"w\" using command down" >/dev/null 2>&1
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
	set _p to ($PT)
	set frontmost of _p to true
	-- This phase used to type ⌘N, and a keystroke lands on whatever the human
	-- last clicked: it reported \"no name field\" twice inside check-all and
	-- passed twice when the same script ran on its own, which is the same
	-- channel the Settings opener above had to stop using. So ask the menu bar
	-- directly, and find the item by its ⌘-char rather than by title — this
	-- machine's UI is Chinese (「文件」/「新建 Agent…」), where a title would
	-- not match. Re-asking is free: 'showingNewSpace' is a Bool, so a second
	-- pick opens nothing new.
	set _f to missing value
	set _w to missing value
	set _how to \"never asked\"
	repeat 12 times
		if _f is missing value then
			set _how to \"no ⌘N menu item\"
			repeat with _top in (menu bar items of menu bar 1 of _p)
				try
					repeat with _mi in (menu items of menu 1 of _top)
						try
							if value of attribute \"AXMenuItemCmdChar\" of _mi is \"n\" then
								click _mi
								set _how to \"asked\"
								exit repeat
							end if
						end try
					end repeat
				end try
				if _how is \"asked\" then exit repeat
			end repeat
		end if
		delay 1
		repeat with _cand in (windows of _p)
			set _try to my findById(_cand, \"agentNameField\", text field, 0)
			if _try is not missing value then
				set _f to _try
				set _w to _cand
				exit repeat
			end if
		end repeat
		if _f is not missing value then exit repeat
	end repeat
	-- The old failure string was undiagnosable: \"no name field\" could not say
	-- whether ⌘N never reached the app, whether a sheet held the key window so
	-- the command was refused, or whether AX simply enumerated nothing. Report
	-- what is actually on screen instead of guessing from the absence.
	if _f is missing value then
		set _d to \"no name field (\" & _how & \")\"
		set _d to _d & \" windows=\" & (count of windows of _p)
		repeat with _cand in (windows of _p)
			set _n to \"?\"
			try
				set _n to (name of _cand) as text
			end try
			set _d to _d & \" [\" & _n
			try
				if (count of sheets of _cand) > 0 then set _d to _d & \" sheet\"
			end try
			if my findById(_cand, \"createAgentButton\", button, 0) is not missing value then set _d to _d & \" review\"
			if my findById(_cand, \"macOSUserPicker\", radio group, 0) is not missing value then set _d to _d & \" picker\"
			set _d to _d & \"]\"
		end repeat
		return _d
	end if
	set value of _f to \"gui verify\"
	-- The account list is filled asynchronously by Directory Service. Reading the
	-- card once caught it mid-flight and reported \"empty account state\" on a
	-- machine that does have an attachable user, so wait for either answer
	-- before deciding which state the wizard is really in (§300).
	set _pkr to missing value
	repeat 6 times
		set _pkr to my findById(_w, \"macOSUserPicker\", radio group, 0)
		if _pkr is not missing value then exit repeat
		if my findById(_w, \"openUsersGroupsButton\", button, 0) is not missing value then exit repeat
		delay 1
	end repeat
	if _pkr is not missing value then
		-- The first radio item is the unselected placeholder; choose the
		-- first real account so this check exercises the enabled path too.
		tell _pkr to click radio button 2
		delay 1
	end if
	delay 1
	-- Selecting an account re-lays the footer (the hint text appears beside the
	-- button), and reading the footer once in that window reported
	-- \"no continue button\" on a build whose wizard advanced fine one run
	-- later (§307, the same two-runs-disagree class as the Advanced reads).
	-- Poll for the button; the enabled/disabled verdict below is unchanged, so
	-- a wizard that really has no way forward still fails.
	set _c to missing value
	repeat 5 times
		set _c to my findById(_w, \"wizardContinue\", button, 0)
		if _c is not missing value then exit repeat
		delay 1
	end repeat
	if _c is missing value then return \"no continue button\"
	if (enabled of _c) as boolean then
		click _c
		delay 2
		if my windowWithId(_p, \"createAgentButton\", button) is missing value then return \"continue did not reach review\"
		return \"step 2\"
	end if
	set _open to my findById(_w, \"openUsersGroupsButton\", button, 0)
	set _refresh to my findById(_w, \"refreshAccountsButton\", button, 0)
	if _open is not missing value and _refresh is not missing value then return \"empty account state\"
	return \"account selection required\"
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
	tell ($PT)
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
	set _p to ($PT)
	set _w to my windowWithId(_p, \"createAgentButton\", button)
	if _w is missing value then return \"missing\"
	set _b to my findById(_w, \"createAgentButton\", button, 0)
	if _b is missing value then return \"missing\"
	return (enabled of _b) as text
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
osascript -e "tell application \"System Events\" to tell ($PT) to key code 53" >/dev/null 2>&1
sleep 1

# --- Deep link: dead Space raises SPACE_NOT_FOUND (§46) ---------------------
TMPROOT="$(mktemp -d /tmp/gui-verify.XXXXXX)"
mkdir -p "$TMPROOT/Spaces"
echo '{"spaces":[]}' > "$TMPROOT/Spaces/index.json"
kill $APP_PID 2>/dev/null; sleep 1
AGENTSPACE_ROOT="$TMPROOT" "$APP_BIN" -NSQuitAlwaysKeepsWindows NO >/dev/null 2>&1 &
APP_PID=$!
PT="first application process whose unix id is $APP_PID"
sleep 4
DEAD_ID="11111111-2222-4333-8444-555555555555"
# Always target the bundle under test.  A bare scheme open can route to an
# older copy in /Applications, making this assertion inspect the wrong app.
# The test root is stripped so that a misroute cannot hand a foreign copy an
# empty registry (§300); if it does misroute, the check below fails loudly
# instead of quietly poisoning the owner's window.
env -u AGENTSPACE_ROOT -u AGENTSPACE_GUI_APP open -a "$APP_BUNDLE" "agentspace://space/$DEAD_ID"
sleep 3
# the alert's first static text is the error code, which is never localized
ALERT=""
for attempt in 1 2 3 4 5 6 7 8; do
  ALERT="$(osascript -e "tell application \"System Events\" to tell ($PT) to return value of static text 1 of sheet 1 of window 1" 2>/dev/null | head -c 16)"
  [ -n "$ALERT" ] && break
  sleep 1
done
check "dead link alert" "SPACE_NOT_FOUND" "$ALERT"

# Leave no pending open event behind. An app killed while a deep-link alert is
# still up hands that URL back to LaunchServices, and the next launch of any
# copy sharing this bundle id opens a second window from it — which is this
# script's own first check tripping over this script's own residue.
osascript -e "tell application \"System Events\" to tell ($PT) to key code 53" >/dev/null 2>&1
sleep 1
osascript -e "tell application \"System Events\" to tell ($PT) to keystroke \"w\" using command down" >/dev/null 2>&1
sleep 1

# --- report ------------------------------------------------------------------
rm -rf "$TMPROOT" /tmp/gui-verify-lib.applescript /tmp/gui-verify-windows.txt
echo
echo "gui-verify: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
