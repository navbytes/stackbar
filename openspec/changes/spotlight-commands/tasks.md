# Tasks

## 1. Spike on macOS 26

Naveen asked for the whole platform at once, so the intents were built
straight away; these checks now run against the real intents on his Mac
(`scripts/install.sh`), and design.md takes what they show.

- [ ] 1.1 A throwaway `RunCommandIntent` over a two-item `EntityStringQuery`: shows in Spotlight ⌘3, entity search as you type
- [ ] 1.2 Quick Key saved for the intent with one entity chosen
- [ ] 1.3 `IndexedEntity` donated to a named index shows in ⌘Space results; opening it runs the `OpenIntent`
- [ ] 1.4 Running with the app quit; `opensIntent` from a background intent
- [ ] 1.5 Record results in design.md and adjust the plan

## 2. Shared core (Linux-tested)
- [x] 2.1 Entity mapping from `CommandSpec`; index diff; search reuses the palette's ranking (`CommandIndexing`)
- [x] 2.2 Preferences: per-command and global "Show in Spotlight"

## 3. App
- [x] 3.1 `CommandEntity`, `PluginEntity`, queries (string, suggested); the index is rebuilt at every launch instead of through `IndexedEntityQuery` reindexing
- [x] 3.2 `RunCommandIntent`, `OpenCommandIntent`, `OpenPluginIntent`, dialogs and errors
- [x] 3.3 `StackbarShortcuts` and `updateAppShortcutParameters()` on change
- [x] 3.4 `CommandSpotlightIndexer` with priorities from frecency
- [x] 3.5 Donate on every run (palette, hotkey, link)
- [x] 3.6 Settings switches

## 4. Build and docs
- [x] 4.1 CI builds the Xcode project unsigned and checks the metadata (`scripts/check-xcode.sh`); `scripts/install.sh` already builds with Xcode. Moving `bundle.sh` to `xcodebuild` stays with release task 3.3, which owns signing
- [x] 4.2 Docs: Spotlight, Shortcuts, Quick Keys; `stackbarOnly`
- [ ] 4.3 Manual checklist from design.md on Naveen's Mac
