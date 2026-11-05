# Third-party code

Stackbar keeps outside code to a short list, and every piece is pinned so a
moved tag or a look-alike repository can't change what we build. Check this
list when you add or bump anything.

## In the app

Only the Xcode release app links these. `Package.swift`, StackbarKit, the
protocol and plugins depend on nothing outside this repository.

| Package | Source (verified against) | Pin | Integrity |
|---|---|---|---|
| Sparkle 2.10.1 | github.com/sparkle-project/Sparkle (linked from sparkle-project.org) | commit `ab7d712` in `project.yml` | binary target SHA-256 `4c2e48a3…022a` in its Package.swift, checked by SwiftPM |
| Sentry 9.31.0 | github.com/getsentry/sentry-cocoa (linked from docs.sentry.io) | commit `2f64c77` in `project.yml` | binary target SHA-256 `86dde13e…3237` in its Package.swift, checked by SwiftPM |

To bump one: open the project's own site and follow its link to the
repository (don't search for it), take the commit the release tag points to
(`git ls-remote <repo> refs/tags/<version>`), put that commit in
`project.yml`, and note the version beside it.

## In CI

- GitHub Actions are all from `actions/*` and pinned by commit, with the tag
  in a comment.
- The release job's crypto (Sparkle's Ed25519 key and signatures) uses Apple's
  CryptoKit through `scripts/ed25519.swift`; no Python or npm package is
  installed there. `scripts/appcast.py` uses only Python's standard library.
- XcodeGen comes from Homebrew's core formula, which checks the release
  archive's SHA-256.
- The site's npm packages are locked with integrity hashes in
  `site/package-lock.json`, all from registry.npmjs.org, and installed with
  `npm ci`.
