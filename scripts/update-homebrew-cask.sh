#!/usr/bin/env bash
# Publishes (or refreshes) the Stackbar cask in navbytes/homebrew-tap so
# `brew install --cask navbytes/tap/stackbar` tracks the release the workflow
# just built. Same flow as Vee's: it writes Casks/stackbar.rb on a
# release/stackbar-<version> branch and opens a PR on the tap. Idempotent.
#
# Runs from the Release workflow after the zip is built. Expects:
#   HOMEBREW_TAP_TOKEN  fine-grained PAT, contents + pull requests write on
#                       navbytes/homebrew-tap (Vee's token works)
#   VERSION             the release version without the v, e.g. 0.14.0
#   ZIP                 path to Stackbar-<version>.zip
# The workflow skips this step when HOMEBREW_TAP_TOKEN is not set.
set -euo pipefail

: "${HOMEBREW_TAP_TOKEN:?HOMEBREW_TAP_TOKEN is required}"
: "${VERSION:?VERSION is required (e.g. 0.14.0)}"
: "${ZIP:?ZIP is required}"
[ -f "$ZIP" ] || { echo "::error::$ZIP not found" >&2; exit 1; }

sha="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "Cask target: stackbar ${VERSION} (sha256 ${sha})"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
tap="$workdir/tap"
git clone --depth 1 "https://x-access-token:${HOMEBREW_TAP_TOKEN}@github.com/navbytes/homebrew-tap.git" "$tap"

branch="release/stackbar-${VERSION}"
remote_branch="$(git -C "$tap" ls-remote --heads origin "refs/heads/$branch")"
if [ -n "$remote_branch" ]; then
  git -C "$tap" fetch origin "refs/heads/$branch"
  git -C "$tap" checkout -B "$branch" FETCH_HEAD
fi
mkdir -p "$tap/Casks"

cat > "$tap/Casks/stackbar.rb" <<EOF
cask "stackbar" do
  version "${VERSION}"
  sha256 "${sha}"

  url "https://github.com/navbytes/stackbar/releases/download/v#{version}/Stackbar-#{version}.zip",
      verified: "github.com/navbytes/stackbar/"
  name "Stackbar"
  desc "Menu-bar host for live plugins written in Swift"
  homepage "https://stackbar.navbytes.io/"

  livecheck do
    url :url
    strategy :github_releases
  end

  # Apple Silicon + macOS 26 (Tahoe) or later, matching the app.
  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Stackbar.app"
  # stackbarctl ships inside the app, so one cask delivers both.
  binary "#{appdir}/Stackbar.app/Contents/MacOS/stackbarctl"

  uninstall quit: "io.navbytes.stackbar"

  zap trash: [
    "~/Library/Application Support/Stackbar",
    "~/Library/Caches/io.navbytes.stackbar",
    "~/Library/Preferences/io.navbytes.stackbar.plist",
  ]

  caveats <<~CAVEATS
    Stackbar compiles plugins on your Mac with Swift. If you have neither
    Xcode nor the Command Line Tools, install them:
      xcode-select --install
  CAVEATS
end
EOF

cd "$tap"
git add -A
if ! git diff --cached --quiet; then
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git commit -m "stackbar ${VERSION}"
  git push origin "HEAD:refs/heads/$branch"
elif [ -z "$remote_branch" ]; then
  echo "Tap already has stackbar ${VERSION}."
  exit 0
fi

export GH_TOKEN="$HOMEBREW_TAP_TOKEN"
open_prs="$(gh pr list --repo navbytes/homebrew-tap --head "$branch" --state open --json number --jq length)"
if [ "$open_prs" = 0 ]; then
  merged_prs="$(gh pr list --repo navbytes/homebrew-tap --head "$branch" --state merged --json number --jq length)"
  if [ "$merged_prs" = 0 ]; then
    gh pr create --repo navbytes/homebrew-tap --base main --head "$branch" \
      --title "stackbar ${VERSION}" --body "Update the tap to the published Stackbar ${VERSION} release."
  fi
fi
echo "Tap PR ready for stackbar ${VERSION}."
