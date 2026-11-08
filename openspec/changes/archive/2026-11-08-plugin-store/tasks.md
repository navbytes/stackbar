# Tasks

> Archived 2026-11-08. The unticked Mac checks below are tracked in `openspec/mac-checks.md`.

## 1. Protocol and index
- [x] 1.1 `Manifest.minimumStackbar` and `homepage`, optional and checked in `problems`
- [x] 1.2 `VersionNumber`
- [x] 1.3 Index format 2: store fields, `revoked`, signature, `checkInstallable`, `updates`, `byCategory`
- [x] 1.4 Refuse an index format newer than the app; format 1 still reads
- [x] 1.5 `PluginIndex.build(root:)` from category folders with screenshots

## 2. CLI
- [x] 2.1 `stackbarctl index build` recursive, `--homepage`, `--revoked`, `--key`
- [x] 2.2 `stackbarctl index verify`; `index search --public-key`; `install --index` checks version and withdrawals

## 3. App
- [x] 3.1 `OfficialIndex` built in, first, not removable, verified against its key
- [x] 3.2 Store pane: categories, screenshots, homepage, Needs Stackbar X, Update, remove an added index
- [x] 3.3 Daily update check; automatic updates with an off switch; withdrawn plugins to the Trash
- [x] 3.4 Fill in `OfficialIndex.publicKey` once Naveen generates the navbytes key

## 4. Release
- [x] 4.1 Stackbar 0.10.0
- [x] 4.2 Tag 0.10.0 (stackbar-plugins pins the 0.10.0 commit until the tag exists; sessions cannot push tags) (moot: stackbar-plugins pins by commit and later releases are tagged)

## 5. Docs and tests
- [x] 5.1 Authoring guide and llms.txt: `minimumStackbar`, `homepage`
- [x] 5.2 Tests: versions, manifest compatibility, index build, gating, withdrawals, review, signing (macOS)

## 6. Store fixes (Naveen, 2026-11-01)
- [x] 6.1 Uninstall drops the install record, stops every copy and trashes every file
- [x] 6.2 A "Turned on" switch per plugin in Settings
- [x] 6.3 Store pane refreshes after install, update and uninstall, with an Uninstall button

## 7. First-party plugins move to the store (Naveen, 2026-11-01)
- [x] 7.1 Clipboard, PR Cockpit, Quicklinks, Snippets, Stay Awake and Up Next live in navbytes/stackbar-plugins with their old ids
- [x] 7.2 `Plugins/` becomes `Tests/Fixtures/BundledPlugins/`, kept for the host tests
- [x] 7.3 `stackbarctl index fetch`; the app build carries their signed bundles for offline first run
- [x] 7.4 `BundledStore`: untouched old copies become store installs of the same id, edited ones stay; per-file settings follow
- [x] 7.5 install.sh stops copying plugin sources; Stackbar 0.11.0
- [x] 7.6 Publish them from stackbar-plugins and check an install from a clean plugins folder on a Mac (published from stackbar-plugins since 2026-11-01)

## 8. Turning plugins off (Naveen, 2026-11-01)
- [x] 8.1 The off setting is kept by plugin id (`PluginSwitches`), so it survives a reinstall, an update or a move; old per-file settings carry over
- [x] 8.2 A plugin that is off isn't built; store updates still install for it
- [x] 8.3 An "Off" badge in the plugin list and the store; Turn On / Turn Off next to Uninstall
- [x] 8.4 Uninstall asks: keep its data, delete its data (storage and sign-ins; shared secrets stay), or turn it off instead

## 9. Store front and release notes (Naveen, 2026-11-03)
- [x] 9.1 The store reads the store's `site.json`: renders per version and each README (description, facts, `## What's new in <version>` notes); stackbar-plugins' publish.sh writes them and lint.py requires a section for the current version
- [x] 9.2 A page per plugin (gallery, what it does, what it asks for, details, web page and source links); `stackbar://store/<id>` opens it
- [x] 9.3 A grid of cards with category chips, All / Installed / Updates (n), Update All, a "New and updated" shelf and the plugin sources folded away (`StoreListing`)
- [x] 9.4 What's new on the plugin page, on the card and on the Update button; the website's plugin pages show it too
- [ ] 9.5 Check the store front, a deep link and Update All on a Mac with 0.15.0
