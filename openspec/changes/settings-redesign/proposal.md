# Settings that look like they ship with macOS

## Why

The plugins look designed; the window around them did not. Settings was a
boxed `TabView` in a hand-made window, the plugin list was text with a dot,
half of a plugin's page hid behind a "Settings | About" control, and a
plugin's hotkeys lived in another tab. On macOS 26 it got none of the sidebar
and toolbar that System Settings, Raycast and Xcode have. Naveen asked
(2026-11-03) for Settings and the Store to look professional and picked this
change first, then the Store window (`store-window`).

Proposal with mockups: https://claude.ai/artifact/2DqRFPNSEP4bbD1GsAu45c

## What changes

- Settings becomes a `NavigationSplitView`: app sections at the top of the
  sidebar (General, Commands & Hotkeys, Agents, Privacy & Secrets, Store),
  each with a coloured symbol tile, then every plugin with its own icon tile
  (manifest `accent` and `symbol`) and a status dot. The sidebar searches.
- One page per plugin, in order of use: header with icon, summary, status and
  an on/off switch; approval and build problems; the plugin's own `settings`
  surface; menu bar and shortcuts (its commands with alias and hotkey);
  permissions as icon rows; secrets; Diagnostics folded away; Rebuild, Edit
  with Claude, Show in Finder, Uninstall.
- A plugin's `settings` sections draw as grouped boxes with trailing switches
  and pickers (`stackbarGroupedSections`), so they read as part of the page.
  No protocol change; panels draw sections as before.
- General gets an About header and grouped rows; Agents gets its own page with
  a Copy button and the plugins that offer tools; a new Privacy & Secrets page
  lists every kind of access across plugins and every secret.
- One `PluginIcon` for Settings and the Store.

## Not in this change

- Moving the Store out of Settings into its own window (`store-window`).
