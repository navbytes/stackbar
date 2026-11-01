#!/bin/sh
# Builds the app through Xcode, unsigned, and checks that the App Intents
# metadata Spotlight and Shortcuts read was extracted. scripts/install.sh
# makes the signed build the same way.
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "check-xcode: run this on a Mac" >&2; exit 1; }
command -v xcodegen >/dev/null || brew install xcodegen
DERIVED=build/xcode-check
xcodegen generate --quiet
xcodebuild -quiet -project Stackbar.xcodeproj -scheme Stackbar -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" build
APP="$DERIVED/Build/Products/Debug/Stackbar.app"
METADATA="$APP/Contents/Resources/Metadata.appintents"
[ -d "$METADATA" ] || { echo "check-xcode: no App Intents metadata in $APP" >&2; exit 1; }
grep -q RunCommandIntent "$METADATA/extract.actionsdata" || { echo "check-xcode: RunCommandIntent is missing from the metadata" >&2; exit 1; }
echo "check-xcode: ok"
