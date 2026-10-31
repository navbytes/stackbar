#!/bin/sh
# Copies what an installed Fluid needs besides its executable into an app
# bundle: fluidctl, the slim FluidKit package plugins are built against, the
# examples, the bundled plugins and llms.txt. Used by bundle.sh and install.sh.
#
#   scripts/embed-fluidkit.sh <Fluid.app> <dir with a release fluidctl>
set -eu
APP=$1
BIN=$2
cd "$(dirname "$0")/.."

KIT="$APP/Contents/Resources/FluidKit"
rm -rf "$KIT"
mkdir -p "$APP/Contents/MacOS" "$KIT/Sources" "$KIT/Examples" "$KIT/Plugins"
cp "$BIN/fluidctl" "$APP/Contents/MacOS/"
cp Packaging/FluidKit-Package.swift "$KIT/Package.swift"
cp -R Sources/FluidProtocol Sources/FluidKit "$KIT/Sources/"
for example in Examples/*/*.swift; do cp "$example" "$KIT/Examples/"; done
for plugin in Plugins/*/*.swift; do cp "$plugin" "$KIT/Plugins/"; done
cp llms.txt "$APP/Contents/Resources/"
