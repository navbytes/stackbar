# Plugin handover

## Why

Store plugins get merged: GitHub folded into PR Cockpit (11-02), and Window
Layouts and Workspaces are merging into one Windows plugin (11-05, Naveen approved the merge
recommendation in "Decide which plugins to combine"). Until now the old plugin
stayed installed and running, the store kept listing it, and the hotkeys and
aliases a person set on its commands were lost, because they are keyed by
plugin id.

## What changes

- `Manifest.replaces: [String]?` names plugins this one takes over.
- The first time such a plugin loads and is on, the host moves the old
  plugin's command preferences (alias, hotkey, switches), palette usage and
  favourites to the new plugin's commands with the same ids, turns the old
  plugin off, posts one notification, and remembers the handover
  (`handovers.json`) so it happens once.
- The old plugin's Settings page says what replaced it and offers Uninstall.
- Stores stop listing a replaced plugin (`PluginIndex.Entry.replaces`), except
  where it is installed.
- Stackbar 0.25.0. No protocol bump: the field is optional and older apps
  ignore it.
