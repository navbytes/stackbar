# Tasks

## 1. Host
- [x] 1.1 File search section (stackbar #93)
- [x] 1.2 `CommandSpec.rootSearch` / `.fallback`, hand-written decoder, protocol 16; StackbarKit modifiers
- [x] 1.3 Root search sessions in `PaletteSession`; rows as entries; side table to the view's action
- [x] 1.4 Fallback section; the query fills the first argument
- [x] 1.5 Grid tiles and 2D arrows; split preview pane
- [x] 1.6 Compact mode setting and window resize
- [x] 1.7 Authoring guide and llms.txt
- [x] 1.8 Tests from design.md

## 2. Plugins (stackbar-plugins)
- [ ] 2.1 Clipboard History and Snippets: `.rootSearch()`, version bumps
- [ ] 2.2 Web Search plugin (fallbacks)
- [ ] 2.3 Window Layouts plugin
- [ ] 2.4 Emoji plugin (grid, preview)
- [ ] 2.5 Pin to the merged stackbar commit; `minimumStackbar` 0.20.0

## 3. Built-ins to plugins
- [x] 3.1 `installedApps`, `findFiles` + `.fileSearch`, `Row.fileIcon`, `rootSearch(section:)`, prefix-led plugin sections, root rows' ⌘K
- [x] 3.2 Remove SystemItems, FileSearch, PaletteCalculator from the palette; MacFinding services
- [x] 3.3 Carry and install-once the core plugins (`BundledStore.corePluginIDs`)
- [ ] 3.4 Applications, Calculator, File Search plugins (stackbar-plugins)

## 4. Release and check
- [ ] 4.1 Release 0.20.0 (0.19.0 shipped before this change; Naveen's call)
- [ ] 4.2 Mac checklist from design.md (Naveen's Mac)
