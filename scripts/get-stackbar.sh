#!/usr/bin/env bash
#
# One-line installer for Stackbar: the app and the `stackbarctl` CLI.
#
#   curl -fsSL https://stackbar.navbytes.io/install.sh | bash
#
# The site serves this file as /install.sh (site/scripts/sync-kit.mjs copies
# it). It installs the newest signed, notarized release into /Applications and
# links stackbarctl onto your PATH. Homebrew does the same and handles upgrades
# (`brew install --cask navbytes/tap/stackbar`); this is for Macs without it.
#
# Not to be confused with scripts/install.sh, which builds from a checkout.
#
# Options go after `bash -s --`, the form that survives a pipe
# (`VAR=x curl … | bash` sets VAR for curl, not for the bash reading this):
#
#   curl -fsSL https://stackbar.navbytes.io/install.sh | bash -s -- --app-dir ~/Applications
#
#   --app-dir DIR   where Stackbar.app goes (default: /Applications)
#   --bin-dir DIR   where the stackbarctl link goes (default: the first existing
#                   of ~/.local/bin, /usr/local/bin, else ~/.local/bin)
#   --version TAG   release to install, e.g. v0.14.0 (default: newest)
#
# STACKBAR_APP_DIR, STACKBAR_BIN_DIR and STACKBAR_VERSION work too when they
# actually reach this script. A flag wins over the environment.
set -euo pipefail

REPO="navbytes/stackbar"

info() { printf '\033[1;35m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$1" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Install Stackbar: the menu-bar app and the `stackbarctl` CLI.

  curl -fsSL https://stackbar.navbytes.io/install.sh | bash
  curl -fsSL https://stackbar.navbytes.io/install.sh | bash -s -- --app-dir ~/Applications

Options:
  --app-dir DIR   where Stackbar.app goes (default: /Applications)
  --bin-dir DIR   where the stackbarctl link goes (default: ~/.local/bin or
                  /usr/local/bin, whichever exists)
  --version TAG   release to install, e.g. v0.14.0 (default: newest)
  -h, --help      show this and exit
USAGE
}

app_dir="${STACKBAR_APP_DIR:-}"
bin_dir="${STACKBAR_BIN_DIR:-}"
version="${STACKBAR_VERSION:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --app-dir) [ $# -ge 2 ] || die "--app-dir needs a directory"; app_dir="$2"; shift 2 ;;
    --bin-dir) [ $# -ge 2 ] || die "--bin-dir needs a directory"; bin_dir="$2"; shift 2 ;;
    --version) [ $# -ge 2 ] || die "--version needs a tag"; version="$2"; shift 2 ;;
    --app-dir=*) app_dir="${1#*=}"; shift ;;
    --bin-dir=*) bin_dir="${1#*=}"; shift ;;
    --version=*) version="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option '$1' (try --help)" ;;
  esac
done

APP_DIR="${app_dir:-/Applications}"

# ── Preflight ────────────────────────────────────────────────────────────────

[ "$(uname -s)" = "Darwin" ] || die "Stackbar is macOS only (found $(uname -s))."

arch="$(uname -m)"
[ "$arch" = "arm64" ] || die "Stackbar needs Apple Silicon; this Mac is $arch. There is no Intel build."

major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 26 ] || die "Stackbar needs macOS 26 or later (found $(sw_vers -productVersion))."

for tool in curl ditto shasum; do
  command -v "$tool" >/dev/null || die "'$tool' is required but not installed."
done

# ── Resolve the release ──────────────────────────────────────────────────────
# /releases/latest skips pre-releases, so fall back to the newest published
# release while every Stackbar build is still marked as one.

api="https://api.github.com/repos/${REPO}"
tag_of() { sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1; }

if [ -z "$version" ]; then
  info "Looking up the newest release…"
  version="$(curl -fsSL "$api/releases/latest" 2>/dev/null | tag_of || true)"
  [ -n "$version" ] || version="$(curl -fsSL "$api/releases?per_page=1" | tag_of || true)"
  [ -n "$version" ] || die "Could not find a Stackbar release. Pin one with --version vX.Y.Z."
fi
case "$version" in v*) ;; *) version="v$version" ;; esac
number="${version#v}"
zip="Stackbar-${number}.zip"
base="https://github.com/${REPO}/releases/download/${version}"

# ── Download and verify ──────────────────────────────────────────────────────

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

info "Downloading Stackbar ${number}…"
curl -fsSL --retry 3 -o "$tmp/$zip" "$base/$zip" || die "Download failed: $base/$zip"

if curl -fsSL --retry 3 -o "$tmp/SHA256SUMS.txt" "$base/SHA256SUMS.txt" 2>/dev/null; then
  expected="$(awk -v f="$zip" '$2 == f || $2 == "*" f { print $1 }' "$tmp/SHA256SUMS.txt")"
  actual="$(shasum -a 256 "$tmp/$zip" | awk '{print $1}')"
  [ -n "$expected" ] || die "SHA256SUMS.txt has no entry for $zip."
  [ "$expected" = "$actual" ] || die "Checksum mismatch for $zip (expected $expected, got $actual)."
  info "Checksum verified."
else
  warn "This release has no SHA256SUMS.txt; skipping the checksum."
fi

ditto -x -k "$tmp/$zip" "$tmp/unpacked" || die "Could not unpack $zip."
[ -d "$tmp/unpacked/Stackbar.app" ] || die "Stackbar.app was not in the archive."

# ── Install the app ──────────────────────────────────────────────────────────
# Try without sudo first and escalate only on failure: `[ -w ]` is wrong both
# for a folder that does not exist yet and for one TCC refuses to write.

escalated=false
run_maybe_sudo() {
  first_error="$("$@" 2>&1 >/dev/null)" && return 0
  if [ "$escalated" = false ]; then
    warn "Need administrator rights, asking for your password."
    escalated=true
  fi
  sudo "$@" && return 0
  [ -n "$first_error" ] && warn "$first_error"
  die "Could not run: $*"
}

[ -d "$APP_DIR" ] || run_maybe_sudo mkdir -p "$APP_DIR"
target="$APP_DIR/Stackbar.app"

if pgrep -xq Stackbar; then
  info "Quitting the running Stackbar…"
  osascript -e 'tell application id "io.navbytes.stackbar" to quit' >/dev/null 2>&1 || pkill -x Stackbar || true
  sleep 1
fi

# Replace rather than merge: a stale file inside the bundle breaks its signature.
if [ -e "$target" ]; then
  info "Replacing ${target}…"
  run_maybe_sudo rm -rf "$target"
fi
info "Installing to ${target}…"
run_maybe_sudo ditto "$tmp/unpacked/Stackbar.app" "$target"

# Releases are notarized and stapled. Clearing the quarantine flag curl leaves
# only skips the "downloaded from the internet" prompt on first launch.
xattr -dr com.apple.quarantine "$target" 2>/dev/null || true

# ── Link the CLI ─────────────────────────────────────────────────────────────

if [ -z "$bin_dir" ]; then
  for candidate in "$HOME/.local/bin" "/usr/local/bin"; do
    if [ -d "$candidate" ]; then bin_dir="$candidate"; break; fi
  done
  [ -n "$bin_dir" ] || bin_dir="$HOME/.local/bin"
fi
[ -d "$bin_dir" ] || run_maybe_sudo mkdir -p "$bin_dir"
run_maybe_sudo ln -sf "$target/Contents/MacOS/stackbarctl" "$bin_dir/stackbarctl"
info "Linked stackbarctl at $bin_dir/stackbarctl"

case ":${PATH}:" in
  *":${bin_dir}:"*) ;;
  *) warn "${bin_dir} is not on your PATH. Add it:"
     # shellcheck disable=SC2016  # $PATH stays literal in the hint
     printf '\n  export PATH="%s:$PATH"\n\n' "$bin_dir" ;;
esac

# ── Toolchain ────────────────────────────────────────────────────────────────
# Store plugins come prebuilt. Writing your own needs Swift from Xcode or the
# Command Line Tools, so mention it, without making it sound required.

if ! xcode-select -p >/dev/null 2>&1; then
  info "Store plugins run as they are. To write your own, install the Command Line Tools:"
  printf '\n  xcode-select --install\n\n'
fi

info "Installed Stackbar ${number}."
echo
echo "  open -a Stackbar      launch the menu-bar app"
echo "  stackbarctl doctor    check the toolchain and setup"
echo
echo "Re-run this to upgrade, or use Homebrew for upgrades through brew:"
echo "  brew install --cask navbytes/tap/stackbar"
