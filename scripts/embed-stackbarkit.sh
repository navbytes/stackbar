#!/bin/sh
# Copies what an installed Stackbar needs besides its executable into an app
# bundle: stackbarctl, the slim StackbarKit package plugins are built against, the
# examples, the first-party plugins' signed bundles and llms.txt. Used by
# bundle.sh and install.sh.
#
# The first-party plugins live in navbytes/stackbar-plugins. Their bundles come
# from the official store, checked against its signing key, so a new Mac gets
# them without a network. Offline, or with STACKBAR_SKIP_BUNDLES=1, the app is
# built without them and they install from the store instead.
#
#   scripts/embed-stackbarkit.sh <Stackbar.app> <dir with a release stackbarctl>
set -eu
APP=$1
BIN=$2
cd "$(dirname "$0")/.."

KIT="$APP/Contents/Resources/StackbarKit"
rm -rf "$KIT"
mkdir -p "$APP/Contents/MacOS" "$KIT/Sources" "$KIT/Examples" "$KIT/Bundles"
cp "$BIN/stackbarctl" "$APP/Contents/MacOS/"
cp Packaging/StackbarKit-Package.swift "$KIT/Package.swift"
cp -R Sources/StackbarProtocol Sources/StackbarKit "$KIT/Sources/"
for example in Examples/*/*.swift; do cp "$example" "$KIT/Examples/"; done
if [ "${STACKBAR_SKIP_BUNDLES:-0}" != 1 ]; then
    "$BIN/stackbarctl" index fetch "$KIT/Bundles" \
        || echo "embed: couldn't fetch the first-party plugins; they will install from the store"
fi
cp llms.txt "$APP/Contents/Resources/"
