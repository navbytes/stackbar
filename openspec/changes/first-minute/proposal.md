# First minute works

## Why

The 2026-11-07 replacement-gap report (project files
`replacement-gaps/report.md`) found that a new user's first minute is where
Stackbar loses switchers from Raycast, Spotlight and Hammerspoon: the core
plugins wait for an approval nobody is asked for, Safari is missing from
Applications, File Search hides iCloud Drive and Dropbox, window snaps run
out after ten a minute, and hotkeys can't use arrows. Naveen said "ok, lets
fix them" on 2026-11-07 and reported the Safari bug in the same message.

## What changes

- Safari (and any app in the App Cryptex, or any browser Launch Services
  knows) is listed by `installedApps()`.
- G1: core plugins are approved as `BundledStore.installCore` installs them.
- G2: `arrangeWindows` allows 120 calls a minute and reads only the windows of
  the apps it places.
- G3: hotkeys take the arrows, Return, Tab, Escape, Delete and US punctuation
  keys; ⌘Tab and ⌘⇧Tab stay refused.
- G5: File Search keeps `~/Library/Mobile Documents` and
  `~/Library/CloudStorage`, and names them "iCloud Drive/…", "Dropbox/…".
- G18: the agent gateway is off on a new Mac; Quicklinks site icons default
  off (plugin).
- G9, G4, G14 (docs): a Permissions page, a Hyper key section, "Coming from
  Spotlight".
- Plugins: Calculator mixed units (G19), Quicklinks "Search Google" fallback
  (G20).

No protocol change. Manifests that use the new hotkey keys need
`minimumStackbar: "0.32.0"`.

## Out of scope

A host-owned Hyper key (G4 proper), a permissions step in Welcome, date math
in Calculator, a "Copied" HUD for every copy action: later batches.
