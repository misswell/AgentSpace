#!/usr/bin/env bash
#
# End-to-end check of the MCP server: bring up a real worker, then speak real
# MCP JSON-RPC to the server over stdio and assert that it drives the CLI and
# that the fail-closed refusal survives the MCP boundary.
#
#   scripts/mcp-smoke.sh
#
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT_DIR="$(pwd)"

MCP_DIR="$ROOT_DIR/packages/agentspace-mcp"
if [[ ! -f "$MCP_DIR/dist/index.js" ]]; then
  echo "== building the MCP server =="
  (cd "$MCP_DIR" && npm install --silent && npm run build) || {
    echo "could not build the MCP server" >&2
    exit 1
  }
fi

echo "== building the CLI and worker =="
swift build --product agentspace-worker --product agentspace 2>&1 \
  | grep -Ev "^warning: 'agentspace'|^\[[0-9]" || true

pkill -f "agentspace-worker --space-id" 2>/dev/null || true

ROOT="${AGENTSPACE_MCP_SMOKE_ROOT:-/tmp/as-mcp}"
rm -rf "$ROOT"
SPACE_ID="$(uuidgen)"
mkdir -p "$ROOT/Spaces" "$ROOT/Runtime/$SPACE_ID"
chmod 700 "$ROOT/Runtime/$SPACE_ID"

python3 - "$ROOT" "$SPACE_ID" <<'PY'
import json, sys
root, space_id = sys.argv[1], sys.argv[2]
json.dump({"spaces": [{
    "id": space_id, "name": "Demo", "username": "_agentspace_demo", "uid": 502,
    "state": "ready", "createdAt": "2026-09-18T11:00:00Z",
    "workspace": {"kind": "none"}, "sharedFolders": [],
    "permissions": {"screenRecording": False, "accessibility": False},
    "autoStartWorker": True,
}]}, open(f"{root}/Spaces/index.json", "w"))
PY

"$ROOT_DIR/.build/debug/agentspace-worker" --space-id "$SPACE_ID" --name Demo \
  --runtime-dir "$ROOT" --quiet >"$ROOT/worker.log" 2>&1 </dev/null &
WORKER_PID=$!
trap 'kill "$WORKER_PID" 2>/dev/null; wait "$WORKER_PID" 2>/dev/null' EXIT

for _ in $(seq 1 60); do
  [[ -S "$ROOT/Runtime/$SPACE_ID/worker.sock" ]] && break
  sleep 0.1
done
if [[ ! -S "$ROOT/Runtime/$SPACE_ID/worker.sock" ]]; then
  echo "worker did not come up; see $ROOT/worker.log" >&2
  exit 1
fi

echo
AGENTSPACE_BIN="$ROOT_DIR/.build/debug/agentspace" \
AGENTSPACE_ROOT="$ROOT" \
  node "$ROOT_DIR/scripts/mcp-smoke.mjs" node "$MCP_DIR/dist/index.js"
STATUS=$?

echo
if [[ $STATUS -eq 0 ]]; then
  echo "PASS — see docs/validation.md section 9."
else
  echo "FAIL (exit $STATUS)" >&2
fi
exit $STATUS
