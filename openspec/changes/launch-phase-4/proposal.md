# Launch phase 4: depth, beta and 1.0

## Why

Phases 1 to 3 made Stackbar a credible switch from Raycast and told that
story on stackbar.app; 0.24.0 added snippet keyword expansion. What is left
before a public 1.0 is the daily commands a switcher still misses (switching
to a window, searching the front app's menus, a handful of store plugins),
install hygiene, a lane for outside authors, and a private beta. Plan
approved by Naveen on 2026-11-05 (doc: "Stackbar Phase 4 plan: depth, beta
and 1.0").

## What changes

- **0.25.0, app:** `Stackbar.focusWindow` (needs `.windows`) and a new
  `.menus` capability with `Stackbar.menuItems()` and
  `Stackbar.pressMenuItem` (protocol 20); palette keys ⌃N/⌃P, ⌃J/⌃K, ⌘, and
  ⌘⌫; Move to Applications at launch; "Install" for `stackbarctl` in
  /usr/local/bin; "Remove all data".
- **Store, alongside 0.25:** Switch Windows, Search Menu Items, Kill Process,
  Recent Projects, Timers, Script Commands, Browser Bookmarks and Tabs.
- **0.26.0:** Color Picker and Dictionary host calls and plugins, a VoiceOver
  pass, the community publishing lane, a Sparkle beta channel.
- **0.9 beta** for about 50 people for two weeks, then **1.0** when the bar
  in the plan is met.

## Out of scope

Ask AI (after these), team features, cloud sync, other platforms.
