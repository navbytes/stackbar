# Tasks

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
- [ ] 4.2 Tag 0.10.0 (stackbar-plugins pins the 0.10.0 commit until the tag exists; sessions cannot push tags)

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
- [ ] 7.6 Publish them from stackbar-plugins and check an install from a clean plugins folder on a Mac
