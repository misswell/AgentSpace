#!/usr/bin/env bash
#
# plan(v3) §32: the hour-scale half of scripts/frame-benchmark.sh.
#
#   scripts/frame-soak.sh [--space NAME] [--hours N] [--minutes N]
#                         [--interval N] [--out FILE]
#
# Same sampler, longer look. A benchmark answers "how fast is one frame"; a soak
# answers the only question a long-lived stream can fail — does anything grow?
# Descriptors, resident memory, the shared mapping, the latency percentiles, and
# how often the socket has to be rebuilt. It samples every 10 seconds instead of
# every 2 so an hour of it is a few hundred RPCs rather than a thousand.
#
# Run it while the Desktop window stays open and the agent's desktop does what
# it normally does. Leaving a Space open with nothing happening is a different
# test (that one is `frame-benchmark.sh --mode static`).
#
# Exit codes are the benchmark's, plus one: a trend the benchmark could not see
# (memory or descriptors growing across the hour) fails here.
#
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT_DIR="$(pwd)"

HOURS=1
MINUTES=""
INTERVAL=10
SPACE=""
OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --space)   SPACE="$2"; shift 2 ;;
    --hours)   HOURS="$2"; shift 2 ;;
    --minutes) MINUTES="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --out)     OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# --minutes exists for the same reason a short run of any long measurement does:
# it is the only way to see the trend arithmetic work without spending an hour.
if [[ -n "$MINUTES" ]]; then
  SECONDS_TOTAL=$(( 60 * MINUTES ))
else
  SECONDS_TOTAL=$(( 3600 * HOURS ))
fi
[[ -n "$OUT" ]] || { mkdir -p "$ROOT_DIR/artifacts"; OUT="$ROOT_DIR/artifacts/frame-soak-$(date +%Y%m%d-%H%M%S).json"; }

echo "== soaking for ${SECONDS_TOTAL}s; the trend is bucketed into ~10 rows in $OUT =="
ARGS=(--seconds "$SECONDS_TOTAL" --interval "$INTERVAL" --trend --out "$OUT")
[[ -n "$SPACE" ]] && ARGS=(--space "$SPACE" "${ARGS[@]}")
scripts/frame-benchmark.sh "${ARGS[@]}"
STATUS=$?
[[ $STATUS -eq 0 || $STATUS -eq 1 ]] || exit $STATUS   # 3 means nothing was measured

python3 - "$OUT" "$SECONDS_TOTAL" "$STATUS" <<'PY'
import json, sys

path, seconds, benchmark_status = sys.argv[1], max(1, int(sys.argv[2])), int(sys.argv[3])
hours = seconds / 3600.0
with open(path) as handle:
    artifact = json.load(handle)

rows = artifact.get("trend") or []
samples = artifact.get("samples") or []


def series(pick):
    return [value for value in (pick(sample) for sample in samples) if isinstance(value, (int, float))]


rss = series(lambda s: (s.get("app") or {}).get("rssKB"))
worker_rss = series(lambda s: (s.get("worker") or {}).get("rssKB"))
fds = series(lambda s: (s.get("app") or {}).get("fds"))


def third(values):
    size = max(1, len(values) // 3)
    return (sum(values[:size]) / size, sum(values[-size:]) / size)


drift = {}
for name, values in (("appRSSKB", rss), ("workerRSSKB", worker_rss), ("appFDs", fds)):
    if len(values) < 6:
        drift[name] = {"verdict": "pending", "note": "not enough samples"}
        continue
    start, end = third(values)
    growth = end - start
    # 20 MB of resident memory or five descriptors of growth over an hour is the
    # line; below it, AppKit and the window server account for the wobble.
    limit = 20480 if name.endswith("RSSKB") else 5
    drift[name] = {"firstThird": round(start, 1), "lastThird": round(end, 1),
                   "growth": round(growth, 1), "allowed": limit,
                   "verdict": "pass" if growth <= limit else "fail"}

# A stream that has to be rebuilt every few minutes is not a soak survivor,
# however flat its memory looks.
delta = artifact.get("countersDeltaOverWindow") or {}
per_hour = {key: round(delta.get(key, 0) / hours, 2)
            for key in ("socketReconnects", "captureTerminations", "unacknowledgedDrops")}
per_hour["modeSwitches"] = round(delta.get("modeSwitchCount", 0) / hours, 2)
stability = {"verdict": "pass" if per_hour["socketReconnects"] <= 2 and per_hour["captureTerminations"] <= 2 else "fail",
             "perHour": per_hour, "windowHours": round(hours, 4)}

artifact["soak"] = {"drift": drift, "stability": stability, "trendRows": len(rows)}
with open(path, "w") as handle:
    json.dump(artifact, handle, indent=2, sort_keys=True)
    handle.write("\n")

print()
print("== soak ==")
failed = []
for name, entry in drift.items():
    body = json.dumps({key: value for key, value in entry.items() if key != "verdict"}, sort_keys=True)
    print(f"  {entry.get('verdict', '?'):8} {name}: {body[:150]}")
    if entry.get("verdict") == "fail":
        failed.append(name)
print(f"  {stability['verdict']:8} stream stability: {json.dumps(per_hour, sort_keys=True)}")
if stability["verdict"] == "fail":
    failed.append("stability")
print(f"\nupdated {path}")
if failed:
    print(f"failed: {', '.join(failed)}")
sys.exit(1 if failed or benchmark_status else 0)
PY
