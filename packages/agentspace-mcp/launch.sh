#!/bin/bash
# Launch only the service next to this script. stdout belongs to MCP.
set -euo pipefail
MCP_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ ! -f "$MCP_DIR/dist/index.js" ]]; then
  echo "AgentSpace MCP is incomplete: missing dist/index.js. Reinstall the app or build the MCP package." >&2
  exit 1
fi

usable_node() {
  local candidate="$1" major
  [[ -x "$candidate" ]] || return 1
  major="$("$candidate" -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null)" || return 1
  [[ "$major" =~ ^[0-9]+$ ]] && [[ "$major" -ge 18 ]]
}

if [[ -n "${AGENTSPACE_MCP_NODE:-}" ]]; then
  if ! usable_node "$AGENTSPACE_MCP_NODE"; then
    echo "AGENTSPACE_MCP_NODE must point to an executable Node.js 18 or newer." >&2
    exit 1
  fi
  exec "$AGENTSPACE_MCP_NODE" "$MCP_DIR/dist/index.js" "$@"
fi

shopt -s nullglob
CANDIDATES=("$(command -v node || true)" /opt/homebrew/bin/node /usr/local/bin/node
            "${HOME}/.volta/bin/node" "${HOME}"/.volta/tools/image/node/*/bin/node)
for candidate in "${CANDIDATES[@]}"; do
  if usable_node "$candidate"; then
    exec "$candidate" "$MCP_DIR/dist/index.js" "$@"
  fi
done
echo "AgentSpace MCP needs Node.js 18 or newer (22 recommended). Install Node or set AGENTSPACE_MCP_NODE to its absolute executable path, then restart the MCP client." >&2
exit 1
