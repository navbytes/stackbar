# Tasks

## 1. Host (navbytes/stackbar)
- [x] 1.1 `Manifest.replaces` with checks; `PluginIndex.Entry.replaces`
- [x] 1.2 `CommandPreferences`, `PaletteUsage`, `PaletteFavorites` move by plugin id
- [x] 1.3 `PluginHandover` (once, remembered) with tests
- [x] 1.4 App: hand over on load, turn the old plugin off, notify; Settings banner with Uninstall
- [x] 1.5 Store hides replaced plugins unless installed
- [x] 1.6 Authoring guide, llms.txt, CHANGELOG (0.25.0)
- [x] 1.7 `Stackbar.open` takes `stackbar://store/<id>` and `stackbar://settings` without the scheme (Applications links to App Switcher)

## 2. Plugins (navbytes/stackbar-plugins)
- [ ] 2.1 Workspaces becomes Windows and takes over Window Layouts (`replaces`), keeping its command ids
- [ ] 2.2 Window Layouts README points to Workspaces; App Switcher link from Applications

## 3. Check
- [ ] 3.1 `swift build && swift test`
- [ ] 3.2 On Naveen's Mac: hotkeys carry over, Window Layouts turns off
