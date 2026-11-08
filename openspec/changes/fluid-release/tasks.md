## 1. Decisions (2026-10-31)

- [x] 1.1 Ship outside the Mac App Store
- [x] 1.2 MIT license (LICENSE, README, Info.plist copyright)
- [x] 1.3 Crash reports through Sentry, opt-in
- [x] 1.4 New name: Stackbar (stackbar.app; register stackbar.app and stackbar.dev)

## 2. Already done elsewhere

- [x] 2.1 App icon (#7)
- [x] 2.2 Plugins sandboxed by default, with a Mac test (#8)
- [x] 2.3 Rebuild plugins after a StackbarKit change; single instance (#6)
- [x] 2.4 StackbarKit and stackbarctl embedded in the Xcode-built app (#4)

## 3. Release build

- [x] 3.1 `scripts/release.sh`: Xcode build, embed, sign with a secure timestamp, notarize, staple, DMG and zip (scripts/release.sh)
- [x] 3.2 Version from the tag, build number that always rises; one Info.plist source (Release workflow checks the tag against StackbarVersion.current)
- [x] 3.3 Mac CI builds the Xcode project (`xcodebuild`), not only `swift build` (scripts/check-xcode.sh in ci.yml)
- [x] 3.4 Tag-driven release job on the macos-26 runner, publishing to GitHub Releases (`.github/workflows/release.yml`; ad-hoc signed until the Developer ID secrets are set)
- [x] 3.5 Homebrew cask (`scripts/update-homebrew-cask.sh` opens a PR on navbytes/homebrew-tap from the Release workflow when `HOMEBREW_TAP_TOKEN` is set) and a one-line installer served at stackbar.navbytes.io/install.sh (`scripts/get-stackbar.sh`)

## 4. Updates and crash reports

- [x] 4.1 Sparkle 2: appcast, EdDSA key, "Check for Updates…" (Updater.swift, appcast.py (launch-phase-2))
- [x] 4.2 Sentry SDK, started only after consent; DSN from a build setting (CrashReports.swift; SENTRY_DSN secret)
- [x] 4.3 "Report a problem" that opens an issue with `stackbarctl doctor` output (Report a Problem… (ProblemReport.swift))

## 5. First run and app chrome

- [x] 5.1 First-run flow: toolchain, permissions, crash-report consent, launch at login (Welcome window)
- [x] 5.2 Move-to-Applications prompt (translocated or outside /Applications) (launch-phase-4 1.4)
- [x] 5.3 About window with version; Help menu with docs and feedback links (About Stackbar, Help menu)
- [x] 5.4 "Install command-line tool" (link `stackbarctl` onto the PATH) (launch-phase-4 1.5)
- [x] 5.5 "Remove all data" (storage, secrets, build cache) (launch-phase-4 1.6)
- [x] 5.6 Agent gateway off by default (new installs, 0.32.0; existing Macs keep theirs)
- [x] 5.7 Install sheet says when a secret name is shared with other plugins ("Also used by" in plugin Settings)

## 6. Ecosystem, docs and policy

- [x] 6.1 Official plugin index with a signed revocation list the app checks (revoked.json in the store index)
- [x] 6.2 Plugin update checks against installed indexes (daily update check (plugin-store 3.3))
- [x] 6.3 Docs site: install, first plugin in five minutes, capabilities, publishing (stackbar.app/docs)
- [x] 6.4 Privacy statement (what crash reports contain) (site docs/privacy.md)
- [x] 6.5 Issue templates asking for `stackbarctl doctor` (.github/ISSUE_TEMPLATE/bug.yml)
- [ ] 6.6 VoiceOver labels in the renderers; wrap UI strings for localization

## 7. Rename (after 1.4)

- [x] 7.1 Bundle ids, app group, Keychain service, data directory with a one-time move
- [x] 7.2 `stackbarctl`, StackbarKit, StackbarProtocol, `.stackbarplugin`, docs (no compatibility alias)
- [x] 7.3 Rename the GitHub repository to navbytes/stackbar (Naveen) (repo is navbytes/stackbar)

## 8. Beta

- [ ] 8.1 Private beta with about 50 developers
- [x] 8.2 Public download (stackbar.app/download, Homebrew cask)
