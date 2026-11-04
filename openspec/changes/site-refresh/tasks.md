# Tasks

## 1. Previews (stackbar, 0.17.0)
- [x] 1.1 `PreviewScene<Plugin>`, `StackbarPlugin.previews`, `--previews`, preview mode from `STACKBAR_PREVIEW` (no refreshes)
- [x] 1.2 `PluginProcess.readPreviews`, `stackbarctl previews`, `stackbarctl render --preview`
- [x] 1.3 Snapshot stand-ins for links, sliders and toggles
- [x] 1.4 Authoring guide and llms.txt; tests
- [x] 1.5 Release 0.17.0 so plugins with previews can require it

## 2. Store renders (stackbar-plugins)
- [x] 2.1 Previews in all 20 plugins (version bumps, minimumStackbar 0.17.0)
- [x] 2.2 `publish.sh` renders previews light and dark into `site.json`; surface renders use `hero`
- [x] 2.3 README `## Highlights` for the six flagships: Up Next, PR Cockpit, Clipboard, System Monitor, World Clock, App Switcher

## 3. Home hero (site)
- [x] 3.1 Live menu bar: six plugins, real menu bar and panel renders, auto-advance, pause on hover, click to jump, reduced motion

## 4. Plugin page (site)
- [x] 4.1 Store loader reads previews and highlights
- [x] 4.2 Hero at full size with the real menu bar render
- [x] 4.3 Highlights, commands and hotkeys, agent tools, version history, FAQ

## 5. Demo loops
- [x] 5.1 `render --frames` records a scripted preview as an animated PNG (`--hold`, `--wait`; copies reach previews)
- [ ] 5.2 Store: `demos.json` scripts, publish renders them into `site.json` `demos`
- [ ] 5.3 Site: the hero and plugin pages play a demo where there is one
