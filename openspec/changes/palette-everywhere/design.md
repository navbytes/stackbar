# Design

## Wire

`CommandSpec` gains `rootSearch: Bool` and `fallback: Bool`, both default
false. Its decoder is written by hand so specs saved or sent by plugins built
before protocol 16 still decode (missing keys are false). Older hosts ignore
the new keys. `problems` rejects `rootSearch` on a run command.

StackbarKit: `Command.rootSearch()` and `Command.fallback()`.

## Root search (`PaletteSession`)

- At the root, with two or more typed characters, every `rootSearch` view
  command whose plugin is running gets a `CommandViewModel`, opened with
  `openView(…, recordUse: false)` so it doesn't count as a use or show in
  Recent. Each later keystroke sets the view's query; the view's own
  coalescing (`ViewSessionState`) keeps one search in flight.
- The palette never starts a plugin to search it.
- `load()` reads each view's rows (`rows(of:)`, the same filter the view
  itself uses), keeps the first three with a primary action, and makes them
  entries: `.navigate` when the action navigates, `.action` otherwise. A side
  table maps the entry id back to the view and the `ActionRef`, so choosing
  it goes through `perform(_:in:)` on the view's own message chain, before
  the close that follows.
- The rows' ids are part of the root cache's key, so the list redraws when a
  plugin answers.
- Views close on `reset()` (the palette hid, or the query emptied).
- Root rows and fallbacks can't be pinned as favourites.

Section order for a typed query: Calculator, Applications/Results (apps first
on a prefix match), plugin sections (by command title), Files, From the
Store, fallbacks.

## Fallbacks

`fallbackEntries()` lists `fallback` commands as `.command` entries. A
fallback the search already found stays in Results only. Choosing one from
the fallback section passes the whole query as the first argument (or the
view's search text), instead of the alias rest.

## Grids and preview

`RowFilter.items(in:)` flattens a `.grid` of rows (also inside sections), and
`scored` filters inside it like a section. `RowFilter.columns(in:)` reports
the first grid's column count; the palette draws `PaletteTile`s in a
`LazyVGrid` and moves the selection by ±columns on up/down and ±1 on
left/right. Other views keep the list.

When the selected row has a `preview`, the list takes 46% of the width and
`PalettePreview` shows the text (monospaced, selectable) and/or the kept
image, with the plugin's image lookup in the environment.

## Compact mode

`paletteCompact` in `UserDefaults`. `PaletteSession.collapsed` is compact
and idle and not showing ⌘K. The controller sizes the window to the 58pt
header when collapsed and to 440pt otherwise, keeping the top edge where the
full palette's top would be.

## Tests

- `PaletteSectionsTests`: plugin sections and fallbacks order, dedupe, wait
  for a query.
- `CommandSpecRootSearchTests`: modifiers, old-spec decoding, round trip,
  validation.
- `ViewNodeQueriesTests`: grids filtered and flattened, column count.
- Mac: open with compact on, type, Esc back to collapsed; Clipboard rows at
  the root paste into the front app; Web Search fallback opens the browser;
  emoji grid arrows; preview pane.
