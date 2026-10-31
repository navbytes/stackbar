## 1. Decisions (2026-10-31)

- [x] 1.1 Ship outside the Mac App Store
- [x] 1.2 MIT license (LICENSE, README, Info.plist copyright)
- [x] 1.3 Crash reports through Sentry, opt-in
- [ ] 1.4 Choose the new name (shortlist checked for apps, domains, Homebrew)

## 2. Already done elsewhere

- [x] 2.1 App icon (#7)
- [x] 2.2 Plugins sandboxed by default, with a Mac test (#8)
- [x] 2.3 Rebuild plugins after a FluidKit change; single instance (#6)
- [x] 2.4 FluidKit and fluidctl embedded in the Xcode-built app (#4)

## 3. Release build

- [ ] 3.1 `scripts/release.sh`: Xcode build, embed, sign with a secure timestamp, notarize, staple, DMG and zip
- [ ] 3.2 Version from the tag, build number that always rises; one Info.plist source
- [ ] 3.3 Mac CI builds the Xcode project (`xcodebuild`), not only `swift build`
- [ ] 3.4 Tag-driven release job on the self-hosted runner, publishing to GitHub Releases
- [ ] 3.5 Homebrew cask

## 4. Updates and crash reports

- [ ] 4.1 Sparkle 2: appcast, EdDSA key, "Check for Updates…"
- [ ] 4.2 Sentry SDK, started only after consent; DSN from a build setting
- [ ] 4.3 "Report a problem" that opens an issue with `fluidctl doctor` output

## 5. First run and app chrome

- [ ] 5.1 First-run flow: toolchain, permissions, crash-report consent, launch at login
- [ ] 5.2 Move-to-Applications prompt (translocated or outside /Applications)
- [ ] 5.3 About window with version; Help menu with docs and feedback links
- [ ] 5.4 "Install command-line tool" (link `fluidctl` onto the PATH)
- [ ] 5.5 "Remove all data" (storage, secrets, build cache)
- [ ] 5.6 Agent gateway off by default
- [ ] 5.7 Install sheet says when a secret name is shared with other plugins

## 6. Ecosystem, docs and policy

- [ ] 6.1 Official plugin index with a signed revocation list the app checks
- [ ] 6.2 Plugin update checks against installed indexes
- [ ] 6.3 Docs site: install, first plugin in five minutes, capabilities, publishing
- [ ] 6.4 Privacy statement (what crash reports contain)
- [ ] 6.5 Issue templates asking for `fluidctl doctor`
- [ ] 6.6 VoiceOver labels in the renderers; wrap UI strings for localization

## 7. Rename (after 1.4)

- [ ] 7.1 Bundle ids, app group, Keychain service, data directory with a one-time move
- [ ] 7.2 `fluidctl`, FluidKit (with a deprecated re-export), `.fluidplugin`, docs

## 8. Beta

- [ ] 8.1 Private beta with about 50 developers
- [ ] 8.2 Public download
