#!/bin/bash
# session-gui-verify.sh — layer 4's UI checks, run inside an agent account's own
# session instead of in front of whoever is sitting at this Mac.
#
# Why this exists (§323 row 863, §324): `scripts/gui-verify.sh` has to clear the
# slate — it closes every AgentSpace copy this uid owns and then drives a window
# of its own on the *human's* screen for a minute or two. During 0.1.31's release
# it ran six times in one afternoon while the owner was working, closing their
# window each time, and the request that came back was
# 「做测试的时候可否尽量不要打扰我操作」. This is the durable answer: the same 13
# checks, driven through `agentspace exec` in the agent account's session.
#
# Nothing appears on this screen, this uid's AgentSpace copies are never
# signalled, and the check cannot reach them even by accident: it runs as the
# agent user, whose kill of the human's pid answers `Operation not permitted`.
#
# Requirements: an attached account with a live worker (that is what
# `agentspace-list` reports), and the CLI + checker binaries built from this
# tree. No Accessibility grant is needed on this side — the grant that matters
# is the one the worker already holds in its own session.
#
# Exit codes, matching scripts/acceptance.sh's convention:
#   0  the checks ran and passed
#   1  the checks ran and something failed
#   3  the checks could not run — not a pass
set -u
cd "$(dirname "$0")/.."

ACCOUNT=""
BUNDLE="${AGENTSPACE_GUI_APP:-dist/AgentSpace.app}"
CLI="${AGENTSPACE_CLI:-.build/debug/agentspace}"
PROBE_BIN=".build/debug/agentspace-gui-check"
PASSTHROUGH=()

usage() {
  cat <<'USAGE'
usage: scripts/session-gui-verify.sh [--account NAME] [--bundle PATH] [--verbose] [--keep-root]

  --account NAME   which attached account's session to run in (default: the only one)
  --bundle PATH    the app bundle under test (default: dist/AgentSpace.app)
  --verbose        print the surfaces the checks read
  --keep-root      leave the scratch registry behind for inspection
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --account) ACCOUNT="${2:-}"; shift 2 ;;
    --bundle)  BUNDLE="${2:-}"; shift 2 ;;
    --verbose|--keep-root) PASSTHROUGH+=("$1"); shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "session-gui-verify: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
done

case "$BUNDLE" in
  /*) ;;
  *) BUNDLE="$PWD/$BUNDLE" ;;
esac

refuse() {
  echo "session-gui-verify: refusing to run — $1" >&2
  shift
  for line in "$@"; do echo "  $line" >&2; done
  exit 3
}

# --- build the two binaries, one product per invocation ----------------------
# Not `swift build --product agentspace --product agentspace-gui-check`: that
# answers 0 having built only ONE of them (§319 row 827), and a gate that
# silently tests yesterday's CLI is the defect class this repository has paid
# for most often.
echo "==> building agentspace + agentspace-gui-check"
swift build --product agentspace 2>&1 | grep -Ev "^\[|^warning: 'agentspace'" || true
swift build --product agentspace-gui-check 2>&1 | grep -Ev "^\[|^warning: 'agentspace'" || true
[ -x "$CLI" ] || refuse "the CLI is not built at $CLI" \
  "Set AGENTSPACE_CLI=/path/to/agentspace, or run swift build --product agentspace."
[ -x "$PROBE_BIN" ] || refuse "the checker is not built at $PROBE_BIN" \
  "Run swift build --product agentspace-gui-check."
[ -d "$BUNDLE" ] || refuse "no app bundle at $BUNDLE" \
  "Pass --bundle /path/to/AgentSpace.app, or build dist/ with scripts/release.sh."

# --- which account's session -------------------------------------------------
# Names may contain spaces, so the name is what sits between the status marker
# and the two spaces before the state label — not a whitespace-split field.
ACCOUNTS="$("$CLI" list 2>/dev/null | sed -n 's/^[●○][[:space:]]\{1,\}\(.*\)[[:space:]]\{2\}\[.*/\1/p')"
COUNT="$(printf '%s' "$ACCOUNTS" | grep -c . || true)"
if [ -z "$ACCOUNT" ]; then
  case "$COUNT" in
    0) refuse "no agent account is attached, so there is no second session to verify in" \
         "Attach one in the AgentSpace app (Connect Account); the console gate" \
         "(scripts/gui-verify.sh) is the one that needs no account." ;;
    1) ACCOUNT="$(printf '%s' "$ACCOUNTS" | head -1)" ;;
    *) refuse "$COUNT agent accounts are attached, so which session to use is ambiguous" \
         "Attached: $(printf '%s' "$ACCOUNTS" | tr '\n' ' ')" \
         "Name one: scripts/session-gui-verify.sh --account NAME" ;;
  esac
fi

# --- that session must be usable, and looking at it must not be the point ----
STATUS="$("$CLI" status "$ACCOUNT" --json 2>&1)" || refuse "could not read the status of '$ACCOUNT'" \
  "$(printf '%s' "$STATUS" | head -3)"

json_flag() { printf '%s' "$1" | grep -E "\"$2\"[[:space:]]*:[[:space:]]*$3" >/dev/null 2>&1; }
json_flag "$STATUS" worker true || refuse "the worker for '$ACCOUNT' is not answering" \
  "The session gate drives the build under test from inside that session, so the" \
  "worker has to be running there. Start it from the AgentSpace app, or reinstall" \
  "the helper if the account has no worker yet."
# An agent desktop that IS the console is the one case where these checks would
# put windows in front of a person: their own screen is that session's screen.
# The worker refuses input in that state for the same reason, by design.
json_flag "$STATUS" onConsole false || refuse "'$ACCOUNT' is on the console right now" \
  "Its desktop is the physical screen, so opening windows in it is exactly the" \
  "disturbance this gate exists to avoid. Re-run when that desktop is in the" \
  "background again."
VERDICT="$(printf '%s' "$STATUS" | sed -n 's/.*"verdict"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
SESSION_LINE="$(printf '%s' "$STATUS" | sed -n 's/.*"stateLabel"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
echo "==> $ACCOUNT: worker answers, state ${SESSION_LINE:-?}, session verdict ${VERDICT:-unreadable}"
echo "    bundle under test: $BUNDLE"
echo "    nothing will open on this screen; the checks run on $ACCOUNT's own desktop"

# --- hand the checker to that session ----------------------------------------
# It has to live somewhere the agent user can traverse: /tmp is 1777, and the
# copy is made world-executable for the same reason. `mktemp -d` alone would
# hand out a 0700 directory the agent user cannot enter.
STAGE="$(mktemp -d /tmp/agentspace-gui-verify.XXXXXX)"
chmod 755 "$STAGE"
cp "$PROBE_BIN" "$STAGE/agentspace-gui-check"
chmod 755 "$STAGE/agentspace-gui-check"
LOG="$(mktemp /tmp/agentspace-gui-verify-log.XXXXXX)"
cleanup() { rm -rf "$STAGE" "$LOG"; }
trap cleanup EXIT

# The checker's own exit code has to survive a channel that flattens it: the
# CLI's `exec` maps any non-zero child exit to 1 (`main.swift`, the exec verb),
# so the code is echoed by the same shell that ran the checker and read back
# from there. `$?` is single-quoted so the *inner* shell expands it, and the
# whole printf is one argument because the CLI joins its command from argv with
# spaces.
# shellcheck disable=SC2016
"$CLI" exec "$ACCOUNT" --timeout 300000 -- "$STAGE/agentspace-gui-check" \
  --bundle "$BUNDLE" ${PASSTHROUGH[@]+"${PASSTHROUGH[@]}"} \
  ';' 'printf "agentspace-gui-check exit: %s\n" "$?"' >"$LOG" 2>&1
STATUS_CODE=$?

CODE="$(sed -n 's/^agentspace-gui-check exit: //p' "$LOG" | tail -1)"
sed -e '/^agentspace-gui-check exit: /d' \
    -e '/^exit [0-9][0-9]* ([0-9][0-9]*ms)$/d' \
    -e '/^exit signal /d' "$LOG"

case "${CODE:-}" in
  0)
    echo
    echo "session-gui-verify: 13 checks passed in $ACCOUNT's session (nothing on this screen)"
    exit 0
    ;;
  1)
    echo
    echo "session-gui-verify: checks FAILED in $ACCOUNT's session — the report above names them" >&2
    exit 1
    ;;
  3)
    echo
    echo "session-gui-verify: the checker refused to run in $ACCOUNT's session (see above)" >&2
    exit 3
    ;;
  "")
    echo
    echo "session-gui-verify: the checker never reported an exit code (exec exited $STATUS_CODE)" >&2
    echo "  — that is 'not measured', not 'passed'." >&2
    exit 3
    ;;
  *)
    echo
    echo "session-gui-verify: the checker exited $CODE in $ACCOUNT's session" >&2
    exit 3
    ;;
esac
