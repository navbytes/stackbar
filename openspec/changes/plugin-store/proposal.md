# The plugin store

## Why

Naveen approved a separate, curated plugins repository,
navbytes/stackbar-plugins, modeled on vee-plugins (plan:
https://claude.ai/artifact/55K7MMncSxc5H8JL1ZdXEJ). Stackbar already installs
signed bundles from any index URL, but the store starts empty, an index can't
say which Stackbar a plugin needs, nothing checks for updates, and nothing can
withdraw a bad release.

## What changes

- `Manifest` gains optional `minimumStackbar` and `homepage`. Unset fields are
  left out of the JSON, so existing bundle signatures still verify.
- Index format 2: `homepage`, `generated`, per-entry `category`, `surfaces`,
  `minimumStackbar`, `screenshot`, `homepage`, `updated`, a `revoked` list and
  an Ed25519 `signature` over the whole index. Every new field is optional;
  format 1 indexes still read and 0.9 apps still read format 2.
- `stackbarctl index build` walks subfolders (the folder is the category, a
  PNG named after the id is the screenshot), takes `--homepage`, `--revoked`
  and `--key` to sign; `stackbarctl index verify` checks a signature.
- The official index (`OfficialIndex`) is built in, listed first and can't be
  removed. It is used only when signed by the navbytes key compiled into the
  app; until that key exists it is left out.
- The store groups by category, shows screenshots and a README link, says
  "Needs Stackbar X" instead of Install, hides withdrawn versions and offers
  Update for older installs.
- On launch and daily, the app installs updates for store-installed plugins
  (a switch turns this off) and moves withdrawn ones to the Trash with a
  notification. Only a signed index can withdraw a plugin.
- Stackbar 0.10.0, the first version plugins can pin to.

## Not in this change

- The four bundled plugins stay in `Plugins/` (decided 2026-11-01).
- A host-level grant for user-chosen network hosts.
- Key rotation records in the index.
