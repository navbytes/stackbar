#!/bin/sh
# Drives the built app through a new user's first minute (Sources/Stackbar/
# AppCheck.swift): Welcome, the starter set, the palette's golden queries and
# speed, Return, ⌘K, every Settings page and the Store, with light and dark
# screenshots. With --upgrade it also opens a home the latest release left
# behind, as an update does. Results and screenshots go to build/app-check/.
#
#   scripts/app-check.sh              a fresh Mac
#   scripts/app-check.sh --upgrade    and an update from the latest release
#
# It changes this user's io.navbytes.stackbar defaults, so run it on a CI
# runner or a spare account, not the Mac you use Stackbar on.
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "app-check: run this on a Mac" >&2; exit 1; }
UPGRADE=0
for a in "$@"; do case $a in --upgrade) UPGRADE=1 ;; *) echo "usage: $0 [--upgrade]" >&2; exit 2 ;; esac; done

OUT="$PWD/build/app-check"
WORK=$(mktemp -d -t stackbar-app-check)
touch "$WORK/.start"
APP=build/Stackbar.app
DEFAULTS=io.navbytes.stackbar
rm -rf "$OUT" && mkdir -p "$OUT"
[ -d "$APP" ] || scripts/bundle.sh

# run <seconds> <name> <command…>: runs an app until it quits on its own, or
# kills it after <seconds>. Its output goes to $OUT/<name>.log, and how it
# ended to the console. Pass the app's variables through `env`: assignments
# in front of a shell function outlive the call in sh, so one run's
# STACKBAR_BENCHMARK would reach the next.
run() {
    seconds=$1 name=$2
    shift 2
    "$@" > "$OUT/$name.log" 2>&1 &
    pid=$!
    ( sleep "$seconds"; kill "$pid" 2>/dev/null ) &
    watchdog=$!
    status=0
    wait "$pid" || status=$?
    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true
    echo "app-check: $name ended with status $status"
}

# 1. A fresh Mac: no defaults, an empty home.
defaults delete "$DEFAULTS" 2>/dev/null || true
run 600 fresh env STACKBAR_HOME="$WORK/fresh" STACKBAR_APPCHECK="$OUT" "$APP/Contents/MacOS/Stackbar"

# 2. An update: the latest release runs first (its benchmark mode installs the
# core plugins, approves them and quits), then this build opens its home.
if [ "$UPGRADE" = 1 ]; then
    mkdir -p "$WORK/old"
    if gh release download --repo "${GITHUB_REPOSITORY:-navbytes/stackbar}" --pattern 'Stackbar-*.zip' --dir "$WORK/old" 2>"$WORK/old/download.log"; then
        ditto -x -k "$WORK"/old/Stackbar-*.zip "$WORK/old"
        xattr -dr com.apple.quarantine "$WORK/old/Stackbar.app" 2>/dev/null || true
        OLD=$(plutil -extract CFBundleShortVersionString raw "$WORK/old/Stackbar.app/Contents/Info.plist")
        echo "app-check: updating from $OLD"
        run 300 old-release env STACKBAR_HOME="$WORK/upgrade" STACKBAR_BENCHMARK="$WORK/old/benchmark.json" "$WORK/old/Stackbar.app/Contents/MacOS/Stackbar"
        PLUGINS=$(python3 -c 'import json,sys; print(",".join(json.load(open(sys.argv[1]))["plugins"]))' "$WORK/old/benchmark.json" 2>/dev/null || true)
        # Someone who updates has seen Welcome already.
        defaults write "$DEFAULTS" welcomeSeen -bool true
        run 600 upgrade env STACKBAR_HOME="$WORK/upgrade" STACKBAR_APPCHECK="$OUT" STACKBAR_APPCHECK_MODE=upgrade \
            STACKBAR_APPCHECK_PLUGINS="$PLUGINS" "$APP/Contents/MacOS/Stackbar"
    else
        echo "app-check: couldn't download the latest release:" >&2
        cat "$WORK/old/download.log" >&2
        exit 1
    fi
fi

# A crash leaves a report; keep it with the results.
find "$HOME/Library/Logs/DiagnosticReports" -name 'Stackbar*' -newer "$WORK/.start" -exec cp {} "$OUT/" \; 2>/dev/null || true

python3 - "$OUT" "$UPGRADE" <<'PY'
import json, os, sys
out, upgrade = sys.argv[1], sys.argv[2] == "1"
files = ["results.json"] + (["upgrade.json"] if upgrade else [])
ok = True
lines = []
for name in files:
    path = os.path.join(out, name)
    if not os.path.exists(path):
        lines.append(f"**{name} was not written: the app quit or hung before the end.**\n")
        ok = False
        continue
    report = json.load(open(path))
    title = "Update from the latest release" if report["mode"] == "upgrade" else "A fresh Mac"
    lines.append(f"### {title}: Stackbar {report['version']} on {report['macOS']}\n")
    lines.append("| | Check | Detail |")
    lines.append("|---|---|---|")
    for check in report["checks"]:
        mark = "✅" if check["passed"] else "❌"
        lines.append(f"| {mark} | {check['name']} | {check['detail'].replace('|', '/')} |")
    lines.append("")
    ok = ok and report["passed"]
lines.append("Screenshots are in the app-check artifact.")
text = "\n".join(lines)
print(text)
summary = os.environ.get("GITHUB_STEP_SUMMARY")
if summary:
    open(summary, "a").write(text + "\n")
sys.exit(0 if ok else 1)
PY
