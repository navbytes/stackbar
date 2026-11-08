# App switcher

## Why

Naveen asked on 2026-11-03 whether rcmd (lowtechguys.com/rcmd) can be built in
Stackbar. In rcmd, you hold Right ⌘ and press an app's first letter to bring
that app to the front, or to open it if it isn't running. Pressing the letter
again hides the app or moves on to the next app with the same letter.
Developers who live on the keyboard switch apps hundreds of times a day, and
⌘Tab gets slower with every app that's open.

Reliability was the open question, so a spike tested it on Naveen's Mac
(`scripts/app-switch-probe.swift`, PR #73):

- From an accessory process like Stackbar, a plain
  `NSRunningApplication.activate` brought the target app to the front in
  30 of 30 automatic switches (median 17ms).
- It also worked in 16 of 16 real Right ⌘ key presses caught by an event tap.
- macOS didn't switch the tap off during either run, and Secure Input never
  came on.

So the switcher needs no private API.

## What changes

- **A key layer in the host** (protocol 14, Stackbar 0.16.0). A plugin
  registers a layer: a trigger key it holds (Right ⌘ by default) and a map
  from a letter or digit to the apps it switches to. The host owns a single
  event tap and decides on each key press on the spot, without waiting on
  the sandboxed plugin:
  - It brings the running app to the front.
  - It opens the app when nothing on that letter is running and the binding
    allows it.
  - It cycles through the apps on that letter.
  - When the app is already in front, it hides the app, cycles its windows,
    or does nothing, depending on the layer.
  - Letters with no binding pass through, so Right ⌘ + C still copies.
  - Holding the trigger, an assign key (Right ⌥) and a letter runs one of
    the plugin's commands with the letter and the frontmost app, which is how
    the plugin learns custom letters.
  - Holding the trigger on its own shows an overlay with the letter map.
- **App calls**: `Stackbar.runningApps()`, `Stackbar.activateApp(_:launch:)`
  and `Stackbar.hideApp(_:)`. They need a new `.apps` capability. The layer
  needs a new `.keyLayer` capability.
- **An `.apps` trigger**: the plugin refreshes when an app opens or quits, so
  it can re-letter.
- **Status**: `Stackbar.keyLayerStatus()` says whether the layer is listening,
  whether Accessibility access is missing, and which app holds Secure Input
  when one does (macOS blocks every key listener while it is on).
- **An App Switcher store plugin** (`Productivity/AppSwitcher` in
  stackbar-plugins):
  - It assigns letters automatically from app names, and you can pin your
    own.
  - Settings choose the trigger key, what a second press does, whether
    pinned apps open when they aren't running, and the overlay.
  - The panel shows the letter map and the status.

## Not in this change, on purpose

- Jumping between Spaces or moving windows to them. It needs private SkyLight
  calls; Workspaces skipped them for the same reason.
- A window grid or Exposé with thumbnails. It needs Screen Recording.
- Fuzzy search for apps. Spotlight covers it (see the Raycast gap analysis).
- Browser tab, terminal and project search (rcmd's Lenses).
- Saved window sets (rcmd's Stages). Workspaces does this.
- Caps Lock as the trigger. The macOS 26.4 betas broke the usual ways of
  remapping it.
