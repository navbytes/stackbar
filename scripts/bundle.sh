#!/bin/sh
# Builds Fluid.app (with fluidctl and the FluidKit sources plugins build
# against) into build/. Runs on a Mac with Xcode 26 or its Command Line Tools.
#
#   scripts/bundle.sh                     ad-hoc signed, for this Mac
#   FLUID_SIGN_IDENTITY="Developer ID Application: …" scripts/bundle.sh
#   FLUID_NOTARY_PROFILE=fluid scripts/bundle.sh   also notarize and staple
#     (create the profile once with: xcrun notarytool store-credentials fluid)
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "bundle: run this on a Mac" >&2; exit 1; }

VERSION=$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' Sources/FluidHostCore/FluidVersion.swift)
BUILD=build
APP="$BUILD/Fluid.app"
IDENTITY=${FLUID_SIGN_IDENTITY:--}

swift build -c release --product Fluid
swift build -c release --product fluidctl
BIN=$(swift build -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/Fluid" "$APP/Contents/MacOS/"
sed "s/@VERSION@/$VERSION/g" Packaging/Info.plist > "$APP/Contents/Info.plist"
scripts/embed-fluidkit.sh "$APP" "$BIN"
mkdir -p "$APP/Contents/Resources"
cp Packaging/AppIcon.icns "$APP/Contents/Resources/"

codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP/Contents/MacOS/fluidctl"
codesign --force --options runtime --timestamp=none --entitlements Packaging/Fluid.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

ZIP="$BUILD/Fluid-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [ -n "${FLUID_NOTARY_PROFILE:-}" ]; then
    [ "$IDENTITY" != "-" ] || { echo "bundle: notarizing needs FLUID_SIGN_IDENTITY" >&2; exit 1; }
    xcrun notarytool submit "$ZIP" --keychain-profile "$FLUID_NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
fi
echo "$APP"
echo "$ZIP"
