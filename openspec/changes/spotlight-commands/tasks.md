# Tasks

## 1. Spike on macOS 26 (before anything else)
- [ ] 1.1 A throwaway `RunCommandIntent` over a two-item `EntityStringQuery`: shows in Spotlight ⌘3, entity search as you type
- [ ] 1.2 Quick Key saved for the intent with one entity chosen
- [ ] 1.3 `IndexedEntity` donated to a named index shows in ⌘Space results; opening it runs the `OpenIntent`
- [ ] 1.4 Running with the app quit; `opensIntent` from a background intent
- [ ] 1.5 Record results in design.md and adjust the plan

## 2. Shared core (Linux-tested)
- [ ] 2.1 Entity mapping from `CommandSpec`; index diff; reuse `CommandSearch`
- [ ] 2.2 Preferences: per-command and global "Show in Spotlight"

## 3. App
- [ ] 3.1 `CommandEntity`, `PluginEntity`, queries (string, suggested, indexed reindex)
- [ ] 3.2 `RunCommandIntent`, `OpenCommandIntent`, `OpenPluginIntent`, dialogs and errors
- [ ] 3.3 `StackbarShortcuts` and `updateAppShortcutParameters()` on change
- [ ] 3.4 `CommandSpotlightIndexer` with priorities from frecency
- [ ] 3.5 Donate on every run (palette, hotkey, link)
- [ ] 3.6 Settings switches

## 4. Build and docs
- [ ] 4.1 `scripts/bundle.sh` on `xcodebuild`; CI builds the Xcode project
- [ ] 4.2 Docs: Spotlight, Shortcuts, Quick Keys; `stackbarOnly`
- [ ] 4.3 Manual checklist from design.md on Naveen's Mac
