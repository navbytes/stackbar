# Launch phase 1: a credible switch from Raycast

## Why

Naveen asked (2026-11-05) what must change before Stackbar can be advertised
as a Raycast alternative and Spotlight replacement. The gap analysis
("Stackbar as a Raycast alternative: launch gap analysis",
https://claude.ai/artifact/MY9RXfR3FZjvwSUkm6Fo3W) found six blockers and
proposed four phases. He approved Phase 1: a Raycast user can put Stackbar on
⌘Space and not miss the basics.

Today the palette hotkey is fixed at ⌃⌥Space, a new install has no first run,
Settings sends people back to Spotlight ("Use macOS for These"), plugins can
show a HUD only by returning a command result, and nothing can lock the Mac,
sleep it or empty the Trash.

## What changes

Host (Stackbar 0.22.0, protocol 18):

- **Palette hotkey.** A recorder in Settings › General and in the welcome
  window. Stored as a hotkey spec (`ctrl+option+space` by default). Choosing
  ⌘Space checks Spotlight's own shortcut and, while it is still on, offers to
  open Keyboard › Keyboard Shortcuts › Spotlight; the palette keeps ⌃⌥Space
  until ⌘Space is free.
- **Welcome.** On first launch a window walks through the hotkey, the
  starter plugins and launch at login, and ends by opening the palette.
- **`Stackbar.hud(_:)`.** A plugin shows the same HUD a command result shows,
  from any action (a panel button, a root-search row). At most 30 a minute.
- **System actions.** `Stackbar.system(_:)` with a new `.systemActions`
  capability: lock the screen, sleep, sleep displays, start the screen saver,
  restart, shut down, log out, empty the Trash, toggle dark mode, hide other
  apps, quit other apps, eject disks.
- **Settings.** "Use macOS for These" becomes "Stackbar replaces", saying
  which command does each thing, and keeps only what macOS still does better.
- **Repo.** CONTRIBUTING, SECURITY, CODE_OF_CONDUCT, issue and PR templates;
  a README that leads with the launcher.

Plugins (stackbar-plugins):

- **System Commands**, a new store plugin: root commands for every system
  action, destructive ones asking first.
- **Calculator**: currency conversion (rates from frankfurter.app, cached a
  day) and times across zones ("5pm london in tokyo").

## Not in this change

Self-update, crash reports, export and import, Raycast import and the site
are Phases 2 and 3. Snippet expansion, window switching, menu-item search and
the Ask AI plugin are Phase 4.
