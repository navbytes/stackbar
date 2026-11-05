# Design

## Release build

`bundle.sh` stays for quick local builds. `release.sh`:

1. `xcodegen generate`, then `xcodebuild` Release with signing off.
2. Embed stackbarctl, StackbarKit and the bundles (`embed-stackbarkit.sh`),
   and prebuild the carried plugins' helpers.
3. Write `SUPublicEDKey` and `SentryDSN` into Info.plist when given.
4. Sign inside out with the hardened runtime and a secure timestamp:
   Sparkle's XPC services, Autoupdate and Updater.app, the frameworks, the
   widget (with its entitlements), the helpers, stackbarctl, then the app.
5. Zip, notarize, staple, zip again.

Signing ourselves rather than through Xcode avoids provisioning profiles in
CI, and is the same order Sparkle documents.

## Updates

- `SUFeedURL` is `https://github.com/navbytes/stackbar/releases/latest/download/appcast.xml`.
  "Latest" skips pre-releases, so a pre-release never reaches Sparkle users.
- `CFBundleVersion` stays equal to the marketing version; Sparkle's
  comparator orders `0.22.0 < 0.23.0` correctly.
- The appcast is written by `scripts/appcast.py`: one item, with the EdDSA
  signature (Ed25519 over the zip, via `cryptography`), length, minimum
  macOS 26, and the CHANGELOG section as HTML.
- The private key is a base64 32-byte Ed25519 seed. Naveen creates it with
  `openssl rand -base64 32 | gh secret set SPARKLE_PRIVATE_KEY -R navbytes/stackbar`;
  the workflow derives the public key, so nothing else needs setting.
- In the app, `Updater` wraps `SPUStandardUpdaterController` behind
  `#if canImport(Sparkle)`; without Sparkle or without a public key it reports
  that updates come from Homebrew or the site.

## Crash reports

`CrashReports` wraps Sentry behind `#if canImport(Sentry)`. It starts only
when `crashReportsAllowed` is true and a DSN is in Info.plist. Events carry
the app and macOS version; plugin names and logs are never attached.

## Export and import

`SettingsArchive` (HostCore, tested on Linux): a versioned JSON document with
the installed plugin ids and sources (store id and version, or local file),
each plugin's settings values, palette favourites and command hotkeys, and the
app's own defaults keys from an allowlist. Import installs missing store
plugins, writes settings, and leaves secrets for the user to enter again.
