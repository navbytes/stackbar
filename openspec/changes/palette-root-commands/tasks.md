# Tasks

## 1. Host
- [x] 1.1 Panel affordances out of `PaletteIndex.all`; no Panel Actions section
- [x] 1.2 "Open <Plugin>" row for every plugin with a panel
- [x] 1.3 `inRootSearch` optional + `mainSearch` key + migration; `RootSearchGate` defaults
- [x] 1.4 `CommandSpec.defaultAlias`, `Command.alias(_:)`, protocol 27; effective alias; symbol aliases
- [x] 1.5 Alias-scoped root search (feed one command, leads)
- [x] 1.6 Fallback list (default, order, threshold); Tab unchanged
- [x] 1.7 Store suggestions only when nothing installed matches
- [x] 1.8 Settings → General: Main Search and Fallbacks lists
- [x] 1.9 Tests, authoring guide + llms.txt, surface parity, CHANGELOG

## 2. Plugins (stackbar-plugins, after the host release)
- [ ] 2.1 Standalone panel actions become commands
- [ ] 2.2 Default aliases for root-search plugins
- [ ] 2.3 Version bumps, minimumStackbar, pin

## 3. Mac check
- [ ] 3.1 Type a few letters: only commands, apps, files, sums; no toggles
- [ ] 3.2 `gs <repo>` shows Git Sync rows with its switch off
