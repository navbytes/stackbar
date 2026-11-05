#!/bin/sh
# Builds the release Stackbar.app: the Xcode project (app, widget, Sparkle,
# Sentry), plus stackbarctl, StackbarKit and the prebuilt helpers, signed
# inside out with Developer ID, notarized and stapled. The Release workflow
# runs it on the macos-26 runner; scripts/bundle.sh is the quick local build.
#
#   STACKBAR_SIGN_IDENTITY="Developer ID Application: …"   required for a signed build
#   STACKBAR_NOTARY_PROFILE=stackbar                          also notarize and staple
#   SPARKLE_PUBLIC_KEY=<base64>                               turns on self-update
#   SENTRY_DSN=<dsn>                                          lets users opt in to crash reports
#
# Without an identity the app is ad-hoc signed, for a dry run on any Mac.
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "release: run this on a Mac" >&2; exit 1; }
command -v xcodegen >/dev/null || brew install xcodegen

VERSION=$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' Sources/StackbarHostCore/StackbarVersion.swift)
BUILD=build
DERIVED="$BUILD/xcode-release"
APP="$BUILD/Stackbar.app"
IDENTITY=${STACKBAR_SIGN_IDENTITY:--}
TIMESTAMP=--timestamp
[ "$IDENTITY" != "-" ] || TIMESTAMP=--timestamp=none
KEYCHAIN_FLAG=""
[ -n "${NOTARY_KEYCHAIN:-}" ] && KEYCHAIN_FLAG="--keychain $NOTARY_KEYCHAIN"

# 1. The Xcode build, unsigned: signing happens below, in one place.
xcodegen generate --quiet
# Sentry's package lists every binary variant, and GitHub's release downloads
# sometimes answer 504. Resolve first and retry; finished downloads are kept.
for attempt in 1 2 3 4 5; do
    xcodebuild -quiet -project Stackbar.xcodeproj -scheme Stackbar \
        -derivedDataPath "$DERIVED" -resolvePackageDependencies && break
    [ "$attempt" = 5 ] && { echo "release: could not resolve packages" >&2; exit 1; }
    echo "release: package resolution failed, retrying in $((attempt * 15))s" >&2
    sleep $((attempt * 15))
done
xcodebuild -quiet -project Stackbar.xcodeproj -scheme Stackbar -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" build
rm -rf "$APP"
mkdir -p "$BUILD"
ditto "$DERIVED/Build/Products/Release/Stackbar.app" "$APP"
[ -d "$APP/Contents/PlugIns/StackbarWidget.appex" ] || { echo "release: the widget is missing" >&2; exit 1; }

# 2. stackbarctl, StackbarKit, the first-party bundles and their helpers.
swift build -c release --product stackbarctl
BIN=$(swift build -c release --show-bin-path)
scripts/embed-stackbarkit.sh "$APP" "$BIN"
KIT="$APP/Contents/Resources/StackbarKit"
set --
for plugin in "$KIT"/Bundles/*.stackbarplugin "$KIT"/Examples/*.swift; do
    [ -f "$plugin" ] && set -- "$@" "$plugin"
done
if [ $# -gt 0 ]; then
    STACKBAR_PACKAGE="$KIT" "$BIN/stackbarctl" helper prebuild "$KIT/Prebuilt" "$@" --cache "$BUILD/prebuild-cache"
fi

# 3. Keys that only the release carries.
PLIST="$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$PLIST"
if [ -n "${SPARKLE_PUBLIC_KEY:-}" ]; then
    plutil -replace SUPublicEDKey -string "$SPARKLE_PUBLIC_KEY" "$PLIST"
fi
if [ -n "${SENTRY_DSN:-}" ]; then
    plutil -replace SentryDSN -string "$SENTRY_DSN" "$PLIST"
fi

# 4. Sign inside out (Sparkle's documented order for a non-sandboxed app).
sign() { codesign --force --options runtime $TIMESTAMP --sign "$IDENTITY" "$@"; }
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE" ]; then
    for xpc in "$SPARKLE"/Versions/B/XPCServices/*.xpc; do
        [ -d "$xpc" ] && sign --preserve-metadata=entitlements "$xpc"
    done
    sign "$SPARKLE/Versions/B/Autoupdate"
    sign "$SPARKLE/Versions/B/Updater.app"
fi
for framework in "$APP"/Contents/Frameworks/*.framework "$APP"/Contents/Frameworks/*.dylib; do
    [ -e "$framework" ] && sign "$framework"
done
WIDGET_ENTITLEMENTS=$(mktemp -t stackbar-widget)
sed 's/\$(AppIdentifierPrefix)//' Packaging/Widget.entitlements > "$WIDGET_ENTITLEMENTS"
sign --entitlements "$WIDGET_ENTITLEMENTS" "$APP/Contents/PlugIns/StackbarWidget.appex"
rm -f "$WIDGET_ENTITLEMENTS"
for helper in "$KIT"/Prebuilt/*; do
    [ -f "$helper" ] && sign "$helper"
done
sign "$APP/Contents/MacOS/stackbarctl"
sign --entitlements Packaging/Stackbar.entitlements "$APP"
codesign --verify --deep --strict "$APP"

# 5. Zip, notarize, staple, zip again.
ZIP="$BUILD/Stackbar-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
if [ -n "${STACKBAR_NOTARY_PROFILE:-}" ]; then
    [ "$IDENTITY" != "-" ] || { echo "release: notarizing needs STACKBAR_SIGN_IDENTITY" >&2; exit 1; }
    # shellcheck disable=SC2086
    xcrun notarytool submit "$ZIP" --keychain-profile "$STACKBAR_NOTARY_PROFILE" $KEYCHAIN_FLAG --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
fi
echo "$APP"
echo "$ZIP"
