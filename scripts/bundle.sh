#!/bin/sh
# Builds Stackbar.app (with stackbarctl and the StackbarKit sources plugins build
# against) into build/. Runs on a Mac with Xcode 26 or its Command Line Tools.
#
#   scripts/bundle.sh                     ad-hoc signed, for this Mac
#   STACKBAR_SIGN_IDENTITY="Developer ID Application: …" scripts/bundle.sh
#   STACKBAR_NOTARY_PROFILE=stackbar scripts/bundle.sh   also notarize and staple
#     (create the profile once with: xcrun notarytool store-credentials stackbar)
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "bundle: run this on a Mac" >&2; exit 1; }

VERSION=$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' Sources/StackbarHostCore/StackbarVersion.swift)
BUILD=build
APP="$BUILD/Stackbar.app"
IDENTITY=${STACKBAR_SIGN_IDENTITY:--}
# Notarization needs a secure timestamp; an ad-hoc signature cannot carry one.
TIMESTAMP=--timestamp
[ "$IDENTITY" != "-" ] || TIMESTAMP=--timestamp=none

swift build -c release --product Stackbar
swift build -c release --product stackbarctl
BIN=$(swift build -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/Stackbar" "$APP/Contents/MacOS/"
sed "s/@VERSION@/$VERSION/g" Packaging/Info.plist > "$APP/Contents/Info.plist"
scripts/embed-stackbarkit.sh "$APP" "$BIN"
mkdir -p "$APP/Contents/Resources"
cp Packaging/AppIcon.icns "$APP/Contents/Resources/"

codesign --force --options runtime "$TIMESTAMP" --sign "$IDENTITY" "$APP/Contents/MacOS/stackbarctl"
codesign --force --options runtime "$TIMESTAMP" --entitlements Packaging/Stackbar.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

ZIP="$BUILD/Stackbar-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [ -n "${STACKBAR_NOTARY_PROFILE:-}" ]; then
    [ "$IDENTITY" != "-" ] || { echo "bundle: notarizing needs STACKBAR_SIGN_IDENTITY" >&2; exit 1; }
    xcrun notarytool submit "$ZIP" --keychain-profile "$STACKBAR_NOTARY_PROFILE" ${NOTARY_KEYCHAIN:+--keychain "$NOTARY_KEYCHAIN"} --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
fi
echo "$APP"
echo "$ZIP"
