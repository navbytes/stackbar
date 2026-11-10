# Design

## Root contents
`PaletteIndex.all` = commands + Stackbar's places + "Open <Plugin>" rows.
`entries` (panel affordances) stay computed for the agent and tests but are
not searched at the root. `PaletteSection.group` drops `.panelActions`.

`setHeadlessPanels` becomes `setPanels`: one `.showPanel` row per plugin
with a panel. `AppDelegate.showPanel` already opens the menu-bar item's
panel or the headless window.

## Main search switch
`CommandPreference.inRootSearch` becomes `Bool?` (nil = the default), saved
under a new key `mainSearch`. Old files: a saved `inRootSearch: false` loads
as `false`; a saved `true` was only ever the default, so it loads as nil.
`RootSearchGate.isOn(entry, preference)` = the preference, or
`defaultOn` = core plugin (`BundledStore.corePluginIDs`) or a root pattern.

## Aliases
`CommandSpec.defaultAlias` (protocol 27), set by `Command.alias(_:)` and
checked by `normalizedAlias`. `CommandPreference.alias`: nil = the default
alias, "" = none, otherwise the user's. `PaletteIndex.setCommands` resolves
the effective alias; a default that clashes with a user alias or an earlier
default is skipped. `normalizedAlias` accepts one word of letters, digits
and `-_.#@/>!:?$%&*+=~`.

Scoped search: when `aliasMatch(query)` names a `.rootSearch()` command,
the palette feeds only that command, with the rest of the line (one
character is enough), ignoring its switch and pattern; `PaletteRoot.build`
marks that section as leading.

## Fallbacks
`CommandPreferences.fallbacks: [CommandKey]?` (nil = default list). The
root offers the listed, enabled `.fallback()` commands in that order when
results plus plugin rows are fewer than `PaletteRoot.fallbackThreshold`
(3). Tab's hand-off keeps reading every enabled fallback command, so Ask AI
works from Tab even when hidden.

## Store
`PaletteSection.group` adds the Store section only when there are no
results and no plugin rows.
