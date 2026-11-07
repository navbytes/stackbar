#!/bin/bash
# Idle-cost probe for Stackbar with the store's plugins installed. macOS only.
# Builds nothing: expects build/Stackbar.app from scripts/bundle.sh.
#   scripts/perf-probe/run.sh [warmup s] [window s]
set -u
cd "$(dirname "$0")/../.."
WARM=${1:-60}; WINDOW=${2:-300}
APP="$PWD/build/Stackbar.app"
OUT="$PWD/build/perf-probe"; mkdir -p "$OUT"
export STACKBAR_HOME="$(mktemp -d)/home"
export STACKBAR_PACKAGE="$APP/Contents/Resources/StackbarKit"
CTL="$APP/Contents/MacOS/stackbarctl"
INDEX=https://navbytes.github.io/stackbar-plugins/index.json
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}

echo "== install store plugins"
IDS=$(curl -fsSL "$INDEX" | python3 -c 'import json,sys; i=json.load(sys.stdin); gone={r["id"] for r in i.get("revoked") or [] if not r.get("versions")}; print(" ".join(sorted({p["id"] for p in i["plugins"]} - gone)))')
ok=(); bad=()
for id in $IDS; do
  if "$CTL" install --index "$INDEX" "$id" > "$OUT/install-$id.txt" 2>&1; then ok+=("$id"); else bad+=("$id"); fi
done
echo "installed ${#ok[@]}: ${ok[*]}"; echo "failed ${#bad[@]}: ${bad[*]:-}"
"$CTL" doctor > "$OUT/doctor.txt" 2>&1 || true

echo "== eslogger / fs_usage (best effort)"
( sudo eslogger exec > "$OUT/eslogger-exec.jsonl" 2> "$OUT/eslogger.err" & ) 2>/dev/null
( sudo fs_usage -w -f exec > "$OUT/fs_usage-exec.txt" 2> "$OUT/fs_usage.err" & ) 2>/dev/null

echo "== launch"
"$APP/Contents/MacOS/Stackbar" > "$OUT/app.log" 2>&1 &
PID=$!
sleep 5
kill -0 $PID 2>/dev/null || { echo "::error::app exited"; cat "$OUT/app.log"; exit 1; }

# Sample the powermetrics and `sample` probes inside the window's last part.
( sleep $((WARM + WINDOW - 40));
  sample $PID 3 -file "$OUT/sample-main.txt" > /dev/null 2>&1
  sudo powermetrics --samplers tasks --show-process-wakeups -n 3 -i 5000 > "$OUT/powermetrics.txt" 2> "$OUT/powermetrics.err"
) &
PROBES=$!

footprint $PID > "$OUT/footprint-start.txt" 2>&1 || true
python3 scripts/perf-probe/sample.py $PID "$WARM" "$WINDOW" "$OUT" || true
wait $PROBES 2>/dev/null
footprint $PID > "$OUT/footprint-end.txt" 2>&1 || true
ps -axo pid,ppid,rss,cputime,command | grep -i stackbar | grep -v grep > "$OUT/ps-end.txt" || true
sudo pkill eslogger 2>/dev/null; sudo pkill fs_usage 2>/dev/null
kill $PID 2>/dev/null; sleep 1

{
  echo "## Stackbar idle probe"
  echo
  echo "Store plugins installed: ${#ok[@]} (failed: ${bad[*]:-none}); warm-up ${WARM} s, window ${WINDOW} s, no UI open."
  echo
  cat "$OUT/summary.md" 2>/dev/null
  echo
  echo "### fs_usage exec events (whole run), by process"
  echo
  if [ -s "$OUT/fs_usage-exec.txt" ]; then
    echo '```'; grep -v '^$' "$OUT/fs_usage-exec.txt" | awk '{print $NF}' | sed 's/\.[0-9]*$//' | sort | uniq -c | sort -rn | head -15; echo '```'
  else echo "no data: $(head -c 200 "$OUT/fs_usage.err")"; fi
  echo
  echo "### eslogger exec"
  echo
  if [ -s "$OUT/eslogger-exec.jsonl" ]; then
    echo '```'; python3 - "$OUT/eslogger-exec.jsonl" <<'PY'
import json, sys, collections, os
c = collections.Counter()
for l in open(sys.argv[1]):
    try: e = json.loads(l)
    except Exception: continue
    ex = e["event"]["exec"]["target"]["executable"]["path"]
    pp = e["process"]["executable"]["path"]
    c[(os.path.basename(pp), os.path.basename(ex))] += 1
print("total", sum(c.values()))
for (p, t), k in c.most_common(20): print(k, p, "->", t)
PY
    echo '```'
  else echo "no data: $(head -c 200 "$OUT/eslogger.err")"; fi
  echo
  echo "### powermetrics (last sample, top by wakeups)"
  echo
  if [ -s "$OUT/powermetrics.txt" ]; then
    echo '```'; grep -iE "^(Name|Stackbar|stackbar|.*helper|.*\.stackbar)" "$OUT/powermetrics.txt" | head -40; echo '```'
  else echo "no data: $(head -c 200 "$OUT/powermetrics.err")"; fi
  echo
  echo "### main thread sample (top of call graph)"
  echo
  echo '```'; sed -n '1,60p' "$OUT/sample-main.txt" 2>/dev/null | cut -c1-160; echo '```'
  echo
  echo "### footprint"
  echo '```'; grep -iE "footprint|Stackbar" "$OUT/footprint-start.txt" | head -4; echo ---; grep -iE "footprint|Stackbar" "$OUT/footprint-end.txt" | head -4; echo '```'
} | tee "$OUT/report.md" >> "$SUMMARY"
