#!/bin/sh
# Decides which CI jobs a change needs, from the changed files on stdin (one
# path per line). Prints `linux=`, `macos=` and `xcode=` lines for
# $GITHUB_OUTPUT. Anything not listed as docs-only runs the full set, so a new
# folder is covered until someone decides otherwise.
#
#   git diff --name-only A...B | .github/scripts/changes.sh
#   .github/scripts/changes.sh --all          everything (pushes we can't diff, manual runs)
set -eu

linux=false macos=false xcode=false
if [ "${1:-}" = --all ]; then
    linux=true macos=true xcode=true
else
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        case "$path" in
            # Read by the Linux tests (AuthoringTests, SurfaceParityTests), not
            # built into anything.
            llms.txt|docs/surface-parity.md)
                linux=true ;;
            # Docs, the site and planning: no Swift job reads them. The site has
            # its own workflow (site.yml), and release.yml only runs on tags.
            site/*|openspec/*|docs/*|*.md|LICENSE|.gitignore|.github/ISSUE_TEMPLATE/* \
            |.github/workflows/site.yml|.github/workflows/release.yml \
            |scripts/get-stackbar.sh|scripts/update-homebrew-cask.sh)
                ;;
            # What the Xcode project builds: the app, its library dependencies,
            # the widget and the packaging around them.
            Sources/Stackbar/*|Sources/StackbarProtocol/*|Sources/StackbarHostCore/*|Sources/StackbarUI/*\
            |Widget/*|Packaging/*|project.yml|Package.swift|Package.resolved\
            |scripts/check-xcode.sh|.github/workflows/ci.yml|.github/scripts/*)
                linux=true macos=true xcode=true ;;
            # Everything else (StackbarKit, stackbarctl, tests, examples, other
            # scripts, anything new) builds and tests with SwiftPM.
            *)
                linux=true macos=true ;;
        esac
    done
fi
echo "linux=$linux"
echo "macos=$macos"
echo "xcode=$xcode"
