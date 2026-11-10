#!/bin/sh
# Checks that a released Stackbar runs plugins on a Mac with neither Xcode nor
# the Command Line Tools. It hides the developer tools (DEVELOPER_DIR pointing
# nowhere, so xcode-select and the swift shim both fail), then:
#   1. renders every plugin the app carries (examples and first-party bundles)
#      from the helpers prebuilt into the app;
#   2. installs plugins from the official store (all but withdrawn ones by
#      default) and
#      renders each, from the store's signed prebuilt helpers.
# macOS only. The No toolchain workflow runs it on a GitHub macOS runner.
#
#   scripts/test-no-toolchain.sh <version> [plugin id...]
#
# STACKBARCTL is the stackbarctl used for store installs; by default the
# release's own. A stackbarctl from 0.20.1 or later fetches the store's helper
# on install as the app does.
set -eu
[ "$(uname)" = Darwin ] || { echo "test-no-toolchain: run this on a Mac" >&2; exit 1; }
VERSION=$1
shift
INDEX=$(python3 "$(dirname "$0")/distribution.py" get store.url)
REPO=${GITHUB_REPOSITORY:-navbytes/stackbar}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

curl -fsSL -o "$WORK/Stackbar.zip" "https://github.com/$REPO/releases/download/v$VERSION/Stackbar-$VERSION.zip"
ditto -x -k "$WORK/Stackbar.zip" "$WORK"
APP="$WORK/Stackbar.app"
spctl --assess --type execute -vv "$APP"
RELEASE_CTL="$APP/Contents/MacOS/stackbarctl"
CTL=${STACKBARCTL:-$RELEASE_CTL}

export STACKBAR_PACKAGE="$APP/Contents/Resources/StackbarKit"
export STACKBAR_HOME="$WORK/home"
export DEVELOPER_DIR="$WORK/no-developer-tools"
# xcode-select -p echoes DEVELOPER_DIR even when it doesn't exist; what
# matters (and what Stackbar checks) is that no developer directory is there.
developer=$(xcode-select -p 2>/dev/null || true)
if [ -n "$developer" ] && [ -d "$developer" ]; then echo "the developer tools are still visible at $developer" >&2; exit 1; fi
if swift --version > /dev/null 2>&1; then echo "swift still runs" >&2; exit 1; fi
echo "== no developer tools: no developer directory, and swift fails"
"$RELEASE_CTL" doctor || true

failures=0
mkdir -p "$WORK/carried"
python3 - "$STACKBAR_PACKAGE/Bundles" "$WORK/carried" <<'PY'
import json, os, sys
for name in sorted(os.listdir(sys.argv[1])) if os.path.isdir(sys.argv[1]) else []:
    if name.endswith(".stackbarplugin"):
        bundle = json.load(open(os.path.join(sys.argv[1], name)))
        with open(os.path.join(sys.argv[2], bundle["manifest"]["id"] + ".swift"), "w") as out:
            out.write(bundle["source"])
PY
cp "$STACKBAR_PACKAGE"/Examples/*.swift "$WORK/carried/"
echo "== plugins the app carries"
for plugin in "$WORK"/carried/*.swift; do
    if "$RELEASE_CTL" render "$plugin" > "$WORK/out.txt" 2>&1; then
        echo "ok   $(basename "$plugin")"
    else
        echo "FAIL $(basename "$plugin")"; sed 's/^/     /' "$WORK/out.txt" | tail -5; failures=$((failures + 1))
    fi
done

if [ $# -eq 0 ]; then
    set -- $(curl -fsSL "$INDEX" | python3 -c 'import json,sys; i=json.load(sys.stdin); gone={r["id"] for r in i.get("revoked") or [] if not r.get("versions")}; print(" ".join(sorted({p["id"] for p in i["plugins"]} - gone)))')
fi
echo "== store plugins ($#)"
for id in "$@"; do
    if "$CTL" install --index "$INDEX" "$id" > "$WORK/out.txt" 2>&1 \
        && file=$(python3 -c 'import json,sys; print(next(r["file"] for r in json.load(open(sys.argv[1])) if r["id"] == sys.argv[2]))' "$STACKBAR_HOME/installed.json" "$id") \
        && "$CTL" render "$file" >> "$WORK/out.txt" 2>&1; then
        how=$(grep -o "using the store's prebuilt helper.*" "$WORK/out.txt" || echo "already on this Mac")
        echo "ok   $id: $how"
    else
        echo "FAIL $id"; sed 's/^/     /' "$WORK/out.txt" | tail -5; failures=$((failures + 1))
    fi
done

[ "$failures" -eq 0 ] || { echo "$failures failed"; exit 1; }
echo "all plugins ran without developer tools"
