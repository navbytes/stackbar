# Design

- **Same command ids carry over.** A merged plugin keeps the old plugin's
  command ids for the commands it inherits, so `old/left-half` maps to
  `new/left-half`. A command the new plugin already has a preference for keeps
  its own; the old preference is dropped so a hotkey is never registered twice.
- **Once.** `PluginHandover` records `from → to`; turning the old plugin back
  on later is the person's choice and is not undone again.
- **Only installed plugins are switched off.** If the old plugin was never
  installed the handover is still recorded (nothing to move) and nothing is
  shown.
- **Not uninstalled automatically.** Uninstalling trashes files and may be
  unwanted (the person may keep it on purpose); turning off is reversible.
- **Store hiding lives in `StoreListing`**, not `PluginIndex.search`, so a
  `stackbar://store` link to the old id still opens its page.
- The index signature covers the raw bytes, so the new optional entry field
  doesn't break verification in older apps.
