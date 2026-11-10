# Commands-only main search

## Why
Naveen (2026-11-10): results from individual plugins clutter the palette's
main search. Raycast keeps its root search to commands: an extension adds
one row per command and its data lives inside the command's own view; there
is no API for an extension's data rows at the root. Stackbar instead put
every panel affordance of every plugin (each button, toggle, link and row,
about 170 fixed labels across the store plus live rows) into the root, let
13 plugins add up to three rows each per keystroke, and offered every
plugin's fallbacks and the Store's suggestions under any text.

Research and the adversarial review are in the thread "Reduce plugin clutter
in the command palette" and the doc "Plugin view in the command palette:
analysis" (a flattened per-plugin page was considered and rejected).

## What changes
- **Panel actions leave the main search.** `PaletteIndex.all` no longer
  includes panel affordances, and the empty root loses its "Panel Actions"
  section. They stay on the panel. `Row.hiddenFromPalette()` still compiles
  and has nothing left to do at the root.
- **"Open <Plugin>" for every plugin with a panel**, not only those without
  a menu-bar item. It opens the real panel (from the menu-bar item, or the
  headless window).
- **Plugin results need two yeses.** The plugin declares `.rootSearch()`
  and the user's per-command "Show results in main search" decides. Unset,
  it is on for the core plugins (Applications, Calculator, File Search) and
  for commands with a root pattern (they answer only text of their shape),
  off for other free-text searchers. A switch the user turned off before
  stays off.
- **Default aliases scope a search.** `Command.alias("gs")` (protocol 27)
  suggests an alias; the user can change or clear it. An alias, a space and
  text (`gs stackbar`) sends the text to that command's root search even
  when it is off for the main search, and its rows lead. A default alias
  already used by another command, or by the user, is skipped. Aliases may
  now be symbols too (`#`), set by the user.
- **Fallbacks are the user's list.** Settings → General lists every
  `.fallback()` command with a switch and an order. Unset, the list is
  Search Google (Quicklinks) and Ask AI. Fallbacks show only when fewer
  than three rows match. Tab still hands text to Ask AI whether or not it
  is in the list.
- **Store suggestions** show only when nothing installed matches.
- Settings → General gets a **Main search** list: every root-search
  command with when it answers, its switch and its alias.
