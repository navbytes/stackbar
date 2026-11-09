---
title: Run your own store
description: Publish plugins for your team from any web server or folder, signed so updates and withdrawals are trusted, and behind a token when it is private.
group: Build plugins
order: 4
---

A store is a folder of signed plugin bundles with an `index.json` beside
them. Any HTTPS server can host one: GitHub Pages, S3, an internal web
server, or a shared folder for a quick test. Stackbar reads it the same way
it reads the official store, and plugins from it run in the same sandbox and
ask for the same permissions.

## 1. Make a publisher key

```sh
stackbarctl keygen --key ~/team-store.key
```

It prints the public key. Keep the private key out of the repository: a CI
secret or your password manager.

## 2. Sign each plugin and build the index

```sh
mkdir -p store/Developer
stackbarctl sign Deploy.swift --publisher "Acme" --key ~/team-store.key -o store/Developer/Deploy.stackbarplugin
stackbarctl index build store --name "Acme" --key ~/team-store.key
```

A subfolder becomes the plugin's category. `index build` writes
`store/index.json` and signs it, and refuses a plugin whose manifest isn't
ready to publish. Upload the whole `store` folder.

Run both again for every new version; a published version should never
change.

## 3. Add it in Stackbar

Settings › Store › Plugin Sources › **Add**, with your public key after the
URL:

```
https://plugins.acme.dev/index.json#key=<public key>
```

With `#key=`, Stackbar refuses the index unless your key signed it, and only
then can it withdraw a version (add it to the file you pass to
`index build --revoked`). Without the key, the store still works, but
nothing it says can take a plugin away.

## A private store

Put the store behind a login that takes a bearer token, keep the token in
Stackbar's secrets, and name it with `#auth=`:

```sh
stackbarctl secret set ACME_STORE_TOKEN
```

```
https://plugins.acme.dev/index.json#key=<public key>&auth=ACME_STORE_TOKEN
```

Stackbar sends `Authorization: Bearer <token>` with every request under the
index's folder on that host (the index, bundles, `helpers.json` and
`site.json`) and to nowhere else. Separate several options with `&`.

## Prebuilt helpers (optional)

Without them, Stackbar builds each plugin on the Mac that installs it, which
needs Xcode or the Command Line Tools. To skip that, build the helpers on a
Mac and list them in `helpers.json` beside the index:

```sh
stackbarctl helper build Deploy.swift --key ~/team-store.key -o store/helpers/deploy --url helpers/deploy
```

It prints the helper's signed record. Collect the records into
`store/helpers.json`:

```json
{ "format": 1, "generated": "2026-11-09T00:00:00Z", "helpers": [ … ] }
```

Build them again whenever you update Stackbar's pinned version, since a
helper is tied to the StackbarKit it was built against.
