#!/usr/bin/env bash
#
# plan(v3) §32: measure the frame engine instead of asserting about it.
#
#   scripts/frame-benchmark.sh [--space NAME] [--seconds N] [--interval N]
#                              [--mode auto|static|motion] [--trend]
#                              [--out FILE]
#
# Run it from your own logged-in desktop with AgentSpace open and a Desktop (or
# Fusion) window actually showing the agent: every number here describes a live
# stream, so with no stream open there is nothing to describe. The script says
# so and exits 3 — which is neither a pass nor a failure.
#
# It writes artifacts/frame-benchmark-<timestamp>.json: the raw samples, the
# derived rates, and one verdict per property §7/§9/§13/§14 ask about. §5 and
# §6 — is the CPU copy the hotspot, do we need a GPU publisher — are decided
# from the `derived` block, which is why this exists before either change.
#
# Exit codes:
#   0  measured, and every verdict held
#   1  measured, and at least one verdict failed
#   3  could not measure: the reason is printed, and it is never a pass.
#
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT_DIR="$(pwd)"

SECONDS_TOTAL=60
INTERVAL=2
MODE=auto
SPACE=""
OUT=""
TREND=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --space)    SPACE="$2"; shift 2 ;;
    --seconds)  SECONDS_TOTAL="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --mode)     MODE="$2"; shift 2 ;;
    --trend)    TREND=1; shift ;;
    --out)      OUT="$2"; shift 2 ;;
    -h|--help)  sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$MODE" in auto|static|motion) ;; *) echo "--mode must be auto, static or motion" >&2; exit 2 ;; esac

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
SAMPLES="$WORK/samples.tsv"
: > "$SAMPLES"

# A precondition that makes measuring pointless is reported as such; the exit
# code is 3 either way, so a caller cannot read "not measured" as "passed".
block() {
  echo "cannot measure: $1" >&2
  exit 3
}

# ---------------------------------------------------------------- binaries

# Prefer the installed app's own CLI: these numbers are supposed to describe
# what the user actually runs, and a development CLI can pair with an installed
# worker in ways the shipped pair never would.
CLI="${AGENTSPACE_CLI:-}"
if [[ -z "$CLI" ]]; then
  for candidate in "/Applications/AgentSpace.app/Contents/Helpers/agentspace" \
                   "$ROOT_DIR/.build/debug/agentspace" \
                   "$ROOT_DIR/.build/release/agentspace"; do
    [[ -x "$candidate" ]] && { CLI="$candidate"; break; }
  done
fi
[[ -n "$CLI" && -x "$CLI" ]] || block "no agentspace CLI found (set AGENTSPACE_CLI)"

APP_BUNDLE="/Applications/AgentSpace.app"
APP_VERSION="unknown"
if [[ -f "$APP_BUNDLE/Contents/Info.plist" ]]; then
  APP_VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || echo unknown)
fi
APP_PID=$(pgrep -f "AgentSpace.app/Contents/MacOS/AgentSpace" | head -1)
[[ -n "$APP_PID" ]] || block "AgentSpace.app is not running — open it and a Desktop window first"

# ---------------------------------------------------------------- the account

if [[ -z "$SPACE" ]]; then
  SPACE=$("$CLI" accounts --json 2>/dev/null | python3 -c '
import json, sys
try:
    accounts = json.load(sys.stdin).get("accounts") or []
except Exception:
    accounts = []
print(accounts[0]["name"] if len(accounts) == 1 else "")')
  [[ -n "$SPACE" ]] || block "there is not exactly one account to measure — pass --space NAME"
fi

STATUS=$("$CLI" status "$SPACE" --json 2>/dev/null || true)
WORKER_PID=$(printf '%s' "$STATUS" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("workerPid") or "")
except Exception:
    print("")')
[[ -n "$WORKER_PID" ]] || block "no worker is running for $SPACE"
WORKER_PATH=$(ps -o comm= -p "$WORKER_PID" | sed 's/^ *//')

# The installed worker is a bare binary kept under Worker/versions/<v>/, so its
# version comes from the path it was launched from, or from asking it directly.
WORKER_VERSION=""
case "$WORKER_PATH" in
  */versions/*) WORKER_VERSION=$(printf '%s' "$WORKER_PATH" | sed -n 's#.*/versions/\([^/]*\)/.*#\1#p') ;;
esac
if [[ -z "$WORKER_VERSION" && -x "$WORKER_PATH" ]]; then
  WORKER_VERSION=$("$WORKER_PATH" --version 2>/dev/null | head -1)
fi
[[ -n "$WORKER_VERSION" ]] || WORKER_VERSION="unknown"

# ---------------------------------------------------------------- the stream

FIRST_STATS=$("$CLI" preview "$SPACE" --stats --json 2>/dev/null || true)
printf '%s' "$FIRST_STATS" | head -c 1 | grep -q '{' || block "the worker answered nothing to frame.stats"
if printf '%s' "$FIRST_STATS" | grep -q 'unknown method'; then
  block "the installed worker (v$WORKER_VERSION) predates the frame engine — plan §14: install the app and press 「重新安装助手…」 so the app and the worker are the same release"
fi
OPEN_STREAMS=$(printf '%s' "$FIRST_STATS" | python3 -c '
import json, sys
print(json.load(sys.stdin).get("openStreams", 0))')
[[ "${OPEN_STREAMS:-0}" -gt 0 ]] || block "no frame stream is open for $SPACE — open the Desktop (or a Fusion window) in AgentSpace and measure again"

# ---------------------------------------------------------------- disk surface
#
# Per-process filesystem accounting (`fs_usage`, `ioalloccount`) needs root, so
# what this measures is the byte total of the directories a frame path could
# plausibly write into and this user can read. The paths it cannot read are
# reported as unreadable rather than silently counted as zero.
DISK_PATHS=("$HOME/Library/Caches/com.agentspace.AgentSpace"
            "$HOME/Library/Application Support/com.agentspace.AgentSpace"
            "/Library/Application Support/AgentSpace/Spaces"
            "/Library/Application Support/AgentSpace/Logs"
            "/Library/Application Support/AgentSpace/Runtime")
disk_snapshot() {
  local label="$1"
  : > "$WORK/disk.$label"
  for path in "${DISK_PATHS[@]}"; do
    if [[ -d "$path" && -r "$path" ]]; then
      printf '%s\t%s\n' "$path" "$(du -k -s "$path" 2>/dev/null | awk '{print $1}')" >> "$WORK/disk.$label"
    else
      printf '%s\tunreadable\n' "$path" >> "$WORK/disk.$label"
    fi
  done
}
disk_snapshot before

# ---------------------------------------------------------------- sampling

echo "== measuring $SPACE for ${SECONDS_TOTAL}s (app pid $APP_PID, worker pid $WORKER_PID, $OPEN_STREAMS frame stream(s) open) =="

CPU_TIME() { ps -o time= -p "$1" 2>/dev/null | tr -d ' '; }
RSS_KB()   { ps -o rss= -p "$1" 2>/dev/null | tr -d ' '; }
FD_COUNT() { lsof -p "$1" 2>/dev/null | tail -n +2 | wc -l | tr -d ' '; }

DEADLINE=$(( $(date +%s) + SECONDS_TOTAL ))
while :; do
  NOW=$(date +%s)
  (( NOW >= DEADLINE )) && break
  STATS=$("$CLI" preview "$SPACE" --stats --json 2>/dev/null | tr -d '\n\t')
  [[ -n "$STATS" ]] || STATS='{}'
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$NOW" "$(CPU_TIME "$APP_PID")" "$(RSS_KB "$APP_PID")" "$(FD_COUNT "$APP_PID")" \
    "$(CPU_TIME "$WORKER_PID")" "$(RSS_KB "$WORKER_PID")" "$(FD_COUNT "$WORKER_PID")" \
    "$STATS" >> "$SAMPLES"
  sleep "$INTERVAL"
done

disk_snapshot after

# The viewer's own numbers live in the app, and the app reports a stream when
# that stream ends. A reconnect inside the window therefore shows up here, which
# is the only way to see the viewer's half without adding a debug panel to the UI.
log show --style compact --start "$(date -r "$(( DEADLINE - SECONDS_TOTAL ))" '+%Y-%m-%d %H:%M:%S')" \
    --end "$(date -r "$DEADLINE" '+%Y-%m-%d %H:%M:%S')" \
    --predicate 'subsystem == "com.agentspace.AgentSpace" AND category == "FrameEngine"' 2>/dev/null \
  | grep -E "frame stream" > "$WORK/viewer.log" || true
[[ -f "$WORK/viewer.log" ]] || : > "$WORK/viewer.log"

[[ -n "$OUT" ]] || { mkdir -p "$ROOT_DIR/artifacts"; OUT="$ROOT_DIR/artifacts/frame-benchmark-$(date +%Y%m%d-%H%M%S).json"; }

python3 - "$SAMPLES" "$WORK/disk.before" "$WORK/disk.after" "$WORK/viewer.log" \
    "$OUT" "$SPACE" "$APP_PID" "$WORKER_PID" "$WORKER_PATH" "$APP_VERSION" "$WORKER_VERSION" \
    "$MODE" "$TREND" "$(( DEADLINE - SECONDS_TOTAL ))" "$DEADLINE" <<'PY'
import json, sys, time

(samples_path, disk_before, disk_after, viewer_log, out_path,
 space, app_pid, worker_pid, worker_path, app_version, worker_version,
 mode, trend, window_start, window_end) = sys.argv[1:16]


def cpu_seconds(text):
    """`ps -o time=` prints [[[HH:]MM:]SS.ss, so read it from the right."""
    parts = (text or "").strip().split(":")
    if not parts or parts == [""]:
        return None
    try:
        numbers = [float(part) for part in parts]
    except ValueError:
        return None
    if len(numbers) == 1:
        return numbers[0]
    if len(numbers) == 2:
        return numbers[0] * 60 + numbers[1]
    return numbers[0] * 3600 + numbers[1] * 60 + numbers[2]


def quantity(text):
    text = (text or "").strip()
    return int(text) if text.isdigit() else None


def streams_of(sample):
    return sample["frameStats"].get("streams") or []


samples = []
for line in open(samples_path):
    fields = line.rstrip("\n").split("\t")
    if len(fields) != 8:
        continue
    wall, app_cpu, app_rss, app_fds, worker_cpu, worker_rss, worker_fds, raw = fields
    try:
        stats = json.loads(raw)
    except ValueError:
        stats = {}
    samples.append({
        "t": int(wall),
        "app": {"cpuSeconds": cpu_seconds(app_cpu), "rssKB": quantity(app_rss), "fds": quantity(app_fds)},
        "worker": {"cpuSeconds": cpu_seconds(worker_cpu), "rssKB": quantity(worker_rss), "fds": quantity(worker_fds)},
        "frameStats": stats,
    })

if not samples:
    print("no samples were collected", file=sys.stderr)
    sys.exit(3)


def total(streams, field):
    return sum(int(stream.get(field, 0) or 0) for stream in streams)


COUNTERS = ["framesCaptured", "framesPublished", "framesDropped", "framesMerged", "fullFrames",
            "deltaFrames", "unacknowledgedDrops", "heartbeatsSent", "captureTerminations",
            "modeSwitchCount", "socketReconnects", "sharedBytes", "videoBytes",
            "videoEncoderActivations", "videoEncoderInvalidations"]
first, last = samples[0], samples[-1]
delta = {field: total(streams_of(last), field) - total(streams_of(first), field) for field in COUNTERS}
open_per_sample = [sample["frameStats"].get("openStreams", 0) for sample in samples]

# Rates over the window, not the worker's lifetime: a count divided by the
# seconds it took is the only number that survives a stream already running
# when the measurement started.
seconds = max(1, last["t"] - first["t"])
bytes_copied = delta["sharedBytes"] + delta["videoBytes"]
worker_cpu = (last["worker"]["cpuSeconds"] or 0) - (first["worker"]["cpuSeconds"] or 0)
app_cpu = (last["app"]["cpuSeconds"] or 0) - (first["app"]["cpuSeconds"] or 0)


def newest(field, default=0):
    """The highest value any stream reported in the last sample that had one."""
    for sample in reversed(samples):
        values = [stream.get(field) for stream in streams_of(sample)]
        values = [value for value in values if isinstance(value, (int, float))]
        if values:
            return max(values)
    return default


derived = {
    "windowSeconds": seconds,
    "capturedFPS": round(delta["framesCaptured"] / seconds, 3),
    "publishedFPS": round(delta["framesPublished"] / seconds, 3),
    "bytesCopied": bytes_copied,
    "megabytesCopied": round(bytes_copied / 1048576.0, 2),
    "bytesPerSecond": int(bytes_copied / seconds),
    "workerCPUSeconds": round(worker_cpu, 2),
    "appCPUSeconds": round(app_cpu, 2),
    "workerCPUpercentOfOneCore": round(100 * worker_cpu / seconds, 1),
    "appCPUpercentOfOneCore": round(100 * app_cpu / seconds, 1),
    # plan §5/§6: whether the CPU copy is the hotspot is only decidable against
    # these two, so they are computed even when nothing else is. Below one tick
    # of clock granularity a CPU delta says nothing, so both say nothing.
    "workerCPUSecondsMeasured": worker_cpu > 0.05,
    "megabytesCopiedPerWorkerCPUSecond": round((bytes_copied / 1048576.0) / worker_cpu, 1) if worker_cpu > 0.05 else None,
    "workerCPUmsPerPublishedFrame": round(1000 * worker_cpu / delta["framesPublished"], 2) if worker_cpu > 0.05 and delta["framesPublished"] else None,
    "captureToPublishP50ms": newest("captureToPublishP50"),
    "captureToPublishP95ms": newest("captureToPublishP95"),
    "dirtyRatio": newest("dirtyRatio"),
    "fullFrameRatio": newest("fullFrameRatio"),
    "pendingDamageArea": newest("pendingDamageArea"),
    "mappingBytesTotal": total(streams_of(last), "mappingBytes"),
    "frameModes": sorted({str(stream.get("frameMode")) for stream in streams_of(last)}),
    "encoderActive": any(bool(stream.get("encoderActive")) for stream in streams_of(last)),
    "app": last["app"], "worker": last["worker"],
}

fd_readings = [sample["app"]["fds"] for sample in samples if sample["app"]["fds"] is not None]
worker_fd_readings = [sample["worker"]["fds"] for sample in samples if sample["worker"]["fds"] is not None]


def disk_snapshot(path):
    snapshot = {}
    for line in open(path):
        name, value = line.rstrip("\n").split("\t")
        snapshot[name] = None if value == "unreadable" else int(value) * 1024
    return snapshot


before, after = disk_snapshot(disk_before), disk_snapshot(disk_after)
disk_deltas = {}
for name, value in before.items():
    other = after.get(name)
    disk_deltas[name] = None if (value is None or other is None) else other - value
disk = {
    "method": "block totals of the directories a frame path could plausibly write into and this user can read; per-process filesystem accounting needs root, so unreadable paths are named rather than counted as zero",
    "beforeBytes": before, "afterBytes": after, "deltaBytes": disk_deltas,
    "unreadable": sorted(name for name, value in before.items() if value is None),
}
writable_delta = sum(value for value in disk_deltas.values() if value is not None)

viewer = [line.strip() for line in open(viewer_log) if "frame stream" in line]


def verdict(name, state, evidence):
    return {"name": name, "verdict": state, "evidence": evidence}


verdicts = [
    verdict("stream_open_whole_window",
            "pass" if open_per_sample and min(open_per_sample) >= 1 else "fail",
            {"samples": len(samples), "minOpenStreams": min(open_per_sample) if open_per_sample else 0}),
    verdict("app_and_worker_same_release",
            "pass" if app_version == worker_version and app_version != "unknown" else "fail",
            {"app": app_version, "worker": worker_version, "workerPath": worker_path,
             "note": "plan §14: numbers from a mismatched pair describe neither release"}),
]

if mode == "static":
    verdicts.append(verdict("static_desktop_is_quiet",
                            "pass" if delta["framesPublished"] == 0 and bytes_copied == 0 else "fail",
                            {"framesPublished": delta["framesPublished"], "bytesCopied": bytes_copied,
                             "heartbeatsSent": delta["heartbeatsSent"],
                             "note": "plan §13: a still desktop may cost heartbeats, never frames"}))
    verdicts.append(verdict("static_desktop_keeps_the_encoder_off",
                            "pass" if delta["videoEncoderActivations"] == 0 and not derived["encoderActive"] else "fail",
                            {"activations": delta["videoEncoderActivations"],
                             "invalidations": delta["videoEncoderInvalidations"],
                             "encoderActive": derived["encoderActive"], "frameModes": derived["frameModes"]}))
elif delta["framesPublished"] == 0:
    verdicts.append(verdict("frames_flowed", "pending",
                            {"framesPublished": 0, "dirtyRatio": derived["dirtyRatio"],
                             "note": "nothing changed on the surface; measure with --mode static to check the quiet case instead"}))
else:
    verdicts.append(verdict("frames_flowed", "pass",
                            {"framesPublished": delta["framesPublished"], "publishedFPS": derived["publishedFPS"],
                             "megabytesCopied": derived["megabytesCopied"]}))

if delta["framesCaptured"] or delta["framesPublished"]:
    verdicts.append(verdict("back_pressure_healthy",
                            "pass" if delta["framesDropped"] + delta["unacknowledgedDrops"] == 0 else "fail",
                            {"framesDropped": delta["framesDropped"], "framesMerged": delta["framesMerged"],
                             "unacknowledgedDrops": delta["unacknowledgedDrops"],
                             "framesCaptured": delta["framesCaptured"]}))
verdicts += [
    verdict("no_reconnects_or_terminations",
            "pass" if delta["socketReconnects"] == 0 and delta["captureTerminations"] == 0 else "fail",
            {"socketReconnects": delta["socketReconnects"], "captureTerminations": delta["captureTerminations"],
             "viewerSummaryLines": len(viewer)}),
    verdict("timestamps_reach_the_stats",
            "pass" if derived["captureToPublishP95ms"] > 0 or delta["framesPublished"] == 0 else "fail",
            {"captureToPublishP50ms": derived["captureToPublishP50ms"],
             "captureToPublishP95ms": derived["captureToPublishP95ms"],
             "note": "plan §9: a zero here while frames are flowing means a timestamp never made it onto the wire"}),
    verdict("shared_memory_within_budget",
            "pass" if derived["mappingBytesTotal"] <= 256 * 1048576 else "fail",
            {"mappingBytesTotal": derived["mappingBytesTotal"], "budgetBytes": 256 * 1048576}),
    verdict("frame_path_wrote_nothing_visible",
            "pass" if writable_delta == 0 else "fail",
            {"deltaBytes": disk_deltas, "unreadable": disk["unreadable"],
             "note": "plan §13: the frame path is shared memory plus a socket, so anything that appeared on disk is a surprise"}),
    verdict("app_descriptors_stable",
            "pass" if len(fd_readings) > 1 and max(fd_readings) - min(fd_readings) <= 2 else "pending",
            {"min": min(fd_readings) if fd_readings else None, "max": max(fd_readings) if fd_readings else None}),
    verdict("worker_descriptors_countable_by_this_user",
            "pass" if worker_fd_readings else "pending",
            {"readings": len(worker_fd_readings),
             "note": "the worker runs as the agent account, so counting its descriptors needs root"}),
    verdict("memcpy_is_the_hotspot",
            "measured" if derived["megabytesCopiedPerWorkerCPUSecond"] is not None else "pending",
            {"megabytesCopiedPerWorkerCPUSecond": derived["megabytesCopiedPerWorkerCPUSecond"],
             "workerCPUmsPerPublishedFrame": derived["workerCPUmsPerPublishedFrame"],
             "workerCPUpercentOfOneCore": derived["workerCPUpercentOfOneCore"],
             "note": "plan §5/§6: a GPU publisher is only justified once these numbers say the copy is the cost"}),
]

trend_rows = []
if int(trend) and len(samples) > 3:
    bucket = max(1, len(samples) // 10)
    for index in range(0, len(samples) - 1, bucket):
        span = samples[index:index + bucket + 1]
        elapsed = max(1, span[-1]["t"] - span[0]["t"])
        trend_rows.append({
            "at": time.strftime("%H:%M:%S", time.localtime(span[-1]["t"])),
            "publishedFPS": round((total(streams_of(span[-1]), "framesPublished")
                                   - total(streams_of(span[0]), "framesPublished")) / elapsed, 2),
            "workerCPUpercent": round(100 * ((span[-1]["worker"]["cpuSeconds"] or 0)
                                             - (span[0]["worker"]["cpuSeconds"] or 0)) / elapsed, 1),
            "appRSSKB": span[-1]["app"]["rssKB"], "workerRSSKB": span[-1]["worker"]["rssKB"],
            "appFDs": span[-1]["app"]["fds"],
            "captureToPublishP95ms": next((stream.get("captureToPublishP95") for stream in
                                           reversed(streams_of(span[-1])) if stream.get("captureToPublishP95")), 0),
        })

artifact = {
    "schema": 1,
    "measuredAt": {"start": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(int(window_start))),
                   "end": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(int(window_end)))},
    "account": space, "mode": mode,
    "versions": {"app": app_version, "worker": worker_version, "workerPath": worker_path},
    "pids": {"app": int(app_pid), "worker": int(worker_pid)},
    "derived": derived,
    "countersDeltaOverWindow": delta,
    "diskWrites": disk,
    "viewerSummaryLines": viewer,
    "samples": samples,
    "trend": trend_rows,
    "verdicts": verdicts,
}
with open(out_path, "w") as handle:
    json.dump(artifact, handle, indent=2, sort_keys=True)
    handle.write("\n")

print()
print(f"  account            {space}  (mode {mode})")
print(f"  versions           app {app_version} / worker {worker_version}")
print(f"  window             {seconds}s over {len(samples)} samples")
print(f"  published          {delta['framesPublished']} frames, {derived['publishedFPS']} fps, "
      f"{derived['megabytesCopied']} MB copied")
print(f"  cpu                worker {derived['workerCPUpercentOfOneCore']}% of a core, "
      f"app {derived['appCPUpercentOfOneCore']}%")
print(f"  memory             app {derived['app']['rssKB']} KB rss, {derived['mappingBytesTotal']} bytes mapped for frames")
print(f"  latency p50/p95    capture→publish {derived['captureToPublishP50ms']} / {derived['captureToPublishP95ms']} ms")
if derived["megabytesCopiedPerWorkerCPUSecond"] is not None:
    print(f"  copy cost          {derived['megabytesCopiedPerWorkerCPUSecond']} MB per worker CPU-second, "
          f"{derived['workerCPUmsPerPublishedFrame']} ms of CPU per published frame")
print(f"  viewer lines       {len(viewer)} frame-stream summary line(s) in the log")
for line in viewer[:8]:
    print(f"    …{line[-150:]}")
print()
for row in trend_rows:
    print(f"  {row['at']}  {row['publishedFPS']} fps  worker {row['workerCPUpercent']}%  "
          f"app {row['appRSSKB']} KB  fds {row['appFDs']}  p95 {row['captureToPublishP95ms']} ms")
print()
for entry in verdicts:
    print(f"  {entry['verdict'].upper():9} {entry['name']}")
    if entry["verdict"] in ("fail", "pending"):
        print(f"            {json.dumps(entry['evidence'], sort_keys=True)[:240]}")
failed = [entry["name"] for entry in verdicts if entry["verdict"] == "fail"]
print(f"\nwrote {out_path}")
if failed:
    print(f"failed verdicts: {', '.join(failed)}")
sys.exit(1 if failed else 0)
PY
