#!/bin/sh
# Builds the signed Stackbar.app with its widget from this checkout and installs
# it on this Mac:
#   - /Applications/Stackbar.app (replacing a running copy)
#   - stackbarctl linked into ~/.local/bin
#   - the first-party plugins' signed bundles, which Stackbar installs from
#     the store on first run (scripts/embed-stackbarkit.sh)
#
# Needs Xcode 26, xcodegen (brew install xcodegen) and an Xcode account for
# the team in project.yml. The first run on a Mac may need
# STACKBAR_ALLOW_PROVISIONING=1 to let Xcode register the App IDs.
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "install: run this on a Mac" >&2; exit 1; }
command -v xcodegen >/dev/null || { echo "install: brew install xcodegen" >&2; exit 1; }

DERIVED=build/xcode
DEST=${STACKBAR_INSTALL_DIR:-/Applications}
PROVISIONING=""
[ -n "${STACKBAR_ALLOW_PROVISIONING:-}" ] && PROVISIONING=-allowProvisioningUpdates

xcodegen generate --quiet
# shellcheck disable=SC2086
xcodebuild -quiet -project Stackbar.xcodeproj -scheme Stackbar -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" $PROVISIONING build
APP="$DERIVED/Build/Products/Release/Stackbar.app"
[ -d "$APP" ] || { echo "install: xcodebuild produced no $APP" >&2; exit 1; }

swift build -c release --product stackbarctl
scripts/embed-stackbarkit.sh "$APP" "$(swift build -c release --show-bin-path)"

# Adding files invalidates the app's signature: sign stackbarctl and the app
# again with the identity and entitlements Xcode used. The widget keeps its
# own signature.
IDENTITY=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)
[ -n "$IDENTITY" ] || IDENTITY=-
ENTITLEMENTS=$(mktemp -t stackbar-entitlements)
codesign -d --entitlements - --xml "$APP" > "$ENTITLEMENTS" 2>/dev/null
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP/Contents/MacOS/stackbarctl"
codesign --force --options runtime --timestamp=none --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
rm -f "$ENTITLEMENTS"
codesign --verify --deep --strict "$APP"

osascript -e 'tell application id "io.navbytes.stackbar" to quit' >/dev/null 2>&1 || true
pkill -x Stackbar 2>/dev/null || true
rm -rf "$DEST/Stackbar.app"
ditto "$APP" "$DEST/Stackbar.app"

mkdir -p "$HOME/.local/bin"
ln -sf "$DEST/Stackbar.app/Contents/MacOS/stackbarctl" "$HOME/.local/bin/stackbarctl"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "install: add ~/.local/bin to PATH to use stackbarctl" ;; esac

open "$DEST/Stackbar.app"
echo "installed $DEST/Stackbar.app"
"$DEST/Stackbar.app/Contents/MacOS/stackbarctl" doctor
