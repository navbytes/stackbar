# Design

## Trust

A bundle's signature covers its manifest and source. A helper cannot be
rebuilt and compared on a Mac without a compiler, so it carries its own
signature by the same publisher:

```
stackbarhelper/1\n<id>\n<version>\n<sourceDigest>\n<stackbarKit>\n<protocol>\n<arch>\n<sha256>
```

The app accepts a helper only when all of these hold:

- the record verifies with the publisher key of the bundle being installed,
  or with the key pinned for that plugin id when the plugin is already
  installed;
- the record's `sourceDigest` is the SHA-256 of the exact source in the
  plugins folder;
- the downloaded bytes match `sha256`.

So an index or `helpers.json` hosted by anyone cannot swap a binary. Only the
publisher who signed the source can vouch for a binary of it. That is the same
trust the user already gives that publisher's source, which they cannot read
in full either.

## Matching

`stackbarKit` is `PluginBuilder.frameworkDigest`: a digest of the StackbarKit
and StackbarProtocol sources. It is the same value that keys local builds,
because a helper built against another StackbarKit is not the same program.
`PluginBuilder.build(source:)` looks for a helper in this order:

1. a local build that is already cached (unchanged);
2. `Prebuilt/<sourceDigest>-<stackbarKit>` in the app (`Resources/StackbarKit`)
   or in the build cache. This is an exact match, preferred even with a
   toolchain, because it skips a slow first build;
3. with a toolchain, a local build (unchanged);
4. without one, `Prebuilt/<sourceDigest>-p<protocol>` in the build cache: a
   helper built for another StackbarKit that speaks this host's protocol. This
   covers the hour between a Stackbar release and the store building for it;
5. otherwise, a failure that names the missing Command Line Tools.

"Toolchain present" on macOS means `STACKBAR_SWIFT` is set or
`xcode-select -p` succeeds. `xcode-select` is a real binary that never shows
the install dialog that the `/usr/bin/swift` shim shows.

## Publishing (stackbar-plugins)

`scripts/helpers.sh` runs on macos-26 in the `release` environment:

- It reads the latest Stackbar releases (`HELPER_RELEASES`, default 4). For
  each one it builds the slim StackbarKit package the app embeds
  (`Packaging/StackbarKit-Package.swift` plus the two source folders), so the
  digest matches the app's.
- For each StackbarKit digest it uses a release `helpers-<digest16>` on
  stackbar-plugins, with one asset per plugin version,
  `<id>-<version>-<source12>`.
- It builds each plugin's current version that is not there yet, with
  `stackbarctl helper build`, which signs the record, then uploads the binary.
  A plugin that does not build against an older StackbarKit is skipped with
  a warning.
- It keeps records on gh-pages at `helpers/<digest16>/*.json`, removes digests
  that are no longer targets, and writes `helpers.json`. Release assets stay.

Binaries live in releases, not on gh-pages, so the Pages branch does not grow
by megabytes on every Stackbar release.

## App flow

- **Install or update from the store:** download the bundle, then fetch the
  helper (exact, or protocol-compatible when there is no toolchain). Without a
  toolchain and without a usable helper, the install fails with "isn't
  prebuilt for this Stackbar yet" and an automatic update stays pending.
  Otherwise, write the source, save the helper, and load.
- **Store check (launch, then daily):** for each installed store plugin whose
  source still matches, fetch the exact helper when it is missing. Fetch a
  protocol-compatible one only without a toolchain. Reload a plugin that
  failed to start once its helper arrives.

## Limits

- Apple Silicon only (`arm64`), like the app.
- Only each plugin's current version is built. Someone who keeps an older
  version with automatic updates off and then updates the app needs the
  update, or a toolchain.
