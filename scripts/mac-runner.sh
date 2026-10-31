#!/bin/sh
# Registers this Mac as a self-hosted GitHub Actions runner for navbytes/fluid
# and installs it as a login service, so macOS CI costs nothing on GitHub.
#
#   1. Get a registration token: GitHub → navbytes/fluid → Settings → Actions →
#      Runners → New self-hosted runner (or `gh api -X POST
#      repos/navbytes/fluid/actions/runners/registration-token -q .token`).
#   2. Run:  scripts/mac-runner.sh <token>
#   3. Set the repository variable FLUID_MAC_RUNNER to "true"
#      (`gh variable set FLUID_MAC_RUNNER -b true -R navbytes/fluid`).
#
# Remove it again with: ~/actions-runner-fluid/svc.sh uninstall &&
# ~/actions-runner-fluid/config.sh remove --token <removal token>
set -eu
[ "$(uname)" = Darwin ] || { echo "mac-runner: run this on a Mac" >&2; exit 1; }
TOKEN=${1:?usage: scripts/mac-runner.sh <registration-token>}
REPO=${FLUID_REPO:-navbytes/fluid}
DIR=${FLUID_RUNNER_DIR:-$HOME/actions-runner-fluid}
VERSION=${RUNNER_VERSION:-$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p')}
[ -n "$VERSION" ] || { echo "mac-runner: could not find the latest runner version; set RUNNER_VERSION" >&2; exit 1; }
case "$(uname -m)" in arm64) ARCH=arm64 ;; *) ARCH=x64 ;; esac

mkdir -p "$DIR"
cd "$DIR"
if [ ! -x ./config.sh ]; then
    curl -fsSL -o runner.tar.gz "https://github.com/actions/runner/releases/download/v$VERSION/actions-runner-osx-$ARCH-$VERSION.tar.gz"
    tar xzf runner.tar.gz
    rm runner.tar.gz
fi
./config.sh --unattended --replace --url "https://github.com/$REPO" --token "$TOKEN" \
    --name "$(scutil --get LocalHostName)-fluid" --labels fluid --work _work
./svc.sh install
./svc.sh start
echo "Runner installed. Now: gh variable set FLUID_MAC_RUNNER -b true -R $REPO"
