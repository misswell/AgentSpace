#!/usr/bin/env bash
#
# End-to-end smoke run: start a real worker against a throwaway root, then drive
# every CLI surface against it and print what came back.
#
# This is what docs/validation.md cites for the CLI, status, screenshot, exec and
# fail-closed behaviour on a single-user machine. It needs no root and no second
# account: the worker runs in whatever session invokes the script, which on a
# normal developer machine is the console — exactly the case where input MUST be
# refused, so the refusal is the observable result.
#
#   scripts/demo.sh
#
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT_DIR="$(pwd)"

echo "== building =="
swift build --product agentspace-worker --product agentspace 2>&1 | grep -Ev "^warning: 'agentspace'|^Building|^\[" || true

WORKER="$ROOT_DIR/.build/debug/agentspace-worker"
CLI="$ROOT_DIR/.build/debug/agentspace"
for binary in "$WORKER" "$CLI"; do
  if [[ ! -x "$binary" ]]; then
    echo "missing $binary — run 'swift build' first" >&2
    exit 1
  fi
done

# A short root: the socket path must fit sockaddr_un.sun_path (103 bytes).
ROOT="${AGENTSPACE_DEMO_ROOT:-/tmp/as-demo}"
rm -rf "$ROOT"
SPACE_ID="$(uuidgen)"
mkdir -p "$ROOT/Spaces" "$ROOT/Runtime/$SPACE_ID"
chmod 700 "$ROOT/Runtime/$SPACE_ID"

python3 - "$ROOT" "$SPACE_ID" <<'PY'
import json, sys, datetime
root, space_id = sys.argv[1], sys.argv[2]
registry = {
    "spaces": [{
        "id": space_id,
        "name": "Demo",
        "username": "_agentspace_demo",
        "uid": 502,
        "state": "ready",
        "createdAt": datetime.datetime.now(datetime.timezone.utc)
            .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "workspace": {"kind": "none"},
        "sharedFolders": [],
        "permissions": {"screenRecording": False, "accessibility": False},
        "autoStartWorker": True,
    }]
}
open(f"{root}/Spaces/index.json", "w").write(json.dumps(registry, indent=2))
PY

# The worker's own stdout/stderr go to a file, never to a descriptor this script
# shares. A background process that inherits a pipe holds its write end open, and
# any `command | sed` downstream would then wait forever for EOF.
"$WORKER" --space-id "$SPACE_ID" --name Demo --runtime-dir "$ROOT" --quiet \
  >"$ROOT/worker.log" 2>&1 </dev/null &
WORKER_PID=$!
trap 'kill "$WORKER_PID" 2>/dev/null; wait "$WORKER_PID" 2>/dev/null' EXIT

for _ in $(seq 1 100); do
  [[ -S "$ROOT/Runtime/$SPACE_ID/worker.sock" ]] && break
  sleep 0.1
done

run() {
  echo
  echo "── \$ agentspace $* ─────────────────────────────────────"
  AGENTSPACE_ROOT="$ROOT" "$CLI" "$@" 2>&1 | sed 's/^/   /'
  echo "   [exit ${PIPESTATUS[0]}]"
}

run list
run status Demo
echo
echo "── \$ agentspace apps Demo (first 6 of many) ─────────────"
AGENTSPACE_ROOT="$ROOT" "$CLI" apps Demo 2>&1 | head -6 | sed 's/^/   /'
run exec Demo "id -un; id -u; sw_vers -productVersion"
run exec Demo "sudo whoami"          # refused by ExecGuard
run exec Demo "exit 7"               # a non-zero exit is a normal result
run screenshot Demo --max-width 640

echo
echo "── fail-closed: every input call must be refused with SESSION_IS_CONSOLE ──"
for cmd in "move Demo 100 100" "click Demo 100 100" "type Demo hello" \
           "key Demo cmd+l" "scroll Demo 0 -100" "drag Demo 1 1 50 50"; do
  run $cmd
done

echo
echo "── --json mode on a refusal (the plan's §2 envelope) ──"
run click Demo 10 10 --json

echo
echo "── doctor ──────────────────────────────────────────────"
AGENTSPACE_ROOT="$ROOT" "$CLI" doctor 2>&1 | sed 's/^/   /'
echo "   [exit ${PIPESTATUS[0]}]"

echo
echo "== done. worker pid was $WORKER_PID =="
