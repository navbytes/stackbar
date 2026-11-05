# Launch phase 2: ship like a product

## Why

Phase 1 made switching from Raycast credible. Phase 2 makes Stackbar behave
like a product people keep: it updates itself, the release is the full Xcode
build with the desktop widget, problems are easy to report, and a setup can be
moved to a new Mac or brought over from Raycast.

## What changes

- **Release build through Xcode.** `scripts/release.sh` builds the app and its
  widget with `xcodebuild`, embeds stackbarctl, StackbarKit and the prebuilt
  helpers, signs inside out with Developer ID, notarizes and staples. The
  Release workflow uses it instead of `bundle.sh`, and gains a dry run that
  builds and notarizes without publishing.
- **Sparkle 2 self-update.** Sparkle in the Xcode app only. The Release
  workflow signs the zip with the EdDSA key in the `SPARKLE_PRIVATE_KEY`
  secret, derives the public key into `SUPublicEDKey`, and publishes
  `appcast.xml` with the release. "Check for Updates…" in the app menu,
  status menu and Settings › Store & Updates, with an automatic-check toggle.
  The cask gets `auto_updates true`.
- **CHANGELOG.md**, one section per version; the release notes and Sparkle's
  update window show that version's section.
- **About, Help and Report a problem.** Help links to the docs and issues;
  "Report a problem" opens a new GitHub issue with `stackbarctl doctor`
  output filled in.
- **Opt-in crash reports.** Sentry in the Xcode app only, started only after
  the user says yes (Welcome window and Settings › Privacy). The DSN comes
  from the `SENTRY_DSN` build setting, so forks and local builds never report.
- **Export and import settings.** One `.stackbarsettings` file with the
  installed plugins, their settings, palette favourites, hotkeys and app
  preferences. Secrets are never exported.
- **Import from Raycast.** Snippets and Quicklinks read Raycast's JSON
  exports (plugin-first, in stackbar-plugins).
- **Benchmark.** A macOS CI workflow that measures launch time, palette open
  time and idle memory, and writes the numbers the site quotes.

## Impact

- New dependencies in the Xcode app target only: Sparkle and Sentry.
  Package.swift, StackbarKit, the protocol and plugins don't change.
- Naveen sets two repository secrets: `SPARKLE_PRIVATE_KEY` (one command, the
  key is never shown) and `SENTRY_DSN` (from a new Sentry project). Without
  them the build ships with updates or crash reports turned off.
