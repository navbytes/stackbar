#!/bin/sh
# Copies what an installed Stackbar needs besides its executable into an app
# bundle: stackbarctl, the slim StackbarKit package plugins are built against, the
# examples, the bundled plugins and llms.txt. Used by bundle.sh and install.sh.
#
#   scripts/embed-stackbarkit.sh <Stackbar.app> <dir with a release stackbarctl>
set -eu
APP=$1
BIN=$2
cd "$(dirname "$0")/.."

KIT="$APP/Contents/Resources/StackbarKit"
rm -rf "$KIT"
mkdir -p "$APP/Contents/MacOS" "$KIT/Sources" "$KIT/Examples" "$KIT/Plugins"
cp "$BIN/stackbarctl" "$APP/Contents/MacOS/"
cp Packaging/StackbarKit-Package.swift "$KIT/Package.swift"
cp -R Sources/StackbarProtocol Sources/StackbarKit "$KIT/Sources/"
for example in Examples/*/*.swift; do cp "$example" "$KIT/Examples/"; done
for plugin in Plugins/*/*.swift; do cp "$plugin" "$KIT/Plugins/"; done
cp llms.txt "$APP/Contents/Resources/"
