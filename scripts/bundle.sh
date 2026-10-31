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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/FluidKit/Sources" "$APP/Contents/Resources/FluidKit/Examples" "$APP/Contents/Resources/FluidKit/Plugins"
cp "$BIN/Fluid" "$BIN/fluidctl" "$APP/Contents/MacOS/"
sed "s/@VERSION@/$VERSION/g" Packaging/Info.plist > "$APP/Contents/Info.plist"
cp Packaging/AppIcon.icns "$APP/Contents/Resources/"

# The slim package plugins are built against: FluidProtocol + FluidKit only.
cp Packaging/FluidKit-Package.swift "$APP/Contents/Resources/FluidKit/Package.swift"
cp -R Sources/FluidProtocol Sources/FluidKit "$APP/Contents/Resources/FluidKit/Sources/"
for example in Examples/*/*.swift; do cp "$example" "$APP/Contents/Resources/FluidKit/Examples/"; done
for plugin in Plugins/*/*.swift; do cp "$plugin" "$APP/Contents/Resources/FluidKit/Plugins/"; done
cp llms.txt "$APP/Contents/Resources/"

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
