# Design

## 1. PluginInstallation
`PluginInstallation` in HostCore owns the `PluginInstaller`, the
`CapabilityLedger`, `PluginSwitches`, the `StorageStore`, the secret store and
where prebuilt helpers go.
- `install(bundle, helper:)` writes the source, saves the helper and remembers
  the signed manifest for the file.
- `confirm(built, file:)` runs once the plugin is built (the app's
  `PluginController.load`, stackbarctl after its build). For a file just
  installed, a manifest that differs from the signed one undoes the install.
  Any other file passes.
- `uninstall(id, loaded:, deleteData:, providers:)` moves every file away,
  forgets the install record, revokes approvals, resets the switch and the
  remembered file ids, and with `deleteData` erases storage and sign-ins. The
  sign-ins come from the manifest when loaded and from the ledger's approval
  either way, so an unloaded plugin's tokens go too.
- `withdraw(record)` is `uninstall` without deleting data.
The app stops live controllers first and refreshes the Store list after.

## 2. PaletteMemory
Wraps `PaletteUsage`, `PalettePicks` and `PaletteFavorites`. One id rule for
recording (the entry's learn id). `PalettePicks` gains `move`. A `revision`
counter bumps on every change; `PaletteSession`'s cache key includes it, so a
clear from Settings reaches an open palette.

## 3. RootSearch
A HostCore module fed the typed text and the commands with a root pattern. It
decides which views to open, keep or close, stamps when each answer arrives
(not when SwiftUI reads it), keeps the per-plugin rows filtered once per
answer, and resolves "run this row" against the freshest answer. A protocol
seam (`open`, `update`, `close`) talks to live views; the app's command view
model is the adapter and tests use a fake.

## 4. One command-view lifecycle (explored, not built)
**Today.** Two drivers talk to an open view. The app's `CommandViewModel`
(macOS only) wraps `ViewSessionState` and adds the rules: waiting for a
restarted plugin, stopped, `canAct`, a submitted form that comes back
without errors finishes (closes the palette), reopening with the newest
text after a restart, and delivering open/update/event/close in order.
`PluginSession` (stackbarctl `render`, the MCP servers) keeps its own
session and seq counters and none of those rules: it waits out each update
in turn, ignores restarts, and can't say a form finished. So what an author checks
headless is not what the palette does.

**Shape.** A HostCore `CommandView` (a value type, like `ViewSessionState`
grown up) that takes inputs and returns what to send:
`open()`, `change(query)`, `perform(action, value)`, `received(seq, root)`,
`pluginRestarted()`, `pluginRunning()`, `pluginStopped(message)`, `close()`.
Each returns `[Send]` (`open`, `update`, `event`, `close`) plus derived state
(`isSearching`, `canAct`, `problem`, `finished`). Two thin adapters: the
app's `CommandViewModel` becomes an `@Observable` shell that runs the sends
on its ordered chain, and `PluginSession` runs them and awaits settle.

**Payoff.** The restart, stop, coalescing and form-finish rules get Linux
tests. `stackbarctl render --event` and the MCP `submit` tool can report
"finished" or the form's errors the way the palette acts on them.
`RootSearchView` (item 3) maps straight onto it.

**Cost and risk.** Medium: about 150 lines move out of `CommandCenter.swift`,
`PluginSession` takes its seqs from the shared type (its one-at-a-time
waits keep working as now). The app half can only
be checked by the macOS jobs and a hand check of typing, restart and form
submit in the palette. No protocol change.

## 5. Rate budgets on HostCall (explored, not built)
**Today.** `HostServices` holds 13 `RateLimiter`s and calls one by hand in
each dispatch case. Shared budgets are invisible: `activateApp`, `hideApp`,
`focusWindow` and `pressMenuItem` share 120 a minute; `chooseFile`,
`saveFile` and `pickColor` share 10. The authoring guide states six limits
(sound, alert, HUD, terminal, calendar writes, system actions) and leaves
out notifications (10), file panels and the colour picker (10), app
switching (120, shared), text reads (30), window arrangements (10), HTTP
(300) and all host calls (1200). A new call can forget its limiter, and the
guide drifts by hand.

**Shape.** `HostCall.budget: RateBudget?` in `HostCall+Description.swift`,
beside `label` and `requirement`, an exhaustive switch with no `default`, so
a new call doesn't compile until it says. `RateBudget` names a pool (`.appSwitching`,
`.filePanels`, …) with its limit, window and the plural used in the refusal.
`HostServices.handle` checks `call.budget` once before dispatch, with one
limiter keyed by pool and plugin; the 13 hand-placed checks go. The guide's
limits table is generated from the pools, like `llms.txt` is checked against
`AuthoringGuide.swift`, and a test fails when they disagree.

**Payoff.** Every limit in one table that the guide is made from; shared
pools are explicit; a new call can't skip the question.

**Cost and risk.** Small: one file in StackbarProtocol, about 40 lines out of
`HostServices`, a guide table. Behaviour stays the same limit for limit;
refusal messages keep their wording. No protocol bump (`budget` is
host-side only). Worth doing on its own; it pairs well with the perf work
because the check moves to one place.
