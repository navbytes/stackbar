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
