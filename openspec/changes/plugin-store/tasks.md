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
