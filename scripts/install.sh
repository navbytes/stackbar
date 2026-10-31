#!/bin/sh
# Builds the signed Fluid.app with its widget from this checkout and installs
# it on this Mac:
#   - /Applications/Fluid.app (replacing a running copy)
#   - fluidctl linked into ~/.local/bin
#   - the bundled plugins (Plugins/) copied into Fluid's plugins folder
#
# Needs Xcode 26, xcodegen (brew install xcodegen) and an Xcode account for
# the team in project.yml. The first run on a Mac may need
# FLUID_ALLOW_PROVISIONING=1 to let Xcode register the App IDs.
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "install: run this on a Mac" >&2; exit 1; }
command -v xcodegen >/dev/null || { echo "install: brew install xcodegen" >&2; exit 1; }

DERIVED=build/xcode
DEST=${FLUID_INSTALL_DIR:-/Applications}
PROVISIONING=""
[ -n "${FLUID_ALLOW_PROVISIONING:-}" ] && PROVISIONING=-allowProvisioningUpdates

xcodegen generate --quiet
# shellcheck disable=SC2086
xcodebuild -quiet -project Fluid.xcodeproj -scheme Fluid -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" $PROVISIONING build
APP="$DERIVED/Build/Products/Release/Fluid.app"
[ -d "$APP" ] || { echo "install: xcodebuild produced no $APP" >&2; exit 1; }

swift build -c release --product fluidctl
scripts/embed-fluidkit.sh "$APP" "$(swift build -c release --show-bin-path)"

# Adding files invalidates the app's signature: sign fluidctl and the app
# again with the identity and entitlements Xcode used. The widget keeps its
# own signature.
IDENTITY=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)
[ -n "$IDENTITY" ] || IDENTITY=-
ENTITLEMENTS=$(mktemp -t fluid-entitlements)
codesign -d --entitlements - --xml "$APP" > "$ENTITLEMENTS" 2>/dev/null
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP/Contents/MacOS/fluidctl"
codesign --force --options runtime --timestamp=none --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
rm -f "$ENTITLEMENTS"
codesign --verify --deep --strict "$APP"

osascript -e 'tell application id "dev.fluid.app" to quit' >/dev/null 2>&1 || true
pkill -x Fluid 2>/dev/null || true
rm -rf "$DEST/Fluid.app"
ditto "$APP" "$DEST/Fluid.app"

mkdir -p "$HOME/.local/bin"
ln -sf "$DEST/Fluid.app/Contents/MacOS/fluidctl" "$HOME/.local/bin/fluidctl"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "install: add ~/.local/bin to PATH to use fluidctl" ;; esac

PLUGINS="$HOME/Library/Application Support/Fluid/Plugins"
mkdir -p "$PLUGINS"
for plugin in Plugins/*/*.swift; do cp "$plugin" "$PLUGINS/"; done

open "$DEST/Fluid.app"
echo "installed $DEST/Fluid.app"
"$DEST/Fluid.app/Contents/MacOS/fluidctl" doctor
