## Distribution: direct, not the App Store

The store requires the App Sandbox for the app and everything it runs, and
forbids executing code that adds features after review. Fluid's core loop
(build a plugin's Swift source with the user's toolchain, run the helper) is
both. A store build would be a fixed utility pack without plugins, `fluidctl`
or agents, so it is out of scope. Raycast, SwiftBar, xbar and Hammerspoon
ship outside the store for the same reasons.

## One release build

`scripts/install.sh` already builds the Xcode project (app plus widget) and
runs `scripts/embed-fluidkit.sh`. `scripts/release.sh` reuses that path and
adds: version and build number from the git tag, signing with
`--timestamp` (notarization rejects `--timestamp=none`), `notarytool`,
`stapler`, a DMG, and the Sparkle archive signature. `bundle.sh` stays for
quick unsigned local builds.

## Updates

Sparkle 2 with `SUFeedURL` pointing at an appcast published with each GitHub
Release, and `SUPublicEDKey` in Info.plist. `CFBundleVersion` is the commit
count on main, so it always rises; `CFBundleShortVersionString` is the tag.
Plugin helpers rebuild after an update because the build cache key includes a
FluidKit digest (#6).

## Crash reports

The Sentry Cocoa SDK starts only when the user has said yes. The consent
question is on the first-run screen and in Settings. Reports carry the app
version, macOS version and stack; plugin names and the host log are attached
only when the user sends a report by hand. The DSN is not a secret but is
kept in Info.plist from a build setting, so forks don't report into it.

## Name

Rename before the first public build, in one pull request: bundle ids
(`dev.fluid.*`), app group, Keychain service, data directory (with a one-time
move from `~/Library/Application Support/Fluid`), `fluidctl`, FluidKit,
`.fluidplugin`, docs. Plugin authors keep their code: FluidKit's new name
ships with a deprecated `FluidKit` re-export for one release.
