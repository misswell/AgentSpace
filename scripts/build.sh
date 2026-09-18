#!/usr/bin/env bash
#
# Build every AgentSpace artifact and sign the worker.
#
#   scripts/build.sh [debug|release]
#
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIGURATION="${1:-debug}"

echo "== swift build ($CONFIGURATION) =="
swift build -c "$CONFIGURATION" --product agentspace-worker --product agentspace --product AgentSpaceApp

BIN_DIR=".build/$CONFIGURATION"
WORKER="$BIN_DIR/agentspace-worker"
CLI="$BIN_DIR/agentspace"

for binary in "$WORKER" "$CLI"; do
  [[ -x "$binary" ]] || { echo "expected $binary to exist" >&2; exit 1; }
done

# Code signing matters more than it looks.
#
# A TCC grant (Accessibility, Screen Recording) is keyed to the binary's *path
# and code requirement*. An unsigned binary gets an ad-hoc signature that changes
# on every rebuild, so every rebuild silently loses both grants and the worker
# starts failing with ACCESSIBILITY_DENIED for no visible reason. Signing with a
# stable Developer ID makes grants survive rebuilds. Ad-hoc (`-`) is the fallback
# for development, where shifting grants are expected and documented.
IDENTITY="${AGENTSPACE_CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
    IDENTITY="$(security find-identity -v -p codesigning \
      | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')"
    echo "== signing with Developer ID: $IDENTITY =="
  else
    IDENTITY="-"
    echo "== no Developer ID found; ad-hoc signing (TCC grants will not survive rebuilds) =="
  fi
fi

# The worker's identifier must be stable across builds for the same reason.
codesign --force --options runtime --timestamp=none \
  --identifier "com.agentspace.AgentSpace.Worker" \
  --sign "$IDENTITY" "$WORKER" 2>&1 | sed 's/^/   /' || {
    echo "   ad-hoc signing failed; retrying without --options runtime"
    codesign --force --identifier "com.agentspace.AgentSpace.Worker" \
      --sign - "$WORKER" 2>&1 | sed 's/^/   /'
  }

codesign --force --timestamp=none \
  --identifier "com.agentspace.AgentSpace.CLI" \
  --sign "$IDENTITY" "$CLI" 2>&1 | sed 's/^/   /' || true

# Sanity: each binary must actually be itself.
#
# The failure this catches is not hypothetical. A GUI product named `AgentSpace`
# and a CLI product named `agentspace` share one path in `.build/debug` on a
# case-insensitive filesystem, so one overwrote the other; `agentspace --version`
# then launched a SwiftUI event loop and hung forever, with no error anywhere.
# Comparing sizes and requiring the expected output is a two-second check that
# turns a silent, baffling hang into a build failure.
echo "== sanity-checking the binaries =="
cli_version="$("$CLI" --version 2>/dev/null | head -1)"
if [[ "$cli_version" != agentspace* ]]; then
  echo "   $CLI did not report a version (got: '${cli_version:-<nothing>}')" >&2
  echo "   this usually means a product name collision overwrote it" >&2
  exit 1
fi
echo "   agentspace       $cli_version"

worker_check="$("$WORKER" --check 2>&1 | head -1)"
if [[ "$worker_check" != *'"ok"'* ]]; then
  echo "   $WORKER --check did not return its readiness JSON" >&2
  exit 1
fi
echo "   agentspace-worker reports readiness"

if [[ "$(shasum -a 256 < "$CLI" | cut -d' ' -f1)" == "$(shasum -a 256 < "$WORKER" | cut -d' ' -f1)" ]]; then
  echo "   the CLI and the worker are the same file" >&2
  exit 1
fi
echo "   the CLI and the worker are distinct binaries"

GUI=".build/$CONFIGURATION/AgentSpaceApp"
if [[ -x "$GUI" ]]; then
  if [[ "$(shasum -a 256 < "$GUI" | cut -d' ' -f1)" == "$(shasum -a 256 < "$CLI" | cut -d' ' -f1)" ]]; then
    echo "   the GUI binary and the CLI are the same file" >&2
    exit 1
  fi
  echo "   the GUI and the CLI are distinct binaries"
fi

echo
echo "== built =="
echo "   $WORKER"
echo "   $CLI"
echo
echo "next:  scripts/test.sh          run the suite"
echo "       scripts/demo.sh          end-to-end run without a second user"
echo "       $WORKER --check          readiness report"
