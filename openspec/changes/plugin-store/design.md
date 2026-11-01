# Design

## Versions

StackbarKit ships inside Stackbar.app and plugins compile against that copy,
so the Stackbar version is the StackbarKit version. `VersionNumber` compares
dotted versions part by part (`0.10.0` > `0.9.3`), with a pre-release suffix
sorting before its release. The wire protocol version stays separate.

## Signing the index

`signedBytes()` is `stackbarindex/1\n` followed by the index without its
signature, as JSON with sorted keys and unescaped slashes, the same canonical
form bundles use. The publisher signs with the same key as its bundles.
Signing needs CryptoKit, so it runs on macOS; verification also needs it,
which is fine because only the macOS app and macOS CI verify.

## Trust

- The official source has a public key; user-added sources don't, and are
  read unsigned as before.
- Withdrawals are honoured only from a signed source, so anyone hosting an
  index can't make the app trash someone else's plugin.
- Updates are offered only by an entry with the installed record's publisher
  name; the publisher pin then refuses a different key regardless.
- An index whose format is newer than the app understands is refused rather
  than half-read.

## Updates

Only plugins in `installed.json` (installed from a store or a bundle) are
checked. Bundled plugins update with the app (PR #18). New capabilities in an
update wait for approval through the capability ledger as before, so a quiet
update can't widen what a plugin may do.
