## Why

Naveen wants Stackbar shipped to thousands of developers (2026-10-31). The
readiness review
([Stackbar: shipping and App Store readiness](https://claude.ai/artifact/1ch8HnDT62akJxa5x3GWod))
found the engine ready and the release machinery missing: no updater, no crash
reporting, no first-run flow, no release pipeline, and gaps in the app's own
chrome.

Decided with Naveen on 2026-10-31:

- **No Mac App Store.** Stackbar compiles plugin source into executables at
  runtime (guideline 2.5.2) and can't run the Xcode toolchain from inside the
  store's sandbox. Stackbar ships as a notarized Developer ID download, through
  GitHub Releases and a Homebrew cask.
- **License: MIT.**
- **Crash reports: Sentry, opt-in.** Nothing is sent until the user agrees.
- **A new name: Stackbar** (stackbar.app). The working name "Fluid" collided with the long-standing Fluid.app. The
  rename happens before the first public build; until then, code keeps
  saying Stackbar.

## What Changes

- One release build: app, widget, `stackbarctl` and StackbarKit, signed with a
  secure timestamp, notarized and stapled, as a DMG and a zip.
- Sparkle 2 updates from an EdDSA-signed appcast; a build number that rises
  on every build.
- Opt-in Sentry crash and error reports, asked on first run and switchable in
  Settings.
- A first-run flow: toolchain check with `xcode-select --install`, the
  permissions each bundled plugin needs, launch at login.
- App chrome: About window with version, Help and "Report a problem", "Check
  for Updates…", "Install command-line tool", "Remove all data", a
  move-to-Applications prompt.
- Safer defaults: the agent gateway off until the user turns it on.
- Distribution: tag-driven release on a GitHub macOS runner, Homebrew
  cask, an official plugin index with a signed revocation list.
- Docs and policy: a short docs site, privacy statement, issue templates.

## Impact

- New dependencies: Sparkle and the Sentry Cocoa SDK, in the app target only.
  StackbarKit, the protocol and plugins don't change.
- Naveen has to create a Sentry project (for its DSN), an EdDSA key for
  Sparkle (`generate_keys`, kept in his Keychain), and notarization
  credentials stored as repository secrets for the release job.
- Vee is untouched.
