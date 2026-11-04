# Prebuilt store plugins

## Why

Stackbar compiled every plugin on the user's Mac, including the ones from the
store. That means a Mac with neither Xcode nor the Command Line Tools ran no
plugin at all. The app opened and the store browsed, but each plugin showed
"could not start" with a raw xcrun error, and macOS could pop up its
"install developer tools" dialog. Naveen asked (2026-11-04) whether Stackbar
works on a Mac without Xcode, and chose prebuilt store plugins as the fix.

## What changes

- **Prebuilt helpers.** The store publishes a compiled helper for each plugin
  version and each recent StackbarKit. Each helper is described by a record that
  the plugin's publisher signs. The record covers the plugin id, the version,
  the source digest, the StackbarKit digest, the protocol version, the
  architecture, and the binary's SHA-256.
- **The app prefers a helper over a build.** `PluginBuilder` looks for a
  prebuilt helper for the exact source and StackbarKit before it compiles.
  It only compiles when there is no helper and a toolchain is present.
- **Downloads.** Before the app installs or updates a store plugin, it
  downloads that plugin's helper from `helpers.json`, beside the index. The
  helper is checked against the record's digest and against the bundle's
  publisher key. After an app update changes StackbarKit, the store check
  fetches new helpers for the plugins already installed.
- **The app's own plugins.** The release build prebuilds the first-party
  bundles and the examples the app carries into `Resources/StackbarKit/Prebuilt`,
  signed with the app. A new Mac runs them offline.
- **No toolchain.** Without Swift, the app never calls `/usr/bin/swift`, so no
  system dialog appears. It falls back to a helper built for the same protocol
  version. If there is no helper either, it says plainly what is missing.
  If no helper exists yet for an update, the update waits instead of breaking
  a plugin that works.
- **stackbarctl.** New commands: `stackbarctl helper kit`, `helper build` and
  `helper prebuild`. `doctor` now reports a missing toolchain as needed only
  for writing plugins.
- **stackbar-plugins.** A Helpers workflow runs hourly and after each publish.
  It builds every current plugin against the StackbarKit of the latest
  Stackbar releases, uploads the binaries as release assets, and writes
  `helpers.json` to gh-pages.

## Not changing

- Plugins you write or edit yourself still build locally and need Xcode or
  the Command Line Tools. A changed source never matches a prebuilt helper.
- Every helper is still signed ad hoc into the App Sandbox on the Mac that
  runs it, from its manifest, the same way a locally built helper is.
- The bundle and index formats are unchanged. `helpers.json` is a separate file
  that older apps ignore.
