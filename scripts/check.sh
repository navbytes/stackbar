#!/bin/sh
# The full local gate: build, test, and on macOS also the app and the plugin
# builder. Run it before pushing; the self-hosted Mac runner runs the same.
set -eu
cd "$(dirname "$0")/.."
swift build
FLUID_BUILD_TESTS=1 swift test
if [ "$(uname)" = Darwin ]; then
    swift build -c release --product Fluid
fi
echo "check: ok"
