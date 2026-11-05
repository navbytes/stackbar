# Tasks

## 1. Release and updates
- [x] 1.1 `scripts/release.sh`: Xcode build with the widget, embed, prebuild helpers, sign inside out, notarize, staple
- [x] 1.2 Release workflow uses it; `dry_run` input; pre-release off by default
- [x] 1.3 Sparkle 2 in the Xcode app; `Updater`; Check for Updates in menus and Settings; automatic checks toggle
- [x] 1.4 `scripts/appcast.py` and the workflow step that signs the zip and publishes `appcast.xml`
- [x] 1.5 CHANGELOG.md; release notes and the appcast use the version's section
- [x] 1.6 Cask `auto_updates true` (homebrew-tap and `update-homebrew-cask.sh`)
- [ ] 1.7 Naveen sets `SPARKLE_PRIVATE_KEY`; a dry run shows a signed appcast

## 2. App chrome and crash reports
- [x] 2.1 Help menu: docs, release notes, Report a Problem (issue with doctor output)
- [x] 2.2 Sentry, opt-in from Welcome and Settings › Privacy; DSN from `SENTRY_DSN`
- [ ] 2.3 Naveen creates the Sentry project and sets `SENTRY_DSN`

## 3. Moving a setup
- [x] 3.1 `SettingsArchive` export and import, with tests
- [x] 3.2 Settings › General: Export Settings…, Import Settings…
- [x] 3.3 Snippets and Quicklinks import Raycast's JSON exports (already in the plugins); Settings › General links to both

## 4. Proof
- [ ] 4.1 Benchmark workflow: launch time, palette open time, idle memory
- [ ] 4.2 Mac check by Naveen: update from 0.23.0 to the next release in place
