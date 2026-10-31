#!/bin/sh
# The full local gate: build, test, and on macOS also the app and the plugin
# builder. Run it before pushing; the macOS CI job runs the same.
set -eu
cd "$(dirname "$0")/.."
swift build
STACKBAR_BUILD_TESTS=1 swift test
if [ "$(uname)" = Darwin ]; then
    swift build -c release --product Stackbar
fi
echo "check: ok"
