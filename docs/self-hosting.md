# Run Stackbar inside your organization

An organization that can't fork (forks of a public repository are public) or
can't install from outside can run its own copy of Stackbar and of its plugin
store. Each copy is a private clone, with its own store, signing key, Apple team
and runners. **It only adds files and never edits an upstream one.** That way,
merging new upstream versions never conflicts.

What your copy adds:

| Repository | Added files |
| --- | --- |
| stackbar | `Packaging/distribution.override.json` |
| stackbar-plugins | `store.override.json`, a deploy workflow for your host, your own plugin folders |

Everything else is repository variables and secrets.

## What stays the same

Your build keeps the bundle id `io.navbytes.stackbar`, the `stackbar://` links
and the plugin ids. So settings, approvals and secrets work the way they do
upstream. You don't need your own bundle id to sign with your own Apple team,
because Developer ID apps outside the App Store don't register bundle ids.

The one catch is that a Mac can't have your build and the public build
installed side by side.

The settings are baked in when the app is built, and its code signature covers
them. No environment variable or user setting can point an installed app at
another store, key or update feed.

## 1. Clone both repositories

```sh
git clone https://github.com/navbytes/stackbar && cd stackbar
git remote rename origin upstream
git remote add origin https://github.com/<org>/stackbar   # an empty private repository
git push origin main
```

Do the same for `navbytes/stackbar-plugins`. Push `main` only: not the tags
(your Release workflow makes your own) and not `gh-pages` (your store is built
fresh and signed with your key).

## 2. Your plugin store (stackbar-plugins)

1. Make a publisher key: `stackbarctl keygen --key <file>`. Store the private half as
   the secret `STACKBAR_PUBLISHER_KEY` in an environment named `release`,
   limited to `main`, and keep a backup. You'll need the public half in step 3.
2. Add `store.override.json` with the keys you change (the defaults are in
   `store.json`):

   ```json
   {
     "name": "Example Corp Plugins",
     "publisher": "Example Corp",
     "homepage": "https://github.com/example-corp/stackbar-plugins",
     "website": null,
     "stackbar": "https://github.com/example-corp/stackbar",
     "idPrefixes": ["io.navbytes.stackbar.plugins.", "com.example.stackbar."],
     "exclude": ["Productivity/AskAI"],
     "helpersURL": "helpers-bin"
   }
   ```

   - `exclude` keeps upstream plugins out of your store without deleting their
     folders. A deleted folder would conflict with every upstream change to it.
   - `helpersURL` is where the app downloads prebuilt plugins from. With
     `helpers-bin`, they sit beside `index.json`, so one host and one token
     serve the whole store. Upstream uses GitHub release assets, which a
     private repository won't serve to the app.

3. If your stackbar repository is private, add a secret `STACKBAR_REPO_TOKEN`:
   a fine-grained PAT with contents read on it. CI uses it to fetch StackbarKit.
4. Publish runs on every push to `main` and writes the signed store to the
   `gh-pages` branch of your private repository. Add a workflow of your own
   that copies it to your internal host. `scripts/export-store.sh <dir>` puts
   `gh-pages` and the prebuilt helper binaries together in one folder, ready
   to upload:

   ```yaml
   # .github/workflows/deploy-store.yml (your copy only)
   name: Deploy store
   on:
     workflow_run:
       workflows: [Publish, Helpers]
       types: [completed]
     workflow_dispatch:
   jobs:
     deploy:
       runs-on: ${{ vars.LINUX_RUNNER || 'ubuntu-latest' }}
       steps:
         - uses: actions/checkout@v4
         - run: scripts/export-store.sh "$RUNNER_TEMP/store"
           env:
             GH_TOKEN: ${{ github.token }}
         - run: <upload "$RUNNER_TEMP/store" to https://plugins.example.com/>
   ```

   Don't use private GitHub Pages: they need a browser sign-in, which the app
   can't do. If your host needs a token, set `store.authSecret` in the app's
   override (section 3), and each person adds that secret in Stackbar's settings.
5. Add your own plugins as new folders, `<Category>/<Name>/<Name>.swift`.

## 3. Your app build (stackbar)

1. Add `Packaging/distribution.override.json` with the keys you change (the
   defaults are in `Packaging/distribution.json`):

   ```json
   {
     "teamID": "ABCDE12345",
     "store": {
       "name": "Example Corp Plugins",
       "url": "https://plugins.example.com/index.json",
       "publicKey": "<the public key from stackbarctl keygen>",
       "publisher": "Example Corp",
       "repository": "https://github.com/example-corp/stackbar-plugins",
       "website": null
     },
     "allowUserStores": false,
     "updates": { "feed": null, "betaFeed": null, "manualNote": "Install new versions from Self Service." },
     "links": {
       "website": null,
       "permissionsHelp": null,
       "repository": "https://github.com/example-corp/stackbar"
     }
   }
   ```

   Run `python3 scripts/distribution.py show` to check it. Unknown keys and
   malformed values fail the build.
2. Set these secrets from your Apple Developer account: `APPLE_CERT_P12`,
   `APPLE_CERT_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`,
   `APPLE_NOTARY_PASSWORD`. Managed Macs usually won't open an app that isn't
   notarized.
3. Set `PLUGINS_DISPATCH_TOKEN`, a fine-grained PAT with actions write on your
   plugins repository. Each release then rebuilds the prebuilt plugins.
4. Leave `SPARKLE_PRIVATE_KEY`, `SENTRY_DSN` and `HOMEBREW_TAP_TOKEN` unset,
   unless you host an update feed, run Sentry or keep a tap.
5. Run Release from the Actions tab. Hand the zip to your Macs through MDM or
   Self Service.

## Repository variables

| Variable | Default | Use |
| --- | --- | --- |
| `MACOS_RUNNER`, `LINUX_RUNNER` | `macos-26`, `ubuntu-latest` | your own runner labels |
| `UPSTREAM_REPO` | unset | turns on the daily sync, e.g. `navbytes/stackbar` |
| `PLUGINS_REPO` | `<owner>/stackbar-plugins` | where Release starts Helpers |
| `HOMEBREW_TAP_REPO` | `navbytes/homebrew-tap` | your own tap |
| `SENTRY_ORG`, `SENTRY_PROJECT` | navbytes' | your Sentry project |
| `DEPLOY_SITE`, `BENCHMARK_RELEASES` | off outside navbytes | the website and post-release benchmark |

## Keep up with upstream

Set `UPSTREAM_REPO`, and a secret `SYNC_TOKEN` (a fine-grained PAT with
contents, pull requests and workflows write on the repository). Each day,
Sync from upstream then merges upstream `main` into `sync/upstream` and opens a
pull request.

- **Merge it with a merge commit, never squash or rebase.** stackbar-plugins
  pins StackbarKit by upstream commit, so your stackbar copy must keep upstream's
  commits.
- **Merge stackbar first and release it, then stackbar-plugins.** The plugins'
  `stackbarRevision` bump points at a commit your stackbar copy must already
  have.
- **To sync by hand** from a checkout:
  `git fetch upstream && git merge upstream/main && git push origin main`.
- **A conflict means an upstream file was edited in your copy.** Move that
  change into your override file.

Your override files list only the keys you change, so a key added upstream
takes its upstream default.
